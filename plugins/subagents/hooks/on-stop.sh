#!/usr/bin/env bash
# on-stop.sh -- Stop hook: prevents Claude from stopping while a workflow is active.
#
# Ralph-style orchestration: when the workflow is in_progress, this hook injects
# the FULL orchestrator prompt (from prompts/orchestrator-loop.md) as the block
# reason. Claude receives identical, self-contained dispatch instructions every
# time — no conversation memory required. State on disk determines behavior.
#
# Uses {"decision":"block","reason":"..."} JSON on stdout (exit 0).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

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

# Check workflow status
STATUS="$(state_get '.status // empty')"

case "$STATUS" in
  completed|stopped|failed|blocked)
    # Terminal states -- allow stop
    exit 0
    ;;
  in_progress)
    # Read the full orchestrator prompt template (Ralph-style)
    PROMPT_FILE="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/..}/prompts/orchestrator-loop.md"

    if [[ ! -f "$PROMPT_FILE" ]]; then
      echo "on-stop: orchestrator prompt not found at $PROMPT_FILE" >&2
      exit 0
    fi

    ORCHESTRATOR_PROMPT="$(cat "$PROMPT_FILE")"

    # Increment loop iteration in state (like Ralph)
    LOOP_ITER="$(state_get '.loopIteration // 0')"
    NEXT_ITER=$((LOOP_ITER + 1))
    state_update ".loopIteration = $NEXT_ITER"

    # Inject the full orchestrator prompt — Ralph-style
    jq -n --arg reason "$ORCHESTRATOR_PROMPT" '{"decision":"block","reason":$reason}'
    exit 0
    ;;
  *)
    # Unknown or empty status -- allow stop
    exit 0
    ;;
esac
