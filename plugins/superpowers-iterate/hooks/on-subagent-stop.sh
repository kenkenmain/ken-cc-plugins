#!/usr/bin/env bash
# on-subagent-stop.sh -- SubagentStop hook for superpowers-iterate workflow phase advancement.
#
# Fires after every subagent completes. When a workflow is active, it validates
# the current phase's output, checks any stage gate, marks the phase completed,
# and advances state to the next phase. Includes iteration loop logic for Phase 8.
# This hook is a pure side-effect hook: it validates and advances state, then exits
# silently. The Stop hook (on-stop.sh) handles re-injecting the orchestrator prompt
# for the next phase (Ralph-style).
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
# 5.5 Iteration loop: Phase 8 decision point
# ---------------------------------------------------------------------------
if [[ "$CURRENT_PHASE" == "8" ]]; then
  REVIEW_STATUS="$(jq -r '.status // "unknown"' "$PHASES_DIR/8-final-review.json" 2>/dev/null)"
  CURRENT_ITER="$(state_get '.currentIteration // 1')"
  MAX_ITER="$(state_get '.maxIterations // 10')"
  MODE="$(state_get '.mode // "full"')"

  if [[ "$REVIEW_STATUS" == "approved" ]]; then
    # Zero issues — advance to Phase 9 (full) or Completion (lite)
    if [[ "$MODE" == "lite" ]]; then
      state_update ".currentPhase = \"C\" | .currentStage = \"FINAL\" | .stages.IMPLEMENT.phases[\"8\"].status = \"completed\""
    else
      state_update ".stages.IMPLEMENT.phases[\"8\"].status = \"completed\""
      # Normal advancement to Phase 9 handled below
    fi
  elif [[ "$CURRENT_ITER" -lt "$MAX_ITER" ]]; then
    # Issues found, iterations remaining — loop back to Phase 1
    NEXT_ITER=$((CURRENT_ITER + 1))

    # Archive current iteration's phase files
    ARCHIVE_DIR="$PHASES_DIR/iter-${CURRENT_ITER}"
    mkdir -p "$ARCHIVE_DIR"
    for f in "$PHASES_DIR"/*.{md,json}; do
      [[ -f "$f" ]] && mv "$f" "$ARCHIVE_DIR/"
    done

    state_update ".currentPhase = \"1\" | .currentStage = \"PLAN\" | .currentIteration = $NEXT_ITER | .stages.IMPLEMENT.phases[\"8\"].status = \"completed\""
    exit 0
  else
    # Max iterations reached — advance to Phase 9 (full) or Completion (lite)
    if [[ "$MODE" == "lite" ]]; then
      state_update ".currentPhase = \"C\" | .currentStage = \"FINAL\" | .stages.IMPLEMENT.phases[\"8\"].status = \"completed\""
    else
      state_update ".stages.IMPLEMENT.phases[\"8\"].status = \"completed\""
      # Normal advancement to Phase 9 handled below
    fi
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
