#!/usr/bin/env bash
# on-task-dispatch.sh -- PreToolUse hook that validates Task tool calls match
# the expected current workflow phase. Adds contextual guidance when the phase
# tag is missing but does NOT block execution (lenient enforcement).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/state.sh
source "$SCRIPT_DIR/lib/state.sh"
# shellcheck source=lib/schedule.sh
source "$SCRIPT_DIR/lib/schedule.sh"

# ---------------------------------------------------------------------------
# 1. Read hook input from stdin
# ---------------------------------------------------------------------------
INPUT="$(cat)"

# ---------------------------------------------------------------------------
# 2. Only validate Task tool calls -- allow everything else
# ---------------------------------------------------------------------------
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"
if [[ "$TOOL_NAME" != "Task" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. If no workflow is active, allow without enforcement
# ---------------------------------------------------------------------------
if ! is_workflow_active; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Get the current phase from state
# ---------------------------------------------------------------------------
CURRENT_PHASE="$(state_get '.currentPhase // empty')"
if [[ -z "$CURRENT_PHASE" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Extract the subagent prompt from the tool input
# ---------------------------------------------------------------------------
PROMPT="$(echo "$INPUT" | jq -r '.tool_input.prompt // ""')"

# ---------------------------------------------------------------------------
# 6. Check if the prompt contains the correct phase tag
# ---------------------------------------------------------------------------
if echo "$PROMPT" | grep -qF "[PHASE $CURRENT_PHASE]"; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 7. Batch phases dispatch multiple parallel subagents -- always allow
# ---------------------------------------------------------------------------
case "$CURRENT_PHASE" in
  1|2|4) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# 8. Missing phase tag on a non-batch phase -- provide context (do not block)
# ---------------------------------------------------------------------------
EXPECTED_OUTPUT="$(get_phase_output "$CURRENT_PHASE")"

jq -n \
  --arg phase "$CURRENT_PHASE" \
  --arg output "$EXPECTED_OUTPUT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": ("Current workflow phase is " + $phase + ". Ensure this subagent is executing phase " + $phase + " work. Write output to .agents/tmp/iterate/phases/" + $output + ".")
    }
  }'

# ---------------------------------------------------------------------------
# 9. Allow execution (exit 0 = do not block)
# ---------------------------------------------------------------------------
exit 0
