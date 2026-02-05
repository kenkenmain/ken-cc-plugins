#!/usr/bin/env bash
# state.sh — Shared state helpers for minions hooks
# Source this from hook scripts: source "$SCRIPT_DIR/lib/state.sh"

STATE_FILE=".agents/tmp/state.json"

# ERR trap — convert unexpected failures into informative exit-2 errors.
# Note: does NOT fire for arithmetic expansion or set -u violations (bash limitation).
trap 'echo "ERROR: ${BASH_SOURCE[1]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR

# Check if workflow is active and owned by this session.
# Returns 0 if we should proceed, exits 0 (allow) if we should not.
check_workflow_active() {
  # No state file = no active workflow
  if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
  fi

  # State file must be a valid JSON object (not a scalar, array, or garbage)
  if ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    echo "ERROR: state.json is not a valid JSON object (found: $(jq -r 'type' "$STATE_FILE" 2>/dev/null || echo 'unparseable')). State may be corrupt." >&2
    exit 2
  fi

  # Plugin guard
  local plugin
  plugin=$(jq -r '.plugin // empty' "$STATE_FILE")
  if [[ "$plugin" != "minions" ]]; then
    exit 0
  fi

  # Session scoping - ownerPpid
  local owner_ppid
  owner_ppid=$(jq -r '.ownerPpid // empty' "$STATE_FILE")
  if [[ -n "$owner_ppid" && "$owner_ppid" != "$PPID" ]]; then
    exit 0
  fi

  # Session scoping - sessionId
  # CLAUDE_SESSION_ID is a forward-compatible placeholder environment variable.
  # It may be provided by Claude Code in future versions to uniquely identify sessions.
  # If not present, the sessionId check is skipped (backward compatible with current Claude Code).
  # When both state.sessionId and CLAUDE_SESSION_ID are set, they must match for the hook to proceed.
  local state_session_id
  state_session_id=$(jq -r '.sessionId // empty' "$STATE_FILE")
  if [[ -n "$state_session_id" && -n "${CLAUDE_SESSION_ID:-}" && "$state_session_id" != "$CLAUDE_SESSION_ID" ]]; then
    exit 0
  fi

  # Status check
  local status
  status=$(jq -r '.status // empty' "$STATE_FILE")
  if [[ "$status" != "in_progress" ]]; then
    exit 0
  fi

  return 0
}

# Read a field from state.json. Exits 2 if the field is missing/empty and required.
# Distinguishes between jq failure (exit 2) and legitimately empty/missing fields.
# Usage: state_get '.currentPhase' [--required]
state_get() {
  local filter="$1"
  local required="${2:-}"
  local value
  # The if-condition prevents ERR trap from firing, giving us a specific error message
  if ! value=$(jq -r "$filter // empty" "$STATE_FILE" 2>&1); then
    echo "ERROR: jq failed querying state.json with filter '$filter': $value" >&2
    exit 2
  fi

  if [[ -z "$value" && "$required" == "--required" ]]; then
    echo "ERROR: state.json field '$filter' is missing or empty. Workflow state is incomplete." >&2
    exit 2
  fi
  echo "$value"
}

# Validate a required integer field from state. Returns the validated integer.
# Usage: validated_int=$(require_int "$value" "fieldname")
require_int() {
  local value="$1"
  local name="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: state.json .$name is not a valid non-negative integer: '${value}'" >&2
    exit 2
  fi
  echo "$value"
}

# Atomic state update with file locking.
# Usage: update_state [jq_args...] 'jq_filter'
# The last argument is always the jq filter. All preceding arguments are passed to jq.
# Automatically provides $ts (current timestamp) as a jq variable.
update_state() {
  local args=()
  while [[ $# -gt 1 ]]; do
    args+=("$1")
    shift
  done
  local filter="$1"
  local timestamp
  timestamp=$(date -Iseconds)

  (
    flock -x -w 5 200 || {
      echo "ERROR: Could not acquire state lock after 5 seconds" >&2
      return 1
    }

    local tmp_file
    tmp_file=$(mktemp "${STATE_FILE}.XXXXXX")

    # Capture stderr separately from stdout for diagnostics
    local jq_err_file
    jq_err_file=$(mktemp "${STATE_FILE}.err.XXXXXX")

    # Clean up temp files on any exit from this subshell (ERR, signal, normal)
    trap 'rm -f "$tmp_file" "$jq_err_file" 2>/dev/null' EXIT

    if jq --arg ts "$timestamp" ${args[@]+"${args[@]}"} "$filter" "$STATE_FILE" >"$tmp_file" 2>"$jq_err_file"; then
      if jq empty "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$STATE_FILE"
        rm -f "$jq_err_file"
        return 0
      else
        echo "ERROR: State update produced invalid JSON" >&2
        rm -f "$tmp_file" "$jq_err_file"
        return 1
      fi
    else
      local jq_err
      jq_err=$(cat "$jq_err_file" 2>/dev/null || echo "unknown error")
      echo "ERROR: jq state update failed: $jq_err" >&2
      rm -f "$tmp_file" "$jq_err_file"
      return 1
    fi
  ) 200>"${STATE_FILE}.lock"
}

# Validate a JSON file exists and is valid JSON.
# Usage: validate_json_file "/path/to/file.json" ["description"]
validate_json_file() {
  local filepath="$1"
  local desc="${2:-$filepath}"

  if [[ ! -f "$filepath" ]]; then
    echo "ERROR: $desc not found at $filepath" >&2
    return 1
  fi

  local jq_err
  if ! jq_err=$(jq empty "$filepath" 2>&1); then
    echo "ERROR: $desc contains invalid JSON: $jq_err" >&2
    return 1
  fi

  return 0
}
