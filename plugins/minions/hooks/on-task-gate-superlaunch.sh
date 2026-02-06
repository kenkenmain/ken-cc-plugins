#!/usr/bin/env bash
# on-task-gate-superlaunch.sh — Task gate for the superlaunch 15-phase pipeline.
# Invoked via exec from on-task-gate.sh when pipeline == "superlaunch".
# Validates that the dispatched agent matches the current phase schedule.
#
# Receives agent type via SL_AGENT_TYPE env var (stdin already consumed by parent hook).
#
# Exit codes:
#   0 silent   — allow (non-minions agent or agent valid for current phase)
#   0 with JSON — block with reason
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/superlaunch.sh"

# stdin was already consumed and validated by the parent hook — read from env
AGENT_TYPE="${SL_AGENT_TYPE:?on-task-gate-superlaunch.sh requires SL_AGENT_TYPE}"

# Allow non-minions agents through
case "$AGENT_TYPE" in
  minions:*) ;; # check below
  *) exit 0 ;;    # not a minions agent, allow
esac

CURRENT_PHASE=$(state_get '.currentPhase' --required)

# Allow if agent is valid for current phase
if is_sl_agent_allowed "$AGENT_TYPE" "$CURRENT_PHASE"; then
  exit 0
fi

# Block with explanation
ALLOWED_PHASES=$(get_sl_agent_phases "$AGENT_TYPE")
if [[ -z "$ALLOWED_PHASES" ]]; then
  # Unknown agent — allow through (might be a supplementary or new agent)
  exit 0
fi

jq -n --arg agent "$AGENT_TYPE" --arg current "$CURRENT_PHASE" --arg allowed "$ALLOWED_PHASES" \
  '{"decision":"block","reason":("Cannot dispatch " + $agent + " during phase " + $current + ". This agent is allowed in phases: " + $allowed + ". Follow the superlaunch schedule.")}'
exit 0
