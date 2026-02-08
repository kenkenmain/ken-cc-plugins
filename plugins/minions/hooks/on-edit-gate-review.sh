#!/usr/bin/env bash
# on-edit-gate-review.sh -- Edit/Write gate for the review pipeline.
# Invoked via exec from on-edit-gate.sh when pipeline == "review".
# Allows edits only during R2 (fix) phase.
#
# Note: .agents/ path, external path, and file_path validation already done by parent hook.
#
# Exit codes:
#   0 silent    -- allow (editable phase)
#   0 with JSON -- deny with hookSpecificOutput
#   2 with stderr -- error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

CURRENT_PHASE=$(state_get '.currentPhase' --required)

# Allow edits during fix phase
case "$CURRENT_PHASE" in
  R2)
    exit 0
    ;;
esac

# Deny edits in all other phases (R1, DONE, STOPPED)
DENY_JSON=$(jq -n --arg phase "$CURRENT_PHASE" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("Cannot edit source files during " + $phase + " phase. Code changes are only allowed during R2 (fix). The review pipeline order is: R1 (review) -> R2 (fix) -> R1 (review).")
    }
  }' 2>/dev/null) || {
  echo "ERROR: Failed to generate deny JSON for review edit gate." >&2
  exit 2
}
printf '%s\n' "$DENY_JSON"
exit 0
