#!/usr/bin/env bash
# lint.sh -- Language-aware lint runner abstraction for ants hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/lint.sh"
#
# Provides defensive lint functions that never crash the calling hook.
# All functions return valid JSON even when linters are unavailable.
#
# Lint output format:
#   {"passed": true|false, "errors": [...], "warnings": [], "skipped": false}
# Error items:
#   {"file": "path", "line": 0, "message": "...", "severity": "error"}

set -euo pipefail

# ===========================================================================
# lint_file -- Run language-appropriate linter on a single file.
#
# Arguments:
#   $1 -- file_path (required)
#
# Output (stdout):
#   JSON object: {"passed": bool, "errors": [...], "warnings": [], "skipped": bool}
#
# Returns 0 always (defensive -- never crashes the hook).
# ===========================================================================
lint_file() {
  local file_path="${1:?lint_file requires a file_path argument}"
  local ext
  ext="${file_path##*.}"

  # Dispatch by extension
  case "$ext" in
    sh)
      _lint_shell "$file_path"
      ;;
    json)
      _lint_json "$file_path"
      ;;
    py)
      _lint_python "$file_path"
      ;;
    ts|tsx)
      _lint_skip "$file_path" "TypeScript linters are project-specific"
      ;;
    *)
      _lint_skip "$file_path" "No linter configured for .$ext files"
      ;;
  esac
}

# ===========================================================================
# lint_check_enabled -- Check if linting is enabled in workflow state.
#
# Reads .lintConfig.enabled from STATE_FILE.
# Defaults to ON (enabled) if lintConfig is null or missing.
#
# Returns 0 (enabled) or 1 (disabled).
# ===========================================================================
lint_check_enabled() {
  if [[ ! -f "$STATE_FILE" ]]; then
    # No state file -- default enabled
    return 0
  fi

  local enabled
  enabled=$(jq -r 'if .lintConfig.enabled == false then "false" else "true" end' "$STATE_FILE" 2>/dev/null || echo "true")

  if [[ "$enabled" == "false" ]]; then
    return 1
  fi
  return 0
}

# ===========================================================================
# lint_format_advisory -- Format lint result JSON as human-readable string.
#
# Arguments:
#   $1 -- lint_result_json (JSON string from lint_file)
#
# Output (stdout):
#   Human-readable string, or empty string if no issues.
# ===========================================================================
lint_format_advisory() {
  local lint_result_json="${1:?lint_format_advisory requires a JSON argument}"

  local passed
  passed=$(printf '%s' "$lint_result_json" | jq -r 'if .passed == false then "false" else "true" end' 2>/dev/null || echo "true")

  if [[ "$passed" == "true" ]]; then
    # No issues -- return empty
    echo ""
    return 0
  fi

  local advisory
  advisory=$(printf '%s' "$lint_result_json" | jq -r '
    .errors[]? |
    "File \(.file): \(.message)"
  ' 2>/dev/null || echo "")

  echo "$advisory"
}

# ===========================================================================
# Internal helpers
# ===========================================================================

# _lint_result -- Emit a lint result JSON object.
# Args: passed(bool) errors_json skipped(bool)
_lint_result() {
  local passed="$1"
  local errors_json="$2"
  local skipped="$3"

  printf '{"passed": %s, "errors": %s, "warnings": [], "skipped": %s}\n' \
    "$passed" "$errors_json" "$skipped"
}

# _lint_skip -- Emit a skipped result.
_lint_skip() {
  local file_path="$1"
  local reason="${2:-No linter available}"
  _lint_result "true" "[]" "true"
}

# _lint_error_item -- Build a single error JSON object.
_lint_error_item() {
  local file="$1"
  local line="${2:-0}"
  local message="$3"
  local severity="${4:-error}"

  # jq is guaranteed available (state.sh exits 2 if missing) -- no fallback needed
  jq -n \
    --arg file "$file" \
    --argjson line "$line" \
    --arg message "$message" \
    --arg severity "$severity" \
    '{"file": $file, "line": $line, "message": $message, "severity": $severity}'
}

# _lint_shell -- Lint a shell script with bash -n.
_lint_shell() {
  local file_path="$1"

  if ! command -v bash &>/dev/null; then
    _lint_skip "$file_path" "bash not available"
    return 0
  fi

  local stderr_output
  if stderr_output=$(bash -n "$file_path" 2>&1); then
    _lint_result "true" "[]" "false"
  else
    local error_item
    error_item=$(_lint_error_item "$file_path" 0 "$stderr_output" "error")
    _lint_result "false" "[$error_item]" "false"
  fi
}

# _lint_json -- Lint a JSON file with jq empty.
_lint_json() {
  local file_path="$1"

  if ! command -v jq &>/dev/null; then
    _lint_skip "$file_path" "jq not available"
    return 0
  fi

  local stderr_output
  if stderr_output=$(jq empty "$file_path" 2>&1); then
    _lint_result "true" "[]" "false"
  else
    local error_item
    error_item=$(_lint_error_item "$file_path" 0 "$stderr_output" "error")
    _lint_result "false" "[$error_item]" "false"
  fi
}

# _lint_python -- Lint a Python file with py_compile.
_lint_python() {
  local file_path="$1"

  if ! command -v python3 &>/dev/null; then
    _lint_skip "$file_path" "python3 not available"
    return 0
  fi

  local stderr_output
  if stderr_output=$(python3 -m py_compile "$file_path" 2>&1); then
    _lint_result "true" "[]" "false"
  else
    local error_item
    error_item=$(_lint_error_item "$file_path" 0 "$stderr_output" "error")
    _lint_result "false" "[$error_item]" "false"
  fi
}
