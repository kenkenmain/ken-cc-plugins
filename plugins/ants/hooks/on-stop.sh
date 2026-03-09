#!/usr/bin/env bash
# on-stop.sh — Graceful shutdown for ants workflow via continue:false
# Sets .shutdown=true in state and signals Claude to stop.
# For complete/blocked/stopped workflows, allows stop without intervention.
# For pswarm with remaining runs, blocks the stop unless shutdown was already requested.
#
# Exit codes:
#   0 silent    — allow stop (no active workflow, complete/blocked/stopped)
#   0 with JSON — continue:false (in_progress → graceful shutdown)
#   2 with stderr — block stop (pswarm with remaining runs, or corrupt state)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

# check_ants_workflow exits 0 if no state file, wrong plugin, wrong session,
# or status is not in_progress. Only returns 0 (continues) for in_progress.
check_ants_workflow

# pswarm guard: block premature stop if runs remain
# Single jq call to avoid TOCTOU between reads
local_fields=$(jq -r '[(.pipeline // "swarm"), (.shutdown // false | tostring), ((.pswarmRun // 1) | tostring), ((.maxRuns // 50) | tostring)] | join("\t")' "$STATE_FILE")
IFS=$'\t' read -r pipeline shutdown_flag pswarm_run max_runs <<< "$local_fields"

if [[ "$pipeline" == "pswarm" && "$shutdown_flag" != "true" ]]; then
  pswarm_run=$(require_int "$pswarm_run" "pswarmRun")
  max_runs=$(require_int "$max_runs" "maxRuns")
  if [[ "$pswarm_run" -lt "$max_runs" ]]; then
    echo "COMPLETION-GATE: pswarm has remaining runs ($pswarm_run/$max_runs). Execute the completion gate in pswarm.md before stopping. Set shutdown=true in state.json to override." >&2
    exit 2
  fi
fi

# Workflow is in_progress — set shutdown flag
update_state '.shutdown = true | .updatedAt = $ts'

# Signal Claude to stop gracefully
continue_false_exit "Ants workflow shutdown initiated. Teammates will complete current tasks."
