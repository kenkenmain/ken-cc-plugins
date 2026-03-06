#!/usr/bin/env bash
# on-subagent-stop.sh — Validate output, advance state, handle loop-back
# Fires when any subagent finishes. Validates output exists, updates state,
# and determines whether to advance or loop back.
#
# Exit codes:
#   0 silent — allow (non-ants agent or no active workflow)
#   0 with JSON — provide context to orchestrator
#   2 with stderr — block, output file missing or corrupt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/swarm.sh"

check_ants_workflow

# Read input from stdin
INPUT=$(cat)
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "ERROR: No valid JSON received on stdin for SubagentStop hook." >&2
  exit 2
fi

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_name // empty')

# Only handle ants agents
case "$AGENT_TYPE" in
  forager|ants:forager|cartographer|ants:cartographer|explore-aggregator|ants:explore-aggregator)
    AGENT="explorer" ;;
  architect|ants:architect)     AGENT="planner" ;;
  blueprint-reviewer|ants:blueprint-reviewer)   AGENT="reviewer" ;;
  # All A3 agents (worker, sentinel, guardian) share the builder completion path.
  # Guardian writes tests (builder-like) and sentinel reviews code -- both produce
  # per-wave outputs that the orchestrator aggregates into A3-build.json.
  worker|ants:worker|sentinel|ants:sentinel|guardian|ants:guardian)
    AGENT="builder" ;;
  queen|ants:queen)         AGENT="queen" ;;
  nurse|ants:nurse)
    AGENT="nurse" ;;
  drone|ants:drone)
    AGENT="drone" ;;
  *) exit 0 ;; # Not an ants agent, allow
esac

LOOP=$(state_get '.loop // 1')
MAX_LOOPS=$(state_get '.maxLoops // 5')
LOOP=$(require_int "$LOOP" "loop")
MAX_LOOPS=$(require_int "$MAX_LOOPS" "maxLoops")

PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

case "$AGENT" in
  explorer)
    # Validate A0 output exists (A0 is top-level, not loop-scoped)
    if [[ ! -f ".agents/tmp/phases/A0-explore.md" ]]; then
      echo "Explorer completed but A0-explore.md not found. Explorer must write output to .agents/tmp/phases/A0-explore.md" >&2
      exit 2
    fi

    # Advance to A1
    if ! update_state '.currentPhase = "A1" | .updatedAt = $ts | .phases.A0.status = "complete"'; then
      echo "ERROR: Failed to advance state from A0 to A1." >&2
      exit 2
    fi
    ;;

  planner)
    # Validate A1 output exists
    if [[ ! -f "${PHASES_DIR}/A1-plan.md" ]]; then
      echo "Planner completed but A1-plan.md not found. Planner must write plan to ${PHASES_DIR}/A1-plan.md" >&2
      exit 2
    fi

    # Advance to A2
    if ! update_state '.currentPhase = "A2" | .updatedAt = $ts | .phases.A1.status = "complete"'; then
      echo "ERROR: Failed to advance state from A1 to A2." >&2
      exit 2
    fi
    ;;

  reviewer)
    # Validate A2 output exists
    if [[ ! -f "${PHASES_DIR}/A2-review.json" ]]; then
      echo "Reviewer completed but A2-review.json not found." >&2
      exit 2
    fi
    if ! validate_json_file "${PHASES_DIR}/A2-review.json" "A2-review.json"; then
      echo "ERROR: A2-review.json is invalid JSON." >&2
      exit 2
    fi

    # Check if blueprint review requires revision
    local review_status
    review_status=$(jq -r '.status // .verdict // empty' "${PHASES_DIR}/A2-review.json" 2>/dev/null || echo "")
    local high_count
    high_count=$(jq -r '[.issues[]? | select(.severity == "HIGH" or .severity == "critical")] | length' "${PHASES_DIR}/A2-review.json" 2>/dev/null || echo "0")

    if [[ "$review_status" == "needs_revision" && "$high_count" -gt 0 ]]; then
      echo "INFO: Blueprint review needs revision with ${high_count} HIGH/critical issues -- looping back to A1." >&2
      NEXT_LOOP=$((LOOP + 1))
      if [[ "$NEXT_LOOP" -gt "$MAX_LOOPS" ]]; then
        if ! update_state '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .phases.A2.status = "complete" | .failure = "Max loops reached: blueprint review has unresolved HIGH issues"'; then
          echo "ERROR: Failed to update state to STOPPED after blueprint review failure." >&2
          exit 2
        fi
      else
        if ! update_state --argjson nextLoop "$NEXT_LOOP" \
          '.currentPhase = "A1" | .loop = $nextLoop | .updatedAt = $ts | .phases.A2.status = "complete" | .loops += [{"loop": $nextLoop, "startedAt": $ts}]'; then
          echo "ERROR: Failed to loop back to A1 after blueprint review failure." >&2
          exit 2
        fi
      fi
    else
      # Advance to A3
      if ! update_state '.currentPhase = "A3" | .updatedAt = $ts | .phases.A2.status = "complete"'; then
        echo "ERROR: Failed to advance state from A2 to A3." >&2
        exit 2
      fi
    fi
    ;;

  builder)
    # When A3-build.json exists and is valid, advance to A4.
    # The orchestrator writes A3-build.json after aggregating all builders.
    if [[ -f "${PHASES_DIR}/A3-build.json" ]]; then
      if ! validate_json_file "${PHASES_DIR}/A3-build.json" "A3-build.json"; then
        echo "ERROR: A3-build.json exists but is invalid. Builders must produce valid JSON." >&2
        exit 2
      fi
      if ! jq -e '.tasks and .files_changed and .all_complete == true' "${PHASES_DIR}/A3-build.json" >/dev/null 2>&1; then
        echo "ERROR: A3-build.json missing required fields or all_complete is not true." >&2
        exit 2
      fi

      # Use mkdir lock to prevent duplicate advancement (race condition guard)
      A3_LOCK_DIR="${PHASES_DIR}/.a3-advance.lock"
      A3_LOCK_STALE_SECONDS=60
      if ! mkdir "$A3_LOCK_DIR" 2>/dev/null; then
        # Check if lock is stale
        if [[ -d "$A3_LOCK_DIR" ]]; then
          a3_lock_mtime=""
          if a3_lock_mtime=$(lock_dir_mtime_epoch "$A3_LOCK_DIR"); then
            a3_lock_age=$(( $(date +%s) - a3_lock_mtime ))
            if [[ "$a3_lock_age" -gt "$A3_LOCK_STALE_SECONDS" ]]; then
              echo "WARNING: Removing stale A3 lock directory (age: ${a3_lock_age}s)" >&2
              rm -rf "$A3_LOCK_DIR"
              mkdir "$A3_LOCK_DIR" 2>/dev/null || {
                echo "INFO: A3 lock contention after stale removal, deferring to other process" >&2
                exit 0
              }
            else
              echo "INFO: A3 lock held by another process (age: ${a3_lock_age}s), deferring advancement" >&2
              exit 0
            fi
          else
            echo "WARNING: Cannot determine A3 lock age, deferring advancement" >&2
            exit 0  # Cannot determine age, fail-closed
          fi
        else
          exit 0
        fi
      fi

      # Idempotency: only advance if still in A3
      CURRENT=$(jq -r '.currentPhase // empty' "$STATE_FILE" 2>/dev/null || echo "")
      if [[ "$CURRENT" == "A3" ]]; then
        if ! update_state '.currentPhase = "A4" | .updatedAt = $ts | .phases.A3.status = "complete"'; then
          rm -rf "$A3_LOCK_DIR" 2>/dev/null || true
          echo "ERROR: Failed to advance state from A3 to A4." >&2
          exit 2
        fi
      fi
      rm -rf "$A3_LOCK_DIR" 2>/dev/null || true
    fi
    # If A3-build.json doesn't exist yet, this is an individual builder completing.
    # The orchestrator aggregates after all builders finish. No state change yet.
    ;;

  queen)
    # Validate A4 output exists
    if [[ ! -f "${PHASES_DIR}/A4-queen-verdict.json" ]]; then
      echo "Queen completed but A4-queen-verdict.json not found." >&2
      exit 2
    fi
    if ! validate_json_file "${PHASES_DIR}/A4-queen-verdict.json" "A4-queen-verdict.json"; then
      echo "ERROR: A4-queen-verdict.json is invalid JSON." >&2
      exit 2
    fi

    # VERDICT and TOTAL_ISSUES are set by parse_queen_verdict in caller scope
    parse_queen_verdict "${PHASES_DIR}/A4-queen-verdict.json"

    if [[ "$VERDICT" == "clean" ]]; then
      # Advance to A5
      if ! update_state --arg verdict "$VERDICT" \
        '.currentPhase = "A5" | .updatedAt = $ts | .phases.A4.status = "complete" | .phases.A4.verdict = $verdict'; then
        echo "ERROR: Failed to advance state from A4 to A5." >&2
        exit 2
      fi
    else
      # Issues found — loop back to A1 or stop
      NEXT_LOOP=$((LOOP + 1))
      if [[ "$NEXT_LOOP" -gt "$MAX_LOOPS" ]]; then
        if ! update_state --arg verdict "$VERDICT" \
          '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .phases.A4.status = "complete" | .phases.A4.verdict = $verdict | .failure = "Max loops reached with unresolved issues"'; then
          echo "ERROR: Failed to update state to STOPPED." >&2
          exit 2
        fi

        jq -n --arg reason "WORKFLOW STOPPED: Maximum loops (${MAX_LOOPS}) reached with unresolved issues. Review the latest A4 outputs in .agents/tmp/phases/loop-${LOOP}/ for remaining issues." \
          '{"decision":"block","reason":$reason}'
      else
        if ! update_state --arg verdict "$VERDICT" --argjson nextLoop "$NEXT_LOOP" \
          '.currentPhase = "A1" | .loop = $nextLoop | .updatedAt = $ts | .phases.A4.status = "complete" | .phases.A4.verdict = $verdict | .loops += [{"loop": $nextLoop, "startedAt": $ts}]'; then
          echo "ERROR: Failed to loop back to A1." >&2
          exit 2
        fi
      fi
    fi
    ;;

  nurse)
    # Validate nurse documentation output (A5-docs.json)
    # Nurse completing does not advance phase -- drone still needs to run.
    if [[ -f "${PHASES_DIR}/A5-docs.json" ]]; then
      if ! validate_json_file "${PHASES_DIR}/A5-docs.json" "A5-docs.json"; then
        echo "WARNING: A5-docs.json exists but is invalid JSON. Drone can still proceed." >&2
      fi
    fi
    # No state change -- nurse is the first sub-step of A5, drone is second.
    ;;

  drone)
    # Validate A5 ship output exists (drone writes this)
    if [[ ! -f "${PHASES_DIR}/A5-ship.json" ]]; then
      echo "Drone completed but A5-ship.json not found." >&2
      exit 2
    fi
    if ! validate_json_file "${PHASES_DIR}/A5-ship.json" "A5-ship.json"; then
      echo "ERROR: A5-ship.json is invalid JSON." >&2
      exit 2
    fi
    if ! jq -e '.commit_sha' "${PHASES_DIR}/A5-ship.json" >/dev/null 2>&1; then
      echo "ERROR: A5-ship.json missing required field (commit_sha)." >&2
      exit 2
    fi

    # Workflow complete
    if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts | .phases.A5.status = "complete"'; then
      echo "ERROR: Failed to mark workflow as complete." >&2
      exit 2
    fi
    ;;
esac

exit 0
