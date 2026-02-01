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
#   falling back to the default (10).
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
# group_issues_by_file <review_result_json> -- Group blocking issues by file.
#   Returns JSON array: [{"id":0,"files":["src/a.ts"],"issues":[...]}, ...]
#   Issues with locations in the same file are grouped together.
#   Single-file or no-location issues produce a single group.
# ---------------------------------------------------------------------------
group_issues_by_file() {
  local review_result="${1:?group_issues_by_file requires review result JSON}"

  echo "$review_result" | jq -c '
    def loc_file:
      .location
      | if (. // "") == "" then "unknown"
        else gsub(":[0-9]+(:[0-9]+)?$"; "")
        | if . == "" then "unknown" else . end
        end;
    [.blockingIssues | sort_by(loc_file) | group_by(loc_file)
    | to_entries[] | {
      id: .key,
      files: [.value[] | loc_file] | unique,
      issues: .value
    }]
  '
}

# ---------------------------------------------------------------------------
# start_fix_cycle <phase_id> <stage> <review_result_json> -- Set up a
#   review-fix cycle in state. Records the issues and attempt counter.
#   Groups issues by file for potential parallel dispatch.
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

  # Group issues by file for parallel fix dispatch
  local groups
  groups="$(group_issues_by_file "$review_result")"
  local group_count
  group_count="$(echo "$groups" | jq 'length')"
  local is_parallel="false"
  if [[ "$group_count" -gt 1 ]]; then
    is_parallel="true"
  fi

  # Write per-phase counter and reviewFix object with groups
  state_update "
    .stages[\"$stage\"].phases[\"$phase_id\"].fixAttempts = $next_attempt |
    .reviewFix = {
      \"phase\": \"$phase_id\",
      \"stage\": \"$stage\",
      \"attempt\": $next_attempt,
      \"maxAttempts\": $max_attempts,
      \"issues\": ($review_result | .blockingIssues),
      \"groups\": $groups,
      \"groupCount\": $group_count,
      \"pendingGroups\": $group_count,
      \"parallel\": $is_parallel
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

# ---------------------------------------------------------------------------
# get_max_stage_restarts -- Read the max stage restarts from state,
#   falling back to the default (3).
# ---------------------------------------------------------------------------
DEFAULT_MAX_STAGE_RESTARTS=3

get_max_stage_restarts() {
  local configured
  configured="$(state_get '.reviewPolicy.maxStageRestarts // empty')"

  if [[ -n "$configured" && "$configured" != "null" ]]; then
    echo "$configured"
  else
    echo "$DEFAULT_MAX_STAGE_RESTARTS"
  fi
}

# ---------------------------------------------------------------------------
# get_first_phase_of_stage <stage> -- Look up the first phase in the
#   schedule that belongs to the given stage.
#   Prints the phase ID (e.g., "2.1") or empty if stage not found.
# ---------------------------------------------------------------------------
get_first_phase_of_stage() {
  local stage="${1:?get_first_phase_of_stage requires a stage name}"

  read_state | jq -r --arg s "$stage" '
    [.schedule[] | select(.stage == $s)] | .[0].phase // empty
  '
}

# ---------------------------------------------------------------------------
# get_phase_outputs_for_stage <stage> -- Return output filenames for all
#   phases in the given stage, one per line.
# ---------------------------------------------------------------------------
get_phase_outputs_for_stage() {
  local stage="${1:?get_phase_outputs_for_stage requires a stage name}"

  local phases
  phases="$(read_state | jq -r --arg s "$stage" '
    [.schedule[] | select(.stage == $s) | .phase] | .[]
  ')"

  local phase output
  while IFS= read -r phase; do
    [[ -z "$phase" ]] && continue
    output="$(get_phase_output "$phase")"
    [[ -n "$output" ]] && echo "$output"
  done <<< "$phases"
}

# ---------------------------------------------------------------------------
# restart_stage <stage> <phase> <reason> -- Restart the given stage from
#   its first phase. Increments the stage restart counter, deletes all
#   phase output files for the stage, resets fix attempt counters, resets
#   currentPhase, and logs to restartHistory.
#
#   Returns 0 on success (restart initiated).
#   Returns 1 if max stage restarts exceeded (caller should block).
# ---------------------------------------------------------------------------
restart_stage() {
  local stage="${1:?restart_stage requires a stage name}"
  local phase="${2:?restart_stage requires the current phase ID}"
  local reason="${3:?restart_stage requires a reason}"

  local max_restarts
  max_restarts="$(get_max_stage_restarts)"

  # Read current restart count for this stage
  local current_restarts
  current_restarts="$(state_get ".stages[\"$stage\"].stageRestarts // 0")"

  if [[ "$current_restarts" -ge "$max_restarts" ]]; then
    return 1
  fi

  local next_restarts=$((current_restarts + 1))

  local first_phase
  first_phase="$(get_first_phase_of_stage "$stage")"

  if [[ -z "$first_phase" ]]; then
    echo "restart_stage: could not find first phase for stage $stage" >&2
    return 1
  fi

  # Delete all phase output files for this stage
  local output_file
  while IFS= read -r output_file; do
    [[ -z "$output_file" ]] && continue
    rm -f "$PHASES_DIR/$output_file"
  done <<< "$(get_phase_outputs_for_stage "$stage")"

  # Build jq expression to reset fix attempts for all phases in this stage
  # and update restart counter, currentPhase, and restartHistory
  local phase_ids
  phase_ids="$(read_state | jq -r --arg s "$stage" '
    [.schedule[] | select(.stage == $s) | .phase] | .[]
  ')"

  local reset_expr=""
  local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    reset_expr="${reset_expr} | .stages[\"$stage\"].phases[\"$p\"] = {}"
  done <<< "$phase_ids"

  state_update "
    .stages[\"$stage\"].stageRestarts = $next_restarts
    ${reset_expr}
    | .currentPhase = \"$first_phase\"
    | del(.reviewFix)
    | del(.supplementaryRun)
    | del(.coverageLoop)
    | .restartHistory = ((.restartHistory // []) + [{
        \"stage\": \"$stage\",
        \"fromPhase\": \"$phase\",
        \"toPhase\": \"$first_phase\",
        \"restart\": $next_restarts,
        \"maxRestarts\": $max_restarts,
        \"reason\": \"$reason\",
        \"at\": now | todate
      }])
  "

  return 0
}
