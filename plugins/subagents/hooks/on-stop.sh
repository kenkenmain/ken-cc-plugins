#!/usr/bin/env bash
# on-stop.sh -- Stop hook: prevents Claude from stopping while a workflow is active.
#
# Ralph-style orchestration: when the workflow is in_progress, this hook generates
# a phase-specific orchestrator prompt (~40 lines) and injects it as the block
# reason. Claude reads state to determine the current phase and dispatches it.
# State on disk determines behavior — no conversation memory required.
#
# Uses {"decision":"block","reason":"..."} JSON on stdout (exit 0).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/schedule.sh"

# Consume stdin (hook input)
cat > /dev/null

# Allow stop if no state file exists (no workflow)
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Only act on subagents workflows (or legacy states without plugin field).
# Prevents cross-plugin interference when both subagents and superpowers-iterate are installed.
PLUGIN="$(state_get '.plugin // empty')"
if [[ -n "$PLUGIN" && "$PLUGIN" != "subagents" ]]; then
  exit 0
fi

# Session scoping: if a different session, don't interfere
if ! check_session_owner; then
  exit 0
fi

# Check workflow status
STATUS="$(state_get '.status // empty')"

case "$STATUS" in
  completed|stopped|failed|blocked)
    # Terminal states -- allow stop
    exit 0
    ;;
  in_progress)
    # Read current phase from state
    CURRENT_PHASE="$(state_get '.currentPhase // empty')"

    if [[ -z "$CURRENT_PHASE" ]]; then
      echo "on-stop: no currentPhase in state" >&2
      exit 0
    fi

    # Generate phase-specific orchestrator prompt (replaces full orchestrator-loop.md)
    ORCHESTRATOR_PROMPT="$(generate_phase_prompt "$CURRENT_PHASE")"

    if [[ -z "$ORCHESTRATOR_PROMPT" ]]; then
      echo "on-stop: failed to generate prompt for phase $CURRENT_PHASE" >&2
      exit 0
    fi

    # Increment loop iteration in state (like Ralph)
    LOOP_ITER="$(state_get '.loopIteration // 0')"
    NEXT_ITER=$((LOOP_ITER + 1))
    state_update ".loopIteration = $NEXT_ITER"

    # Inject the phase-specific orchestrator prompt — Ralph-style
    jq -n --arg reason "$ORCHESTRATOR_PROMPT" '{"decision":"block","reason":$reason}'
    exit 0
    ;;
  *)
    # Unknown or empty status -- allow stop
    exit 0
    ;;
esac
