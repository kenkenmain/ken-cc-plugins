#!/usr/bin/env bash
# on-teammate-idle.sh — TeammateIdle handler for queen-driven dispatch model
#
# In the queen-driven model, the queen dispatches work to teammates via
# SendMessage. This hook's role is simplified:
#   1. Check preconditions (circuit breaker, shutdown, session ownership)
#   2. If queen is already dispatched, exit 0 (queen handles dispatch via SendMessage)
#   3. If queen is NOT dispatched yet and a phase is pending, create the initial queen task
#
# Exit codes:
#   0 silent — allow idle (queen is dispatching, or workflow complete/blocked)
#   2 with stderr — assign initial queen kickoff task

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
source "$SCRIPT_DIR/lib/teams.sh"

check_ants_workflow

# Read stdin (Agent Teams passes hook input JSON)
INPUT=$(cat)

# Batch-read all needed state fields in a single jq call
local_fields=$(jq -r '[
  (.shutdown // false | tostring),
  (.queenDispatched // false | tostring),
  (.status // "unknown"),
  (.currentPhase // "DONE"),
  (.task // ""),
  ((.loop // 1) | tostring)
] | join("\t")' "$STATE_FILE")
IFS=$'\t' read -r shutdown_flag queen_dispatched status current_phase task loop <<< "$local_fields"

# Check for graceful shutdown
if [[ "$shutdown_flag" == "true" ]]; then
  teams_log "Shutdown flag set, allowing idle (graceful shutdown)"
  exit 0
fi

# Circuit breaker check: if tripped, stop assigning work
if cb_is_tripped; then
  teams_log "Circuit breaker tripped, allowing idle"
  if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Circuit breaker tripped: too many consecutive failures"'; then
    echo "ERROR: Failed to update state to blocked after circuit breaker trip." >&2
    exit 2
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Queen-driven dispatch logic
# ---------------------------------------------------------------------------

# If queen is already dispatched and workflow is in progress, do nothing.
# The queen handles all task dispatch via SendMessage.
if [[ "$queen_dispatched" == "true" && "$status" == "in_progress" ]]; then
  teams_log "Queen already dispatched, allowing idle (queen handles dispatch)"
  exit 0
fi

# Queen is NOT dispatched yet — check if there is a pending phase to kick off
case "$current_phase" in
  A0|A1|A2|A3|A4|A5)
    # Check phase status — need a separate read since phase is dynamic
    phase_status=$(state_get ".phases.${current_phase}.status // \"unknown\"")
    if [[ "$phase_status" == "pending" ]]; then
      teams_log "Queen not dispatched, phase $current_phase is pending — creating initial queen task"

      if [[ -z "$task" ]]; then
        echo "ERROR: state.json field '.task' is missing or empty. Workflow state is incomplete." >&2
        exit 2
      fi

      # Sanitize task description before interpolation into prompt
      task="$(printf '%s' "$task" | head -c 2000 | tr -d '\000-\031')"

      # Mark queen as dispatched to prevent duplicate kickoffs
      if ! update_state '.queenDispatched = true | .updatedAt = $ts'; then
        echo "ERROR: Failed to mark queenDispatched in state.json" >&2
        exit 2
      fi

      # Build a queen kickoff prompt
      PROMPT="## Ants Colony — Queen Kickoff

Task: ${task}
Current Phase: ${current_phase}
Loop: ${loop}
Status: ${status}

You are the queen. Dispatch the appropriate agents for phase ${current_phase} using SendMessage.
Read the workflow state from .agents/tmp/state.json and the phase prompt templates to determine
which agents to dispatch and what instructions to give them.

Coordinate the colony. Assign work to teammates via SendMessage. Monitor progress and advance
phases as agents complete their work."

      # Assign the queen kickoff via exit 2
      printf '%s\n' "$PROMPT" >&2
      exit 2
    fi
    ;;
esac

# No actionable state — allow idle
teams_log "No action needed (phase=$current_phase, queenDispatched=$queen_dispatched), allowing idle"
exit 0
