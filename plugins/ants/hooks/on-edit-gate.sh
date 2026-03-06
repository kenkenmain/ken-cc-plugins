#!/usr/bin/env bash
# on-edit-gate.sh — Block Edit/Write to source files outside build/ship phases
# PreToolUse hook for Edit and Write tools. Prevents the orchestrator from
# bypassing the A0->A1->A2->A3 pipeline by directly editing source files
# during non-build phases (e.g., during A4 queen review).
#
# Edit/Write are allowed in:
#   A3 (build)  — builders need to modify source files
#   A5 (ship)   — shipper needs to update docs, changelogs, etc.
#   .agents/    — workflow output files are always writable
#
# Exit codes:
#   0 silent    — allow (no active workflow, allowed phase, or .agents/ path)
#   0 with JSON — deny with hookSpecificOutput
#   2 with stderr — error/block (fail-closed: missing file_path, jq failure)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

check_ants_workflow

# Read input
INPUT=$(cat)
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "ERROR: No valid JSON received on stdin for PreToolUse hook." >&2
  exit 2
fi

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

# Block if file path is empty or missing — fail-closed for security gate
if [[ -z "$FILE_PATH" ]]; then
  echo "ERROR: Edit/Write tool call has no file_path — blocking as precaution." >&2
  exit 2
fi

# Canonicalize path to prevent traversal bypasses (e.g., /../.agents/../../etc/passwd)
# realpath -m works even if the file does not exist yet (needed for Write creating new files)
if command -v realpath &>/dev/null; then
  FILE_PATH=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
fi

# Allow .agents/ writes in any phase (workflow output files)
if [[ "$FILE_PATH" =~ (^|/)\.agents/ ]]; then
  exit 0
fi

# Allow writes to external paths (outside project directory)
# The gate only protects project source files — temp files, scratchpads, etc. are fine
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
if command -v realpath &>/dev/null; then
  PROJECT_DIR=$(realpath -m "$PROJECT_DIR" 2>/dev/null || echo "$PROJECT_DIR")
fi
if [[ "$FILE_PATH" == /* ]] && [[ "$FILE_PATH" != "$PROJECT_DIR"/* ]]; then
  exit 0
fi

CURRENT_PHASE=$(state_get '.currentPhase' --required)

# Allow edits during build and ship phases
case "$CURRENT_PHASE" in
  A3|A5)
    exit 0
    ;;
esac

# Deny edits in all other phases
DENY_JSON=$(jq -n --arg phase "$CURRENT_PHASE" \
  '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": ("Cannot edit source files during " + $phase + " phase. Code changes are only allowed during A3 (build) and A5 (ship). Issues found in A4 must be resolved through the A1\u2192A2\u2192A3 loop.")
    }
  }' 2>/dev/null) || {
  echo "ERROR: Failed to generate deny JSON for edit gate." >&2
  exit 2
}
printf '%s\n' "$DENY_JSON"
exit 0
