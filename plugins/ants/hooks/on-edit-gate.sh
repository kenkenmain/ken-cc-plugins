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
shutdown_check

# Read input (cap at 1MB to prevent memory exhaustion, matching other hooks)
input=$(head -c 1048576)
if [[ -z "$input" ]] || ! printf '%s' "$input" | jq empty 2>/dev/null; then
  echo "ERROR: No valid JSON received on stdin for PreToolUse hook." >&2
  exit 2
fi

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')

# Block if file path is empty or missing — fail-closed for security gate
if [[ -z "$file_path" ]]; then
  echo "ERROR: Edit/Write tool call has no file_path — blocking as precaution." >&2
  exit 2
fi

# Canonicalize path to prevent traversal bypasses (e.g., /../.agents/../../etc/passwd)
# Try realpath -m (GNU) first, fall back to realpath without -m (BSD macOS), then python
canonicalized=false
if command -v realpath &>/dev/null; then
  canon=$(realpath -m "$file_path" 2>/dev/null) || canon=$(realpath "$file_path" 2>/dev/null) || canon=""
  if [[ -n "$canon" ]]; then
    file_path="$canon"
    canonicalized=true
  fi
fi
if [[ "$canonicalized" == "false" ]] && command -v python3 &>/dev/null; then
  canon=$(python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$file_path" 2>/dev/null) || canon=""
  if [[ -n "$canon" ]]; then
    file_path="$canon"
    canonicalized=true
  fi
fi
# Fail-closed: if canonicalization failed and path has traversal sequences, block
if [[ "$canonicalized" == "false" && "$file_path" == *".."* ]]; then
  echo "ERROR: Path contains '..' and canonicalization failed -- blocking edit." >&2
  exit 2
fi

# Allow .agents/ writes in any phase (workflow output files)
if [[ "$file_path" =~ (^|/)\.agents/ ]]; then
  exit 0
fi

# Allow writes to external paths (outside project directory)
# The gate only protects project source files — temp files, scratchpads, etc. are fine
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
if command -v realpath &>/dev/null; then
  project_dir=$(realpath -m "$project_dir" 2>/dev/null || realpath "$project_dir" 2>/dev/null || echo "$project_dir")
fi
if [[ "$file_path" == /* ]] && [[ "$file_path" != "$project_dir"/* ]]; then
  exit 0
fi

current_phase=$(state_get '.currentPhase' --required)

# Allow edits during build and ship phases
case "$current_phase" in
  A3)
    # During A3, check file ownership via task pool if available
    has_pool=$(jq -r '.taskPool // empty | if type == "array" and length > 0 then "yes" else "no" end' "$STATE_FILE")
    if [[ "$has_pool" == "yes" ]]; then
      source "$SCRIPT_DIR/lib/task-pool.sh"
      if owner_json=$(pool_get_file_owner "$file_path"); then
        owner_task=$(echo "$owner_json" | jq -r '.task_id // "unknown"')
        echo "INFO: File ${file_path} is owned by task ${owner_task} (advisory)" >&2
      fi
    fi
    exit 0
    ;;
  A5)
    exit 0
    ;;
esac

# Deny edits in all other phases
deny_json=$(jq -n --arg phase "$current_phase" \
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
printf '%s\n' "$deny_json"
exit 0
