#!/usr/bin/env bash
# on-subagent-stop-superlaunch.sh — SubagentStop hook for the superlaunch pipeline.
# Invoked via exec from on-subagent-stop.sh when pipeline == "superlaunch".
# Validates output, advances state, handles review-fix cycles and coverage loops.
#
# Receives agent type via SL_AGENT_TYPE env var (stdin already consumed by parent hook).
#
# Exit codes:
#   0 silent — allow (supplementary agent, aggregator, or non-superlaunch agent)
#   0 with JSON — provide context to orchestrator
#   2 with stderr — block, output file missing or corrupt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/superlaunch.sh"

# stdin was already consumed and validated by the parent hook — read from env
AGENT_TYPE="${SL_AGENT_TYPE:?on-subagent-stop-superlaunch.sh requires SL_AGENT_TYPE}"

CURRENT_PHASE=$(state_get '.currentPhase' --required)
PHASES_DIR=".agents/tmp/phases"

# Skip supplementary and aggregator agents — they don't drive phase advancement
if is_sl_supplementary_agent "$AGENT_TYPE"; then
  exit 0
fi
if is_sl_aggregator_agent "$AGENT_TYPE"; then
  # Aggregator wrote the phase output file. Check if we should advance.
  local_output=$(get_sl_phase_output "$CURRENT_PHASE")
  if [[ -n "$local_output" && -f "${PHASES_DIR}/${local_output}" ]]; then
    if validate_json_file "${PHASES_DIR}/${local_output}" "$local_output" 2>/dev/null || [[ "$local_output" == *.md ]]; then
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

        # Check gate if crossing stages
        if [[ "$local_next_stage" != "$local_current_stage" ]]; then
          local_gate_name="${local_current_stage}->${local_next_stage}"
          if ! validate_sl_gate "$local_gate_name" "$PHASES_DIR"; then
            echo "ERROR: Gate $local_gate_name failed. Cannot advance to $local_next_stage." >&2
            exit 2
          fi
        fi

        if ! update_state --arg phase "$local_next_phase" --arg stage "$local_next_stage" \
          '.currentPhase = $phase | .currentStage = $stage | .updatedAt = $ts'; then
          echo "ERROR: Failed to advance from $CURRENT_PHASE to $local_next_phase." >&2
          exit 2
        fi
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

# For review phases, handle verdict
PHASE_TYPE=$(jq -r --arg p "$CURRENT_PHASE" '.schedule[] | select(.phase == $p) | .type // empty' "$STATE_FILE" 2>/dev/null || echo "")

if [[ "$PHASE_TYPE" == "review" ]]; then
  if [[ ! -f "${PHASES_DIR}/${OUTPUT_FILE}" ]]; then
    echo "Review agent completed but ${OUTPUT_FILE} not found." >&2
    exit 2
  fi
  if ! validate_json_file "${PHASES_DIR}/${OUTPUT_FILE}" "$OUTPUT_FILE"; then
    echo "ERROR: ${OUTPUT_FILE} is invalid JSON." >&2
    exit 2
  fi

  # Read review status
  REVIEW_STATUS=$(jq -r '.status // empty' "${PHASES_DIR}/${OUTPUT_FILE}" 2>/dev/null || echo "")

  if [[ "$REVIEW_STATUS" == "needs_revision" || "$REVIEW_STATUS" == "blocked" ]]; then
    # Check fix attempt limits
    FIX_ATTEMPTS=$(state_get ".fixAttempts[\"$CURRENT_PHASE\"] // 0" 2>/dev/null || echo "0")
    MAX_FIX=$(state_get '.reviewPolicy.maxFixAttempts // 10' 2>/dev/null || echo "10")

    if [[ "$FIX_ATTEMPTS" -ge "$MAX_FIX" ]]; then
      # Check stage restart limits
      CURRENT_STAGE=$(state_get '.currentStage // empty')
      RESTART_COUNT=$(state_get ".stages[\"$CURRENT_STAGE\"].restartCount // 0" 2>/dev/null || echo "0")
      MAX_RESTARTS=$(state_get '.reviewPolicy.maxStageRestarts // 3' 2>/dev/null || echo "3")

      if [[ "$RESTART_COUNT" -ge "$MAX_RESTARTS" ]]; then
        # Both tiers exhausted — block
        if ! update_state '.status = "blocked" | .updatedAt = $ts'; then
          echo "ERROR: Failed to set blocked status." >&2
          exit 2
        fi
        exit 0
      fi

      # Restart stage from first phase
      FIRST_PHASE=$(jq -r --arg s "$CURRENT_STAGE" '.stages[$s].phases[0] // empty' "$STATE_FILE" 2>/dev/null || echo "")
      if [[ -n "$FIRST_PHASE" ]]; then
        if ! update_state --arg phase "$FIRST_PHASE" --arg stage "$CURRENT_STAGE" --argjson rc "$((RESTART_COUNT + 1))" \
          '.currentPhase = $phase | .currentStage = $stage | .updatedAt = $ts | .stages[$stage].restartCount = $rc | .fixAttempts = {} | del(.supplementaryRun)'; then
          echo "ERROR: Failed to restart stage $CURRENT_STAGE." >&2
          exit 2
        fi
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

  # Review approved — check for coverage loop (phase S11)
  if [[ "$CURRENT_PHASE" == "S11" ]]; then
    COVERAGE_MET=$(jq -r '.coverage.met // true' "${PHASES_DIR}/${OUTPUT_FILE}" 2>/dev/null || echo "true")
    if [[ "$COVERAGE_MET" == "false" ]]; then
      COVERAGE_ITER=$(state_get '.coverageLoop.iteration // 0' 2>/dev/null || echo "0")
      if [[ "$COVERAGE_ITER" -lt 20 ]]; then
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
    fi
  fi
else
  # Non-review phase — validate output exists
  if [[ ! -f "${PHASES_DIR}/${OUTPUT_FILE}" ]]; then
    echo "Agent completed but ${OUTPUT_FILE} not found." >&2
    exit 2
  fi
  # Validate JSON outputs
  if [[ "$OUTPUT_FILE" == *.json ]]; then
    if ! validate_json_file "${PHASES_DIR}/${OUTPUT_FILE}" "$OUTPUT_FILE"; then
      echo "ERROR: ${OUTPUT_FILE} is invalid JSON." >&2
      exit 2
    fi
  fi
fi

# Clear reviewFix if set (fix cycle completed successfully)
if state_get '.reviewFix // empty' 2>/dev/null | grep -q .; then
  update_state 'del(.reviewFix) | .updatedAt = $ts' 2>/dev/null || true
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

  # Check gate if crossing stages
  if [[ "$NEXT_STAGE" != "$CURRENT_STAGE" ]]; then
    GATE_NAME="${CURRENT_STAGE}->${NEXT_STAGE}"
    if ! validate_sl_gate "$GATE_NAME" "$PHASES_DIR"; then
      echo "ERROR: Gate $GATE_NAME failed. Cannot advance to $NEXT_STAGE." >&2
      exit 2
    fi
    # Mark current stage complete
    if ! update_state --arg stage "$CURRENT_STAGE" \
      '.stages[$stage].status = "complete" | .updatedAt = $ts'; then
      echo "ERROR: Failed to mark stage $CURRENT_STAGE as complete." >&2
      exit 2
    fi
  fi

  if ! update_state --arg phase "$NEXT_PHASE" --arg stage "$NEXT_STAGE" \
    '.currentPhase = $phase | .currentStage = $stage | .updatedAt = $ts'; then
    echo "ERROR: Failed to advance from $CURRENT_PHASE to $NEXT_PHASE." >&2
    exit 2
  fi
fi

exit 0
