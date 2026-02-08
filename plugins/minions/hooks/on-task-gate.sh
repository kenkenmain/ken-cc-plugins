#!/usr/bin/env bash
# on-task-gate.sh — Block out-of-order Task dispatches
# PreToolUse hook for Task tool. Validates that the dispatched agent
# matches the current phase and that required prerequisites exist.
#
# Exit codes:
#   0 silent   — allow (no active workflow or non-minions agent)
#   0 with JSON — block with reason
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

check_workflow_active

# Read input
INPUT=$(cat)
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "ERROR: No valid JSON received on stdin for PreToolUse hook." >&2
  exit 2
fi

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty')

# Delegate to pipeline-specific handlers (stdin already consumed, pass via env)
if [[ "$(state_get '.pipeline // "launch"')" == "cursor" ]]; then
  export CURSOR_AGENT_TYPE="$AGENT_TYPE"
  exec "$SCRIPT_DIR/on-task-gate-cursor.sh"
fi
if [[ "$(state_get '.pipeline // "launch"')" == "superlaunch" ]]; then
  export SL_AGENT_TYPE="$AGENT_TYPE"
  exec "$SCRIPT_DIR/on-task-gate-superlaunch.sh"
fi

# Map agent type to expected phase
case "$AGENT_TYPE" in
  explorer-files|minions:explorer-files) exit 0 ;;
  explorer-architecture|minions:explorer-architecture) exit 0 ;;
  explorer-tests|minions:explorer-tests) exit 0 ;;
  explorer-patterns|minions:explorer-patterns) exit 0 ;;
  scout|minions:scout) EXPECTED_PHASE="F1" ;;
  builder|minions:builder) EXPECTED_PHASE="F2" ;;
  critic|minions:critic) EXPECTED_PHASE="F3" ;;
  pedant|minions:pedant) EXPECTED_PHASE="F3" ;;
  witness|minions:witness) EXPECTED_PHASE="F3" ;;
  security-reviewer|minions:security-reviewer) EXPECTED_PHASE="F3" ;;
  silent-failure-hunter|minions:silent-failure-hunter) EXPECTED_PHASE="F3" ;;
  shipper|minions:shipper) EXPECTED_PHASE="F4" ;;
  *) exit 0 ;; # Not a minions agent, allow
esac

CURRENT_PHASE=$(state_get '.currentPhase' --required)
LOOP=$(state_get '.loop')
LOOP=$(require_int "$LOOP" "loop")
PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

# Check phase matches
if [[ "$CURRENT_PHASE" != "$EXPECTED_PHASE" ]]; then
  jq -n --arg agent "$AGENT_TYPE" --arg expected "$EXPECTED_PHASE" --arg current "$CURRENT_PHASE" \
    '{"decision":"block","reason":("Cannot dispatch " + $agent + " during phase " + $current + ". Expected phase: " + $expected + ". Follow the workflow order: F1 (scout) → F2 (builder) → F3 (critic/pedant/witness/security-reviewer/silent-failure-hunter) → F4 (shipper).")}'
  exit 0
fi

# Check prerequisites exist
case "$EXPECTED_PHASE" in
  F2)
    if [[ ! -f "${PHASES_DIR}/f1-plan.md" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start F2 (build): f1-plan.md not found. Scout must complete first."}'
      exit 0
    fi
    ;;
  F3)
    if [[ ! -f "${PHASES_DIR}/f2-tasks.json" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start F3 (review): f2-tasks.json not found. Builders must complete first."}'
      exit 0
    fi
    validate_err=$(validate_json_file "${PHASES_DIR}/f2-tasks.json" "f2-tasks.json" 2>&1) || {
      echo "WARNING: f2-tasks.json validation: $validate_err" >&2
      jq -n --arg err "$validate_err" \
        '{"decision":"block","reason":("Cannot start F3 (review): f2-tasks.json is invalid JSON. Details: " + $err)}'
      exit 0
    }
    ;;
  F4)
    VERDICT_FILE="${PHASES_DIR}/f3-verdict.json"
    if [[ ! -f "$VERDICT_FILE" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start F4 (ship): f3-verdict.json not found. Reviewers must complete first."}'
      exit 0
    fi
    if ! VERDICT=$(jq -r '.overall_verdict // empty' "$VERDICT_FILE" 2>&1); then
      echo "ERROR: f3-verdict.json is corrupt or unreadable: $VERDICT" >&2
      exit 2
    fi
    if [[ "$VERDICT" != "clean" ]]; then
      jq -n --arg v "$VERDICT" \
        '{"decision":"block","reason":("Cannot start F4 (ship): F3 verdict is \"" + $v + "\", not \"clean\". Issues must be resolved first (loop back to F1).")}'
      exit 0
    fi
    ;;
esac

# All checks pass, allow dispatch
exit 0
