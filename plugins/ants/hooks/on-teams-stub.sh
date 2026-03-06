#!/usr/bin/env bash
# on-teams-stub.sh — No-op stub for future Agent Teams events.
# Logs the event for diagnostics and exits 0 (allow).
#
# This hook is registered for TeammateIdle and TaskCompleted events
# so that when the Agent Teams API becomes available, these events are
# already wired up. The actual logic will be implemented when teams.sh
# dispatch mode switches from "subagent" to "teams".
#
# Exit codes:
#   0 always — no-op, allow the event

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read event type from stdin if available
INPUT=""
if ! test -t 0; then
  INPUT=$(cat 2>/dev/null || true)
fi

EVENT_TYPE="${CLAUDE_HOOK_EVENT_NAME:-unknown}"

echo "[TEAMS-STUB] Received event: ${EVENT_TYPE} (no-op)" >&2

exit 0
