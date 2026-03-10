#!/usr/bin/env bash
# on-task-completed.sh — TaskCompleted checkpoint gate for queen-driven workflow
# Fires when a teammate marks a task complete. Validates checkpoint files exist
# and are well-formed. The queen drives phase transitions via SendMessage —
# this hook only gates on checkpoint validity.
#
# Exit codes:
#   0 — accept task completion (checkpoint valid)
#   2 with stderr — reject completion (checkpoint missing/invalid, feedback provided)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/swarm.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
source "$SCRIPT_DIR/lib/teams.sh"
source "$SCRIPT_DIR/lib/webhook.sh"

check_ants_workflow

# Shutdown check — exit early if workflow is shutting down
shutdown_check

# ---------------------------------------------------------------------------
# Phase handlers — each validates checkpoint files (no phase transitions)
# ---------------------------------------------------------------------------

handle_a0() {
  # A0 output is top-level (not loop-scoped) — hardcoded path is intentional
  if [[ ! -f ".agents/tmp/phases/A0-explore.md" ]]; then
    teams_reject_completion "A0-explore.md not found. Explorer must write output to .agents/tmp/phases/A0-explore.md"
    exit 2
  fi

  cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2
  webhook_phase_event "A0" "completed" || true
  teams_log "A0 checkpoint valid"
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

  if [[ -f "${phases_dir}/A1-tasks.json" ]]; then
    if validate_json_file "${phases_dir}/A1-tasks.json" "A1-tasks.json"; then
      teams_log "A1-tasks.json found, A3 sub-tasks available for dynamic dispatch"
    else
      teams_log "WARNING: A1-tasks.json exists but is invalid JSON — A3 task pool will not be available"
    fi
  fi

  webhook_phase_event "A1" "completed" || true
  teams_log "A1 checkpoint valid"
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
  webhook_phase_event "A2" "completed" || true
  teams_log "A2 checkpoint valid"
}

handle_a3_worker() {
  local input="$1"
  local task_subject="$2"

  local has_pool
  has_pool=$(state_get '.taskPool // empty | if type == "array" and length > 0 then "yes" else "no" end')

  if [[ "$has_pool" == "yes" ]]; then
    source "$SCRIPT_DIR/lib/task-pool.sh"
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
  sentinel_name=$(printf '%s' "$task_subject" | grep -oiE 'sentinel-(correctness|security|perf|style|accessibility|observability|api-contracts|data-integrity)' | head -1 | tr '[:upper:]' '[:lower:]' || echo "")
  if [[ -z "$sentinel_name" ]]; then
    teams_reject_completion "Cannot extract sentinel name from task subject. Expected sentinel-correctness, sentinel-security, sentinel-perf, sentinel-style, sentinel-accessibility, sentinel-observability, sentinel-api-contracts, or sentinel-data-integrity."
    exit 2
  fi

  # Validate sentinel output JSON exists and is valid before accepting completion
  local sentinel_output_file
  sentinel_output_file="${phases_dir}/A3-review.${sentinel_name}.json"
  if [[ ! -f "$sentinel_output_file" ]]; then
    teams_reject_completion "${sentinel_name} output file not found at ${sentinel_output_file}. Sentinel must write review output before completing."
    exit 2
  fi
  if ! validate_json_file "$sentinel_output_file" "A3-review.${sentinel_name}.json"; then
    teams_reject_completion "${sentinel_name} output file is invalid JSON: ${sentinel_output_file}"
    exit 2
  fi

  local marker_file
  marker_file="${phases_dir}/.${sentinel_name}.done"
  touch "$marker_file"
  teams_log "${sentinel_name} completed, marker written to ${marker_file}"

  # Check if all eight sentinels are done
  local all_done=true
  local s
  for s in correctness security perf style accessibility observability api-contracts data-integrity; do
    [[ -f "${phases_dir}/.sentinel-${s}.done" ]] || { all_done=false; break; }
  done
  if [[ "$all_done" == "true" ]]; then
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
  if ! arbiter_meta=$(jq -r '{verdict: (.summary.verdict // ""), critical_count: ([.issues[]? | select(.severity == "critical")] | length)} | "\(.verdict)\t\(.critical_count)"' "${phases_dir}/A3-quality.json" 2>/dev/null); then
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
    # Reject completion so A3 does not advance with critical issues
    teams_reject_completion "Arbiter found ${critical_count} critical issues. Fix and resubmit."
    exit 2
  else
    cb_record_success || echo "WARNING: Failed to reset circuit breaker counter" >&2
  fi

  teams_log "A3 arbiter checkpoint valid"
}

# ─────────────────────────────────────────────────────────────
# LEGACY: Agent Teams mode only (not called in swarm/pswarm path)
# This function handles A3 result aggregation in the Agent Teams delegate
# pipeline where TaskCompleted hooks validate worker output. In the current
# orchestrator-driven swarm/pswarm path, A3 aggregation is performed by
# the review-arbiter agent dispatched directly by the orchestrator command.
# Kept for potential Agent Teams reactivation.
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
  teams_log "A3 checkpoint valid (build + quality)"
}

handle_a4() {
  local phases_dir="$1"

  if [[ ! -f "${phases_dir}/A4-queen-verdict.json" ]]; then
    teams_reject_completion "A4-queen-verdict.json not found. Queen must write verdict before A4 can complete."
    exit 2
  fi
  if ! validate_json_file "${phases_dir}/A4-queen-verdict.json" "A4-queen-verdict.json"; then
    teams_reject_completion "A4-queen-verdict.json is invalid JSON."
    exit 2
  fi

  # Validate required fields: verdict must exist and be a recognized value
  local verdict_value
  verdict_value=$(jq -r '.verdict // empty' "${phases_dir}/A4-queen-verdict.json" 2>/dev/null || echo "")
  if [[ -z "$verdict_value" ]]; then
    teams_reject_completion "A4-queen-verdict.json missing required 'verdict' field."
    exit 2
  fi
  if [[ "$verdict_value" != "clean" && "$verdict_value" != "issues_found" ]]; then
    teams_reject_completion "A4-queen-verdict.json has unrecognized verdict '${verdict_value}'. Expected 'clean' or 'issues_found'."
    exit 2
  fi

  # Validate evidence array exists (queen must provide reasoning)
  if ! jq -e 'has("evidence") and (.evidence | type == "array") and (.evidence | length > 0)' "${phases_dir}/A4-queen-verdict.json" >/dev/null 2>&1; then
    teams_reject_completion "A4-queen-verdict.json missing or empty 'evidence' array. Queen must provide reasoning for the verdict."
    exit 2
  fi

  webhook_phase_event "A4" "completed" || true
  teams_log "A4 checkpoint valid (verdict: ${verdict_value})"
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
  teams_log "A5 checkpoint valid"
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
  loop=$(require_int "$loop" "loop")
  local phases_dir=".agents/tmp/phases/loop-${loop}"

  case "$phase" in
    A0)          handle_a0 ;;
    A1)          handle_a1 "$phases_dir" ;;
    A2)          handle_a2 "$phases_dir" ;;
    A3-worker)   handle_a3_worker "$INPUT" "$TASK_SUBJECT" ;;
    A3-guardian) handle_a3_guardian ;;
    A3-sentinel) handle_a3_sentinel "$phases_dir" "$TASK_SUBJECT" ;;
    A3-arbiter)  handle_a3_arbiter "$phases_dir" ;;
    A3)          handle_a3_aggregate "$phases_dir" ;;
    A4)          handle_a4 "$phases_dir" ;;
    A5)          handle_a5 "$phases_dir" ;;
  esac

  exit 0
}

main
