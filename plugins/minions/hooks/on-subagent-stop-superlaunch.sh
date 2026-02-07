#!/usr/bin/env bash
# on-subagent-stop-superlaunch.sh — SubagentStop hook for the superlaunch pipeline.
# Invoked via exec from on-subagent-stop.sh when pipeline == "superlaunch".
# Validates output, advances state, handles review-fix cycles and coverage loops.
#
# Receives agent type via SL_AGENT_TYPE env var (stdin already consumed by parent hook).
#
# Exit codes:
#   0 silent — allow (supplementary agent, non-superlaunch agent, or lock contention)
#   0 with JSON — provide context to orchestrator (block notice on workflow blocked)
#   2 with stderr — block, output file missing/corrupt/invalid

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/superlaunch.sh"

# stdin was already consumed and validated by the parent hook — read from env
AGENT_TYPE="${SL_AGENT_TYPE:?on-subagent-stop-superlaunch.sh requires SL_AGENT_TYPE}"

CURRENT_PHASE=$(state_get '.currentPhase' --required)
PHASES_DIR=".agents/tmp/phases"
COVERAGE_MAX_ITERATIONS=20
PHASE_LOCK_STALE_SECONDS=120
PHASE_LOCK_DIR=""

emit_block_notice() {
  local reason="$1"
  local jq_out
  if ! jq_out=$(jq -n --arg reason "$reason" '{"decision":"block","reason":$reason}' 2>&1); then
    echo "ERROR: Failed to generate block notice JSON: $jq_out" >&2
    exit 2
  fi
  echo "$jq_out"
}

lock_dir_mtime_epoch() {
  local lock_dir="$1"
  local mtime
  if mtime=$(stat -c %Y "$lock_dir" 2>/dev/null); then
    echo "$mtime"
    return 0
  fi
  if mtime=$(stat -f %m "$lock_dir" 2>/dev/null); then
    echo "$mtime"
    return 0
  fi
  # Cannot determine mtime — treat lock as non-stale (fail-closed)
  return 1
}

cleanup_phase_lock() {
  if [[ -n "${PHASE_LOCK_DIR:-}" ]]; then
    rm -rf "$PHASE_LOCK_DIR" 2>/dev/null || true
    PHASE_LOCK_DIR=""
  fi
}

acquire_phase_lock() {
  local phase="$1"
  local lock_dir
  lock_dir="${PHASES_DIR}/.sl-${phase}-advance.lock"

  if mkdir "$lock_dir" 2>/dev/null; then
    PHASE_LOCK_DIR="$lock_dir"
    trap cleanup_phase_lock EXIT
    return 0
  fi

  if [[ -d "$lock_dir" ]]; then
    local lock_age now mtime
    now=$(date +%s)
    if ! mtime="$(lock_dir_mtime_epoch "$lock_dir")"; then
      # Cannot determine lock age — treat as non-stale (fail-closed)
      return 1
    fi
    lock_age=$((now - mtime))
    if [[ "$lock_age" -gt "$PHASE_LOCK_STALE_SECONDS" ]]; then
      echo "WARNING: Removing stale superlaunch phase lock $lock_dir (age: ${lock_age}s)." >&2
      rm -rf "$lock_dir" 2>/dev/null || true
      if mkdir "$lock_dir" 2>/dev/null; then
        PHASE_LOCK_DIR="$lock_dir"
        trap cleanup_phase_lock EXIT
        return 0
      fi
    fi
  fi

  # Another hook instance is already processing this phase.
  return 1
}

guard_locked_phase_context() {
  local expected_phase="$1"
  local live_phase live_status

  live_phase="$(state_get '.currentPhase // empty')"
  live_status="$(state_get '.status // empty')"

  # If another hook already advanced/blocked/completed, this invocation is stale.
  if [[ "$live_status" != "in_progress" || "$live_phase" != "$expected_phase" ]]; then
    return 1
  fi

  return 0
}

# Skip supplementary agents — they don't drive phase advancement
if is_sl_supplementary_agent "$AGENT_TYPE"; then
  exit 0
fi
# Aggregator agents drive phase advancement after validating their output file.
if is_sl_aggregator_agent "$AGENT_TYPE"; then
  if ! acquire_phase_lock "$CURRENT_PHASE"; then
    echo "INFO: Phase lock for $CURRENT_PHASE held by another hook instance; skipping." >&2
    exit 0
  fi
  if ! guard_locked_phase_context "$CURRENT_PHASE"; then
    echo "INFO: Phase $CURRENT_PHASE already advanced or workflow no longer in_progress; skipping." >&2
    exit 0
  fi

  # Aggregator wrote the phase output file. Check if we should advance.
  local_output=$(get_sl_phase_output "$CURRENT_PHASE")
  if [[ -z "$local_output" ]]; then
    echo "ERROR: No phase output file configured for aggregator phase $CURRENT_PHASE." >&2
    exit 2
  fi
  if [[ ! -f "${PHASES_DIR}/${local_output}" ]]; then
    echo "ERROR: Aggregator completed but ${local_output} not found." >&2
    exit 2
  fi
  if [[ "$local_output" == *.json ]] && ! validate_json_file "${PHASES_DIR}/${local_output}" "$local_output"; then
    echo "ERROR: ${local_output} is invalid JSON." >&2
    exit 2
  fi
  if [[ "$local_output" == *.md ]] && [[ ! -s "${PHASES_DIR}/${local_output}" ]]; then
    echo "ERROR: ${local_output} is empty." >&2
    exit 2
  fi

  # Check if we're crossing a stage gate
  local_current_stage=$(state_get '.currentStage // empty')
  local_next_json=$(get_sl_next_phase "$CURRENT_PHASE")

  if [[ "$local_next_json" == "null" ]]; then
    # Last phase — workflow complete
    if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts'; then
      echo "ERROR: Failed to mark superlaunch workflow as complete." >&2
      exit 2
    fi
  else
    local_next_phase=$(echo "$local_next_json" | jq -r '.phase')
    local_next_stage=$(echo "$local_next_json" | jq -r '.stage')
    if [[ -z "$local_next_phase" || "$local_next_phase" == "null" || -z "$local_next_stage" || "$local_next_stage" == "null" ]]; then
      echo "ERROR: Next phase entry is malformed (phase=$local_next_phase, stage=$local_next_stage)." >&2
      exit 2
    fi

    # Check gate if crossing stages
    if [[ "$local_next_stage" != "$local_current_stage" ]]; then
      local_gate_name="${local_current_stage}->${local_next_stage}"
      if ! validate_sl_gate "$local_gate_name" "$PHASES_DIR"; then
        echo "ERROR: Gate $local_gate_name failed. Cannot advance to $local_next_stage." >&2
        exit 2
      fi
      # Atomic stage-transition update to avoid partially updated state.
      if ! update_state --arg phase "$local_next_phase" --arg nextStage "$local_next_stage" --arg currentStage "$local_current_stage" \
        '.stages[$currentStage].status = "complete" | .currentPhase = $phase | .currentStage = $nextStage | .updatedAt = $ts'; then
        echo "ERROR: Failed to transition from stage $local_current_stage to $local_next_stage." >&2
        exit 2
      fi
    else
      if ! update_state --arg phase "$local_next_phase" --arg stage "$local_next_stage" \
        '.currentPhase = $phase | .currentStage = $stage | .updatedAt = $ts'; then
        echo "ERROR: Failed to advance from $CURRENT_PHASE to $local_next_phase." >&2
        exit 2
      fi
    fi
  fi
  exit 0
fi

# Check if this agent is expected in the current phase
if ! is_sl_agent_allowed "$AGENT_TYPE" "$CURRENT_PHASE"; then
  # Not a superlaunch agent or not expected — silently allow
  exit 0
fi

# Check phase output file exists
OUTPUT_FILE=$(get_sl_phase_output "$CURRENT_PHASE")
if [[ -z "$OUTPUT_FILE" ]]; then
  exit 0
fi

# For dispatch phases with aggregators, the output is written by the aggregator, not the primary agent
if sl_phase_has_aggregator "$CURRENT_PHASE"; then
  # Primary agent done — aggregator still needs to run. Don't advance yet.
  exit 0
fi

if ! acquire_phase_lock "$CURRENT_PHASE"; then
  echo "INFO: Phase lock for $CURRENT_PHASE held by another hook instance; skipping." >&2
  exit 0
fi
if ! guard_locked_phase_context "$CURRENT_PHASE"; then
  echo "INFO: Phase $CURRENT_PHASE already advanced or workflow no longer in_progress; skipping." >&2
  exit 0
fi

# For review phases, handle verdict
PHASE_TYPE=$(jq -r --arg p "$CURRENT_PHASE" '.schedule[] | select(.phase == $p) | .type // empty' "$STATE_FILE") || {
  echo "ERROR: Failed to extract phase type for $CURRENT_PHASE from state schedule." >&2
  exit 2
}
if [[ -z "$PHASE_TYPE" ]]; then
  echo "ERROR: Phase $CURRENT_PHASE not found in state schedule or has no type." >&2
  exit 2
fi

if [[ "$PHASE_TYPE" == "review" ]]; then
  if [[ ! -f "${PHASES_DIR}/${OUTPUT_FILE}" ]]; then
    echo "ERROR: Review agent completed but ${OUTPUT_FILE} not found." >&2
    exit 2
  fi
  if ! validate_json_file "${PHASES_DIR}/${OUTPUT_FILE}" "$OUTPUT_FILE"; then
    echo "ERROR: ${OUTPUT_FILE} is invalid JSON." >&2
    exit 2
  fi

  # Read review status
  REVIEW_STATUS=$(jq -r '.status // empty' "${PHASES_DIR}/${OUTPUT_FILE}")

  case "$REVIEW_STATUS" in
    approved|needs_revision|needs_coverage|blocked) ;;
    *)
      echo "ERROR: ${OUTPUT_FILE} has unexpected status '${REVIEW_STATUS}'. Expected approved, needs_revision, needs_coverage, or blocked." >&2
      exit 2
      ;;
  esac

  REVIEW_ISSUES="$(jq -r 'if (.issues? | type) == "array" then (.issues | length) else 0 end' "${PHASES_DIR}/${OUTPUT_FILE}")"
  if ! [[ "$REVIEW_ISSUES" =~ ^[0-9]+$ ]]; then
    echo "ERROR: ${OUTPUT_FILE} has invalid issues[] structure; expected an array." >&2
    exit 2
  fi
  if [[ "$REVIEW_STATUS" == "approved" && "$REVIEW_ISSUES" -gt 0 ]]; then
    echo "WARNING: ${OUTPUT_FILE} reported status=approved with ${REVIEW_ISSUES} issues. Forcing needs_revision." >&2
    REVIEW_STATUS="needs_revision"
  fi

  if [[ "$REVIEW_STATUS" == "needs_coverage" ]]; then
    if [[ "$CURRENT_PHASE" != "S11" ]]; then
      echo "ERROR: ${OUTPUT_FILE} returned needs_coverage outside phase S11." >&2
      exit 2
    fi

    COVERAGE_THRESHOLD="$(state_get '.coverageThreshold // 90')"
    COVERAGE_THRESHOLD="$(require_int "$COVERAGE_THRESHOLD" "coverageThreshold")"
    COVERAGE_CURRENT="$(jq -r 'if (.coverage.current? | type) == "number" then (.coverage.current | tostring) else "" end' "${PHASES_DIR}/${OUTPUT_FILE}")"
    COVERAGE_MET="$(jq -r 'if (.coverage.met? | type) == "boolean" then (.coverage.met | tostring) else "" end' "${PHASES_DIR}/${OUTPUT_FILE}")"
    if [[ -z "$COVERAGE_CURRENT" || ( "$COVERAGE_MET" != "true" && "$COVERAGE_MET" != "false" ) ]]; then
      echo "ERROR: ${OUTPUT_FILE} must include coverage.current (number) and coverage.met (boolean) for S11." >&2
      exit 2
    fi
    if [[ "$COVERAGE_MET" == "true" ]]; then
      echo "ERROR: ${OUTPUT_FILE} returned needs_coverage while coverage.met is true." >&2
      exit 2
    fi
    # Cross-check: if coverage is actually at or above threshold, treat as approved
    if ! COVERAGE_AT_OR_ABOVE="$(jq -r --argjson threshold "$COVERAGE_THRESHOLD" '.coverage.current >= $threshold' "${PHASES_DIR}/${OUTPUT_FILE}" 2>&1)"; then
      echo "WARNING: Failed to cross-check coverage against threshold: $COVERAGE_AT_OR_ABOVE. Assuming not met." >&2
      COVERAGE_AT_OR_ABOVE="false"
    fi
    if [[ "$COVERAGE_AT_OR_ABOVE" == "true" ]]; then
      echo "WARNING: ${OUTPUT_FILE} reported needs_coverage but coverage.current >= ${COVERAGE_THRESHOLD}. Treating as approved." >&2
      REVIEW_STATUS="approved"
    else
      COVERAGE_ITER=$(state_get '.coverageLoop.iteration // 0')
      if [[ "$COVERAGE_ITER" -lt "$COVERAGE_MAX_ITERATIONS" ]]; then
        # Loop back to S9
        if ! update_state --argjson iter "$((COVERAGE_ITER + 1))" \
          '.currentPhase = "S9" | .coverageLoop.iteration = $iter | .updatedAt = $ts'; then
          echo "ERROR: Failed to loop back to S9 for coverage." >&2
          exit 2
        fi
        # Delete stale S9-S11 output for clean re-run
        rm -f "${PHASES_DIR}/S9-test-dev.json" "${PHASES_DIR}/S10-test-dev-review.json" "${PHASES_DIR}/S11-test-review.json" 2>/dev/null || true
        exit 0
      fi

      if ! update_state --argjson max "$COVERAGE_MAX_ITERATIONS" \
        '.status = "blocked" | .failure = ("Coverage threshold not met after " + ($max | tostring) + " iterations") | .updatedAt = $ts'; then
        echo "ERROR: Failed to block workflow after max coverage loops." >&2
        exit 2
      fi
      emit_block_notice "WORKFLOW BLOCKED: Coverage threshold not met after ${COVERAGE_MAX_ITERATIONS} iterations."
      exit 0
    fi
  fi

  if [[ "$REVIEW_STATUS" == "needs_revision" || "$REVIEW_STATUS" == "blocked" ]]; then
    # Check fix attempt limits
    FIX_ATTEMPTS=$(state_get ".fixAttempts[\"$CURRENT_PHASE\"] // 0")
    MAX_FIX=$(state_get '.reviewPolicy.maxFixAttempts // 10')

    if [[ "$FIX_ATTEMPTS" -ge "$MAX_FIX" ]]; then
      # Check stage restart limits
      CURRENT_STAGE=$(state_get '.currentStage // empty')
      RESTART_COUNT=$(state_get ".stages[\"$CURRENT_STAGE\"].restartCount // 0")
      MAX_RESTARTS=$(state_get '.reviewPolicy.maxStageRestarts // 3')

      if [[ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]]; then
        # Both tiers exhausted — block
        if ! update_state --arg phase "$CURRENT_PHASE" --arg stage "$CURRENT_STAGE" --argjson maxFix "$MAX_FIX" --argjson maxRestarts "$MAX_RESTARTS" \
          '.status = "blocked"
          | .failure = ("Review gate failed in " + $phase + " (" + $stage + "): reached max fix attempts (" + ($maxFix | tostring) + ") and max stage restarts (" + ($maxRestarts | tostring) + ")")
          | .updatedAt = $ts'; then
          echo "ERROR: Failed to set blocked status." >&2
          exit 2
        fi
        emit_block_notice "WORKFLOW BLOCKED: ${CURRENT_PHASE} review exceeded max fix attempts (${MAX_FIX}) and max stage restarts (${MAX_RESTARTS})."
        exit 0
      fi

      # Restart stage from first phase
      FIRST_PHASE=$(jq -r --arg s "$CURRENT_STAGE" '.stages[$s].phases[0] // empty' "$STATE_FILE")
      if [[ -z "$FIRST_PHASE" ]]; then
        echo "ERROR: Cannot restart stage $CURRENT_STAGE — no phases defined in state." >&2
        exit 2
      fi
      if ! update_state --arg phase "$FIRST_PHASE" --arg stage "$CURRENT_STAGE" --argjson rc "$((RESTART_COUNT + 1))" \
        '.currentPhase = $phase
        | .currentStage = $stage
        | .updatedAt = $ts
        | .stages[$stage].restartCount = $rc
        | .fixAttempts = {}
        | .coverageLoop.iteration = 0
        | del(.reviewFix)
        | del(.supplementaryRun)'; then
        echo "ERROR: Failed to restart stage $CURRENT_STAGE." >&2
        exit 2
      fi
      # Remove stale outputs from the restarted stage to avoid false validation.
      STAGE_PHASES=$(jq -r --arg s "$CURRENT_STAGE" '.stages[$s].phases[]? // empty' "$STATE_FILE")
      if [[ -n "$STAGE_PHASES" ]]; then
        while IFS= read -r phase; do
          [[ -z "$phase" ]] && continue
          output_file=$(get_sl_phase_output "$phase")
          [[ -z "$output_file" ]] && continue
          rm -f "${PHASES_DIR}/${output_file}" 2>/dev/null || true
          case "$phase" in
            S0) rm -f "${PHASES_DIR}/S0-explore."*.tmp 2>/dev/null || true ;;
            S2) rm -f "${PHASES_DIR}/S2-plan."*.tmp 2>/dev/null || true ;;
          esac
        done <<< "$STAGE_PHASES"
      fi
    else
      # Start fix cycle — set reviewFix and supplementaryRun so re-review dispatches supplementary agents
      if ! update_state --arg phase "$CURRENT_PHASE" --argjson attempts "$((FIX_ATTEMPTS + 1))" \
        '.reviewFix = {"phase": $phase} | .fixAttempts[$phase] = $attempts | .supplementaryRun[$phase] = true | .updatedAt = $ts'; then
        echo "ERROR: Failed to start review-fix cycle." >&2
        exit 2
      fi
    fi
    exit 0
  fi

  # Review approved — but for S11, cross-validate coverage.met against threshold before advancing
  if [[ "$CURRENT_PHASE" == "S11" ]]; then
    COVERAGE_THRESHOLD="$(state_get '.coverageThreshold // 90')"
    COVERAGE_THRESHOLD="$(require_int "$COVERAGE_THRESHOLD" "coverageThreshold")"
    COVERAGE_CURRENT="$(jq -r 'if (.coverage.current? | type) == "number" then (.coverage.current | tostring) else "" end' "${PHASES_DIR}/${OUTPUT_FILE}")"
    COVERAGE_MET="$(jq -r 'if (.coverage.met? | type) == "boolean" then (.coverage.met | tostring) else "" end' "${PHASES_DIR}/${OUTPUT_FILE}")"
    if [[ -z "$COVERAGE_CURRENT" || ( "$COVERAGE_MET" != "true" && "$COVERAGE_MET" != "false" ) ]]; then
      echo "ERROR: ${OUTPUT_FILE} must include coverage.current (number) and coverage.met (boolean) for S11." >&2
      exit 2
    fi
    if ! COVERAGE_AT_OR_ABOVE="$(jq -r --argjson threshold "$COVERAGE_THRESHOLD" '.coverage.current >= $threshold' "${PHASES_DIR}/${OUTPUT_FILE}" 2>&1)"; then
      echo "WARNING: Failed to cross-check coverage against threshold: $COVERAGE_AT_OR_ABOVE. Assuming not met." >&2
      COVERAGE_AT_OR_ABOVE="false"
    fi
    if [[ "$COVERAGE_MET" == "true" && "$COVERAGE_AT_OR_ABOVE" != "true" ]]; then
      echo "WARNING: ${OUTPUT_FILE} has coverage.met=true below threshold ${COVERAGE_THRESHOLD}. Forcing loopback." >&2
      COVERAGE_MET="false"
    fi
    if [[ "$COVERAGE_MET" == "false" ]]; then
      COVERAGE_ITER=$(state_get '.coverageLoop.iteration // 0')
      if [[ "$COVERAGE_ITER" -lt "$COVERAGE_MAX_ITERATIONS" ]]; then
        # Loop back to S9
        if ! update_state --argjson iter "$((COVERAGE_ITER + 1))" \
          '.currentPhase = "S9" | .coverageLoop.iteration = $iter | .updatedAt = $ts'; then
          echo "ERROR: Failed to loop back to S9 for coverage." >&2
          exit 2
        fi
        # Delete stale S9-S11 output for clean re-run
        rm -f "${PHASES_DIR}/S9-test-dev.json" "${PHASES_DIR}/S10-test-dev-review.json" "${PHASES_DIR}/S11-test-review.json" 2>/dev/null || true
        exit 0
      fi

      if ! update_state --argjson max "$COVERAGE_MAX_ITERATIONS" \
        '.status = "blocked" | .failure = ("Coverage threshold not met after " + ($max | tostring) + " iterations") | .updatedAt = $ts'; then
        echo "ERROR: Failed to block workflow after max coverage loops." >&2
        exit 2
      fi
      emit_block_notice "WORKFLOW BLOCKED: Coverage threshold not met after ${COVERAGE_MAX_ITERATIONS} iterations."
      exit 0
    fi
  fi
else
  # Non-review phase — validate output exists
  if [[ ! -f "${PHASES_DIR}/${OUTPUT_FILE}" ]]; then
    echo "ERROR: Agent completed but ${OUTPUT_FILE} not found." >&2
    exit 2
  fi
  # Validate JSON outputs
  if [[ "$OUTPUT_FILE" == *.json ]]; then
    if ! validate_json_file "${PHASES_DIR}/${OUTPUT_FILE}" "$OUTPUT_FILE"; then
      echo "ERROR: ${OUTPUT_FILE} is invalid JSON." >&2
      exit 2
    fi
  elif [[ "$OUTPUT_FILE" == *.md ]] && [[ ! -s "${PHASES_DIR}/${OUTPUT_FILE}" ]]; then
    echo "ERROR: ${OUTPUT_FILE} is empty." >&2
    exit 2
  fi
fi

# Clear reviewFix if set (fix cycle completed successfully)
if state_get '.reviewFix // empty' | grep -q .; then
  if ! update_state 'del(.reviewFix) | .updatedAt = $ts'; then
    echo "WARNING: Failed to clear reviewFix from state. Fix cycle may repeat unnecessarily." >&2
  fi
fi

# Advance to next phase
CURRENT_STAGE=$(state_get '.currentStage // empty')
NEXT_JSON=$(get_sl_next_phase "$CURRENT_PHASE")

if [[ "$NEXT_JSON" == "null" ]]; then
  # Last phase — workflow complete
  if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts'; then
    echo "ERROR: Failed to mark superlaunch workflow as complete." >&2
    exit 2
  fi
else
  NEXT_PHASE=$(echo "$NEXT_JSON" | jq -r '.phase')
  NEXT_STAGE=$(echo "$NEXT_JSON" | jq -r '.stage')
  if [[ -z "$NEXT_PHASE" || "$NEXT_PHASE" == "null" || -z "$NEXT_STAGE" || "$NEXT_STAGE" == "null" ]]; then
    echo "ERROR: Next phase entry is malformed (phase=$NEXT_PHASE, stage=$NEXT_STAGE)." >&2
    exit 2
  fi

  # Check gate if crossing stages
  if [[ "$NEXT_STAGE" != "$CURRENT_STAGE" ]]; then
    GATE_NAME="${CURRENT_STAGE}->${NEXT_STAGE}"
    if ! validate_sl_gate "$GATE_NAME" "$PHASES_DIR"; then
      echo "ERROR: Gate $GATE_NAME failed. Cannot advance to $NEXT_STAGE." >&2
      exit 2
    fi
    # Atomic stage-transition update to avoid partially updated state.
    if ! update_state --arg phase "$NEXT_PHASE" --arg nextStage "$NEXT_STAGE" --arg currentStage "$CURRENT_STAGE" \
      '.stages[$currentStage].status = "complete" | .currentPhase = $phase | .currentStage = $nextStage | .updatedAt = $ts'; then
      echo "ERROR: Failed to transition from stage $CURRENT_STAGE to $NEXT_STAGE." >&2
      exit 2
    fi
  else
    if ! update_state --arg phase "$NEXT_PHASE" --arg stage "$NEXT_STAGE" \
      '.currentPhase = $phase | .currentStage = $stage | .updatedAt = $ts'; then
      echo "ERROR: Failed to advance from $CURRENT_PHASE to $NEXT_PHASE." >&2
      exit 2
    fi
  fi
fi

exit 0
