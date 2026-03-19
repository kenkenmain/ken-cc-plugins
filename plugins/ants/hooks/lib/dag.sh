#!/usr/bin/env bash
# dag.sh --- Phase-level DAG status tracker for ants v0.6 hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/dag.sh"
#
# Simple phase-status tracker. The actual DAG scheduling lives in A3's task
# pool (see task-pool.sh for dependency-driven dispatch). This library reads
# and writes the v6 state.json `.phases` object:
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
# Reset functions also increment `.taskGraphVersion` to signal the command's
# monitoring loop that a new task graph needs to be created via TaskCreate.
# Signal flags (needsA3Tasks, needsA5Tasks, needsLoopReset, needsPswarmReset)
# are cleared on reset to prevent stale signals from previous iterations.
#
# Provides:
#   reset_phases_for_loop()    --- Reset A1-A4 to pending, increment taskGraphVersion, clear signal flags
#   reset_phases_for_pswarm()  --- Reset A0-A5 to pending, increment taskGraphVersion, reset team state, clear all signal flags

set -euo pipefail

# ===========================================================================
# Phase Status Functions
# ===========================================================================

# Reset phases A1 through A4 to pending for loop-back.
# Called when the verdict is "issues_found" and the workflow loops
# back from A4 to A1 for another iteration.
# A0 (explore) is NOT reset -- exploration results persist across loops.
# A5 (ship) is NOT reset -- it only runs after a clean verdict.
# Also increments taskGraphVersion to signal task graph recreation, and
# clears signal flags (needsA3Tasks, needsA5Tasks, needsLoopReset).
# Usage: reset_phases_for_loop
reset_phases_for_loop() {
  # Note: .phases.A3 = {"status": "pending"} implicitly clears buildTrackComplete
  # by overwriting the entire A3 object (same as the pswarm reset path).
  if ! update_state \
    '.phases = (.phases // {})
     | .phases.A1 = {"status": "pending"}
     | .phases.A2 = {"status": "pending"}
     | .phases.A3 = {"status": "pending"}
     | .phases.A4 = {"status": "pending"}
     | .taskGraphVersion = ((.taskGraphVersion // 0) + 1)
     | .needsA3Tasks = false
     | .needsA5Tasks = false
     | .needsLoopReset = false'; then
    echo "ERROR: Failed to reset phases A1-A4 for loop-back" >&2
    return 1
  fi
}

# Reset all phases A0 through A5 to pending for pswarm run boundaries.
# Called when the pswarm pipeline completes a full A0→A5 run and is about
# to start a new run. Unlike reset_phases_for_loop(), this also resets
# A0 (exploration) because each pswarm run re-explores the changed codebase.
# Also increments taskGraphVersion to signal task graph recreation, resets
# teamCreated and teammateCount, and clears all signal flags.
# Usage: reset_phases_for_pswarm
reset_phases_for_pswarm() {
  if ! update_state \
    '.phases = (.phases // {})
     | .phases.A0 = {"status": "pending"}
     | .phases.A1 = {"status": "pending"}
     | .phases.A2 = {"status": "pending"}
     | .phases.A3 = {"status": "pending"}
     | .phases.A4 = {"status": "pending"}
     | .phases.A5 = {"status": "pending"}
     | .taskGraphVersion = ((.taskGraphVersion // 0) + 1)
     | .teamCreated = false
     | .teammateCount = 0
     | .needsA3Tasks = false
     | .needsA5Tasks = false
     | .needsLoopReset = false
     | .needsPswarmReset = false'; then
    echo "ERROR: Failed to reset phases A0-A5 for pswarm run" >&2
    return 1
  fi
}
