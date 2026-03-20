#!/usr/bin/env bash
# on-stop.sh — Graceful shutdown for ants workflow via continue:false
# Sets .shutdown=true in state and signals Claude to stop.
# For complete/blocked/stopped workflows, allows stop without intervention.
# For pswarm with remaining runs, blocks the stop unless shutdown was already requested.
# For queen-as-persistent-dispatcher: blocks premature stop unless A4 verdict exists
# or workflow has reached a terminal state (complete/blocked/STOPPED).
#
# Exit codes:
#   0 silent    — allow stop (no active workflow, complete/blocked/stopped)
#   0 with JSON — continue:false (in_progress → graceful shutdown)
#   2 with stderr — block stop (queen without verdict, pswarm with remaining runs, or corrupt state)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

# check_ants_workflow exits 0 if no state file, wrong plugin, wrong session,
# or status is not in_progress. Only returns 0 (continues) for in_progress.
check_ants_workflow

# Single jq call to batch-read all guard fields — avoids TOCTOU between reads
local_fields=$(jq -r '[(.pipeline // "swarm"), (.shutdown // false | tostring), ((.pswarmRun // 1) | tostring), ((.maxRuns // 50) | tostring), (.currentPhase // "A0"), ((.loop // 1) | tostring)] | join("\t")' "$STATE_FILE")
IFS=$'\t' read -r pipeline shutdown_flag pswarm_run max_runs current_phase loop <<< "$local_fields"

# Queen-as-persistent-dispatcher guard:
# The queen drives A0→A5 and must not stop prematurely. Block stop unless:
#   1. A4-queen-verdict.json exists for the current loop (decision was made), OR
#   2. currentPhase is DONE or STOPPED (workflow reached terminal state), OR
#   3. shutdown flag is already set (explicit override)
if [[ "$shutdown_flag" != "true" && "$current_phase" != "DONE" && "$current_phase" != "STOPPED" ]]; then
  loop=$(require_int "$loop" "loop")
  verdict_file=".agents/tmp/phases/loop-${loop}/A4-queen-verdict.json"
  if [[ "$(realpath -m "$verdict_file")" != "$(realpath .agents/tmp/phases/)"* ]]; then
    echo "STOP-GATE: verdict_file path escapes allowed directory" >&2
    exit 2
  fi
  if [[ ! -f "$verdict_file" ]]; then
    echo "STOP-GATE: Queen has not written A4-queen-verdict.json for loop ${loop}. The pipeline decision (ship vs loop) is required before stopping. Complete A4 verdict or set shutdown=true in state.json to override." >&2
    exit 2
  fi
fi

# pswarm guard: block premature stop if runs remain
if [[ "$pipeline" == "pswarm" && "$shutdown_flag" != "true" ]]; then
  pswarm_run=$(require_int "$pswarm_run" "pswarmRun")
  max_runs=$(require_int "$max_runs" "maxRuns")
  if [[ "$pswarm_run" -lt "$max_runs" ]]; then
    echo "COMPLETION-GATE: pswarm has remaining runs ($pswarm_run/$max_runs). Execute the completion gate in pswarm.md before stopping. Set shutdown=true in state.json to override." >&2
    exit 2
  fi
fi

# Workflow is in_progress — set shutdown flag
if ! update_state '.shutdown = true | .updatedAt = $ts'; then
  echo "ERROR: Failed to persist shutdown flag to state.json" >&2
  exit 2
fi

# Signal Claude to stop gracefully
continue_false_exit "Ants workflow shutdown initiated. Teammates will complete current tasks."
