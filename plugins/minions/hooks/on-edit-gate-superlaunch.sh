#!/usr/bin/env bash
# on-edit-gate-superlaunch.sh — Edit/Write gate for the superlaunch pipeline.
# Invoked via exec from on-edit-gate.sh when pipeline == "superlaunch".
# Allows edits only during IMPLEMENT and FINAL stages.
#
# Note: .agents/ path check and file_path validation already done by parent hook.
#
# Exit codes:
#   0 silent    — allow (editable stage)
#   0 with JSON — deny with hookSpecificOutput
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

CURRENT_STAGE=$(state_get '.currentStage // empty')

# Allow edits during IMPLEMENT and FINAL stages
case "$CURRENT_STAGE" in
  IMPLEMENT|FINAL)
    exit 0
    ;;
esac

# Deny edits in all other stages
DENY_JSON=$(jq -n --arg stage "$CURRENT_STAGE" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("Cannot edit source files during " + $stage + " stage. Code changes are only allowed during IMPLEMENT and FINAL stages. Issues found in reviews must be resolved through the review-fix cycle.")
    }
  }' 2>/dev/null) || {
  echo "ERROR: Failed to generate deny JSON for superlaunch edit gate." >&2
  exit 2
}
printf '%s\n' "$DENY_JSON"
exit 0
