#!/usr/bin/env bash
# on-stop-cursor.sh — Stop hook for the cursor pipeline.
# Invoked via exec from on-stop.sh when pipeline == "cursor".
# Reads state.json, processes C3 verdicts, generates orchestrator prompts.
#
# Exit codes:
#   0 with JSON — block Claude's stop and inject next phase prompt
#   0 silent    — allow stop (terminal state)
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/cursor.sh"

CURRENT_PHASE=$(state_get '.currentPhase' --required)
LOOP=$(state_get '.loop')
MAX_LOOPS=$(state_get '.maxLoops')
FIX_CYCLE=$(state_get '.fixCycle // 0')
MAX_FIX_CYCLES=$(state_get '.maxFixCycles // 5')
TASK=$(state_get '.task' --required)

LOOP=$(require_int "$LOOP" "loop")
MAX_LOOPS=$(require_int "$MAX_LOOPS" "maxLoops")
FIX_CYCLE=$(require_int "$FIX_CYCLE" "fixCycle")
MAX_FIX_CYCLES=$(require_int "$MAX_FIX_CYCLES" "maxFixCycles")

PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

# Recovery: advance state if output files exist but SubagentStop didn't fire.
# Note: 2>/dev/null is intentional — this is a best-effort recovery path.
# C2→C3: if c2-tasks.json exists and valid, advance to C3
if [[ "$CURRENT_PHASE" == "C2" && -f "${PHASES_DIR}/c2-tasks.json" ]]; then
  if validate_json_file "${PHASES_DIR}/c2-tasks.json" "c2-tasks.json" 2>/dev/null; then
    if jq -e '.tasks and .files_changed and .all_complete == true' "${PHASES_DIR}/c2-tasks.json" >/dev/null 2>&1; then
      if update_state '.currentPhase = "C3" | .updatedAt = $ts | .loops[-1].c2.status = "complete"'; then
        CURRENT_PHASE="C3"
      fi
    else
      echo "WARNING: c2-tasks.json exists but failed schema check; re-generating C2 prompt." >&2
    fi
  else
    echo "WARNING: c2-tasks.json exists but is invalid JSON; re-generating C2 prompt." >&2
  fi
fi

# C2.5→C3: if c2.5-fixes.json exists and valid, advance to C3
if [[ "$CURRENT_PHASE" == "C2.5" && -f "${PHASES_DIR}/c2.5-fixes.json" ]]; then
  if validate_json_file "${PHASES_DIR}/c2.5-fixes.json" "c2.5-fixes.json" 2>/dev/null; then
    if jq -e '.fixes and .files_changed and .all_complete == true' "${PHASES_DIR}/c2.5-fixes.json" >/dev/null 2>&1; then
      if update_state '.currentPhase = "C3" | .updatedAt = $ts'; then
        CURRENT_PHASE="C3"
      fi
    else
      echo "WARNING: c2.5-fixes.json exists but failed schema check; re-generating C2.5 prompt." >&2
    fi
  else
    echo "WARNING: c2.5-fixes.json exists but is invalid JSON; re-generating C2.5 prompt." >&2
  fi
fi

# C3 verdict processing
if [[ "$CURRENT_PHASE" == "C3" && -f "${PHASES_DIR}/c3-judge.json" ]]; then
  if ! validate_json_file "${PHASES_DIR}/c3-judge.json" "c3-judge.json"; then
    echo "ERROR: c3-judge.json exists but is invalid JSON." >&2
    exit 2
  fi

  VERDICT=$(jq -r '.verdict // empty' "${PHASES_DIR}/c3-judge.json") || {
    echo "ERROR: Failed to read verdict from c3-judge.json." >&2
    exit 2
  }

  # Validate verdict is one of the expected values
  if [[ "$VERDICT" != "approve" && "$VERDICT" != "fix" && "$VERDICT" != "replan" ]]; then
    echo "ERROR: c3-judge.json has unexpected verdict '${VERDICT}'. Expected approve, fix, or replan." >&2
    exit 2
  fi

  # Cross-validate: if verdict is approve but issues exist, force fix
  TOTAL_ISSUES=$(jq -r '.summary.total_issues // 0' "${PHASES_DIR}/c3-judge.json") || TOTAL_ISSUES=0
  if ! [[ "$TOTAL_ISSUES" =~ ^[0-9]+$ ]]; then
    echo "WARNING: c3-judge.json .summary.total_issues is not a valid integer ('${TOTAL_ISSUES}'). Defaulting to 0." >&2
    TOTAL_ISSUES=0
  fi
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
    echo "WARNING: c3-judge.json reports approve with critical/warning issues. Forcing fix." >&2
    VERDICT="fix"
  fi

  # Note: replan is handled AFTER this case block to catch both direct replan
  # verdicts and forced replans when fix cycles are exhausted.
  case "$VERDICT" in
    approve)
      if ! update_state --arg verdict "$VERDICT" \
        '.currentPhase = "C4" | .updatedAt = $ts | .loops[-1].c3.status = "complete" | .loops[-1].c3.verdict = $verdict'; then
        echo "ERROR: Failed to advance state from C3 to C4." >&2
        exit 2
      fi
      CURRENT_PHASE="C4"
      ;;

    fix)
      NEXT_FIX=$((FIX_CYCLE + 1))
      if [[ "$NEXT_FIX" -gt "$MAX_FIX_CYCLES" ]]; then
        # Max fix cycles exhausted — treat as replan
        echo "WARNING: Max fix cycles (${MAX_FIX_CYCLES}) reached. Forcing replan." >&2
        VERDICT="replan"
        # Fall through to replan handling below
      else
        # Remove stale files for clean re-run
        rm -f "${PHASES_DIR}/c3-judge.json" 2>/dev/null || true
        rm -f "${PHASES_DIR}/c2.5-fixes.json" 2>/dev/null || true
        rm -f "${PHASES_DIR}/.c25-advance.lock" 2>/dev/null || true
        if ! update_state --argjson fc "$NEXT_FIX" --arg verdict "$VERDICT" \
          '.currentPhase = "C2.5" | .fixCycle = $fc | .updatedAt = $ts | .loops[-1].c3.status = "complete" | .loops[-1].c3.verdict = $verdict'; then
          echo "ERROR: Failed to advance state from C3 to C2.5." >&2
          exit 2
        fi
        CURRENT_PHASE="C2.5"
      fi
      ;;
  esac

  # Handle replan (either direct or forced from fix exhaustion)
  if [[ "$VERDICT" == "replan" ]]; then
    NEXT_LOOP=$((LOOP + 1))
    if [[ "$NEXT_LOOP" -gt "$MAX_LOOPS" ]]; then
      if ! update_state --arg verdict "$VERDICT" \
        '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .loops[-1].c3.status = "complete" | .loops[-1].c3.verdict = $verdict | .failure = "Max replans reached"'; then
        echo "ERROR: Failed to update state to STOPPED." >&2
        exit 2
      fi
      CURRENT_PHASE="STOPPED"
    else
      if ! update_state --arg verdict "$VERDICT" --argjson nextLoop "$NEXT_LOOP" \
        '.currentPhase = "C1" | .loop = $nextLoop | .fixCycle = 0 | .updatedAt = $ts | .loops[-1].c3.status = "complete" | .loops[-1].c3.verdict = $verdict | .loops += [{"loop": $nextLoop, "startedAt": $ts, "c1": {"status": "pending"}, "c2": {"status": "pending"}, "c3": {"status": "pending"}}]'; then
        echo "ERROR: Failed to loop back to C1." >&2
        exit 2
      fi
      LOOP="$NEXT_LOOP"
      PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"
      CURRENT_PHASE="C1"
    fi
  fi
fi

# Allow stop on terminal states
case "$CURRENT_PHASE" in
  DONE|STOPPED)
    exit 0
    ;;
esac

# Generate phase-specific prompt
PROMPT=$(generate_cursor_prompt "$CURRENT_PHASE")

# Block stop and inject the orchestrator prompt
if ! jq_out=$(jq -n --arg reason "$PROMPT" '{"decision":"block","reason":$reason}' 2>&1); then
  echo "ERROR: jq failed to encode cursor prompt for phase ${CURRENT_PHASE}: $jq_out" >&2
  exit 2
fi
echo "$jq_out"
