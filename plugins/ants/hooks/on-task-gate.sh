#!/usr/bin/env bash
# on-task-gate.sh — Block out-of-order Task dispatches
# PreToolUse hook for Task tool. Validates that the dispatched agent
# matches the current phase and that required prerequisites exist.
#
# Exit codes:
#   0 silent   — allow (no active workflow or non-ants agent)
#   0 with JSON — block with reason
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/swarm.sh"

check_ants_workflow

# Read input
INPUT=$(cat)
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "ERROR: No valid JSON received on stdin for PreToolUse hook." >&2
  exit 2
fi

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty')

# Map agent type to expected phase
case "$AGENT_TYPE" in
  forager|ants:forager|cartographer|ants:cartographer|explore-aggregator|ants:explore-aggregator)
    EXPECTED_PHASE="A0" ;;
  architect|ants:architect)     EXPECTED_PHASE="A1" ;;
  blueprint-reviewer|ants:blueprint-reviewer)   EXPECTED_PHASE="A2" ;;
  worker|ants:worker|sentinel|ants:sentinel|guardian|ants:guardian|\
  sentinel-correctness|ants:sentinel-correctness|\
  sentinel-security|ants:sentinel-security|\
  sentinel-perf|ants:sentinel-perf|\
  review-arbiter|ants:review-arbiter|\
  review-fixer|ants:review-fixer)
    EXPECTED_PHASE="A3" ;;
  queen|ants:queen)         EXPECTED_PHASE="A4" ;;
  nurse|ants:nurse|drone|ants:drone)
    EXPECTED_PHASE="A5" ;;
  *) exit 0 ;; # Not an ants agent, allow
esac

CURRENT_PHASE=$(state_get '.currentPhase' --required)
LOOP=$(state_get '.loop // 1')
LOOP=$(require_int "$LOOP" "loop")
PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

# Check phase matches
if [[ "$CURRENT_PHASE" != "$EXPECTED_PHASE" ]]; then
  jq -n --arg agent "$AGENT_TYPE" --arg expected "$EXPECTED_PHASE" --arg current "$CURRENT_PHASE" \
    '{"decision":"block","reason":("Cannot dispatch " + $agent + " during phase " + $current + ". Expected phase: " + $expected + ". Follow the workflow order: A0 (explorer) -> A1 (planner) -> A2 (reviewer) -> A3 (builder) -> A4 (queen) -> A5 (shipper).")}'
  exit 0
fi

# Check prerequisites exist
case "$EXPECTED_PHASE" in
  A1)
    if [[ ! -f ".agents/tmp/phases/A0-explore.md" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start A1 (plan): A0-explore.md not found. Explorer must complete first."}'
      exit 0
    fi
    ;;
  A2)
    if [[ ! -f "${PHASES_DIR}/A1-plan.md" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start A2 (review): A1-plan.md not found. Planner must complete first."}'
      exit 0
    fi
    ;;
  A3)
    if [[ ! -f "${PHASES_DIR}/A1-plan.md" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start A3 (build): A1-plan.md not found. Planner must complete first."}'
      exit 0
    fi
    ;;
  A4)
    if [[ ! -f "${PHASES_DIR}/A3-build.json" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start A4 (queen review): A3-build.json not found. Builders must complete first."}'
      exit 0
    fi
    validate_err=$(validate_json_file "${PHASES_DIR}/A3-build.json" "A3-build.json" 2>&1) || {
      echo "WARNING: A3-build.json validation: $validate_err" >&2
      jq -n --arg err "$validate_err" \
        '{"decision":"block","reason":("Cannot start A4 (queen review): A3-build.json is invalid JSON. Details: " + $err)}'
      exit 0
    }
    # Quality track output is expected for dual-track design but not strictly required
    # (sentinel results may be embedded in A3-build.json). Log a warning if missing.
    if [[ ! -f "${PHASES_DIR}/A3-quality.json" ]]; then
      echo "WARNING: No quality track output found (A3-quality.json). Queen will proceed with build track output only." >&2
    fi
    ;;
  A5)
    VERDICT_FILE="${PHASES_DIR}/A4-queen-verdict.json"
    if [[ ! -f "$VERDICT_FILE" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start A5 (ship): A4-queen-verdict.json not found. Queen must complete first."}'
      exit 0
    fi
    if ! VERDICT=$(jq -r '.verdict // empty' "$VERDICT_FILE" 2>&1); then
      echo "ERROR: A4-queen-verdict.json is corrupt or unreadable: $VERDICT" >&2
      exit 2
    fi
    if [[ "$VERDICT" != "clean" ]]; then
      jq -n --arg v "$VERDICT" \
        '{"decision":"block","reason":("Cannot start A5 (ship): Queen verdict is \"" + $v + "\", not \"clean\". Issues must be resolved first (loop back to A1).")}'
      exit 0
    fi
    ;;
esac

# All checks pass, allow dispatch
exit 0
