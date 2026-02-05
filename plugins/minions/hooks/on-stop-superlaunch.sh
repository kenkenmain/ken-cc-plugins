#!/usr/bin/env bash
# on-stop-superlaunch.sh — Stop hook for the superlaunch 15-phase pipeline.
# Invoked via exec from on-stop.sh when pipeline == "superlaunch".
# Reads state.json, generates a schedule-driven orchestrator prompt,
# and injects it as {"decision":"block","reason":"<prompt>"}.
#
# Exit codes:
#   0 with JSON — block Claude's stop and inject next phase prompt
#   0 silent    — allow stop (terminal state)
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/superlaunch.sh"

CURRENT_PHASE=$(state_get '.currentPhase' --required)

# Allow stop on terminal states
case "$CURRENT_PHASE" in
  DONE|STOPPED|COMPLETE)
    exit 0
    ;;
esac

# Generate schedule-driven prompt
PROMPT=$(generate_sl_prompt "$CURRENT_PHASE")

# Block stop and inject the orchestrator prompt
if ! jq_out=$(jq -n --arg reason "$PROMPT" '{"decision":"block","reason":$reason}' 2>&1); then
  echo "ERROR: jq failed to encode superlaunch prompt for phase ${CURRENT_PHASE}: $jq_out" >&2
  exit 2
fi
echo "$jq_out"
