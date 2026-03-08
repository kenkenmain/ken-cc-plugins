#!/usr/bin/env bash
# dag.sh --- Phase-level DAG status tracker for ants v0.3 hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/dag.sh"
#
# Simple phase-status tracker. The actual DAG scheduling lives in A3's task
# pool (see task-pool.sh for dependency-driven dispatch). This library reads
# and writes the v3 state.json `.phases` object:
#
#   "phases": {
#     "A0": {"status": "complete"},
#     "A1": {"status": "in_progress"},
#     "A2": {"status": "pending"},
#     ...
#   }
#
# Valid statuses: pending | in_progress | complete
#
# Provides:
#   reset_phases_for_loop()   --- Reset A1-A4 to pending for loop-back

set -euo pipefail

# ===========================================================================
# Phase Status Functions
# ===========================================================================

# Reset phases A1 through A4 to pending for loop-back.
# Called when the queen verdict is "issues_found" and the workflow loops
# back from A4 to A1 for another iteration.
# A0 (explore) is NOT reset -- exploration results persist across loops.
# A5 (ship) is NOT reset -- it only runs after a clean verdict.
# Usage: reset_phases_for_loop
reset_phases_for_loop() {
  if ! update_state \
    '.phases = (.phases // {})
     | .phases.A1 = {"status": "pending"}
     | .phases.A2 = {"status": "pending"}
     | .phases.A3 = {"status": "pending"}
     | .phases.A4 = {"status": "pending"}'; then
    echo "ERROR: Failed to reset phases A1-A4 for loop-back" >&2
    return 1
  fi
}
