#!/usr/bin/env bash
# webhook.sh -- Fire-and-forget HTTP webhook notifications for ants hooks
# Source this from hook scripts: source "$SCRIPT_DIR/lib/webhook.sh"
#
# Provides webhook_fire(), webhook_phase_event(), and webhook_workflow_event()
# for sending HTTP notifications to an external URL configured in state.json.
#
# All webhook calls are non-blocking (background curl) and never fail the hook.

set -euo pipefail

# webhook_fire -- Send a webhook notification
# Arguments:
#   $1 = event name (e.g., "phase.completed", "workflow.blocked")
#   $2 = JSON payload data (optional, defaults to "{}")
# Returns 0 always. Errors are swallowed.
webhook_fire() {
  local event="${1:?webhook_fire requires event name}"
  local payload="${2:-"{}"}"

  # Check curl availability at call time (not source time)
  if ! command -v curl &>/dev/null; then
    return 0
  fi

  # Read webhook URL from state
  local url
  url=$(jq -r '.webhookUrl // empty' "$STATE_FILE" 2>/dev/null || echo "")
  if [[ -z "$url" ]]; then
    return 0
  fi

  # Validate URL scheme -- only allow http:// and https:// to prevent SSRF
  if [[ ! "$url" =~ ^https?:// ]]; then
    echo "WARNING: webhookUrl has disallowed scheme (only http/https permitted), skipping" >&2
    return 0
  fi

  # Build ISO timestamp
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")

  # Build full webhook body
  local body
  body=$(jq -n \
    --arg event "$event" \
    --arg timestamp "$timestamp" \
    --arg plugin "ants" \
    --argjson data "$payload" \
    '{"event": $event, "timestamp": $timestamp, "plugin": $plugin, "data": $data}' 2>/dev/null || echo "")

  if [[ -z "$body" ]]; then
    return 0
  fi

  # POST in background with 5s timeout -- never block, never fail.
  # Background curls are short-lived (max 5s) and self-terminate.
  # --max-redirs 0 prevents redirect-based SSRF bypasses.
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$body" \
    --max-time 5 \
    --max-redirs 0 \
    "$url" &>/dev/null &

  return 0
}

# webhook_phase_event -- Send a phase lifecycle event
# Arguments:
#   $1 = phase ID (e.g., "A0", "A3")
#   $2 = status ("started"|"completed"|"failed")
webhook_phase_event() {
  local phase="${1:?webhook_phase_event requires phase ID}"
  local status="${2:?webhook_phase_event requires status}"

  local loop
  loop=$(jq -r '.loop // 1' "$STATE_FILE" 2>/dev/null || echo "1")

  local payload
  payload=$(jq -n \
    --arg phase "$phase" \
    --arg status "$status" \
    --argjson loop "$loop" \
    '{"phase": $phase, "status": $status, "loop": $loop}' 2>/dev/null || echo '{}')

  webhook_fire "phase.${status}" "$payload"
}

# webhook_workflow_event -- Send a workflow lifecycle event
# Arguments:
#   $1 = status ("completed"|"blocked"|"stopped")
webhook_workflow_event() {
  local status="${1:?webhook_workflow_event requires status}"

  local task
  task=$(jq -r '.task // empty' "$STATE_FILE" 2>/dev/null || echo "")
  local loop
  loop=$(jq -r '.loop // 1' "$STATE_FILE" 2>/dev/null || echo "1")

  local payload
  payload=$(jq -n \
    --arg status "$status" \
    --arg task "$task" \
    --argjson loop "$loop" \
    '{"status": $status, "task": $task, "loop": $loop}' 2>/dev/null || echo '{}')

  webhook_fire "workflow.${status}" "$payload"
}
