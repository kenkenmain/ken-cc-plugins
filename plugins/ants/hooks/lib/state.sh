#!/usr/bin/env bash
# state.sh — Shared state helpers for ants hooks
# Source this from hook scripts: source "$SCRIPT_DIR/lib/state.sh"

# Bootstrap: STATE_FILE, jq check, ERR trap
set -euo pipefail
_ANTS_STATE_DIR="${BASH_SOURCE[0]%/*}/../../../../lib"
[[ -f "$_ANTS_STATE_DIR/common-state.sh" ]] || { echo "ERROR: cannot locate common-state.sh" >&2; exit 2; }
source "$_ANTS_STATE_DIR/common-state.sh"

# Check if an ants workflow is active and owned by this session.
# Returns 0 if we should proceed, exits 0 (allow) if we should not.
check_ants_workflow() {
  # No state file = no active workflow
  if [[ ! -f "$STATE_FILE" ]]; then
    exit 0
  fi

  # State file must be a valid JSON object (not a scalar, array, or garbage)
  if ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
    echo "ERROR: state.json is not a valid JSON object (found: $(jq -r 'type' "$STATE_FILE" 2>/dev/null || echo 'unparseable')). State may be corrupt." >&2
    exit 2
  fi

  # Batch-read all guard fields in a single jq call to avoid repeated file reads
  local guard_fields
  guard_fields=$(jq -r '[.plugin // "", .status // "", .ownerPpid // "", .sessionId // "", (.version // 1 | tostring)] | join("\t")' "$STATE_FILE")
  local plugin status owner_ppid state_session_id version
  IFS=$'\t' read -r plugin status owner_ppid state_session_id version <<< "$guard_fields"

  # Plugin guard — only handle ants workflows
  if [[ "$plugin" != "ants" ]]; then
    exit 0
  fi

  # Session scoping - ownerPpid
  if [[ -n "$owner_ppid" && "$owner_ppid" != "$PPID" ]]; then
    exit 0
  fi

  # Session scoping - sessionId
  if [[ -n "$state_session_id" && -n "${CLAUDE_SESSION_ID:-}" && "$state_session_id" != "$CLAUDE_SESSION_ID" ]]; then
    exit 0
  fi

  # Status check
  if [[ "$status" != "in_progress" ]]; then
    exit 0
  fi

  # Migrate state schema if needed (fall-through: v1->v2->v3->v4->v5)
  if [[ "$version" == "1" ]]; then
    migrate_state_v1_to_v2
    version="2"
  fi
  if [[ "$version" == "2" ]]; then
    migrate_state_v2_to_v3
    version="3"
  fi
  if [[ "$version" == "3" ]]; then
    migrate_state_v3_to_v4
    version="4"
  fi
  if [[ "$version" == "4" ]]; then
    migrate_state_v4_to_v5
    version="5"
  fi

  return 0
}

# Read a field from state.json. Exits 2 if the field is missing/empty and required.
# Usage: state_get '.currentPhase' [--required]
state_get() {
  local filter="$1"
  local required="${2:-}"
  local value
  # Append `// empty` to convert null → "" for required checks.
  # Callers with fallbacks (e.g., '.loop // 1') produce '.loop // 1 // empty'
  # which is correct: jq alternative is left-associative, so 1 stays 1.
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
#   - mkdir fallback includes stale lock detection (30s timeout)
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
        exit 1
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

  # Clean up temp files on any exit from this function scope
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

# Get the mtime of a directory as epoch seconds (cross-platform: macOS/Linux).
# Returns 0 on success with mtime on stdout, 1 on failure.
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

# Migrate state.json from v1 to v2.
# Adds phases, circuitBreaker, taskPool, dispatchMode, and agentTeamsAvailable
# fields if missing. Safe to call multiple times -- only sets fields that do not exist.
# Usage: migrate_state_v1_to_v2
migrate_state_v1_to_v2() {
  echo "INFO: Migrating state.json from v1 to v2" >&2
  if ! update_state '
    .version = 2 |
    .phases //= {
      "A0": {"status": "pending"},
      "A1": {"status": "pending"},
      "A2": {"status": "pending"},
      "A3": {"status": "pending"},
      "A4": {"status": "pending"},
      "A5": {"status": "pending"}
    } |
    .circuitBreaker //= {
      "consecutiveFailures": 0,
      "maxConsecutiveFailures": 5,
      "maxFixAttempts": 5,
      "maxStageRestarts": 2,
      "fixAttempts": {},
      "stageRestarts": 0
    } |
    .taskPool //= [] |
    .dispatchMode //= "subagent" |
    .agentTeamsAvailable //= false
  '; then
    echo "ERROR: Failed to migrate state from v1 to v2" >&2
    return 1
  fi
  echo "INFO: State migration v1->v2 complete" >&2
  return 0
}

# Migrate state.json from v2 to v3.
# Removes dispatchMode and agentTeamsAvailable fields (teams-only in v0.3).
# Adds teamName field if missing.
# Usage: migrate_state_v2_to_v3
migrate_state_v2_to_v3() {
  echo "INFO: Migrating state.json from v2 to v3" >&2
  if ! update_state '
    .version = 3 |
    del(.dispatchMode) |
    del(.agentTeamsAvailable) |
    .teamName //= ("ants-" + (.branch // "default" | split("/") | last))
  '; then
    echo "ERROR: Failed to migrate state from v2 to v3" >&2
    return 1
  fi
  echo "INFO: State migration v2->v3 complete" >&2
  return 0
}

# Migrate state.json from v3 to v4.
# Adds worktreePath, messages, planApproved, shutdown, webhookUrl, lintConfig,
# configSnapshot, and compactMetadata fields if missing.
# Usage: migrate_state_v3_to_v4
migrate_state_v3_to_v4() {
  echo "INFO: Migrating state.json from v3 to v4" >&2
  if ! update_state '
    .version = 4 |
    .worktreePath //= null |
    .messages //= [] |
    .planApproved //= false |
    .shutdown //= false |
    .webhookUrl //= null |
    .lintConfig //= null |
    .configSnapshot //= null |
    .compactMetadata //= null
  '; then
    echo "ERROR: Failed to migrate state from v3 to v4" >&2
    return 1
  fi
  echo "INFO: State migration v3->v4 complete" >&2
  return 0
}

# Migrate state.json from v4 to v5.
# Adds webSearch field if missing (defaults to false).
# Usage: migrate_state_v4_to_v5
migrate_state_v4_to_v5() {
  echo "INFO: Migrating state.json from v4 to v5" >&2
  if ! update_state '
    .version = 5 |
    .webSearch //= false
  '; then
    echo "ERROR: Failed to migrate state from v4 to v5" >&2
    return 1
  fi
  echo "INFO: State migration v4->v5 complete" >&2
  return 0
}

# Output a continue:false JSON response and exit 0.
# Used by hooks that need to signal Claude to stop gracefully.
# Usage: continue_false_exit "reason message"
continue_false_exit() {
  local reason="${1:?continue_false_exit requires a reason}"
  jq -n --arg reason "$reason" '{"continue": false, "stopReason": $reason}'
  exit 0
}

# Check if the shutdown flag is set in state.json.
# If true, calls continue_false_exit to stop the workflow gracefully.
# Usage: shutdown_check
shutdown_check() {
  local shutdown_flag
  shutdown_flag=$(jq -r '.shutdown // false' "$STATE_FILE" 2>/dev/null || echo "false")
  if [[ "$shutdown_flag" == "true" ]]; then
    continue_false_exit "Ants workflow shutting down gracefully (shutdown flag set)"
  fi
}

# Add a message to the messages array in state.json for cross-phase communication.
# Usage: add_message "from_agent" "to_agent" "message content"
add_message() {
  local from="${1:?add_message requires from}"
  local to="${2:?add_message requires to}"
  local content="${3:?add_message requires content}"
  update_state --arg from "$from" --arg to "$to" --arg content "$content" \
    '.messages += [{"from": $from, "to": $to, "content": $content, "loop": (.loop // 1), "addedAt": $ts}]'
}

# Get messages targeted at a specific recipient from state.json.
# Returns a JSON array of matching messages, or "[]" if none found.
# Usage: msgs=$(get_messages_for "architect")
get_messages_for() {
  local recipient="${1:?get_messages_for requires recipient}"
  jq -r --arg to "$recipient" '[.messages[]? | select(.to == $to)]' "$STATE_FILE" 2>/dev/null || echo "[]"
}
