#!/usr/bin/env bash
# on-stop.sh — Ralph-style loop driver for minions workflow
# Reads state.json, generates a phase-specific orchestrator prompt,
# and injects it as {"decision":"block","reason":"<prompt>"} to drive the loop.
#
# Exit codes:
#   0 with JSON — block Claude's stop and inject next phase prompt
#   0 silent    — allow stop (no active workflow or workflow complete)
#   2 with stderr — error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

check_workflow_active

# Delegate to pipeline-specific handlers
[[ "$(state_get '.pipeline // "launch"')" == "cursor" ]] && exec "$SCRIPT_DIR/on-stop-cursor.sh"
[[ "$(state_get '.pipeline // "launch"')" == "superlaunch" ]] && exec "$SCRIPT_DIR/on-stop-superlaunch.sh"
[[ "$(state_get '.pipeline // "launch"')" == "review" ]] && exec "$SCRIPT_DIR/on-stop-review.sh"

CURRENT_PHASE=$(state_get '.currentPhase' --required)
LOOP=$(state_get '.loop')
MAX_LOOPS=$(state_get '.maxLoops')
TASK=$(state_get '.task' --required)

# Validate integers
LOOP=$(require_int "$LOOP" "loop")
MAX_LOOPS=$(require_int "$MAX_LOOPS" "maxLoops")

PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

# Recovery: advance state if output files exist but SubagentStop didn't fire.
# F2→F3: if f2-tasks.json exists and valid, advance to F3
# Note: 2>/dev/null is intentional — this is a best-effort recovery path.
# If validation fails, we fall through to regenerate the F2 prompt below.
if [[ "$CURRENT_PHASE" == "F2" && -f "${PHASES_DIR}/f2-tasks.json" ]]; then
  if validate_json_file "${PHASES_DIR}/f2-tasks.json" "f2-tasks.json" 2>/dev/null; then
    if jq -e '.tasks and .files_changed and .all_complete == true' "${PHASES_DIR}/f2-tasks.json" >/dev/null; then
      if ! update_state '.currentPhase = "F3" | .updatedAt = $ts | .loops[-1].f2.status = "complete"'; then
        echo "ERROR: Failed to advance state from F2 to F3 in Stop hook." >&2
        exit 2
      fi
      CURRENT_PHASE="F3"
    fi
  fi
fi

# F3→F4/loop: if f3-verdict.json exists and valid, advance based on verdict
if [[ "$CURRENT_PHASE" == "F3" && -f "${PHASES_DIR}/f3-verdict.json" ]]; then
  if ! validate_json_file "${PHASES_DIR}/f3-verdict.json" "f3-verdict.json"; then
    echo "ERROR: f3-verdict.json exists but is invalid JSON. Cannot process F3 verdict." >&2
    exit 2
  fi
  # Cross-validate verdict against issue counts to catch agents reporting clean with non-zero issues.
  VERDICT=$(jq -r '.overall_verdict // empty' "${PHASES_DIR}/f3-verdict.json") || {
    echo "ERROR: Failed to read overall_verdict from f3-verdict.json." >&2
    exit 2
  }
  TOTAL_ISSUES=$(jq -r '
    if (.total_issues? | type) == "number" then
      (.total_issues | floor | tostring)
    else
      (
        ((.critic.issues // 0)
        + (.pedant.issues // 0)
        + (.witness.issues // 0)
        + (.security_reviewer.issues // 0)
        + (.silent_failure_hunter.issues // 0)) | floor | tostring
      )
    end
  ' "${PHASES_DIR}/f3-verdict.json") || {
    echo "ERROR: Failed to compute total_issues from f3-verdict.json." >&2
    exit 2
  }

  if ! [[ "$TOTAL_ISSUES" =~ ^[0-9]+$ ]]; then
    echo "ERROR: f3-verdict.json has invalid total_issues value." >&2
    exit 2
  fi

  # Fail-safe: issue counts take precedence over declared verdict.
  if [[ "$VERDICT" == "clean" && "$TOTAL_ISSUES" -gt 0 ]]; then
    echo "WARNING: f3-verdict.json reports clean with ${TOTAL_ISSUES} issues. Forcing issues_found." >&2
    VERDICT="issues_found"
  fi

  if [[ "$VERDICT" != "clean" && "$VERDICT" != "issues_found" ]]; then
    if [[ "$TOTAL_ISSUES" -gt 0 ]]; then
      echo "WARNING: f3-verdict.json has unexpected overall_verdict '${VERDICT}'. Inferred issues_found from ${TOTAL_ISSUES} issues." >&2
      VERDICT="issues_found"
    else
      echo "ERROR: f3-verdict.json has unexpected overall_verdict '$VERDICT' and no issues to infer from." >&2
      exit 2
    fi
  fi

  if [[ "$VERDICT" == "clean" ]]; then
    if ! update_state --arg verdict "$VERDICT" \
      '.currentPhase = "F4" | .updatedAt = $ts | .loops[-1].f3.status = "complete" | .loops[-1].f3.verdict = $verdict | .loops[-1].verdict = "clean"'; then
      echo "ERROR: Failed to advance state from F3 to F4 in Stop hook." >&2
      exit 2
    fi
    CURRENT_PHASE="F4"
  elif [[ "$VERDICT" == "issues_found" ]]; then
    NEXT_LOOP=$((LOOP + 1))
    if [[ "$NEXT_LOOP" -gt "$MAX_LOOPS" ]]; then
      if ! update_state --arg verdict "$VERDICT" \
        '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .loops[-1].f3.status = "complete" | .loops[-1].f3.verdict = $verdict | .loops[-1].verdict = "issues_found" | .failure = "Max loops reached with unresolved issues"'; then
        echo "ERROR: Failed to update state to STOPPED in Stop hook." >&2
        exit 2
      fi
      CURRENT_PHASE="STOPPED"
    else
      if ! update_state --arg verdict "$VERDICT" --argjson nextLoop "$NEXT_LOOP" \
        '.currentPhase = "F1" | .loop = $nextLoop | .updatedAt = $ts | .loops[-1].f3.status = "complete" | .loops[-1].f3.verdict = $verdict | .loops[-1].verdict = "issues_found" | .loops += [{"loop": $nextLoop, "startedAt": $ts, "f1": {"status": "pending"}, "f2": {"status": "pending"}, "f3": {"status": "pending"}}]'; then
        echo "ERROR: Failed to loop back to F1 in Stop hook." >&2
        exit 2
      fi
      # Re-read updated loop for prompt generation
      LOOP="$NEXT_LOOP"
      PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"
      CURRENT_PHASE="F1"
    fi
  fi
fi

# Generate phase-specific prompt
case "$CURRENT_PHASE" in
  F1)
    EXPLORER_CONTEXT=""
    if [[ -s ".agents/tmp/phases/f0-explorer-context.md" ]]; then
      EXPLORER_CONTEXT="Pre-gathered codebase context is available from parallel explorer agents. Read .agents/tmp/phases/f0-explorer-context.md before exploring. Use this context to skip redundant exploration and focus on planning."
    fi

    PREV_CONTEXT=""
    if [[ "$LOOP" -gt 1 ]]; then
      PREV=$((LOOP - 1))
      PREV_CONTEXT="IMPORTANT: This is loop ${LOOP}. Read the previous loop's review outputs:
- .agents/tmp/phases/loop-${PREV}/f3-critic.json
- .agents/tmp/phases/loop-${PREV}/f3-pedant.json
- .agents/tmp/phases/loop-${PREV}/f3-witness.json
- .agents/tmp/phases/loop-${PREV}/f3-security-reviewer.json
- .agents/tmp/phases/loop-${PREV}/f3-silent-failure-hunter.json

Plan targeted fixes for the issues found. Do NOT re-plan the entire feature."
    fi

    PROMPT="## Minions Orchestrator — Phase F1 (Scout) — Loop ${LOOP}/${MAX_LOOPS}

Read .agents/tmp/state.json to confirm currentPhase is F1.

Dispatch the **scout** agent (subagent_type: minions:scout) with this prompt:

Task: ${TASK}

${EXPLORER_CONTEXT}

${PREV_CONTEXT}

Scout must write its plan to: .agents/tmp/phases/loop-${LOOP}/f1-plan.md

Create the directory first: mkdir -p .agents/tmp/phases/loop-${LOOP}"
    ;;

  F2)
    PROMPT="## Minions Orchestrator — Phase F2 (Build) — Loop ${LOOP}/${MAX_LOOPS}

Read .agents/tmp/state.json to confirm currentPhase is F2.
Read the plan at .agents/tmp/phases/loop-${LOOP}/f1-plan.md.

Parse the task table from the plan. For each task, dispatch a **builder** agent (subagent_type: minions:builder) in parallel.

Each builder receives:
- Task description and acceptance criteria from the plan
- Task ID (the task number)

After ALL builders complete, aggregate their outputs into:
.agents/tmp/phases/loop-${LOOP}/f2-tasks.json

The aggregated file should be a JSON object with:
{
  \"tasks\": [ ...each builder's output JSON... ],
  \"files_changed\": [ ...deduplicated list of all changed files... ],
  \"all_complete\": true
}"
    ;;

  F3)
    PROMPT="## Minions Orchestrator — Phase F3 (Review) — Loop ${LOOP}/${MAX_LOOPS}

Read .agents/tmp/state.json to confirm currentPhase is F3.
Read .agents/tmp/phases/loop-${LOOP}/f2-tasks.json for the list of changed files.

Dispatch these 5 agents IN PARALLEL:

1. **critic** (subagent_type: minions:critic) — correctness review
2. **pedant** (subagent_type: minions:pedant) — quality review
3. **witness** (subagent_type: minions:witness) — runtime verification
4. **security-reviewer** (subagent_type: minions:security-reviewer) — deep security review
5. **silent-failure-hunter** (subagent_type: minions:silent-failure-hunter) — error handling review

Pass each agent the list of changed files from f2-tasks.json.

Each agent writes its output to:
- .agents/tmp/phases/loop-${LOOP}/f3-critic.json
- .agents/tmp/phases/loop-${LOOP}/f3-pedant.json
- .agents/tmp/phases/loop-${LOOP}/f3-witness.json
- .agents/tmp/phases/loop-${LOOP}/f3-security-reviewer.json
- .agents/tmp/phases/loop-${LOOP}/f3-silent-failure-hunter.json

After ALL 5 complete, aggregate their verdicts into:
.agents/tmp/phases/loop-${LOOP}/f3-verdict.json

{
  \"critic\": { \"verdict\": \"clean|issues_found\", \"issues\": N },
  \"pedant\": { \"verdict\": \"clean|issues_found\", \"issues\": N },
  \"witness\": { \"verdict\": \"clean|issues_found\", \"issues\": N },
  \"security_reviewer\": { \"verdict\": \"clean|issues_found\", \"issues\": N },
  \"silent_failure_hunter\": { \"verdict\": \"clean|issues_found\", \"issues\": N },
  \"overall_verdict\": \"clean|issues_found\",
  \"total_issues\": N
}"
    ;;

  F4)
    PROMPT="## Minions Orchestrator — Phase F4 (Ship) — Loop ${LOOP}

Read .agents/tmp/state.json to confirm currentPhase is F4.

Dispatch the **shipper** agent (subagent_type: minions:shipper) with this prompt:

Task: ${TASK}

Read .agents/tmp/phases/loop-${LOOP}/f2-tasks.json for the list of changed files.
Update documentation, create a git commit, and open a PR.

Shipper must write its output to: .agents/tmp/phases/loop-${LOOP}/f4-ship.json"
    ;;

  DONE|STOPPED)
    # Workflow complete or stopped, allow stop
    exit 0
    ;;

  *)
    echo "ERROR: Unknown currentPhase '${CURRENT_PHASE}' in state.json" >&2
    exit 2
    ;;
esac

# Block stop and inject the orchestrator prompt
if ! jq_out=$(jq -n --arg reason "$PROMPT" '{"decision":"block","reason":$reason}' 2>&1); then
  echo "ERROR: jq failed to encode orchestrator prompt for phase ${CURRENT_PHASE}: $jq_out" >&2
  exit 2
fi
echo "$jq_out"
