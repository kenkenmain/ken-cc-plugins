#!/usr/bin/env bash
# on-pre-compact.sh — PreCompact event handler for ants workflow.
# Saves critical workflow state metadata before context compaction.
# This ensures that after compaction, the workflow can resume
# by reading the preserved metadata from state.json.
#
# Exit codes:
#   0 — always (PreCompact cannot block)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

check_ants_workflow

# Build task pool summary if available
pool_summary='null'
has_pool=$(jq -r 'if .taskPool then "yes" else "no" end' "$STATE_FILE" 2>/dev/null || echo "no")
if [[ "$has_pool" == "yes" ]]; then
  pool_summary=$(jq '{
    total: (.taskPool | length),
    complete: ([.taskPool[] | select(.status == "complete")] | length),
    ready: ([.taskPool[] | select(.status == "ready")] | length),
    pending: ([.taskPool[] | select(.status == "pending")] | length),
    claimed: ([.taskPool[] | select(.status == "claimed")] | length),
    failed: ([.taskPool[] | select(.status == "failed")] | length)
  }' "$STATE_FILE" 2>/dev/null || echo 'null')
fi

# Save metadata to state (reads currentPhase, loop, status directly from state.json)
if ! update_state --argjson poolSummary "$pool_summary" \
  '.compactMetadata = {
    "savedAt": $ts,
    "currentPhase": .currentPhase,
    "loop": .loop,
    "status": .status,
    "taskPoolSummary": $poolSummary
  }'; then
  echo "WARNING: Failed to save compact metadata to state.json" >&2
fi

echo "INFO: PreCompact metadata saved" >&2
exit 0
