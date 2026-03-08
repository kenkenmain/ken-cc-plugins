#!/usr/bin/env bash
# state.sh — Shared state helpers for minions hooks
# Source this from hook scripts: source "$SCRIPT_DIR/lib/state.sh"

# Bootstrap: STATE_FILE, jq check, ERR trap
set -euo pipefail
_MINIONS_STATE_DIR="${BASH_SOURCE[0]%/*}/../../../shared/lib"
[[ -f "$_MINIONS_STATE_DIR/common-state.sh" ]] || { echo "ERROR: cannot locate common-state.sh" >&2; exit 2; }
source "$_MINIONS_STATE_DIR/common-state.sh"

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

# Internal helper for update_state — performs the actual jq transform and atomic write.
# Usage: _update_state_inner "$timestamp" "$filter" [jq_args...]
_update_state_inner() {
  local timestamp="$1"
  local filter="$2"
  shift 2
  local args=("$@")

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
}

# Probe flock availability once at source time to avoid fork+exec on every state write
_FLOCK_AVAILABLE=false
command -v flock &>/dev/null && _FLOCK_AVAILABLE=true

# Atomic state update with file locking.
# Usage: update_state [jq_args...] 'jq_filter'
# The last argument is always the jq filter. All preceding arguments are passed to jq.
# Automatically provides $ts (current timestamp) as a jq variable.
#
# Locking strategy:
#   - Uses flock when available (Linux, macOS with util-linux)
#   - Falls back to mkdir-based locking on stock macOS (flock unavailable)
#   - mkdir fallback includes stale lock detection (5s timeout)
update_state() {
  local args=()
  while [[ $# -gt 1 ]]; do
    args+=("$1")
    shift
  done
  local filter="$1"
  local timestamp
  timestamp=$(date -Iseconds)

  if [[ "$_FLOCK_AVAILABLE" == "true" ]]; then
    # flock-based locking (Linux, macOS with util-linux)
    (
      flock -x -w 5 200 || {
        echo "ERROR: Could not acquire state lock after 5 seconds" >&2
        return 1
      }

      _update_state_inner "$timestamp" "$filter" "${args[@]+"${args[@]}"}"
    ) 200>"${STATE_FILE}.lock"
  else
    # mkdir-based locking fallback (stock macOS without flock)
    local lock_dir="${STATE_FILE}.lockdir"
    local lock_stale_seconds=5
    local lock_acquired=false
    local attempt

    for attempt in 1 2 3 4 5 6 7 8 9 10; do
      if mkdir "$lock_dir" 2>/dev/null; then
        lock_acquired=true
        break
      fi

      # Check for stale lock
      if [[ -d "$lock_dir" ]]; then
        local lock_mtime
        if lock_mtime=$(lock_dir_mtime_epoch "$lock_dir"); then
          local lock_age
          lock_age=$(( $(date +%s) - lock_mtime ))
          if [[ "$lock_age" -gt "$lock_stale_seconds" ]]; then
            echo "WARNING: Removing stale state lock (age: ${lock_age}s)" >&2
            rm -rf "$lock_dir"
            if mkdir "$lock_dir" 2>/dev/null; then
              lock_acquired=true
              break
            fi
          fi
        fi
      fi

      # Brief sleep between attempts (total wait ~5s max)
      sleep 0.5
    done

    if [[ "$lock_acquired" != "true" ]]; then
      echo "ERROR: Could not acquire state lock after 5 seconds (mkdir fallback)" >&2
      return 1
    fi

    # Use subshell to scope the EXIT trap (avoids overwriting caller's trap)
    (
      trap 'rm -rf "$lock_dir" 2>/dev/null' EXIT
      _update_state_inner "$timestamp" "$filter" "${args[@]+"${args[@]}"}"
    )
  fi
}

# Get the mtime of a directory as epoch seconds (cross-platform).
# Returns 0 on success with mtime on stdout, 1 on failure (fail-closed: caller should skip stale check).
# Usage: if mtime=$(lock_dir_mtime_epoch "$dir"); then ... fi
lock_dir_mtime_epoch() {
  local lock_dir="$1"
  local mtime
  if mtime=$(stat -c %Y "$lock_dir" 2>/dev/null); then
    echo "$mtime"
    return 0
  fi
  if mtime=$(stat -f %m "$lock_dir" 2>/dev/null); then
    echo "$mtime"
    return 0
  fi
  # Cannot determine mtime — treat lock as non-stale (fail-closed)
  return 1
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
