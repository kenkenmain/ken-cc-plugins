#!/usr/bin/env bash
# state.sh -- Shared library for reading/writing .agents/tmp/state.json
# Source this file from hook scripts: source "$(dirname "$0")/lib/state.sh"
set -euo pipefail

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
STATE_DIR="${CLAUDE_PROJECT_DIR:-.}/.agents/tmp"
STATE_FILE="$STATE_DIR/state.json"
STATE_TMP="$STATE_DIR/state.json.tmp"
PHASES_DIR="$STATE_DIR/phases"

# ---------------------------------------------------------------------------
# read_state -- Read the current state file, or echo {} if it does not exist.
# ---------------------------------------------------------------------------
read_state() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo '{}'
  fi
}

# ---------------------------------------------------------------------------
# state_get <jq_expr> -- Extract a value from state using a jq expression.
#   Example: state_get '.status'
#   Example: state_get '.currentPhase // empty'
# ---------------------------------------------------------------------------
state_get() {
  local expr="${1:?state_get requires a jq expression}"
  read_state | jq -r "$expr"
}

# ---------------------------------------------------------------------------
# state_write <json_string> -- Atomically write validated JSON to state.json.
#   Pipes through jq to ensure the payload is valid JSON, writes to a
#   temporary file, then moves it into place so readers never see a
#   partial write.
# ---------------------------------------------------------------------------
state_write() {
  local new_state="${1:?state_write requires a JSON string}"

  # Ensure the state directory exists
  mkdir -p "$STATE_DIR"

  # Validate JSON and pretty-print into the temp file
  echo "$new_state" | jq '.' > "$STATE_TMP"

  # Atomic replace
  mv "$STATE_TMP" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# state_update <jq_expr> -- Read current state, apply a jq transformation,
#   set updatedAt to the current ISO-8601 timestamp, and write back.
#   Example: state_update '.status = "in_progress"'
#   Example: state_update '.currentPhase = 3 | .phaseStatus = "running"'
# ---------------------------------------------------------------------------
state_update() {
  local expr="${1:?state_update requires a jq expression}"

  local current
  current="$(read_state)"

  local updated
  updated="$(echo "$current" | jq --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$expr | .updatedAt = \$ts")"

  state_write "$updated"
}

# ---------------------------------------------------------------------------
# phase_file_exists <filename> -- Check whether a phase marker file exists
#   under .agents/tmp/phases/. Returns 0 if it exists, 1 otherwise.
#   Example: if phase_file_exists "phase-3.json"; then ...
# ---------------------------------------------------------------------------
phase_file_exists() {
  local filename="${1:?phase_file_exists requires a filename}"
  [[ -f "$PHASES_DIR/$filename" ]]
}

# ---------------------------------------------------------------------------
# is_workflow_active -- Returns 0 (true) when the state file exists, belongs
#   to the subagents plugin (or has no plugin field for backward compat), and
#   the workflow status is "in_progress". Returns 1 (false) otherwise. The
#   plugin check prevents interference when both the subagents and
#   superpowers-iterate plugins are installed.
# ---------------------------------------------------------------------------
is_workflow_active() {
  # Fast-path: no state file at all
  [[ -f "$STATE_FILE" ]] || return 1

  local plugin status
  plugin="$(state_get '.plugin // empty')"
  status="$(state_get '.status // empty')"

  # Claim ownership if plugin is "subagents" or absent (backward compat with v2 states without plugin field)
  if [[ -n "$plugin" && "$plugin" != "subagents" ]]; then
    return 1
  fi

  [[ "$status" == "in_progress" ]]
}
