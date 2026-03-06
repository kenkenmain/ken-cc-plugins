#!/usr/bin/env bash
# on-stop.sh — Ralph-style loop driver for ants workflow
# Reads state.json, generates a phase-specific orchestrator prompt,
# and injects it as {"decision":"block","reason":"<prompt>"} to drive the loop.
#
# Exit codes:
#   0 with JSON — block Claude's stop and inject next phase prompt
#   0 silent    — allow stop (no active workflow or workflow complete)
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/swarm.sh"
source "$SCRIPT_DIR/lib/dag.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
source "$SCRIPT_DIR/lib/teams.sh"

check_ants_workflow

CURRENT_PHASE=$(state_get '.currentPhase' --required)
LOOP=$(state_get '.loop // 1')
MAX_LOOPS=$(state_get '.maxLoops // 5')

# Validate integers
LOOP=$(require_int "$LOOP" "loop")
MAX_LOOPS=$(require_int "$MAX_LOOPS" "maxLoops")

PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

# Recovery: advance state if output files exist but SubagentStop didn't fire.

# A3->A4: if A3-build.json exists and valid, advance to A4
if [[ "$CURRENT_PHASE" == "A3" && -f "${PHASES_DIR}/A3-build.json" ]]; then
  if validate_json_file "${PHASES_DIR}/A3-build.json" "A3-build.json" 2>/dev/null; then
    if jq -e '.tasks and .files_changed and .all_complete == true' "${PHASES_DIR}/A3-build.json" >/dev/null 2>&1; then
      echo "INFO: Recovery path triggered -- advancing A3->A4 in Stop hook (SubagentStop may not have fired)" >&2
      if ! update_state '.currentPhase = "A4" | .updatedAt = $ts | .phases.A3.status = "complete"'; then
        echo "ERROR: Failed to advance state from A3 to A4 in Stop hook." >&2
        exit 2
      fi
      CURRENT_PHASE="A4"
    fi
  fi
fi

# A4->A5/loop: if A4-queen-verdict.json exists and valid, advance based on verdict
if [[ "$CURRENT_PHASE" == "A4" && -f "${PHASES_DIR}/A4-queen-verdict.json" ]]; then
  echo "INFO: Recovery path triggered -- processing A4 verdict in Stop hook (SubagentStop may not have fired)" >&2
  if ! validate_json_file "${PHASES_DIR}/A4-queen-verdict.json" "A4-queen-verdict.json"; then
    echo "ERROR: A4-queen-verdict.json exists but is invalid JSON." >&2
    exit 2
  fi

  # VERDICT is set by parse_queen_verdict in caller scope
  parse_queen_verdict "${PHASES_DIR}/A4-queen-verdict.json"

  # Use shared verdict handler (defined in swarm.sh)
  RESULT_PHASE=""
  handle_a4_verdict "$VERDICT" "$LOOP" "$MAX_LOOPS"
  CURRENT_PHASE="$RESULT_PHASE"

  if [[ "$RESULT_PHASE" == "BLOCKED" ]]; then
    exit 0  # Allow stop -- workflow is now blocked
  elif [[ "$RESULT_PHASE" == "A1" ]]; then
    LOOP=$((LOOP + 1))
    PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"
  fi
fi

# Circuit breaker check: if tripped, halt the workflow
if cb_is_tripped; then
  echo "INFO: Circuit breaker is tripped, halting workflow" >&2
  if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Circuit breaker tripped: too many consecutive failures"'; then
    echo "ERROR: Failed to update state to blocked after circuit breaker trip." >&2
    exit 2
  fi
  exit 0
fi

# Generate phase-specific prompt
case "$CURRENT_PHASE" in
  A0|A1|A2|A3|A4|A5)
    PROMPT="$(generate_swarm_prompt "$CURRENT_PHASE")"
    ;;

  DONE|STOPPED)
    # Workflow complete or stopped — allow stop
    exit 0
    ;;

  *)
    echo "ERROR: Unknown currentPhase '${CURRENT_PHASE}' in state.json" >&2
    exit 2
    ;;
esac

# Block stop and inject the orchestrator prompt
if ! jq_out=$(jq -n --arg reason "$PROMPT" '{"decision":"block","reason":$reason}' 2>&1); then
  echo "ERROR: jq failed to encode orchestrator prompt for phase ${CURRENT_PHASE}: $jq_out" >&2
  exit 2
fi
echo "$jq_out"
