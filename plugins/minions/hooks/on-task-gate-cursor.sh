#!/usr/bin/env bash
# on-task-gate-cursor.sh — Task gate for the cursor pipeline.
# Invoked via exec from on-task-gate.sh when pipeline == "cursor".
# Validates that the dispatched agent matches the current phase
# and that required prerequisites exist.
#
# Receives agent type via CURSOR_AGENT_TYPE env var (stdin already consumed by parent hook).
#
# Exit codes:
#   0 silent   — allow (non-cursor agent or agent valid for current phase)
#   0 with JSON — block with reason
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/cursor.sh"

AGENT_TYPE="${CURSOR_AGENT_TYPE:?on-task-gate-cursor.sh requires CURSOR_AGENT_TYPE}"

# Allow non-minions agents through
case "$AGENT_TYPE" in
  minions:*|sub-scout|cursor-builder|judge|shipper|explorer-*) ;; # check below
  *) exit 0 ;;
esac

CURRENT_PHASE=$(state_get '.currentPhase' --required)

# Allow explorers in any phase (they run pre-C1)
case "$AGENT_TYPE" in
  explorer-*|minions:explorer-*) exit 0 ;;
esac

# Check agent is allowed in current phase
if is_cursor_agent_allowed "$AGENT_TYPE" "$CURRENT_PHASE"; then
  # Check prerequisites
  LOOP=$(state_get '.loop')
  LOOP=$(require_int "$LOOP" "loop")
  PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

  case "$CURRENT_PHASE" in
    C2)
      if [[ ! -f "${PHASES_DIR}/c1-plan.md" ]]; then
        jq -n '{"decision":"block","reason":"Cannot start C2 (build): c1-plan.md not found. Sub-scouts must complete and plan must be aggregated first."}'
        exit 0
      fi
      ;;
    C2.5)
      # Trust the state machine: if currentPhase is C2.5, the judge already issued a fix verdict.
      # c3-judge.json is cleaned up during fix transitions to prevent stale verdict processing,
      # so we validate via fixCycle in state.json instead of the file.
      fix_cycle=$(state_get '.fixCycle // 0')
      if ! [[ "$fix_cycle" =~ ^[0-9]+$ ]] || [[ "$fix_cycle" -lt 1 ]]; then
        jq -n '{"decision":"block","reason":"Cannot start C2.5 (fix): fixCycle is 0 or missing. Judge must issue a fix verdict first."}'
        exit 0
      fi
      ;;
    C3)
      # C3 requires either c2-tasks.json (first judge) or c2.5-fixes.json (after fix cycle)
      if [[ ! -f "${PHASES_DIR}/c2-tasks.json" && ! -f "${PHASES_DIR}/c2.5-fixes.json" ]]; then
        jq -n '{"decision":"block","reason":"Cannot start C3 (judge): neither c2-tasks.json nor c2.5-fixes.json found. Builders must complete first."}'
        exit 0
      fi
      ;;
    C4)
      VERDICT_FILE="${PHASES_DIR}/c3-judge.json"
      if [[ ! -f "$VERDICT_FILE" ]]; then
        jq -n '{"decision":"block","reason":"Cannot start C4 (ship): c3-judge.json not found. Judge must complete first."}'
        exit 0
      fi
      VERDICT=$(jq -r '.verdict // empty' "$VERDICT_FILE" 2>/dev/null || echo "")
      if [[ "$VERDICT" != "approve" ]]; then
        jq -n --arg v "$VERDICT" \
          '{"decision":"block","reason":("Cannot start C4 (ship): judge verdict is \"" + $v + "\", not \"approve\".")}'
        exit 0
      fi
      ;;
  esac

  exit 0
fi

# Block with explanation
ALLOWED_PHASES=$(get_cursor_agent_phases "$AGENT_TYPE")
if [[ -z "$ALLOWED_PHASES" ]]; then
  # Not a recognized cursor pipeline agent — allow through without gating
  echo "WARNING: Unrecognized agent '${AGENT_TYPE}' in cursor task gate; allowing through." >&2
  exit 0
fi

jq -n --arg agent "$AGENT_TYPE" --arg current "$CURRENT_PHASE" --arg allowed "$ALLOWED_PHASES" \
  '{"decision":"block","reason":("Cannot dispatch " + $agent + " during phase " + $current + ". This agent is allowed in phases: " + $allowed + ". Follow the cursor pipeline order: C1 (sub-scout) → C2 (cursor-builder) → C3 (judge) → C4 (shipper).")}'
exit 0
