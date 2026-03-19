#!/usr/bin/env bash
# on-task-completed.sh — TaskCompleted quality gate and state advancement engine
# for ants v0.6 Agent Teams delegate mode.
#
# Fires when a teammate marks a task complete. Validates checkpoint files,
# advances state (currentPhase, phase statuses), sets signal flags for the
# command's monitoring loop (needsA3Tasks, needsA5Tasks, needsLoopReset,
# needsPswarmReset), and evaluates A4 verdict INLINE after A3 arbiter
# completes (no separate A4 agent dispatch).
#
# Hooks are shell scripts — they CANNOT call TaskCreate, TaskUpdate, or
# any Claude tools. They can only read/write state.json, read output files,
# write signal flags, and exit 0 (accept) or exit 2 (reject with feedback).
#
# Exit codes:
#   0 — accept task completion (checkpoint valid, state advanced)
#   2 with stderr — reject completion (checkpoint missing/invalid, feedback provided)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/swarm.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
source "$SCRIPT_DIR/lib/teams.sh"
source "$SCRIPT_DIR/lib/webhook.sh"
source "$SCRIPT_DIR/lib/dag.sh"
source "$SCRIPT_DIR/lib/task-pool.sh"

check_ants_workflow

# Shutdown check — exit early if workflow is shutting down
shutdown_check

# ---------------------------------------------------------------------------
# Phase handlers — validate checkpoint files AND advance state
# ---------------------------------------------------------------------------

handle_a0() {
  # A0 output is top-level (not loop-scoped) — hardcoded path is intentional
  if [[ ! -f ".agents/tmp/phases/A0-explore.md" ]]; then
    teams_reject_completion "A0-explore.md not found. Explorer must write output to .agents/tmp/phases/A0-explore.md"
    exit 2
  fi

  cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2
  webhook_phase_event "A0" "completed" || true

  # Advance state: A0 complete -> A1 pending
  if ! update_state '
    .currentPhase = "A1" |
    .updatedAt = $ts |
    .phases.A0.status = "complete" |
    .phases.A0.completedAt = $ts |
    .phases.A1.status = "pending"
  '; then
    teams_reject_completion "A0 valid but failed to advance state to A1. Retry."
    exit 2
  fi

  webhook_phase_event "A1" "started" || true
  teams_log "A0 complete, advanced to A1"
}

handle_a1() {
  local phases_dir="$1"

  if [[ ! -f "${phases_dir}/A1-plan.md" ]]; then
    teams_reject_completion "A1-plan.md not found. Planner must write plan to ${phases_dir}/A1-plan.md"
    exit 2
  fi

  # planApproved gate — reject if plan has not been approved
  local plan_approved
  plan_approved=$(state_get '.planApproved // false')
  if [[ "$plan_approved" != "true" ]]; then
    if ! update_state '.updatedAt = $ts | .phases.A1.status = "pending"'; then
      echo "ERROR: Failed to mark plan as awaiting approval." >&2
      exit 2
    fi
    webhook_phase_event "A1" "completed" || true
    teams_log "A1 plan written, awaiting approval before proceeding"
    teams_reject_completion "Plan written but planApproved is false. Set planApproved=true in state.json to proceed."
    exit 2
  fi

  cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2

  # Initialize task pool and set signal flag if A1-tasks.json exists
  if [[ -f "${phases_dir}/A1-tasks.json" ]]; then
    if validate_json_file "${phases_dir}/A1-tasks.json" "A1-tasks.json"; then
      # Initialize task pool from A1-tasks.json
      if pool_init; then
        teams_log "Task pool initialized from A1-tasks.json"
      else
        teams_log "WARNING: pool_init failed — A3 task pool will not be available"
      fi
    else
      teams_log "WARNING: A1-tasks.json exists but is invalid JSON — A3 task pool will not be available"
    fi
  fi

  # Advance state: A1 complete -> A2 pending (merging needsA3Tasks into the same
  # atomic update to prevent premature signal flag visibility before state is ready)
  if ! update_state '
    .currentPhase = "A2" |
    .updatedAt = $ts |
    .phases.A1.status = "complete" |
    .phases.A1.completedAt = $ts |
    .phases.A2.status = "pending" |
    .needsA3Tasks = true
  '; then
    teams_reject_completion "A1 valid but failed to advance state to A2. Retry."
    exit 2
  fi

  webhook_phase_event "A1" "completed" || true
  webhook_phase_event "A2" "started" || true
  teams_log "A1 complete, advanced to A2"
}

handle_a2() {
  local phases_dir="$1"

  if [[ ! -f "${phases_dir}/A2-review.json" ]]; then
    teams_reject_completion "A2-review.json not found. Reviewer must write review to ${phases_dir}/A2-review.json"
    exit 2
  fi
  if ! validate_json_file "${phases_dir}/A2-review.json" "A2-review.json"; then
    teams_reject_completion "A2-review.json is invalid JSON."
    exit 2
  fi

  # Validate that the review has a status field
  local review_status
  review_status=$(jq -r '.status // empty' "${phases_dir}/A2-review.json" 2>/dev/null || echo "")
  if [[ -z "$review_status" ]]; then
    teams_reject_completion "A2-review.json missing .status field. Review must produce a verdict."
    exit 2
  fi

  cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2

  # Branch on review verdict
  if [[ "$review_status" == "needs_revision" ]]; then
    # Count HIGH severity issues
    local high_count
    high_count=$(jq '[.issues[]? | select(.severity == "HIGH" or .severity == "high" or .severity == "critical")] | length' "${phases_dir}/A2-review.json" 2>/dev/null || echo "0")
    [[ "${high_count:-0}" =~ ^[0-9]+$ ]] || high_count="0"

    if [[ "$high_count" -gt 0 ]]; then
      teams_log "A2 review: needs_revision with ${high_count} HIGH issues — looping back to A1"

      # Check fix attempt budget for A2
      if ! cb_increment_fix_attempts "A2"; then
        teams_log "WARNING: Fix attempt budget exhausted for A2"
        if ! update_state '
          .status = "blocked" |
          .updatedAt = $ts |
          .phases.A2.status = "complete" |
          .phases.A2.completedAt = $ts |
          .failure = "Fix attempt budget exhausted for A2 review"
        '; then
          teams_reject_completion "A2 fix budget exhausted but failed to update state."
          exit 2
        fi
        teams_reject_completion "Fix attempt budget exhausted for A2 review. Workflow blocked."
        exit 2
      fi

      # Check max loops
      local loop
      loop=$(state_get '.loop // 1')
      loop=$(require_int "$loop" "loop")
      local max_loops
      max_loops=$(state_get '.maxLoops // 5')
      max_loops=$(require_int "$max_loops" "maxLoops")
      local next_loop=$((loop + 1))

      if [[ "$next_loop" -gt "$max_loops" ]]; then
        if ! update_state '
          .status = "stopped" |
          .currentPhase = "STOPPED" |
          .updatedAt = $ts |
          .phases.A2.status = "complete" |
          .phases.A2.completedAt = $ts |
          .failure = "Max loops reached during A2 review loop-back"
        '; then
          teams_reject_completion "Max loops reached but failed to update state."
          exit 2
        fi
        teams_log "Max loops reached, workflow stopped"
        webhook_phase_event "A2" "completed" || true
        return 0
      fi

      # Loop back to A1
      # IMPORTANT: reset_phases_for_loop clears signal flags, so call it BEFORE setting needsLoopReset.
      # Failure is fatal -- stale phase statuses from previous loop would cause incorrect dispatch.
      if ! reset_phases_for_loop; then
        teams_reject_completion "reset_phases_for_loop failed during A2 loop-back. State may be stale. Retry."
        exit 2
      fi
      if ! update_state --argjson nextLoop "$next_loop" '
        .currentPhase = "A1" |
        .loop = $nextLoop |
        .updatedAt = $ts |
        .phases.A2.status = "complete" |
        .phases.A2.completedAt = $ts |
        .needsLoopReset = true
      '; then
        teams_reject_completion "A2 loop-back failed to update state."
        exit 2
      fi
      webhook_phase_event "A2" "completed" || true
      teams_log "A2 review needs_revision with HIGH issues, looped back to A1 (loop ${next_loop})"
      return 0
    fi

    # needs_revision but no HIGH issues — advance to A3 with advisory
    teams_log "A2 review: needs_revision but no HIGH issues — advancing to A3 with advisory"
  fi

  # Advance state: A2 complete -> A3 pending
  if ! update_state '
    .currentPhase = "A3" |
    .updatedAt = $ts |
    .phases.A2.status = "complete" |
    .phases.A2.completedAt = $ts |
    .phases.A3.status = "in_progress"
  '; then
    teams_reject_completion "A2 valid but failed to advance state to A3. Retry."
    exit 2
  fi

  webhook_phase_event "A2" "completed" || true
  webhook_phase_event "A3" "started" || true
  teams_log "A2 complete, advanced to A3"
}

handle_a3_worker() {
  local input="$1"
  local task_subject="$2"

  local has_pool
  has_pool=$(state_get '.taskPool // empty | if type == "array" and length > 0 then "yes" else "no" end')

  if [[ "$has_pool" == "yes" ]]; then
    # Extract task_id from completion input (primary path)
    local task_id
    task_id=$(printf '%s' "$input" | jq -r '.output.taskId // .output.task_id // empty' || echo "")
    # Fallback: extract task ID from subject line
    # Expected subject formats: "A3 Worker: T1 - description" or "A3 Worker: my-task-id ..."
    if [[ -z "$task_id" ]]; then
      if [[ "$task_subject" =~ ^A3[[:space:]][Ww]orker:[[:space:]]*([A-Za-z0-9_-]+) ]]; then
        task_id="${BASH_REMATCH[1]}"
      fi
    fi

    if [[ -n "$task_id" ]]; then
      if ! [[ "$task_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
        teams_log "WARNING: Invalid task_id extracted: '${task_id}', skipping pool_complete_task"
        task_id=""
      fi
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
      webhook_phase_event "A3" "build_track_complete" || true
    fi
  fi

  cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2

  if [[ "$has_pool" != "yes" ]]; then
    teams_log "WARNING: A3 worker completed but no valid task pool found (backward compat fallback)"
  fi
  teams_log "A3 worker completed"
}

handle_a3_guardian() {
  local phases_dir="$1"

  # Mark guardian complete in state -- reject if update fails to keep state/markers in sync
  if ! update_state '.updatedAt = $ts | .phases.A3.guardianDone = true'; then
    teams_reject_completion "Failed to mark guardian as done in state. Retry."
    exit 2
  fi

  local marker_file
  marker_file="${phases_dir}/.guardian.done"
  touch "$marker_file"

  teams_log "A3 guardian completed"
}

handle_a3_sentinel() {
  local phases_dir="$1"
  local task_subject="$2"

  # Validate sentinel name against allowlist to prevent arbitrary file writes
  local sentinel_name
  sentinel_name=$(printf '%s' "$task_subject" | grep -oiE 'sentinel-(correctness|security|perf|style)' | head -1 | tr '[:upper:]' '[:lower:]' || echo "")
  if [[ -z "$sentinel_name" ]]; then
    teams_reject_completion "Cannot extract sentinel name from task subject. Expected sentinel-correctness, sentinel-security, sentinel-perf, or sentinel-style."
    exit 2
  fi

  local marker_file
  marker_file="${phases_dir}/.${sentinel_name}.done"
  touch "$marker_file"
  teams_log "${sentinel_name} completed, marker written to ${marker_file}"

  # Check if all four sentinels are done
  if [[ -f "${phases_dir}/.sentinel-correctness.done" ]] \
     && [[ -f "${phases_dir}/.sentinel-security.done" ]] \
     && [[ -f "${phases_dir}/.sentinel-perf.done" ]] \
     && [[ -f "${phases_dir}/.sentinel-style.done" ]]; then
    if ! update_state '.updatedAt = $ts | .phases.A3.sentinelsDone = true'; then
      teams_reject_completion "All sentinels done but failed to update state. Retry."
      exit 2
    fi
    teams_log "All sentinels complete, arbiter can proceed"
  fi
}

handle_a3_simplifier() {
  local phases_dir="$1"

  # Mark simplifier complete in state -- reject if update fails to keep state/markers in sync
  if ! update_state '.updatedAt = $ts | .phases.A3.simplifierDone = true'; then
    teams_reject_completion "Failed to mark simplifier as done in state. Retry."
    exit 2
  fi

  local marker_file
  marker_file="${phases_dir}/.simplifier.done"
  touch "$marker_file"

  teams_log "A3 simplifier completed"

  # Check if all quality agents are done (sentinels + guardian + simplifier)
  local sentinels_done
  sentinels_done=$(state_get '.phases.A3.sentinelsDone // false')
  local guardian_done
  guardian_done=$(state_get '.phases.A3.guardianDone // false')

  if [[ "$sentinels_done" == "true" && "$guardian_done" == "true" ]]; then
    teams_log "All quality agents complete (sentinels + guardian + simplifier), arbiter can proceed"
  fi
}

handle_a3_fixer() {
  local phases_dir="$1"

  # Review-fixer applied targeted repairs after arbiter found critical issues
  local marker_file
  marker_file="${phases_dir}/.review-fixer.done"
  touch "$marker_file"

  teams_log "A3 review-fixer completed"
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

  # Mark arbiter done in state -- reject if update fails (keystone event for A4 verdict)
  if ! update_state '.updatedAt = $ts | .phases.A3.arbiterDone = true'; then
    teams_reject_completion "Failed to mark arbiter as done in state. Retry."
    exit 2
  fi

  # ─────────────────────────────────────────────────────────────
  # INLINE A4 VERDICT — evaluate quality verdict and write
  # A4-queen-verdict.json directly from this hook
  # ─────────────────────────────────────────────────────────────

  # Batch-read critical and warning counts in a single jq pass
  local quality_meta
  if ! quality_meta=$(jq -r '{
    critical_count: ([.issues[]? | select(.severity == "critical" or .severity == "HIGH" or .severity == "high")] | length),
    warning_count: ([.issues[]? | select(.severity == "warning" or .severity == "WARNING")] | length),
    all_issues: ([.issues[]?] | length)
  } | "\(.critical_count)\t\(.warning_count)\t\(.all_issues)"' "${phases_dir}/A3-quality.json" 2>/dev/null); then
    teams_reject_completion "Failed to parse issue counts from A3-quality.json"
    exit 2
  fi

  local critical_count warning_count all_issues
  IFS=$'\t' read -r critical_count warning_count all_issues <<< "$quality_meta"
  critical_count="${critical_count:-0}"
  warning_count="${warning_count:-0}"
  all_issues="${all_issues:-0}"
  critical_count=$(require_int "$critical_count" "critical_count")
  warning_count=$(require_int "$warning_count" "warning_count")
  all_issues=$(require_int "$all_issues" "all_issues")

  # Determine verdict: clean if no critical or warning issues
  local verdict="clean"
  local actionable_count=$((critical_count + warning_count))
  if [[ "$actionable_count" -gt 0 ]]; then
    verdict="issues_found"
  fi

  teams_log "A4 inline verdict: ${verdict} (critical=${critical_count}, warning=${warning_count}, total=${all_issues})"

  # Write A4-queen-verdict.json with evidence
  mkdir -p "$phases_dir"
  local timestamp
  timestamp=$(date -Iseconds)
  if ! jq -n \
    --arg verdict "$verdict" \
    --argjson critical "$critical_count" \
    --argjson warning "$warning_count" \
    --argjson total "$all_issues" \
    --arg ts "$timestamp" \
    '{
      "verdict": $verdict,
      "total_issues": ($critical + $warning),
      "critical_issues": $critical,
      "warning_issues": $warning,
      "info_issues": ($total - $critical - $warning),
      "evidence": [
        ("Arbiter found " + ($critical | tostring) + " critical and " + ($warning | tostring) + " warning issues"),
        ("Total issues across all severities: " + ($total | tostring)),
        ("Verdict evaluated inline by TaskCompleted hook at " + $ts)
      ],
      "evaluatedAt": $ts,
      "evaluatedBy": "on-task-completed.sh (inline A4)"
    }' > "${phases_dir}/A4-queen-verdict.json"; then
    teams_reject_completion "Failed to write A4-queen-verdict.json"
    exit 2
  fi

  webhook_phase_event "A3" "completed" || true

  if [[ "$verdict" == "clean" ]]; then
    # Clean verdict — mark A3/A4 complete, advance to A5, set signal flag
    if ! update_state '
      .updatedAt = $ts |
      .phases.A3.status = "complete" |
      .phases.A3.completedAt = $ts |
      .phases.A4.status = "complete" |
      .phases.A4.completedAt = $ts
    '; then
      teams_reject_completion "Failed to mark A3/A4 as complete in state."
      exit 2
    fi

    webhook_phase_event "A4" "completed" || true
    cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2

    if ! update_state '
      .currentPhase = "A5" |
      .updatedAt = $ts |
      .needsA5Tasks = true
    '; then
      teams_reject_completion "Clean verdict but failed to advance state to A5. Retry."
      exit 2
    fi

    webhook_phase_event "A5" "started" || true
    teams_log "A4 verdict clean, advanced to A5 (needsA5Tasks signal set)"
  else
    # Issues found — use handle_a4_verdict() from swarm.sh for battle-tested loop-back logic.
    # NOTE: Do NOT mark A3/A4 complete here. handle_a4_verdict() calls
    # reset_phases_for_loop() first (which clears A1-A4 to pending), then sets
    # A4 status to complete with the verdict. Marking A3/A4 complete before
    # handle_a4_verdict would be overwritten by reset_phases_for_loop anyway.
    local loop
    loop=$(state_get '.loop // 1')
    loop=$(require_int "$loop" "loop")
    local max_loops
    max_loops=$(state_get '.maxLoops // 5')
    max_loops=$(require_int "$max_loops" "maxLoops")

    # Mark A3 complete and set currentPhase to A4 so handle_a4_verdict() idempotency guard passes.
    # A4 completion is handled inside handle_a4_verdict after reset_phases_for_loop.
    if ! update_state '
      .currentPhase = "A4" |
      .updatedAt = $ts |
      .phases.A3.status = "complete" |
      .phases.A3.completedAt = $ts
    '; then
      teams_reject_completion "Failed to set currentPhase to A4 for verdict evaluation. Retry."
      exit 2
    fi

    # handle_a4_verdict sets RESULT_PHASE in caller scope
    local RESULT_PHASE=""
    handle_a4_verdict "$verdict" "$loop" "$max_loops"

    case "$RESULT_PHASE" in
      A1)
        # Loop-back: set signal flag for command's monitoring loop
        if ! update_state '.needsLoopReset = true'; then
          teams_reject_completion "Failed to set needsLoopReset signal flag. Command cannot create fresh tasks without it. Retry."
          exit 2
        fi
        webhook_phase_event "A4" "loop_back" || true
        teams_log "A4 verdict issues_found, looped back to A1 (needsLoopReset signal set)"
        ;;
      STOPPED)
        webhook_phase_event "A4" "stopped" || true
        teams_log "A4 verdict issues_found, max loops reached — workflow stopped"
        ;;
      BLOCKED)
        webhook_phase_event "A4" "blocked" || true
        teams_log "A4 verdict issues_found, budget exhausted — workflow blocked"
        ;;
      A5)
        # Should not happen for issues_found, but handle gracefully
        teams_log "WARNING: handle_a4_verdict returned A5 for issues_found verdict"
        ;;
      *)
        teams_log "A4 verdict already processed (RESULT_PHASE=${RESULT_PHASE})"
        ;;
    esac
  fi
}

# ─────────────────────────────────────────────────────────────
# LEGACY: Agent Teams mode catch-all for A3 aggregate validation.
# In v0.6, individual A3 sub-type handlers (worker, sentinel, guardian,
# simplifier, arbiter, fixer) handle all A3 tasks. This catch-all should
# not fire for properly-formed task subjects. Kept as safety fallback.
# ─────────────────────────────────────────────────────────────
handle_a3_aggregate() {
  local phases_dir="$1"

  # Validate A3-build.json: existence + valid JSON + required fields in a single jq call
  if [[ ! -f "${phases_dir}/A3-build.json" ]]; then
    teams_reject_completion "A3-build.json not found. Build track must produce aggregate output."
    exit 2
  fi
  if ! jq -e '.tasks and .files_changed and .all_complete == true' "${phases_dir}/A3-build.json" >/dev/null 2>&1; then
    teams_reject_completion "A3-build.json is invalid JSON, missing required fields (tasks, files_changed), or all_complete is not true."
    exit 2
  fi

  # Validate A3-quality.json: existence + valid JSON in a single jq call
  if [[ ! -f "${phases_dir}/A3-quality.json" ]]; then
    teams_reject_completion "A3-quality.json not found. Quality track (arbiter) must complete before A3 gate passes."
    exit 2
  fi
  if ! jq empty "${phases_dir}/A3-quality.json" 2>/dev/null; then
    teams_reject_completion "A3-quality.json exists but is invalid JSON."
    exit 2
  fi

  webhook_phase_event "A3" "completed" || true
  teams_log "WARNING: A3 legacy catch-all handler fired -- task subject did not match any v0.6 sub-type pattern (subject may be malformed or from stale state)"
  teams_log "A3 checkpoint valid (build + quality) [legacy catch-all]"
}

# ─────────────────────────────────────────────────────────────
# LEGACY: A4 verdict is now evaluated inline by handle_a3_arbiter().
# This function is retained as a compatibility shim. If a task with
# an A4 subject fires, it validates the verdict file if present but
# does not perform any state transitions.
# ─────────────────────────────────────────────────────────────
handle_a4() {
  local phases_dir="$1"

  if [[ -f "${phases_dir}/A4-queen-verdict.json" ]]; then
    if validate_json_file "${phases_dir}/A4-queen-verdict.json" "A4-queen-verdict.json"; then
      teams_log "A4 verdict file valid (inline verdict already processed by A3 arbiter)"
    else
      teams_reject_completion "A4-queen-verdict.json is invalid JSON."
      exit 2
    fi
  fi

  teams_log "A4 handler (legacy compatibility — verdict evaluated inline by A3 arbiter)"
}

handle_a5_nurse() {
  local phases_dir="$1"

  # Nurse writes A5-docs.json — validate it exists
  if [[ -f "${phases_dir}/A5-docs.json" ]]; then
    teams_log "A5 nurse completed (A5-docs.json found)"
  else
    teams_log "A5 nurse completed (no A5-docs.json, optional)"
  fi

  # Mark nurse as done so teams_get_next_ready_task() can route to drone
  if ! update_state '.phases.A5.nurseDone = true | .updatedAt = $ts'; then
    teams_reject_completion "Failed to set nurseDone in state. Drone dispatch depends on this flag. Retry."
    exit 2
  fi

  # Nurse completion accepted — drone task is blockedBy nurse and will start next
  return 0
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

  webhook_phase_event "A5" "completed" || true

  # Check pipeline type
  local pipeline
  pipeline=$(state_get '.pipeline // "swarm"')

  if [[ "$pipeline" == "pswarm" ]]; then
    # pswarm: check if more runs are needed
    local pswarm_run
    pswarm_run=$(state_get '.pswarmRun // 1')
    pswarm_run=$(require_int "$pswarm_run" "pswarmRun")
    local max_runs
    max_runs=$(state_get '.maxRuns // 50')
    max_runs=$(require_int "$max_runs" "maxRuns")

    if [[ "$pswarm_run" -lt "$max_runs" ]]; then
      # More runs available — reset for next pswarm run
      local next_run=$((pswarm_run + 1))

      if ! reset_phases_for_pswarm; then
        teams_log "ERROR: reset_phases_for_pswarm failed"
        if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Failed to reset phases for pswarm run boundary"'; then
          teams_reject_completion "Pswarm reset failed and could not block workflow."
          exit 2
        fi
        teams_log "Workflow blocked due to pswarm reset failure"
        return 0
      fi

      if ! cb_reset_for_run; then
        teams_log "WARNING: cb_reset_for_run failed — circuit breaker state may be stale"
      fi

      if ! update_state --argjson nextRun "$next_run" '
        .pswarmRun = $nextRun |
        .loop = 1 |
        .currentPhase = "A0" |
        .updatedAt = $ts |
        .needsPswarmReset = true
      '; then
        teams_reject_completion "A5 valid but failed to reset state for pswarm run ${next_run}. Retry."
        exit 2
      fi

      webhook_phase_event "A0" "started" || true
      teams_log "A5 complete, pswarm run ${pswarm_run} done, starting run ${next_run} (needsPswarmReset signal set)"
      return 0
    fi
  fi

  # Workflow complete (swarm/sswarm, or pswarm max runs reached)
  if ! update_state '
    .status = "complete" |
    .currentPhase = "DONE" |
    .updatedAt = $ts |
    .phases.A5.status = "complete" |
    .phases.A5.completedAt = $ts
  '; then
    teams_reject_completion "A5 valid but failed to mark workflow complete. Retry."
    exit 2
  fi

  webhook_workflow_event "completed" || true
  teams_log "A5 complete, workflow DONE"
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
  # IMPORTANT: A3 sub-patterns MUST appear before the generic A3* catch-all
  # (bash case uses first-match semantics).
  local phase=""
  case "$TASK_SUBJECT" in
    "A3 Guardian"*|"A3 guardian"*|"A3-guardian"*)
      phase="A3-guardian" ;;
    "A3 Worker"*|"A3 worker"*|"A3-worker"*)
      phase="A3-worker" ;;
    "A3 Sentinel"*|"A3 sentinel"*|"A3-sentinel"*)
      phase="A3-sentinel" ;;
    "A3 Simplifier"*|"A3 simplifier"*|"A3-simplifier"*)
      phase="A3-simplifier" ;;
    "A3 Review Arbiter"*|"A3 Arbiter"*|"A3 arbiter"*|"A3-arbiter"*)
      phase="A3-arbiter" ;;
    "A3 Review Fixer"*|"A3 review fixer"*|"A3-review-fixer"*|"A3 Review-Fixer"*)
      phase="A3-fixer" ;;
    "A3"*) phase="A3" ;;
    "A0 Forager"*|"A0 Cartographer"*) phase="A0-sub" ;;
    "A0 Explore Aggregator"*|"A0: Colony Exploration"*|"A0"*) phase="A0" ;;
    "A1 Architect"[[:space:]][0-9]*) phase="A1-sub" ;;
    "A1 Plan Arbiter"*) phase="A1" ;;
    "A1"*) phase="A1" ;;
    "A2 Blueprint Reviewer"[[:space:]][0-9]*) phase="A2-sub" ;;
    "A2 Review Lead"*) phase="A2" ;;
    "A2"*) phase="A2" ;;
    "A4"*) phase="A4" ;;
    "A5 Nurse"*|"A5 nurse"*|"A5-nurse"*) phase="A5-nurse" ;;
    "A5 Drone"*|"A5 drone"*|"A5-drone"*) phase="A5-drone" ;;
    "A5"*) phase="A5" ;;
    *)
      # Not an ants phase task, allow completion
      exit 0
      ;;
  esac

  local loop
  loop=$(state_get '.loop // 1')
  loop=$(require_int "$loop" "loop")
  local phases_dir=".agents/tmp/phases/loop-${loop}"

  case "$phase" in
    A0-sub)        teams_log "A0 sub-task completed (${TASK_SUBJECT}), awaiting aggregator"; return 0 ;;
    A0)            handle_a0 ;;
    A1-sub)        teams_log "A1 competing sub-task completed (${TASK_SUBJECT}), awaiting arbiter"; return 0 ;;
    A1)            handle_a1 "$phases_dir" ;;
    A2-sub)        teams_log "A2 competing sub-task completed (${TASK_SUBJECT}), awaiting lead"; return 0 ;;
    A2)            handle_a2 "$phases_dir" ;;
    A3-worker)     handle_a3_worker "$INPUT" "$TASK_SUBJECT" ;;
    A3-guardian)   handle_a3_guardian "$phases_dir" ;;
    A3-sentinel)   handle_a3_sentinel "$phases_dir" "$TASK_SUBJECT" ;;
    A3-simplifier) handle_a3_simplifier "$phases_dir" ;;
    A3-arbiter)    handle_a3_arbiter "$phases_dir" ;;
    A3-fixer)      handle_a3_fixer "$phases_dir" ;;
    A3)            handle_a3_aggregate "$phases_dir" ;;
    A4)            handle_a4 "$phases_dir" ;;
    A5-nurse)      handle_a5_nurse "$phases_dir" ;;
    A5-drone)      handle_a5 "$phases_dir" ;;
    A5)            handle_a5 "$phases_dir" ;;
  esac

  exit 0
}

main
