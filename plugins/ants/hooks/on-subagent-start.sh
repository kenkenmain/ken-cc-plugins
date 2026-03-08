#!/usr/bin/env bash
# on-subagent-start.sh — SubagentStart event handler for ants workflow.
# Injects workflow context (phase, loop, status) into subagent via
# additionalContext so teammates are aware of the current workflow state.
#
# Exit codes:
#   0 — always (SubagentStart is non-blocking)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

# check_ants_workflow exits 0 if no active ants workflow for this session
check_ants_workflow

# Workflow is active — read state summary
current_phase=$(state_get '.currentPhase // "unknown"')
loop=$(state_get '.loop // 1')
status=$(state_get '.status // "unknown"')
stage=$(jq -r '.currentPhase as $cp | (.schedule // [] | map(select(.phase == $cp)) | .[0].stage) // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")

# Build context summary and output additionalContext for the subagent (jq for safe JSON)
jq -n \
  --arg phase "$current_phase" \
  --arg loop "$loop" \
  --arg status "$status" \
  --arg stage "$stage" \
  '{"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": ("Ants workflow active: phase=" + $phase + ", loop=" + $loop + ", status=" + $status + ", stage=" + $stage)}}'

exit 0
