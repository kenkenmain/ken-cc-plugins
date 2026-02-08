#!/usr/bin/env bash
# on-stop-review.sh -- Stop hook for the review pipeline.
# Invoked via exec from on-stop.sh when pipeline == "review".
# Reads state.json, performs recovery when phase outputs already exist,
# and injects a phase-specific orchestrator prompt.
#
# Exit codes:
#   0 with JSON -- block Claude's stop and inject next phase prompt
#   0 silent    -- allow stop (terminal state)
#   2 with stderr -- error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

CURRENT_PHASE=$(state_get '.currentPhase' --required)
ITERATION=$(state_get '.iteration')
MAX_ITERATIONS=$(state_get '.maxIterations')
TASK=$(state_get '.task' --required)

ITERATION=$(require_int "$ITERATION" "iteration")
MAX_ITERATIONS=$(require_int "$MAX_ITERATIONS" "maxIterations")

PHASES_DIR=".agents/tmp/phases/review-${ITERATION}"

# Recovery: process R1 verdict if file exists but SubagentStop did not run.
if [[ "$CURRENT_PHASE" == "R1" && -f "${PHASES_DIR}/r1-verdict.json" ]]; then
  if ! validate_json_file "${PHASES_DIR}/r1-verdict.json" "r1-verdict.json"; then
    echo "ERROR: r1-verdict.json exists but is invalid JSON. Cannot recover R1 state." >&2
    exit 2
  fi

  TOTAL_ISSUES=$(jq -r '.total_issues // 0' "${PHASES_DIR}/r1-verdict.json") || {
    echo "ERROR: Failed to read total_issues from r1-verdict.json." >&2
    exit 2
  }
  if ! [[ "$TOTAL_ISSUES" =~ ^[0-9]+$ ]]; then
    echo "ERROR: r1-verdict.json has invalid total_issues value '$TOTAL_ISSUES'." >&2
    exit 2
  fi

  VERDICT=$(jq -r '.overall_verdict // empty' "${PHASES_DIR}/r1-verdict.json") || {
    echo "ERROR: Failed to read overall_verdict from r1-verdict.json." >&2
    exit 2
  }

  if [[ "$VERDICT" == "clean" && "$TOTAL_ISSUES" -gt 0 ]]; then
    echo "WARNING: r1-verdict.json reports clean with ${TOTAL_ISSUES} issues. Forcing issues_found." >&2
    VERDICT="issues_found"
  fi

  if [[ "$VERDICT" != "clean" && "$VERDICT" != "issues_found" ]]; then
    if [[ "$TOTAL_ISSUES" -gt 0 ]]; then
      echo "WARNING: r1-verdict.json has unexpected overall_verdict '${VERDICT}'. Inferred issues_found from ${TOTAL_ISSUES} issues." >&2
      VERDICT="issues_found"
    else
      echo "ERROR: r1-verdict.json has unexpected overall_verdict '$VERDICT' and no issues to infer from." >&2
      exit 2
    fi
  fi

  if [[ "$VERDICT" == "clean" ]]; then
    if ! update_state --arg verdict "$VERDICT" \
      '.currentPhase = "DONE" | .status = "complete" | .updatedAt = $ts | .iterations[-1].r1.status = "complete" | .iterations[-1].r1.verdict = $verdict | .iterations[-1].verdict = "clean"'; then
      echo "ERROR: Failed to mark review workflow as complete in Stop hook recovery." >&2
      exit 2
    fi
    CURRENT_PHASE="DONE"
  elif [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
    if ! update_state --arg verdict "$VERDICT" \
      '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .iterations[-1].r1.status = "complete" | .iterations[-1].r1.verdict = $verdict | .iterations[-1].verdict = "issues_found" | .failure = "Max iterations reached with unresolved issues"'; then
      echo "ERROR: Failed to mark review workflow STOPPED in Stop hook recovery." >&2
      exit 2
    fi
    CURRENT_PHASE="STOPPED"
  else
    if ! update_state --arg verdict "$VERDICT" \
      '.currentPhase = "R2" | .updatedAt = $ts | .iterations[-1].r1.status = "complete" | .iterations[-1].r1.verdict = $verdict'; then
      echo "ERROR: Failed to advance from R1 to R2 in Stop hook recovery." >&2
      exit 2
    fi
    CURRENT_PHASE="R2"
  fi
fi

# Recovery: if R2 summary exists, advance to next iteration R1.
if [[ "$CURRENT_PHASE" == "R2" && -s "${PHASES_DIR}/r2-fix-summary.md" ]]; then
  NEXT_ITERATION=$((ITERATION + 1))
  NEXT_ITER_DIR=".agents/tmp/phases/review-${NEXT_ITERATION}"
  mkdir -p "$NEXT_ITER_DIR"

  if ! update_state --argjson nextIter "$NEXT_ITERATION" \
    '.currentPhase = "R1" | .iteration = $nextIter | .updatedAt = $ts | .iterations[-1].r2.status = "complete" | .iterations += [{"iteration": $nextIter, "startedAt": $ts, "r1": {"status": "pending"}, "r2": {"status": "pending"}, "verdict": null}]'; then
    echo "ERROR: Failed to recover from R2 to next iteration R1 in Stop hook." >&2
    exit 2
  fi

  ITERATION="$NEXT_ITERATION"
  PHASES_DIR=".agents/tmp/phases/review-${ITERATION}"
  CURRENT_PHASE="R1"
fi

# Terminal states
case "$CURRENT_PHASE" in
  DONE|STOPPED)
    exit 0
    ;;
esac

# Generate phase-specific prompt
case "$CURRENT_PHASE" in
  R1)
    PREV_CONTEXT=""
    if [[ "$ITERATION" -gt 1 ]]; then
      PREV=$((ITERATION - 1))
      PREV_CONTEXT=$(cat <<EOF_PREV
IMPORTANT: This is iteration ${ITERATION}. Previous review found issues that were fixed.
Read the previous iteration outputs for context:
- .agents/tmp/phases/review-${PREV}/r1-critic.json
- .agents/tmp/phases/review-${PREV}/r1-pedant.json
- .agents/tmp/phases/review-${PREV}/r1-witness.json
- .agents/tmp/phases/review-${PREV}/r1-security-reviewer.json
- .agents/tmp/phases/review-${PREV}/r1-silent-failure-hunter.json
- .agents/tmp/phases/review-${PREV}/r2-fix-summary.md

Focus on verifying previous fixes and finding new issues introduced by fixes. Do not simply re-report issues that are already fixed.
EOF_PREV
)
    fi

    PROMPT=$(cat <<EOF_PROMPT
[PHASE R1]

## Review Orchestrator -- Phase R1 (Review) -- Iteration ${ITERATION}/${MAX_ITERATIONS}

Read .agents/tmp/state.json to confirm currentPhase is R1.

Create the output directory first:
mkdir -p .agents/tmp/phases/review-${ITERATION}

Dispatch these 5 review agents IN PARALLEL:

1. critic (subagent_type: minions:critic) -- correctness review
2. pedant (subagent_type: minions:pedant) -- quality review
3. witness (subagent_type: minions:witness) -- runtime verification
4. security-reviewer (subagent_type: minions:security-reviewer) -- security review
5. silent-failure-hunter (subagent_type: minions:silent-failure-hunter) -- error handling review

Task: ${TASK}

${PREV_CONTEXT}

Each agent must write output JSON to:
- .agents/tmp/phases/review-${ITERATION}/r1-critic.json
- .agents/tmp/phases/review-${ITERATION}/r1-pedant.json
- .agents/tmp/phases/review-${ITERATION}/r1-witness.json
- .agents/tmp/phases/review-${ITERATION}/r1-security-reviewer.json
- .agents/tmp/phases/review-${ITERATION}/r1-silent-failure-hunter.json

After ALL 5 complete, aggregate into:
.agents/tmp/phases/review-${ITERATION}/r1-verdict.json

{
  "critic": { "verdict": "clean|issues_found", "issues": N },
  "pedant": { "verdict": "clean|issues_found", "issues": N },
  "witness": { "verdict": "clean|issues_found", "issues": N },
  "security_reviewer": { "verdict": "clean|issues_found", "issues": N },
  "silent_failure_hunter": { "verdict": "clean|issues_found", "issues": N },
  "overall_verdict": "clean|issues_found",
  "total_issues": N
}
EOF_PROMPT
)
    ;;

  R2)
    TOTAL_ISSUES=0
    if [[ -f "${PHASES_DIR}/r1-verdict.json" ]]; then
      TOTAL_ISSUES=$(jq -r '.total_issues // 0' "${PHASES_DIR}/r1-verdict.json" 2>/dev/null) || TOTAL_ISSUES=0
      if ! [[ "$TOTAL_ISSUES" =~ ^[0-9]+$ ]]; then
        TOTAL_ISSUES=0
      fi
    fi

    PROMPT=$(cat <<EOF_PROMPT
[PHASE R2]

## Review Orchestrator -- Phase R2 (Fix) -- Iteration ${ITERATION}/${MAX_ITERATIONS}

Read .agents/tmp/state.json to confirm currentPhase is R2.

The review phase found ${TOTAL_ISSUES} issue(s) across all 5 reviewers. ALL issues must be fixed, regardless of severity (critical, warning, and info).

Dispatch the review-fixer agent (subagent_type: minions:review-fixer) with this prompt:

Task: ${TASK}
Iteration: ${ITERATION}/${MAX_ITERATIONS}

Read ALL review output files from the current iteration:
- .agents/tmp/phases/review-${ITERATION}/r1-critic.json
- .agents/tmp/phases/review-${ITERATION}/r1-pedant.json
- .agents/tmp/phases/review-${ITERATION}/r1-witness.json
- .agents/tmp/phases/review-${ITERATION}/r1-security-reviewer.json
- .agents/tmp/phases/review-${ITERATION}/r1-silent-failure-hunter.json

For each issue found by any reviewer:
1. Read the affected file
2. Understand the issue and suggestion
3. Apply the fix using Edit (preferred) or Write

Fix ALL issues -- critical, warning, and info. Do not skip any severity level.

After fixing, write a summary to:
.agents/tmp/phases/review-${ITERATION}/r2-fix-summary.md
EOF_PROMPT
)
    ;;

  *)
    echo "ERROR: Unknown currentPhase '${CURRENT_PHASE}' in state.json for review pipeline" >&2
    exit 2
    ;;
esac

if ! jq_out=$(jq -n --arg reason "$PROMPT" '{"decision":"block","reason":$reason}' 2>&1); then
  echo "ERROR: jq failed to encode review prompt for phase ${CURRENT_PHASE}: $jq_out" >&2
  exit 2
fi
echo "$jq_out"
