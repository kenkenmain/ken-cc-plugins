#!/usr/bin/env bash
# on-orchestrator-guard.sh -- PreToolUse hook that blocks the orchestrator from
# directly editing code files during an active workflow.
#
# Problem: The orchestrator should dispatch subagents (task-agent, fix-dispatcher)
# for all code changes. Nothing previously prevented Claude from using Edit/Write
# directly, bypassing the subagent architecture entirely.
#
# Solution: Block Edit/Write calls to any file outside .agents/tmp/ during an
# active workflow. The orchestrator legitimately writes state and phase output
# files under .agents/tmp/, but all code changes must go through subagents.
#
# Exit 0 with no output = allow
# Exit 0 with {"decision":"block","reason":"..."} = block with guidance
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=lib/state.sh
source "$SCRIPT_DIR/lib/state.sh"

# ---------------------------------------------------------------------------
# 1. Read hook input from stdin
# ---------------------------------------------------------------------------
INPUT="$(cat)"

# ---------------------------------------------------------------------------
# 2. If no active workflow, allow (don't interfere with normal editing)
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
# 5. Get the file path being edited/written
# ---------------------------------------------------------------------------
FILE_PATH="$(echo "$INPUT" | jq -r '.tool_input.file_path // ""')"
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 6. Always allow writes to state and phase output files
# ---------------------------------------------------------------------------
if [[ "$FILE_PATH" == *".agents/tmp/"* ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 7. Allow during review-fix cycles (fix-dispatcher is a subagent, but if
#    the orchestrator needs to make a quick fix, don't block it)
# ---------------------------------------------------------------------------
REVIEW_FIX="$(state_get '.reviewFix // empty')"
if [[ -n "$REVIEW_FIX" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 8. Block — orchestrator must dispatch a subagent for code changes
# ---------------------------------------------------------------------------
CURRENT_PHASE="$(state_get '.currentPhase // "unknown"')"
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"

jq -n \
  --arg phase "$CURRENT_PHASE" \
  --arg tool "$TOOL_NAME" \
  --arg file "$FILE_PATH" \
  '{
    "decision": "block",
    "reason": ("Direct " + $tool + " to code files is blocked during active workflow (phase " + $phase + "). The orchestrator must dispatch subagents for all code changes.\n\nBlocked file: " + $file + "\n\nCorrect pattern:\n1. For implementation phases: dispatch subagents:task-agent via Task tool\n2. For review-fix cycles: dispatch subagents:fix-dispatcher via Task tool\n3. Only .agents/tmp/ files (state, phase outputs) can be written directly\n\nThe orchestrator is a thin dispatcher — read state, dispatch subagents, let hooks advance.")
  }'

exit 0
