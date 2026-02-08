#!/usr/bin/env bash
# on-subagent-stop-cursor.sh — SubagentStop hook for the cursor pipeline.
# Invoked via exec from on-subagent-stop.sh when pipeline == "cursor".
# Validates output, advances state, handles judge verdicts.
#
# Receives agent type via CURSOR_AGENT_TYPE env var (stdin already consumed by parent hook).
#
# Exit codes:
#   0 silent — allow (non-cursor agent or explorers)
#   0 with JSON — provide context to orchestrator
#   2 with stderr — block, output file missing or corrupt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/cursor.sh"

AGENT_TYPE="${CURSOR_AGENT_TYPE:?on-subagent-stop-cursor.sh requires CURSOR_AGENT_TYPE}"

# Map agent type
case "$AGENT_TYPE" in
  explorer-files|minions:explorer-files) exit 0 ;;
  explorer-architecture|minions:explorer-architecture) exit 0 ;;
  explorer-tests|minions:explorer-tests) exit 0 ;;
  explorer-patterns|minions:explorer-patterns) exit 0 ;;
  sub-scout|minions:sub-scout) AGENT="sub-scout" ;;
  cursor-builder|minions:cursor-builder) AGENT="cursor-builder" ;;
  judge|minions:judge) AGENT="judge" ;;
  shipper|minions:shipper) AGENT="shipper" ;;
  *)
    # Not a recognized cursor pipeline agent — allow stop without processing
    echo "WARNING: Unrecognized agent '${AGENT_TYPE}' in cursor SubagentStop; allowing through." >&2
    exit 0
    ;;
esac

LOOP=$(state_get '.loop')
MAX_LOOPS=$(state_get '.maxLoops')
FIX_CYCLE=$(state_get '.fixCycle // 0')
MAX_FIX_CYCLES=$(state_get '.maxFixCycles // 5')

LOOP=$(require_int "$LOOP" "loop")
MAX_LOOPS=$(require_int "$MAX_LOOPS" "maxLoops")
FIX_CYCLE=$(require_int "$FIX_CYCLE" "fixCycle")
MAX_FIX_CYCLES=$(require_int "$MAX_FIX_CYCLES" "maxFixCycles")

PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

case "$AGENT" in
  sub-scout)
    # Sub-scouts write partial plans. The orchestrator aggregates into c1-plan.md.
    # Only advance when c1-plan.md exists (orchestrator writes it after aggregation).
    if [[ ! -f "${PHASES_DIR}/c1-plan.md" ]]; then
      # Not all sub-scouts done or orchestrator hasn't aggregated yet
      exit 0
    fi

    if [[ ! -s "${PHASES_DIR}/c1-plan.md" ]]; then
      echo "ERROR: c1-plan.md exists but is empty." >&2
      exit 2
    fi

    # Idempotency: only advance if still in C1
    CURRENT=$(jq -r '.currentPhase // empty' "$STATE_FILE" 2>/dev/null) || {
      echo "WARNING: Failed to read currentPhase for idempotency check; skipping advancement." >&2
      exit 0
    }
    if [[ "$CURRENT" == "C1" ]]; then
      if ! update_state '.currentPhase = "C2" | .updatedAt = $ts | .loops[-1].c1.status = "complete"'; then
        echo "ERROR: Failed to advance state from C1 to C2." >&2
        exit 2
      fi
    fi
    ;;

  cursor-builder)
    CURRENT_PHASE=$(state_get '.currentPhase' --required)

    if [[ "$CURRENT_PHASE" == "C2" ]]; then
      # Builders in C2: wait for c2-tasks.json (orchestrator writes after all builders)
      if [[ -f "${PHASES_DIR}/c2-tasks.json" ]]; then
        if ! validate_json_file "${PHASES_DIR}/c2-tasks.json" "c2-tasks.json"; then
          echo "ERROR: c2-tasks.json is invalid JSON." >&2
          exit 2
        fi
        if ! jq -e '.tasks and .files_changed and .all_complete == true' "${PHASES_DIR}/c2-tasks.json" >/dev/null 2>&1; then
          exit 0  # Not all complete yet
        fi

        # Use lock to prevent duplicate advancement
        C2_LOCK_DIR="${PHASES_DIR}/.c2-advance.lock"
        if ! mkdir "$C2_LOCK_DIR" 2>/dev/null; then
          if [[ -d "$C2_LOCK_DIR" ]]; then
            local_mtime=""
            if local_mtime=$(lock_dir_mtime_epoch "$C2_LOCK_DIR"); then
              local_age=$(( $(date +%s) - local_mtime ))
              if [[ "$local_age" -gt 60 ]]; then
                rm -rf "$C2_LOCK_DIR"
                mkdir "$C2_LOCK_DIR" 2>/dev/null || exit 0
              else
                exit 0
              fi
            else
              exit 0
            fi
          else
            exit 0
          fi
        fi

        CURRENT=$(jq -r '.currentPhase // empty' "$STATE_FILE" 2>/dev/null) || {
          echo "WARNING: Failed to read currentPhase for C2 idempotency check; skipping advancement." >&2
          rm -rf "$C2_LOCK_DIR" 2>/dev/null || true
          exit 0
        }
        if [[ "$CURRENT" == "C2" ]]; then
          if ! update_state '.currentPhase = "C3" | .updatedAt = $ts | .loops[-1].c2.status = "complete"'; then
            rm -rf "$C2_LOCK_DIR" 2>/dev/null || true
            echo "ERROR: Failed to advance state from C2 to C3." >&2
            exit 2
          fi
        fi
        rm -rf "$C2_LOCK_DIR" 2>/dev/null || true
      fi

    elif [[ "$CURRENT_PHASE" == "C2.5" ]]; then
      # Fix-builders in C2.5: wait for c2.5-fixes.json
      if [[ -f "${PHASES_DIR}/c2.5-fixes.json" ]]; then
        if ! validate_json_file "${PHASES_DIR}/c2.5-fixes.json" "c2.5-fixes.json"; then
          echo "ERROR: c2.5-fixes.json is invalid JSON." >&2
          exit 2
        fi
        if ! jq -e '.fixes and .files_changed and .all_complete == true' "${PHASES_DIR}/c2.5-fixes.json" >/dev/null 2>&1; then
          exit 0
        fi

        C25_LOCK_DIR="${PHASES_DIR}/.c25-advance.lock"
        if ! mkdir "$C25_LOCK_DIR" 2>/dev/null; then
          if [[ -d "$C25_LOCK_DIR" ]]; then
            local_mtime=""
            if local_mtime=$(lock_dir_mtime_epoch "$C25_LOCK_DIR"); then
              local_age=$(( $(date +%s) - local_mtime ))
              if [[ "$local_age" -gt 60 ]]; then
                rm -rf "$C25_LOCK_DIR"
                mkdir "$C25_LOCK_DIR" 2>/dev/null || exit 0
              else
                exit 0
              fi
            else
              exit 0
            fi
          else
            exit 0
          fi
        fi

        CURRENT=$(jq -r '.currentPhase // empty' "$STATE_FILE" 2>/dev/null) || {
          echo "WARNING: Failed to read currentPhase for C2.5 idempotency check; skipping advancement." >&2
          rm -rf "$C25_LOCK_DIR" 2>/dev/null || true
          exit 0
        }
        if [[ "$CURRENT" == "C2.5" ]]; then
          if ! update_state '.currentPhase = "C3" | .updatedAt = $ts'; then
            rm -rf "$C25_LOCK_DIR" 2>/dev/null || true
            echo "ERROR: Failed to advance state from C2.5 to C3." >&2
            exit 2
          fi
        fi
        rm -rf "$C25_LOCK_DIR" 2>/dev/null || true
      fi
    fi
    ;;

  judge)
    # Validate C3 output
    if [[ ! -f "${PHASES_DIR}/c3-judge.json" ]]; then
      echo "Judge completed but c3-judge.json not found." >&2
      exit 2
    fi
    if ! validate_json_file "${PHASES_DIR}/c3-judge.json" "c3-judge.json"; then
      echo "ERROR: c3-judge.json is invalid JSON." >&2
      exit 2
    fi

    VERDICT=$(jq -r '.verdict // empty' "${PHASES_DIR}/c3-judge.json") || {
      echo "ERROR: Failed to read verdict from c3-judge.json." >&2
      exit 2
    }
    if [[ "$VERDICT" != "approve" && "$VERDICT" != "fix" && "$VERDICT" != "replan" ]]; then
      echo "ERROR: c3-judge.json has unexpected verdict '${VERDICT}'. Expected approve, fix, or replan." >&2
      exit 2
    fi

    # Cross-validate: approve with critical/warning issues → force fix
    CRITICAL=$(jq -r '.summary.critical // 0' "${PHASES_DIR}/c3-judge.json") || CRITICAL=0
    WARNING=$(jq -r '.summary.warning // 0' "${PHASES_DIR}/c3-judge.json") || WARNING=0
    if ! [[ "$CRITICAL" =~ ^[0-9]+$ ]]; then
      echo "WARNING: c3-judge.json .summary.critical is not a valid integer ('${CRITICAL}'). Defaulting to 0." >&2
      CRITICAL=0
    fi
    if ! [[ "$WARNING" =~ ^[0-9]+$ ]]; then
      echo "WARNING: c3-judge.json .summary.warning is not a valid integer ('${WARNING}'). Defaulting to 0." >&2
      WARNING=0
    fi

    if [[ "$VERDICT" == "approve" && $(( CRITICAL + WARNING )) -gt 0 ]]; then
      echo "WARNING: Judge approved with ${CRITICAL} critical + ${WARNING} warning issues. Forcing fix." >&2
      VERDICT="fix"
    fi

    # Note: replan is handled AFTER this case block to catch both direct replan
    # verdicts and forced replans when fix cycles are exhausted.
    case "$VERDICT" in
      approve)
        if ! update_state --arg verdict "$VERDICT" \
          '.currentPhase = "C4" | .updatedAt = $ts | .loops[-1].c3.status = "complete" | .loops[-1].c3.verdict = $verdict'; then
          echo "ERROR: Failed to advance from C3 to C4." >&2
          exit 2
        fi
        ;;

      fix)
        NEXT_FIX=$((FIX_CYCLE + 1))
        if [[ "$NEXT_FIX" -gt "$MAX_FIX_CYCLES" ]]; then
          # Exhausted fix cycles — force replan
          echo "WARNING: Max fix cycles (${MAX_FIX_CYCLES}) reached. Forcing replan." >&2
          VERDICT="replan"
          # Fall through to replan below
        else
          # Remove stale files for clean re-run
          rm -f "${PHASES_DIR}/c2.5-fixes.json" 2>/dev/null || true
          rm -f "${PHASES_DIR}/.c25-advance.lock" 2>/dev/null || true
          rm -f "${PHASES_DIR}/c3-judge.json" 2>/dev/null || true
          if ! update_state --argjson fc "$NEXT_FIX" --arg verdict "fix" \
            '.currentPhase = "C2.5" | .fixCycle = $fc | .updatedAt = $ts | .loops[-1].c3.status = "complete" | .loops[-1].c3.verdict = $verdict'; then
            echo "ERROR: Failed to advance from C3 to C2.5." >&2
            exit 2
          fi
        fi
        ;;
    esac

    # Handle replan (direct or forced from fix exhaustion)
    if [[ "$VERDICT" == "replan" ]]; then
      NEXT_LOOP=$((LOOP + 1))
      if [[ "$NEXT_LOOP" -gt "$MAX_LOOPS" ]]; then
        if ! update_state --arg verdict "replan" \
          '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .loops[-1].c3.status = "complete" | .loops[-1].c3.verdict = $verdict | .failure = "Max replans reached"'; then
          echo "ERROR: Failed to update state to STOPPED." >&2
          exit 2
        fi
        jq -n --arg reason "WORKFLOW STOPPED: Maximum replans (${MAX_LOOPS}) reached. Review the latest judge output in ${PHASES_DIR}/c3-judge.json for remaining issues." \
          '{"decision":"block","reason":$reason}'
      else
        if ! update_state --arg verdict "replan" --argjson nextLoop "$NEXT_LOOP" \
          '.currentPhase = "C1" | .loop = $nextLoop | .fixCycle = 0 | .updatedAt = $ts | .loops[-1].c3.status = "complete" | .loops[-1].c3.verdict = $verdict | .loops += [{"loop": $nextLoop, "startedAt": $ts, "c1": {"status": "pending"}, "c2": {"status": "pending"}, "c3": {"status": "pending"}}]'; then
          echo "ERROR: Failed to loop back to C1." >&2
          exit 2
        fi
      fi
    fi
    ;;

  shipper)
    if [[ ! -f "${PHASES_DIR}/c4-ship.json" ]]; then
      echo "Shipper completed but c4-ship.json not found." >&2
      exit 2
    fi
    if ! validate_json_file "${PHASES_DIR}/c4-ship.json" "c4-ship.json"; then
      echo "ERROR: c4-ship.json is invalid JSON." >&2
      exit 2
    fi
    if ! jq -e '.commit_sha and .docs_updated' "${PHASES_DIR}/c4-ship.json" >/dev/null 2>&1; then
      echo "ERROR: c4-ship.json missing required fields (commit_sha, docs_updated)." >&2
      exit 2
    fi

    if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts | .loops[-1].c4 = {"status": "complete"}'; then
      echo "ERROR: Failed to mark workflow as complete." >&2
      exit 2
    fi
    ;;
esac

exit 0
