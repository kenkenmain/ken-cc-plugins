#!/usr/bin/env bash
# on-codex-guard.sh -- PreToolUse hook that blocks direct Codex MCP calls
# during an active subagents workflow.
#
# Problem: When the orchestrator calls mcp__codex-xhigh__codex or
# mcp__codex-high__codex synchronously, the call blocks the entire
# conversation with no timeout enforcement. If the MCP server hangs,
# the workflow is stuck indefinitely — Layer 2 (TaskOutput timeout)
# never fires because the call was never backgrounded.
#
# Solution: Block direct MCP calls and force all Codex usage through
# background-dispatched Task agents, which support TaskOutput timeout.
#
# Exit 0 with no output = allow
# Exit 0 with {"decision":"block","reason":"..."} = block with guidance
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
# 2. If no active workflow, allow (don't interfere with manual Codex usage)
# ---------------------------------------------------------------------------
if ! is_workflow_active; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Plugin guard: only act on subagents workflows
# ---------------------------------------------------------------------------
STATE_PLUGIN="$(state_get '.plugin // empty')"
if [[ -n "$STATE_PLUGIN" && "$STATE_PLUGIN" != "subagents" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 4. Session scoping: if a different session, don't interfere
# ---------------------------------------------------------------------------
if ! check_session_owner; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 4b. Subagent bypass: if this call comes from a subagent (different
#     transcript_path than the orchestrator), allow it. The codex-* subagent
#     types (codex-reviewer, codex-task-agent, etc.) have only Codex MCP as
#     a tool — they MUST call it to do their job. Timeout protection is
#     already enforced at the orchestrator level by on-task-dispatch.sh
#     (which requires run_in_background: true for codex agents) and by the
#     orchestrator's TaskOutput timeout polling. Blocking the nested call
#     here would make those agents non-functional.
# ---------------------------------------------------------------------------
INPUT_TRANSCRIPT="$(echo "$INPUT" | jq -r '.transcript_path // ""')"
OWNER_TRANSCRIPT="$(state_get '.ownerTranscriptPath // empty')"
if [[ -n "$INPUT_TRANSCRIPT" && -n "$OWNER_TRANSCRIPT" && "$INPUT_TRANSCRIPT" != "$OWNER_TRANSCRIPT" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 5. Block direct MCP call — must go through background Task dispatch
# ---------------------------------------------------------------------------
CURRENT_PHASE="$(state_get '.currentPhase // "unknown"')"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"

# Determine phase-appropriate timeout for the guidance message
local_timeout="$(get_phase_timeout "$CURRENT_PHASE" 2>/dev/null || echo 300000)"

jq -n \
  --arg phase "$CURRENT_PHASE" \
  --arg tool "$TOOL_NAME" \
  --arg timeout "$local_timeout" \
  '{
    "decision": "block",
    "reason": ("Direct " + $tool + " calls are blocked during active workflow (phase " + $phase + "). Codex MCP must be dispatched through a background Task agent for timeout protection.\n\nCorrect pattern:\n1. Task(subagent_type=\"subagents:codex-reviewer\", run_in_background=true, prompt=\"...\")\n2. TaskOutput(task_id, block=true, timeout=" + $timeout + ")\n3. If timeout: TaskStop(task_id), then write {\"status\":\"timeout\",\"issues\":[],\"codexTimeout\":true}\n\nThis prevents indefinite hangs when the MCP server is unresponsive.")
  }'

exit 0
