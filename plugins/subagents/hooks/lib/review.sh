#!/usr/bin/env bash
# review.sh -- Review output validation for blocking on issues.
# Requires state.sh to be sourced first (provides: read_state, state_get,
# phase_file_exists, PHASES_DIR).
set -euo pipefail

# ---------------------------------------------------------------------------
# Default minimum severity that blocks progression.
# Can be overridden in state.json via .reviewPolicy.minBlockSeverity
# Valid values: LOW, MEDIUM, HIGH
# ---------------------------------------------------------------------------
DEFAULT_MIN_BLOCK_SEVERITY="LOW"
DEFAULT_MAX_FIX_ATTEMPTS=10

# ---------------------------------------------------------------------------
# Severity ordering for comparison
# ---------------------------------------------------------------------------
severity_rank() {
  case "${1^^}" in
    LOW)    echo 1 ;;
    MEDIUM) echo 2 ;;
    HIGH)   echo 3 ;;
    *)      echo 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# is_review_phase <phase_id> -- Check if the given phase is a review phase
#   by looking up its type in the schedule.
#   Returns 0 (true) if type is "review", 1 (false) otherwise.
# ---------------------------------------------------------------------------
is_review_phase() {
  local phase_id="${1:?is_review_phase requires a phase ID}"

  local phase_type
  phase_type="$(read_state | jq -r --arg p "$phase_id" \
    '.schedule[] | select(.phase == $p) | .type // empty')"

  [[ "$phase_type" == "review" ]]
}

# ---------------------------------------------------------------------------
# get_min_block_severity -- Read the minimum blocking severity from state,
#   falling back to the default (LOW).
#   Checks state.json .reviewPolicy.minBlockSeverity
# ---------------------------------------------------------------------------
get_min_block_severity() {
  local configured
  configured="$(state_get '.reviewPolicy.minBlockSeverity // empty')"

  if [[ -n "$configured" ]]; then
    echo "${configured^^}"
  else
    echo "$DEFAULT_MIN_BLOCK_SEVERITY"
  fi
}

# ---------------------------------------------------------------------------
# validate_review_output <phase_id> -- For review phases, read the output
#   JSON and check if any issues meet or exceed the minimum blocking severity.
#
#   Prints a JSON result on stdout:
#     {"passed":true,"issueCount":0,"blockingIssues":[]}
#     {"passed":false,"issueCount":3,"blockingIssues":[...]}
#
#   Returns 0 always (caller reads the JSON to decide).
# ---------------------------------------------------------------------------
validate_review_output() {
  local phase_id="${1:?validate_review_output requires a phase ID}"

  local output_file
  output_file="$(get_phase_output "$phase_id")"

  local review_path="$PHASES_DIR/$output_file"

  if [[ ! -f "$review_path" ]]; then
    jq -n '{"passed":false,"issueCount":0,"blockingIssues":[],"error":"review output file not found"}'
    return 0
  fi

  local min_severity
  min_severity="$(get_min_block_severity)"
  local min_rank
  min_rank="$(severity_rank "$min_severity")"

  # Extract status and issues from the review JSON.
  # Handle both review schemas: status can be "approved"/"needs_revision"/"blocked"
  local review_status
  review_status="$(jq -r '.status // empty' "$review_path")"

  # If status is already "approved", pass regardless of residual issues
  if [[ "$review_status" == "approved" ]]; then
    jq -n '{"passed":true,"issueCount":0,"blockingIssues":[]}'
    return 0
  fi

  # Count issues at or above the minimum blocking severity
  local blocking_issues
  blocking_issues="$(jq -c --arg min "$min_severity" '
    def sev_rank:
      if . == "HIGH" then 3
      elif . == "MEDIUM" then 2
      elif . == "LOW" then 1
      else 0
      end;
    ($min | sev_rank) as $min_rank |
    [(.issues // [])[] | select((.severity | sev_rank) >= $min_rank)]
  ' "$review_path")"

  local issue_count
  issue_count="$(echo "$blocking_issues" | jq 'length')"

  if [[ "$issue_count" -gt 0 ]]; then
    jq -n --argjson count "$issue_count" --argjson issues "$blocking_issues" \
      '{"passed":false,"issueCount":$count,"blockingIssues":$issues}'
  else
    jq -n '{"passed":true,"issueCount":0,"blockingIssues":[]}'
  fi
}

# ---------------------------------------------------------------------------
# is_fix_cycle_active -- Check if a review-fix cycle is in progress.
#   Returns 0 (true) if state.reviewFix exists and is not null.
# ---------------------------------------------------------------------------
is_fix_cycle_active() {
  local fix_state
  fix_state="$(state_get '.reviewFix.phase // empty')"
  [[ -n "$fix_state" ]]
}

# ---------------------------------------------------------------------------
# get_max_fix_attempts -- Read the max fix attempts from state,
#   falling back to the default (3).
# ---------------------------------------------------------------------------
get_max_fix_attempts() {
  local configured
  configured="$(state_get '.reviewPolicy.maxFixAttempts // empty')"

  if [[ -n "$configured" && "$configured" != "null" ]]; then
    echo "$configured"
  else
    echo "$DEFAULT_MAX_FIX_ATTEMPTS"
  fi
}

# ---------------------------------------------------------------------------
# start_fix_cycle <phase_id> <stage> <review_result_json> -- Set up a
#   review-fix cycle in state. Records the issues and attempt counter.
#   Does NOT advance the phase — keeps currentPhase on the review phase.
# ---------------------------------------------------------------------------
start_fix_cycle() {
  local phase_id="${1:?start_fix_cycle requires a phase ID}"
  local stage="${2:?start_fix_cycle requires a stage}"
  local review_result="${3:?start_fix_cycle requires review result JSON}"

  # Read per-phase attempt counter (persists across fix cycles)
  local current_attempt
  current_attempt="$(state_get ".stages[\"$stage\"].phases[\"$phase_id\"].fixAttempts // 0")"
  local next_attempt=$((current_attempt + 1))

  local max_attempts
  max_attempts="$(get_max_fix_attempts)"

  # Write both per-phase counter and reviewFix object
  state_update "
    .stages[\"$stage\"].phases[\"$phase_id\"].fixAttempts = $next_attempt |
    .reviewFix = {
      \"phase\": \"$phase_id\",
      \"stage\": \"$stage\",
      \"attempt\": $next_attempt,
      \"maxAttempts\": $max_attempts,
      \"issues\": ($review_result | .blockingIssues)
    }
  "
}

# ---------------------------------------------------------------------------
# complete_fix_cycle -- Called when a fix agent completes. Removes the stale
#   review output file and clears reviewFix so the orchestrator re-dispatches
#   the review phase fresh.
# ---------------------------------------------------------------------------
complete_fix_cycle() {
  local fix_phase
  fix_phase="$(state_get '.reviewFix.phase')"

  # Remove the stale review output so the reviewer runs fresh
  local review_output
  review_output="$(get_phase_output "$fix_phase")"
  rm -f "$PHASES_DIR/$review_output"

  # Clear the fix cycle
  state_update 'del(.reviewFix)'
}
