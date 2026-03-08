#!/usr/bin/env bash
# on-task-completed.sh — TaskCompleted quality gate for Agent Teams dispatch
# Fires when a teammate marks a task complete. Validates output files,
# enforces stage gates, advances state, and handles A4 verdict logic.
#
# Exit codes:
#   0 — accept task completion (output valid, state advanced)
#   2 with stderr — reject completion (output missing/invalid, feedback provided)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/swarm.sh"
source "$SCRIPT_DIR/lib/dag.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
source "$SCRIPT_DIR/lib/teams.sh"
source "$SCRIPT_DIR/lib/webhook.sh"

check_ants_workflow

# Shutdown check — exit early if workflow is shutting down
shutdown_check

# ---------------------------------------------------------------------------
# Phase handlers — each validates output and advances state
# ---------------------------------------------------------------------------

handle_a0() {
  # A0 output is top-level (not loop-scoped) — hardcoded path is intentional
  if [[ ! -f ".agents/tmp/phases/A0-explore.md" ]]; then
    teams_reject_completion "A0-explore.md not found. Explorer must write output to .agents/tmp/phases/A0-explore.md"
    exit 2
  fi

  if ! update_state '.currentPhase = "A1" | .updatedAt = $ts | .phases.A0.status = "complete"'; then
    echo "ERROR: Failed to advance state from A0 to A1." >&2
    exit 2
  fi
  cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2
  webhook_phase_event "A0" "completed" || true
  teams_log "A0 complete, advancing to A1"
}

handle_a1() {
  local phases_dir="$1"

  if [[ ! -f "${phases_dir}/A1-plan.md" ]]; then
    teams_reject_completion "A1-plan.md not found. Planner must write plan to ${phases_dir}/A1-plan.md"
    exit 2
  fi

  # Check if plan approval is required (v0.4 feature)
  local plan_approved
  plan_approved=$(state_get '.planApproved // false')
  if [[ "$plan_approved" != "true" ]]; then
    # Plan not yet approved -- keep standard "pending" status and reject
    # completion so TeammateIdle does not re-dispatch A1.
    if ! update_state '.updatedAt = $ts | .phases.A1.status = "pending"'; then
      echo "ERROR: Failed to mark plan as awaiting approval." >&2
      exit 2
    fi
    webhook_phase_event "A1" "completed" || true
    teams_log "A1 plan written, awaiting approval before A2"
    # Reject so TaskCompleted re-fires when plan is approved and A1 re-submitted
    teams_reject_completion "Plan written but planApproved is false. Set planApproved=true in state.json to proceed."
    exit 2
  fi

  if ! update_state '.currentPhase = "A2" | .updatedAt = $ts | .phases.A1.status = "complete"'; then
    echo "ERROR: Failed to advance state from A1 to A2." >&2
    exit 2
  fi
  cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2

  if [[ -f "${phases_dir}/A1-tasks.json" ]]; then
    if validate_json_file "${phases_dir}/A1-tasks.json" "A1-tasks.json"; then
      teams_log "A1-tasks.json found, A3 sub-tasks available for dynamic dispatch"
    else
      teams_log "WARNING: A1-tasks.json exists but is invalid JSON — A3 task pool will not be available"
    fi
  fi

  webhook_phase_event "A1" "completed" || true
  teams_log "A1 complete, advancing to A2"
}

handle_a2() {
  local phases_dir="$1"
  local loop="$2"
  local max_loops="$3"

  if [[ ! -f "${phases_dir}/A2-review.json" ]]; then
    teams_reject_completion "A2-review.json not found. Reviewer must write review to ${phases_dir}/A2-review.json"
    exit 2
  fi
  if ! validate_json_file "${phases_dir}/A2-review.json" "A2-review.json"; then
    teams_reject_completion "A2-review.json is invalid JSON."
    exit 2
  fi

  # Batch-read review status and high-severity count in a single jq pass
  local review_meta
  if ! review_meta=$(jq -r '{status: (.status // .verdict // ""), high_count: ([.issues[]? | select(.severity == "HIGH" or .severity == "critical")] | length)} | "\(.status)\t\(.high_count)"' "${phases_dir}/A2-review.json" 2>/dev/null); then
    teams_reject_completion "Failed to parse A2-review.json"
    exit 2
  fi
  local review_status
  review_status=$(printf '%s' "$review_meta" | cut -f1)
  local high_count
  high_count=$(printf '%s' "$review_meta" | cut -f2)
  high_count="${high_count:-0}"
  high_count=$(require_int "$high_count" "high_count")
  if [[ -z "$review_status" ]]; then
    teams_reject_completion "A2-review.json has neither .status nor .verdict field. Review must produce a verdict."
    exit 2
  fi

  if [[ "$review_status" == "needs_revision" && "$high_count" -gt 0 ]]; then
    teams_log "Blueprint review needs revision with ${high_count} HIGH/critical issues -- looping back to A1"
    local next_loop
    next_loop=$((loop + 1))

    if [[ "$next_loop" -gt "$max_loops" ]]; then
      if ! update_state '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .phases.A2.status = "complete" | .failure = "Max loops reached: blueprint review has unresolved HIGH issues"'; then
        echo "ERROR: Failed to update state to STOPPED after blueprint review failure." >&2
        exit 2
      fi
    else
      # Check stage restart budget BEFORE updating state to avoid orphaned loop entries
      if ! cb_increment_stage_restarts; then
        echo "WARNING: Stage restart budget exhausted after blueprint review failure." >&2
        if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Stage restart budget exhausted"'; then
          echo "ERROR: Failed to set blocked status after stage restart budget exhaustion." >&2
          exit 2
        fi
        exit 0  # Accept completion — workflow is now blocked
      fi

      if ! update_state --argjson nextLoop "$next_loop" \
        '.currentPhase = "A1" | .loop = $nextLoop | .updatedAt = $ts | .phases.A2.status = "complete" | .loops += [{"loop": $nextLoop, "startedAt": $ts}]'; then
        echo "ERROR: Failed to loop back to A1 after blueprint review failure." >&2
        exit 2
      fi
      if ! reset_phases_for_loop; then
        echo "ERROR: Failed to reset phases for loop-back from A2" >&2
        exit 2
      fi
      if ! cb_reset_for_loop; then
        echo "ERROR: Failed to reset circuit breaker for loop -- blocking workflow" >&2
        if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Circuit breaker reset failed during loop-back"'; then
          echo "ERROR: Failed to set blocked status after cb_reset_for_loop failure" >&2
          exit 2
        fi
        exit 0
      fi
    fi
  else
    if ! update_state '.currentPhase = "A3" | .updatedAt = $ts | .phases.A2.status = "complete"'; then
      echo "ERROR: Failed to advance state from A2 to A3." >&2
      exit 2
    fi
    cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2
    webhook_phase_event "A2" "completed" || true
    teams_log "A2 complete, advancing to A3"
  fi
}

handle_a3_worker() {
  local input="$1"
  local task_subject="$2"

  local has_pool
  has_pool=$(jq -r '.taskPool // empty | if type == "array" and length > 0 then "yes" else "no" end' "$STATE_FILE")

  if [[ "$has_pool" == "yes" ]]; then
    source "$SCRIPT_DIR/lib/task-pool.sh"
    # Extract task_id from completion input
    local task_id
    task_id=$(printf '%s' "$input" | jq -r '.output.taskId // .output.task_id // empty' || echo "")
    # Fallback: try extracting task ID from subject (format: "A3 Worker: T1 - description")
    if [[ -z "$task_id" ]]; then
      task_id=$(printf '%s' "$task_subject" | grep -oE '[Tt]ask[_ ][A-Za-z0-9_-]+|Worker:? [A-Za-z0-9_-]+' | head -1 | sed 's/.*[: ] *//' || echo "")
    fi

    if [[ -n "$task_id" ]]; then
      if ! pool_complete_task "$task_id"; then
        teams_reject_completion "Failed to complete task $task_id in pool."
        exit 2
      fi
    else
      teams_reject_completion "Worker completed but no task_id found in output. Include taskId in output JSON."
      exit 2
    fi

    if pool_is_complete; then
      teams_log "All tasks in pool complete, build track ready for quality review"
      if ! update_state '.updatedAt = $ts | .phases.A3.buildTrackComplete = true'; then
        echo "ERROR: Failed to mark build track complete -- rejecting to prevent state inconsistency" >&2
        teams_reject_completion "Build track complete but state update failed. Retry."
        exit 2
      fi
    fi
  fi

  teams_log "A3 worker completed"
}

handle_a3_guardian() {
  # Guardian (test writer) is not a pool task — accept completion without pool logic
  teams_log "A3 guardian completed"
}

handle_a3_sentinel() {
  local phases_dir="$1"
  local task_subject="$2"

  # Validate sentinel name against allowlist to prevent arbitrary file writes
  local sentinel_name
  sentinel_name=$(printf '%s' "$task_subject" | grep -oiE 'sentinel-(correctness|security|perf)' | head -1 | tr '[:upper:]' '[:lower:]' || echo "")
  if [[ -z "$sentinel_name" ]]; then
    teams_reject_completion "Cannot extract sentinel name from task subject. Expected sentinel-correctness, sentinel-security, or sentinel-perf."
    exit 2
  fi

  local marker_file
  marker_file="${phases_dir}/.${sentinel_name}.done"
  touch "$marker_file"
  teams_log "${sentinel_name} completed, marker written to ${marker_file}"

  # Check if all three sentinels are done
  if [[ -f "${phases_dir}/.sentinel-correctness.done" ]] \
     && [[ -f "${phases_dir}/.sentinel-security.done" ]] \
     && [[ -f "${phases_dir}/.sentinel-perf.done" ]]; then
    teams_log "All sentinels complete, arbiter can proceed"
  fi
}

handle_a3_arbiter() {
  local phases_dir="$1"

  if [[ ! -f "${phases_dir}/A3-quality.json" ]]; then
    teams_reject_completion "A3-quality.json not found. Arbiter must write consolidated verdict."
    exit 2
  fi
  if ! validate_json_file "${phases_dir}/A3-quality.json" "A3-quality.json"; then
    teams_reject_completion "A3-quality.json is invalid JSON."
    exit 2
  fi

  # Batch-read arbiter verdict and critical count in a single jq pass
  local arbiter_meta
  if ! arbiter_meta=$(jq -r '{verdict: (.verdict // ""), critical_count: ([.issues[]? | select(.severity == "critical")] | length)} | "\(.verdict)\t\(.critical_count)"' "${phases_dir}/A3-quality.json" 2>/dev/null); then
    teams_reject_completion "Failed to parse A3-quality.json"
    exit 2
  fi
  local arbiter_verdict
  arbiter_verdict=$(printf '%s' "$arbiter_meta" | cut -f1)
  local critical_count
  critical_count=$(printf '%s' "$arbiter_meta" | cut -f2)
  critical_count="${critical_count:-0}"
  critical_count=$(require_int "$critical_count" "critical_count")

  if [[ "$arbiter_verdict" == "issues_found" && "$critical_count" -gt 0 ]]; then
    teams_log "Arbiter found ${critical_count} critical issues, recording failure"
    if ! cb_record_failure; then
      echo "WARNING: cb_record_failure state update failed -- proceeding with rejection" >&2
    fi
    if cb_is_tripped; then
      echo "WARNING: Circuit breaker tripped after arbiter failure" >&2
      if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Circuit breaker tripped: arbiter found critical issues"'; then
        echo "ERROR: Failed to update state to blocked after circuit breaker trip" >&2
        teams_reject_completion "Circuit breaker tripped but failed to update state — rejecting to prevent inconsistent state."
        exit 2
      fi
      teams_reject_completion "Circuit breaker tripped after arbiter found ${critical_count} critical issues. Workflow is blocked."
      exit 2
    fi
    # Reject completion so A3 does not advance to A4 with critical issues
    teams_reject_completion "Arbiter found ${critical_count} critical issues. Fix and resubmit."
    exit 2
  else
    cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2
  fi

  teams_log "A3 arbiter complete"
}

handle_a3_aggregate() {
  local phases_dir="$1"

  if [[ ! -f "${phases_dir}/A3-build.json" ]]; then
    teams_reject_completion "A3-build.json not found. Build track must produce aggregate output."
    exit 2
  fi
  if ! validate_json_file "${phases_dir}/A3-build.json" "A3-build.json"; then
    teams_reject_completion "A3-build.json exists but is invalid JSON."
    exit 2
  fi
  if ! jq -e '.tasks and .files_changed and .all_complete == true' "${phases_dir}/A3-build.json" >/dev/null 2>&1; then
    teams_reject_completion "A3-build.json missing required fields or all_complete is not true."
    exit 2
  fi

  # Gate: A3-quality.json must exist before advancing to A4
  if [[ ! -f "${phases_dir}/A3-quality.json" ]]; then
    teams_reject_completion "A3-quality.json not found. Quality track (arbiter) must complete before advancing to A4."
    exit 2
  fi
  if ! validate_json_file "${phases_dir}/A3-quality.json" "A3-quality.json"; then
    teams_reject_completion "A3-quality.json exists but is invalid JSON."
    exit 2
  fi

  # Idempotency: only advance if still in A3
  local current
  current=$(jq -r '.currentPhase // empty' "$STATE_FILE" 2>/dev/null || echo "")
  if [[ "$current" == "A3" ]]; then
    if ! update_state '.currentPhase = "A4" | .updatedAt = $ts | .phases.A3.status = "complete"'; then
      echo "ERROR: Failed to advance state from A3 to A4." >&2
      exit 2
    fi
    webhook_phase_event "A3" "completed" || true
    teams_log "A3 complete (build + quality), advancing to A4"
  else
    teams_log "A3->A4 already advanced (currentPhase=$current), skipping"
  fi
}

handle_a4() {
  local phases_dir="$1"
  local loop="$2"
  local max_loops="$3"

  if [[ ! -f "${phases_dir}/A4-queen-verdict.json" ]]; then
    teams_reject_completion "A4-queen-verdict.json not found. Queen must write verdict."
    exit 2
  fi
  if ! validate_json_file "${phases_dir}/A4-queen-verdict.json" "A4-queen-verdict.json"; then
    teams_reject_completion "A4-queen-verdict.json is invalid JSON."
    exit 2
  fi

  # VERDICT is set by parse_queen_verdict in caller scope — clear stale values first
  VERDICT=""
  parse_queen_verdict "${phases_dir}/A4-queen-verdict.json"
  if [[ -z "$VERDICT" ]]; then
    teams_reject_completion "parse_queen_verdict did not set VERDICT. Queen verdict file may be malformed."
    exit 2
  fi

  # Use shared verdict handler (defined in swarm.sh)
  RESULT_PHASE=""
  handle_a4_verdict "$VERDICT" "$loop" "$max_loops"

  if [[ -z "$RESULT_PHASE" ]]; then
    teams_reject_completion "handle_a4_verdict did not set RESULT_PHASE. Verdict handling may have failed silently."
    exit 2
  fi

  webhook_phase_event "A4" "completed" || true

  case "$RESULT_PHASE" in
    A5)
      teams_log "A4 verdict clean, advancing to A5"
      ;;
    A1)
      teams_log "A4 verdict issues_found, looping back to A1"
      ;;
    STOPPED)
      teams_log "Maximum loops (${max_loops}) reached with unresolved issues"
      ;;
    BLOCKED)
      teams_log "Workflow blocked (circuit breaker or restart budget exhausted)"
      ;;
    *)
      teams_reject_completion "Unexpected RESULT_PHASE '${RESULT_PHASE}' from handle_a4_verdict."
      exit 2
      ;;
  esac
}

handle_a5() {
  local phases_dir="$1"

  if [[ ! -f "${phases_dir}/A5-ship.json" ]]; then
    teams_reject_completion "A5-ship.json not found. Shipper must write output."
    exit 2
  fi
  if ! validate_json_file "${phases_dir}/A5-ship.json" "A5-ship.json"; then
    teams_reject_completion "A5-ship.json is invalid JSON."
    exit 2
  fi
  if ! jq -e '.commit_sha' "${phases_dir}/A5-ship.json" >/dev/null 2>&1; then
    teams_reject_completion "A5-ship.json missing required field (commit_sha)."
    exit 2
  fi

  local pipeline
  pipeline=$(state_get '.pipeline // "swarm"')

  if [[ "$pipeline" == "pswarm" ]]; then
    local pswarm_run
    pswarm_run=$(state_get '.pswarmRun // 1')
    pswarm_run=$(require_int "$pswarm_run" "pswarmRun")
    local max_runs
    max_runs=$(state_get '.maxRuns // 50')
    max_runs=$(require_int "$max_runs" "maxRuns")

    if [[ "$pswarm_run" -ge "$max_runs" ]]; then
      # Max runs exhausted — mark complete
      if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts | .phases.A5.status = "complete"'; then
        echo "ERROR: Failed to mark pswarm workflow as complete." >&2
        exit 2
      fi
      webhook_phase_event "A5" "completed" || true
      webhook_workflow_event "completed" || true
      teams_log "pswarm complete: maxRuns ($max_runs) reached after run $pswarm_run"
    else
      local next_run
      next_run=$((pswarm_run + 1))

      # Re-check shutdown flag before starting next run
      local is_shutdown
      is_shutdown=$(state_get '.shutdown // false')
      if [[ "$is_shutdown" == "true" ]]; then
        if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts | .phases.A5.status = "complete"'; then
          echo "ERROR: Failed to mark pswarm workflow as complete after shutdown." >&2
          exit 2
        fi
        webhook_phase_event "A5" "completed" || true
        webhook_workflow_event "completed" || true
        teams_log "pswarm: shutdown requested, completing after run $pswarm_run"
        return
      fi

      # Atomic reset for next pswarm run — combines state fields, phase resets,
      # and circuit breaker resets into a single update_state call to avoid
      # non-atomic intermediate states and redundant lock/jq cycles.
      if ! update_state --argjson nextRun "$next_run" \
        '.pswarmRun = $nextRun | .loop = 1 | .planApproved = false | .taskPool = []
         | .currentPhase = "A0" | .status = "in_progress" | .updatedAt = $ts
         | .phases = (.phases // {})
         | .phases.A0 = {"status": "pending"}
         | .phases.A1 = {"status": "pending"}
         | .phases.A2 = {"status": "pending"}
         | .phases.A3 = {"status": "pending"}
         | .phases.A4 = {"status": "pending"}
         | .phases.A5 = {"status": "pending"}
         | .circuitBreaker.stageRestarts = 0
         | .circuitBreaker.fixAttempts = {}
         | .circuitBreaker.consecutiveFailures = 0'; then
        echo "ERROR: Failed to reset state for next pswarm run." >&2
        exit 2
      fi
      webhook_phase_event "A5" "completed" || true
      teams_log "pswarm: run $pswarm_run shipped, starting run $next_run of $max_runs"
    fi
  else
    # Original swarm behavior
    if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts | .phases.A5.status = "complete"'; then
      echo "ERROR: Failed to mark workflow as complete." >&2
      exit 2
    fi
    webhook_phase_event "A5" "completed" || true
    webhook_workflow_event "completed" || true
    teams_log "A5 complete, workflow DONE"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  # Read input from stdin with size limit (prevent memory bombs)
  local INPUT
  INPUT=$(head -c 1048576)  # 1MB limit
  if [[ -z "$INPUT" ]]; then
    echo "ERROR: Empty stdin for TaskCompleted hook." >&2
    exit 2
  fi
  # Validate JSON structure
  if ! printf '%s' "$INPUT" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "ERROR: stdin is not a valid JSON object for TaskCompleted hook." >&2
    exit 2
  fi

  # Extract task subject to determine which phase completed
  local TASK_SUBJECT
  TASK_SUBJECT=$(printf '%s' "$INPUT" | jq -r '.task_subject // .subject // empty')
  if [[ -z "$TASK_SUBJECT" ]]; then
    teams_log "WARNING: TaskCompleted event has no task_subject or subject field"
    # Cannot route to a phase handler — reject so the task is retried
    teams_reject_completion "TaskCompleted event missing task_subject/subject field. Cannot validate."
    exit 2
  fi

  # Map task subject to phase ID.
  # Subjects are anchored: "A3 Worker: ...", "A0: ...", etc.
  # Match start-of-subject to avoid misrouting when descriptions mention other phases.
  local phase=""
  case "$TASK_SUBJECT" in
    "A3 Guardian"*|"A3 guardian"*|"A3-guardian"*)
      phase="A3-guardian" ;;
    "A3 Worker"*|"A3 worker"*|"A3-worker"*)
      phase="A3-worker" ;;
    "A3 Sentinel"*|"A3 sentinel"*|"A3-sentinel"*)
      phase="A3-sentinel" ;;
    "A3 Arbiter"*|"A3 arbiter"*|"A3-arbiter"*)
      phase="A3-arbiter" ;;
    "A3"*) phase="A3" ;;
    "A0"*) phase="A0" ;;
    "A1"*) phase="A1" ;;
    "A2"*) phase="A2" ;;
    "A4"*) phase="A4" ;;
    "A5"*) phase="A5" ;;
    *)
      # Not an ants phase task, allow completion
      exit 0
      ;;
  esac

  local loop
  loop=$(state_get '.loop // 1')
  local max_loops
  max_loops=$(state_get '.maxLoops // 5')
  loop=$(require_int "$loop" "loop")
  max_loops=$(require_int "$max_loops" "maxLoops")
  local phases_dir=".agents/tmp/phases/loop-${loop}"

  case "$phase" in
    A0)          handle_a0 ;;
    A1)          handle_a1 "$phases_dir" ;;
    A2)          handle_a2 "$phases_dir" "$loop" "$max_loops" ;;
    A3-worker)   handle_a3_worker "$INPUT" "$TASK_SUBJECT" ;;
    A3-guardian) handle_a3_guardian ;;
    A3-sentinel) handle_a3_sentinel "$phases_dir" "$TASK_SUBJECT" ;;
    A3-arbiter)  handle_a3_arbiter "$phases_dir" ;;
    A3)          handle_a3_aggregate "$phases_dir" ;;
    A4)          handle_a4 "$phases_dir" "$loop" "$max_loops" ;;
    A5)          handle_a5 "$phases_dir" ;;
  esac

  exit 0
}

main
