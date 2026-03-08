#!/usr/bin/env bash
# on-post-edit-lint.sh -- PostToolUse lint advisory for Edit/Write
# Runs lint on files after successful edits during build/ship phases.
# Non-blocking: provides lint results as informational context only.
#
# Exit codes:
#   0 -- always (PostToolUse is non-blocking)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/lint.sh"

check_ants_workflow

# Only lint during build/ship phases
current_phase=$(state_get '.currentPhase' --required)
case "$current_phase" in
  A3|A5) ;;
  *) exit 0 ;;
esac

# Check if lint is enabled
if ! lint_check_enabled; then
  exit 0
fi

# Read input
input=$(cat)
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
if [[ -z "$file_path" ]]; then
  exit 0
fi

# Skip .agents/ files
if [[ "$file_path" =~ (^|/)\.agents/ ]]; then
  exit 0
fi

# Run lint
lint_result=$(lint_file "$file_path" 2>/dev/null || echo '{"passed": true, "errors": [], "warnings": []}')
advisory=$(lint_format_advisory "$lint_result" 2>/dev/null || echo "")

if [[ -n "$advisory" ]]; then
  echo "LINT: $advisory" >&2
fi

exit 0
