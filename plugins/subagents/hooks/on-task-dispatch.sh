#!/usr/bin/env bash
# on-task-dispatch.sh -- PreToolUse hook that validates Task tool calls match
# the expected current workflow phase. Adds contextual guidance when the phase
# tag is missing but does NOT block execution (lenient enforcement).
#
# Also enforces run_in_background: true for Codex agent dispatches to prevent
# synchronous MCP calls that can hang indefinitely without timeout protection.
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
# 3b. Guard: only process subagents state (ignore other plugins' workflows)
# ---------------------------------------------------------------------------
STATE_PLUGIN="$(state_get '.plugin // empty')"
if [[ -n "$STATE_PLUGIN" && "$STATE_PLUGIN" != "subagents" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 3c. Session scoping: if a different session, don't interfere
# ---------------------------------------------------------------------------
if ! check_session_owner; then
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
# 5. Enforce run_in_background for Codex agent dispatches
# ---------------------------------------------------------------------------
SUBAGENT_TYPE="$(echo "$INPUT" | jq -r '.tool_input.subagent_type // ""')"
RUN_IN_BG="$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')"

if [[ "$SUBAGENT_TYPE" == *"codex"* && "$RUN_IN_BG" != "true" ]]; then
  jq -n --arg agent "$SUBAGENT_TYPE" '{
    "decision": "block",
    "reason": ("Codex agent \"" + $agent + "\" must use run_in_background: true for timeout protection. Re-dispatch with:\n  Task(subagent_type=\"" + $agent + "\", run_in_background=true, prompt=\"...\")\nThen poll:\n  TaskOutput(task_id, block=true, timeout=300000)\nThis prevents indefinite hangs when the Codex MCP server is unresponsive.")
  }'
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Extract the subagent prompt from the tool input
# ---------------------------------------------------------------------------
PROMPT="$(echo "$INPUT" | jq -r '.tool_input.prompt // ""')"

# ---------------------------------------------------------------------------
# 7. Check if the prompt contains the correct phase tag
# ---------------------------------------------------------------------------
if echo "$PROMPT" | grep -qF "[PHASE $CURRENT_PHASE]"; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 8. Batch phases dispatch multiple parallel subagents -- always allow
# ---------------------------------------------------------------------------
case "$CURRENT_PHASE" in
  0|1.2|2.1) exit 0 ;;
esac

# ---------------------------------------------------------------------------
# 9. Missing phase tag on a non-batch phase -- provide context (do not block)
# ---------------------------------------------------------------------------
EXPECTED_OUTPUT="$(get_phase_output "$CURRENT_PHASE")"

jq -n \
  --arg phase "$CURRENT_PHASE" \
  --arg output "$EXPECTED_OUTPUT" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "additionalContext": ("Current workflow phase is " + $phase + ". Ensure this subagent is executing phase " + $phase + " work. Write output to .agents/tmp/phases/" + $output + ".")
    }
  }'

# ---------------------------------------------------------------------------
# 10. Allow execution (exit 0 = do not block)
# ---------------------------------------------------------------------------
exit 0
