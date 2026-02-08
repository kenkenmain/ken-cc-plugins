#!/usr/bin/env bash
# on-edit-gate-cursor.sh — Edit/Write gate for the cursor pipeline.
# Invoked via exec from on-edit-gate.sh when pipeline == "cursor".
# Allows edits only during C2 (build), C2.5 (fix), and C4 (ship) phases.
#
# Note: .agents/ path, external path, and file_path validation already done by parent hook.
#
# Exit codes:
#   0 silent    — allow (editable phase)
#   0 with JSON — deny with hookSpecificOutput
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

CURRENT_PHASE=$(state_get '.currentPhase' --required)

# Allow edits during build, fix, and ship phases
case "$CURRENT_PHASE" in
  C2|C2.5|C4)
    exit 0
    ;;
esac

# Deny edits in all other phases
DENY_JSON=$(jq -n --arg phase "$CURRENT_PHASE" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("Cannot edit source files during " + $phase + " phase. Code changes are only allowed during C2 (build), C2.5 (fix), and C4 (ship). Issues found by the judge must be resolved through fix cycles (C2.5) or replanning (C1).")
    }
  }' 2>/dev/null) || {
  echo "ERROR: Failed to generate deny JSON for cursor edit gate." >&2
  exit 2
}
printf '%s\n' "$DENY_JSON"
exit 0
