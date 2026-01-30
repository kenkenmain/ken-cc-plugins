#!/usr/bin/env bash
# on-subagent-stop.sh -- SubagentStop hook for workflow phase advancement.
#
# Fires after every subagent completes. When a workflow is active, it validates
# the current phase's output, checks any stage gate, marks the phase completed,
# and advances state to the next phase. This hook is a pure side-effect hook:
# it validates and advances state, then exits silently. The Stop hook (on-stop.sh)
# handles re-injecting the orchestrator prompt for the next phase (Ralph-style).
#
# Exit codes:
#   0 - Allow (no active workflow, or workflow advanced / completed)
#   2 - Validation failure (missing output file or failed gate)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source shared libraries
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/gates.sh"
source "$SCRIPT_DIR/lib/schedule.sh"

# ---------------------------------------------------------------------------
# 1. Consume stdin (hook input -- ignored for now)
# ---------------------------------------------------------------------------
cat > /dev/null

# ---------------------------------------------------------------------------
# 2. If workflow not active, exit silently (allow, no output)
# ---------------------------------------------------------------------------
if ! is_workflow_active; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Read currentPhase and currentStage from state
# ---------------------------------------------------------------------------
CURRENT_PHASE="$(state_get '.currentPhase // empty')"
CURRENT_STAGE="$(state_get '.currentStage // empty')"

if [[ -z "$CURRENT_PHASE" || -z "$CURRENT_STAGE" ]]; then
  echo "on-subagent-stop: no currentPhase or currentStage in state" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 4. Validate: expected output file for currentPhase exists
# ---------------------------------------------------------------------------
EXPECTED_OUTPUT="$(get_phase_output "$CURRENT_PHASE")"

if [[ -z "$EXPECTED_OUTPUT" ]]; then
  echo "on-subagent-stop: unknown phase '$CURRENT_PHASE' -- no expected output" >&2
  exit 2
fi

if ! phase_file_exists "$EXPECTED_OUTPUT"; then
  echo "on-subagent-stop: expected output file '$EXPECTED_OUTPUT' not found for phase $CURRENT_PHASE" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 5. Check if currentPhase triggers a stage gate
# ---------------------------------------------------------------------------
GATE_KEY="$(get_gate_for_phase "$CURRENT_PHASE")"

if [[ -n "$GATE_KEY" ]]; then
  GATE_RESULT="$(validate_gate "$GATE_KEY")"
  GATE_PASSED="$(echo "$GATE_RESULT" | jq -r '.passed')"

  if [[ "$GATE_PASSED" != "true" ]]; then
    GATE_MISSING="$(echo "$GATE_RESULT" | jq -r '.missing | join(", ")')"
    echo "on-subagent-stop: stage gate '$GATE_KEY' failed -- missing: $GATE_MISSING" >&2
    exit 2
  fi
fi

# ---------------------------------------------------------------------------
# 6. Mark current phase completed in state
# ---------------------------------------------------------------------------
state_update ".stages[\"$CURRENT_STAGE\"].phases[\"$CURRENT_PHASE\"].status = \"completed\""

# ---------------------------------------------------------------------------
# 7. Get next phase and decide: advance or complete
# ---------------------------------------------------------------------------
NEXT_PHASE_JSON="$(get_next_phase "$CURRENT_PHASE")"

if [[ "$NEXT_PHASE_JSON" == "null" ]]; then
  # All phases done -- mark workflow completed, output nothing
  state_update ".status = \"completed\""
  exit 0
fi

# Advance state to the next phase
NEXT_PHASE="$(echo "$NEXT_PHASE_JSON" | jq -r '.phase')"
NEXT_STAGE="$(echo "$NEXT_PHASE_JSON" | jq -r '.stage')"

state_update ".currentPhase = \"$NEXT_PHASE\" | .currentStage = \"$NEXT_STAGE\""

# ---------------------------------------------------------------------------
# 8. Exit silently — no stdout output.
#    The Stop hook (on-stop.sh) handles re-injecting the full orchestrator
#    prompt (Ralph-style). This hook only validates and advances state.
# ---------------------------------------------------------------------------
exit 0
