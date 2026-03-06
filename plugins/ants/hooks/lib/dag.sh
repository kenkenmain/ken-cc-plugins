#!/usr/bin/env bash
# dag.sh --- Phase-level DAG status tracker for ants v0.2 hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/dag.sh"
#
# Per S3 plan review: this is a SIMPLE phase-status tracker, NOT a full
# graph computation engine. The actual DAG scheduling lives in A3's task
# pool (see swarm.sh wave functions). This library reads and writes the
# v2 state.json `.phases` object:
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
#   get_phase_status()        --- Read phase status from state.json
#   is_phase_complete()       --- Check if a specific phase is complete
#   mark_phase_in_progress()  --- Mark a phase as in_progress
#   mark_phase_complete()     --- Mark a phase as complete
#   reset_phases_for_loop()   --- Reset A1-A4 to pending for loop-back

set -euo pipefail

# Valid phase IDs for validation
readonly DAG_PHASES="A0 A1 A2 A3 A4 A5"

# Valid phase statuses
readonly DAG_STATUS_PENDING="pending"
readonly DAG_STATUS_COMPLETE="complete"

# ===========================================================================
# Internal Helpers
# ===========================================================================

# Validate that a phase ID is known. Exits 2 on invalid input.
# Usage: _validate_phase_id "A3"
_validate_phase_id() {
  local phase="${1:?_validate_phase_id requires a phase ID}"
  local p
  for p in $DAG_PHASES; do
    if [[ "$p" == "$phase" ]]; then
      return 0
    fi
  done
  echo "ERROR: Invalid phase ID '${phase}'. Valid phases: ${DAG_PHASES}" >&2
  exit 2
}

# ===========================================================================
# Phase Status Functions
# ===========================================================================

# Read the status of a phase from state.json `.phases.{phase}.status`.
# Falls back to "pending" if the phases object or phase entry is missing
# (backward compatibility with v1 state files).
# Usage: status=$(get_phase_status "A2")
get_phase_status() {
  local phase="${1:?get_phase_status requires a phase ID}"
  _validate_phase_id "$phase"

  local status
  status=$(state_get ".phases.${phase}.status")

  # Fallback for v1 state files or missing entries
  if [[ -z "$status" ]]; then
    echo "$DAG_STATUS_PENDING"
    return 0
  fi

  echo "$status"
}

# Check if a specific phase is complete.
# Returns 0 (true) if complete, 1 (false) otherwise.
# Usage: if is_phase_complete "A0"; then echo "done"; fi
is_phase_complete() {
  local phase="${1:?is_phase_complete requires a phase ID}"
  local status
  status=$(get_phase_status "$phase")
  [[ "$status" == "$DAG_STATUS_COMPLETE" ]]
}

# Mark a phase as in_progress in state.json.
# Initializes the `.phases` object if it does not exist.
# Usage: mark_phase_in_progress "A1"
mark_phase_in_progress() {
  local phase="${1:?mark_phase_in_progress requires a phase ID}"
  _validate_phase_id "$phase"

  if ! update_state --arg phase "$phase" \
    '.phases = (.phases // {}) | .phases[$phase] = {"status": "in_progress", "startedAt": $ts}'; then
    echo "ERROR: Failed to mark phase ${phase} as in_progress" >&2
    return 1
  fi
}

# Mark a phase as complete in state.json.
# Initializes the `.phases` object if it does not exist.
# Usage: mark_phase_complete "A0"
mark_phase_complete() {
  local phase="${1:?mark_phase_complete requires a phase ID}"
  _validate_phase_id "$phase"

  if ! update_state --arg phase "$phase" \
    '.phases = (.phases // {}) | .phases[$phase].status = "complete" | .phases[$phase].completedAt = $ts'; then
    echo "ERROR: Failed to mark phase ${phase} as complete" >&2
    return 1
  fi
}

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
