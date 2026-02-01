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
source "$SCRIPT_DIR/lib/review.sh"
source "$SCRIPT_DIR/lib/fallback.sh"

# ---------------------------------------------------------------------------
# 1. Read stdin (hook input -- contains agent metadata)
# ---------------------------------------------------------------------------
HOOK_INPUT="$(cat)"

# ---------------------------------------------------------------------------
# 2. If workflow not active, exit silently (allow, no output)
# ---------------------------------------------------------------------------
if ! is_workflow_active; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 2b. Guard: only process subagents state (ignore other plugins' workflows)
# ---------------------------------------------------------------------------
STATE_PLUGIN="$(state_get '.plugin // empty')"
if [[ -n "$STATE_PLUGIN" && "$STATE_PLUGIN" != "subagents" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 2c. Session scoping: if a different session, don't interfere
# ---------------------------------------------------------------------------
if ! check_session_owner; then
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
# 4. Review-fix cycle: if a fix agent just completed, clear the cycle
#    and let the orchestrator re-dispatch the review phase fresh.
#    For parallel fix groups: decrement pending counter, only clear when
#    all groups are done.
#    IMPORTANT: This check MUST come before output file validation (4a/4b)
#    because complete_fix_cycle deletes the review output file. Concurrent
#    fix-dispatchers completing after that deletion would hit a missing-file
#    path if we checked output first.
# ---------------------------------------------------------------------------
# Extract agent type from hook input for dispatch-specific logic
AGENT_TYPE="$(echo "$HOOK_INPUT" | jq -r '.agent_type // .agentName // .subagent_type // .agentType // .type // empty' 2>/dev/null || echo "")"

if is_fix_cycle_active && [[ "$AGENT_TYPE" == "subagents:fix-dispatcher" ]]; then
  # Only fix-dispatcher completions should decrement/clear the fix cycle.
  # Other agents (supplementary reviewers, etc.) completing during a fix
  # cycle are ignored — they don't produce the phase output file.
  #
  # Use flock for atomicity — concurrent fix-dispatchers completing at the
  # same time must not both read the same pendingGroups value.
  GROUP_COUNT="$(state_get '.reviewFix.groupCount // 1')"
  if [[ "$GROUP_COUNT" -gt 1 ]]; then
    LOCK_FILE="$STATE_DIR/state.lock"
    # Atomic decrement: flock ensures only one process decrements at a time.
    # Stdout capture keeps the result in-process (no shared temp file).
    PENDING="$(
      (
        flock -x 200
        PENDING_INNER="$(state_get '.reviewFix.pendingGroups // 0')"
        PENDING_INNER=$((PENDING_INNER - 1))
        state_update ".reviewFix.pendingGroups = $PENDING_INNER"
        echo "$PENDING_INNER"
      ) 200>"$LOCK_FILE"
    )"
    if [[ "$PENDING" -gt 0 ]]; then
      # More fix groups still running — wait
      exit 0
    fi
  fi
  complete_fix_cycle
  # Don't advance — currentPhase stays on the review phase.
  # Stop hook will re-inject orchestrator → orchestrator sees no reviewFix
  # → dispatches review again.
  exit 0
fi

# If a fix cycle is active but a non-fix agent completed (e.g., late
# supplementary agent or unknown agent type), ignore it — fixes are
# still in progress. Note: if AGENT_TYPE extraction fails (empty) for a
# fix-dispatcher, this path also fires. The workflow recovers because
# the Stop hook re-injects the orchestrator which sees reviewFix.pendingGroups
# still > 0 and re-dispatches. This is a fallback — ideally AGENT_TYPE
# extraction works and the flock path above handles it cleanly.
if is_fix_cycle_active; then
  exit 0
fi

# ---------------------------------------------------------------------------
# 4a. Validate: expected output file for currentPhase exists
# ---------------------------------------------------------------------------
EXPECTED_OUTPUT="$(get_phase_output "$CURRENT_PHASE")"

if [[ -z "$EXPECTED_OUTPUT" ]]; then
  echo "on-subagent-stop: unknown phase '$CURRENT_PHASE' -- no expected output" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 4b. Check for Codex timeout output or missing output — handle with fallback
# ---------------------------------------------------------------------------
if is_codex_timeout "$CURRENT_PHASE"; then
  handle_missing_or_timeout "$CURRENT_PHASE" "$CURRENT_STAGE"
  exit 0  # Let Stop hook re-inject → orchestrator re-dispatches with updated agents
fi

if ! phase_file_exists "$EXPECTED_OUTPUT"; then
  # Check if the completing agent is supplementary — supplementary agents
  # don't produce the phase output file, so a missing file is expected.
  # AGENT_TYPE was extracted earlier (section 4).
  if [[ -n "$AGENT_TYPE" ]] && is_supplementary_agent "$AGENT_TYPE"; then
    exit 0  # Supplementary agent done — ignore, primary will write output
  fi
  handle_missing_or_timeout "$CURRENT_PHASE" "$CURRENT_STAGE"
  exit 0  # Let Stop hook re-inject → retry
fi

# ---------------------------------------------------------------------------
# 4c. For review phases: validate review output for blocking issues.
#     Dynamic supplementary: on first failure with "on-issues" policy,
#     trigger a supplementary run before starting fix cycles.
#     If issues found after supplementary, start a fix cycle.
# ---------------------------------------------------------------------------
if is_review_phase "$CURRENT_PHASE"; then
  REVIEW_RESULT="$(validate_review_output "$CURRENT_PHASE")"
  REVIEW_PASSED="$(echo "$REVIEW_RESULT" | jq -r '.passed')"

  # Clear supplementaryRun for this phase when review passes, so future
  # re-reviews (after stage restart) start fresh with primary-only again
  if [[ "$REVIEW_PASSED" == "true" ]]; then
    state_update "del(.supplementaryRun[\"$CURRENT_PHASE\"])" 2>/dev/null || true
  fi

  if [[ "$REVIEW_PASSED" != "true" ]]; then
    # Dynamic supplementary: on first failure, trigger supplementary run
    SUPP_POLICY="$(get_supplementary_policy 2>/dev/null || echo "on-issues")"
    if [[ "$SUPP_POLICY" == "on-issues" ]]; then
      SUPP_RUN="$(state_get ".supplementaryRun[\"$CURRENT_PHASE\"] // false")"
      if [[ "$SUPP_RUN" != "true" ]]; then
        # Check if this phase has supplementary agents at all
        SUPP_LIST="$(_raw_supplementary_agents "$CURRENT_PHASE" 2>/dev/null || echo "")"
        if [[ -n "$SUPP_LIST" ]]; then
          # First failure: mark for supplementary run, delete output so
          # review re-dispatches with supplementary included
          state_update ".supplementaryRun[\"$CURRENT_PHASE\"] = true"
          rm -f "$PHASES_DIR/$EXPECTED_OUTPUT"
          exit 0
        fi
      fi
    fi

    ISSUE_COUNT="$(echo "$REVIEW_RESULT" | jq -r '.issueCount')"
    MIN_SEV="$(get_min_block_severity)"
    MAX_ATTEMPTS="$(get_max_fix_attempts)"

    # Check per-phase fix attempt counter (persists across fix cycles)
    CURRENT_ATTEMPT="$(state_get ".stages[\"$CURRENT_STAGE\"].phases[\"$CURRENT_PHASE\"].fixAttempts // 0")"

    if [[ "$CURRENT_ATTEMPT" -ge "$MAX_ATTEMPTS" ]]; then
      # Fix attempts exhausted — try restarting the entire stage
      RESTART_REASON="Review phase $CURRENT_PHASE exhausted $MAX_ATTEMPTS fix attempts ($ISSUE_COUNT issue(s) remain)"

      if restart_stage "$CURRENT_STAGE" "$CURRENT_PHASE" "$RESTART_REASON"; then
        # Stage restart succeeded — orchestrator will re-dispatch from first phase
        echo "on-subagent-stop: stage $CURRENT_STAGE restarted (fix attempts exhausted at phase $CURRENT_PHASE) -- retrying from first phase" >&2
        exit 0
      fi

      # Stage restarts also exhausted — truly block
      MAX_RESTARTS="$(get_max_stage_restarts)"
      CURRENT_RESTARTS="$(state_get ".stages[\"$CURRENT_STAGE\"].stageRestarts // 0")"
      state_update "
        .status = \"blocked\" |
        .stages[\"$CURRENT_STAGE\"].blockReason = \"Review phase $CURRENT_PHASE failed after $MAX_ATTEMPTS fix attempts x $MAX_RESTARTS stage restarts ($ISSUE_COUNT issue(s) remain)\" |
        .stages[\"$CURRENT_STAGE\"].phases[\"$CURRENT_PHASE\"].status = \"blocked\" |
        .stages[\"$CURRENT_STAGE\"].phases[\"$CURRENT_PHASE\"].reviewResult = $REVIEW_RESULT |
        del(.reviewFix)
      "
      echo "on-subagent-stop: review phase $CURRENT_PHASE blocked after $MAX_ATTEMPTS fix attempts x $CURRENT_RESTARTS stage restarts -- $ISSUE_COUNT issue(s) remain at severity >= $MIN_SEV" >&2
      exit 2
    fi

    # Start a fix cycle — don't advance, don't block.
    # Orchestrator will see state.reviewFix and dispatch a fix agent.
    start_fix_cycle "$CURRENT_PHASE" "$CURRENT_STAGE" "$REVIEW_RESULT"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# 4d. Coverage loop: if phase 3.5 completed with needs_coverage status,
#     loop back to phase 3.3 instead of advancing.
# ---------------------------------------------------------------------------
if [[ "$CURRENT_PHASE" == "3.5" ]]; then
  REVIEW_OUTPUT="$PHASES_DIR/$(get_phase_output "3.5")"
  if [[ -f "$REVIEW_OUTPUT" ]]; then
    COVERAGE_MET="$(jq -r '.coverage.met // true' "$REVIEW_OUTPUT")"
    REVIEW_STATUS="$(jq -r '.status // empty' "$REVIEW_OUTPUT")"

    if [[ "$COVERAGE_MET" == "false" && "$REVIEW_STATUS" == "needs_coverage" ]]; then
      CURRENT_COVERAGE="$(jq -r '.coverage.current // 0' "$REVIEW_OUTPUT")"
      THRESHOLD="$(state_get '.coverageThreshold // 90')"

      # Read or initialize coverage loop state
      LOOP_ITERATION="$(state_get '.coverageLoop.iteration // 0')"
      MAX_LOOP="$(state_get '.coverageLoop.maxIterations // 20')"
      NEXT_LOOP=$((LOOP_ITERATION + 1))

      if [[ "$NEXT_LOOP" -gt "$MAX_LOOP" ]]; then
        # Max iterations reached — proceed to FINAL with warning
        state_update "
          .coverageLoop.exhausted = true |
          .coverageLoop.finalCoverage = $CURRENT_COVERAGE |
          .stages[\"$CURRENT_STAGE\"].phases[\"$CURRENT_PHASE\"].status = \"completed\"
        "
        # Fall through to gate check and normal advancement
      else
        # Loop back to 3.3: update state, delete stale outputs
        state_update "
          .coverageLoop = {
            \"currentCoverage\": $CURRENT_COVERAGE,
            \"threshold\": $THRESHOLD,
            \"iteration\": $NEXT_LOOP,
            \"maxIterations\": $MAX_LOOP,
            \"reason\": \"Coverage ${CURRENT_COVERAGE}% < ${THRESHOLD}% threshold\"
          } |
          .currentPhase = \"3.3\" |
          .stages[\"$CURRENT_STAGE\"].phases[\"$CURRENT_PHASE\"].status = \"completed\"
        "
        # Delete stale output files for 3.3, 3.4, 3.5
        rm -f "$PHASES_DIR/3.3-test-dev.json"
        rm -f "$PHASES_DIR/3.4-test-dev-review.json"
        rm -f "$PHASES_DIR/3.5-test-review.json"
        exit 0
      fi
    fi
  fi
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
