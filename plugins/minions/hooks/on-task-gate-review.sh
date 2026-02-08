#!/usr/bin/env bash
# on-task-gate-review.sh -- Task gate for the review pipeline.
# Invoked via exec from on-task-gate.sh when pipeline == "review".
# Validates that the dispatched agent matches the current phase.
#
# Receives agent type via REVIEW_AGENT_TYPE env var (stdin already consumed by parent hook).
#
# Exit codes:
#   0 silent    -- allow (non-minions agent or agent valid for current phase)
#   0 with JSON -- block with reason
#   2 with stderr -- error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

AGENT_TYPE="${REVIEW_AGENT_TYPE:?on-task-gate-review.sh requires REVIEW_AGENT_TYPE}"

# Allow non-minions agents through
case "$AGENT_TYPE" in
  minions:*|critic|pedant|witness|security-reviewer|silent-failure-hunter|review-fixer) ;;
  *) exit 0 ;;
esac

CURRENT_PHASE=$(state_get '.currentPhase' --required)
ITERATION=$(state_get '.iteration // 1')
ITERATION=$(require_int "$ITERATION" "iteration")

# Map agent to expected phase
case "$AGENT_TYPE" in
  critic|minions:critic|pedant|minions:pedant|witness|minions:witness|security-reviewer|minions:security-reviewer|silent-failure-hunter|minions:silent-failure-hunter)
    EXPECTED_PHASE="R1"
    ;;
  review-fixer|minions:review-fixer)
    EXPECTED_PHASE="R2"
    ;;
  *)
    exit 0
    ;;
esac

if [[ "$CURRENT_PHASE" != "$EXPECTED_PHASE" ]]; then
  jq -n --arg agent "$AGENT_TYPE" --arg expected "$EXPECTED_PHASE" --arg current "$CURRENT_PHASE" \
    '{"decision":"block","reason":("Cannot dispatch " + $agent + " during phase " + $current + ". Expected phase: " + $expected + ". Review pipeline order: R1 (review agents) -> R2 (review-fixer) -> R1 (re-review).")}'
  exit 0
fi

# Phase-specific prerequisite checks
case "$EXPECTED_PHASE" in
  R2)
    ITER_DIR=".agents/tmp/phases/review-${ITERATION}"
    VERDICT_FILE="${ITER_DIR}/r1-verdict.json"
    if [[ ! -f "$VERDICT_FILE" ]]; then
      jq -n '{"decision":"block","reason":"Cannot start R2 (fix): r1-verdict.json not found. Review agents must complete first."}'
      exit 0
    fi

    if ! validate_json_file "$VERDICT_FILE" "r1-verdict.json" >/dev/null 2>&1; then
      jq -n '{"decision":"block","reason":"Cannot start R2 (fix): r1-verdict.json is invalid JSON."}'
      exit 0
    fi

    VERDICT=$(jq -r '.overall_verdict // empty' "$VERDICT_FILE" 2>/dev/null || echo "")
    TOTAL_ISSUES=$(jq -r '.total_issues // 0' "$VERDICT_FILE" 2>/dev/null || echo "0")
    if ! [[ "$TOTAL_ISSUES" =~ ^[0-9]+$ ]]; then
      TOTAL_ISSUES=0
    fi

    if [[ "$VERDICT" == "clean" && "$TOTAL_ISSUES" -eq 0 ]]; then
      jq -n '{"decision":"block","reason":"Cannot start R2 (fix): R1 verdict is clean with zero issues. Workflow should complete instead of entering fix phase."}'
      exit 0
    fi
    ;;
esac

exit 0
