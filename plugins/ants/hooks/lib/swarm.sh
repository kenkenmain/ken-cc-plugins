#!/usr/bin/env bash
# swarm.sh — Pipeline-specific helpers for ants 6-phase workflow hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/swarm.sh"
#
# Ants phases: A0 (explore) -> A1 (plan) -> A2 (review) -> A3 (build) -> A4 (queen) -> A5 (ship)
#
# Provides:
#   get_phase_output()      — Expected output filename for each phase
#   get_phase_input()       — Input file dependencies for each phase
#   get_phase_agent()       — Primary agent for each phase
#   generate_swarm_prompt() — Build orchestrator prompt from phase metadata
#   parse_queen_verdict()   — Parse and validate A4 verdict from JSON file
#   init_wave_schedule()    — Initialize wave-based build schedule
#   advance_build_wave()    — Advance to next build wave
#   is_a3_complete()        — Check if all build waves are complete

set -euo pipefail

# ===========================================================================
# Phase Output Files
# ===========================================================================

get_phase_output() {
  local phase="${1:?get_phase_output requires a phase ID}"
  case "$phase" in
    A0) echo "A0-explore.md" ;;
    A1) echo "A1-plan.md" ;;
    A2) echo "A2-review.json" ;;
    A3) echo "A3-build.json" ;;
    A4) echo "A4-queen-verdict.json" ;;
    A5) echo "A5-ship.json" ;;
    *)  echo "" ;;
  esac
}

# ===========================================================================
# Phase Input Files
# ===========================================================================

get_phase_input() {
  local phase="${1:?get_phase_input requires a phase ID}"
  case "$phase" in
    A0)
      echo "- Task description from state.json \`.task\` field"
      ;;
    A1)
      echo "- \`.agents/tmp/phases/A0-explore.md\`"
      ;;
    A2)
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A1-plan.md\`"
      ;;
    A3)
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A1-plan.md\`"
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A2-review.json\` (if plan was revised)"
      ;;
    A4)
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A3-build.json\`"
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A1-plan.md\`"
      echo "- Run \`git diff\` for current changes"
      ;;
    A5)
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A4-queen-verdict.json\`"
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A3-build.json\`"
      ;;
    *)
      echo "- None"
      ;;
  esac
}

# ===========================================================================
# Phase Agent Routing
# ===========================================================================

# Returns all agents for a phase as a space-delimited list.
# For single-agent phases, returns one agent. For multi-agent phases (A0, A3, A5),
# returns all agents. The first agent listed is the primary agent used in prompts.
get_phase_agent() {
  local phase="${1:?get_phase_agent requires a phase ID}"
  case "$phase" in
    A0) echo "ants:forager ants:cartographer ants:explore-aggregator" ;;
    A1) echo "ants:architect" ;;
    A2) echo "ants:blueprint-reviewer" ;;
    A3) echo "ants:worker ants:sentinel ants:guardian ants:sentinel-correctness ants:sentinel-security ants:sentinel-perf ants:review-arbiter ants:review-fixer" ;;
    A4) echo "ants:queen" ;;
    A5) echo "ants:nurse ants:drone" ;;
    *)  echo "" ;;
  esac
}

# ===========================================================================
# Wave Tracking (A3 build parallelism)
# ===========================================================================

# Initialize wave schedule from the plan. Writes .waves[] to state.
# Usage: init_wave_schedule
init_wave_schedule() {
  if ! update_state '.waves = [{"wave": 1, "status": "pending", "startedAt": $ts}] | .currentWave = 1'; then
    echo "ERROR: Failed to initialize wave schedule" >&2
    return 1
  fi
}

# Advance to the next build wave. Returns 0 if advanced, 1 if all waves done.
# Usage: advance_build_wave
advance_build_wave() {
  local current_wave
  current_wave="$(state_get '.currentWave // 1')"
  current_wave=$(require_int "$current_wave" "currentWave")

  local total_waves
  total_waves="$(state_get '.totalWaves // 1')"
  total_waves=$(require_int "$total_waves" "totalWaves")

  local next_wave=$((current_wave + 1))

  if [[ "$next_wave" -gt "$total_waves" ]]; then
    return 1
  fi

  if ! update_state --argjson nw "$next_wave" \
    '.currentWave = $nw | .waves[-1].status = "complete" | .waves += [{"wave": $nw, "status": "pending", "startedAt": $ts}]'; then
    echo "ERROR: Failed to advance to wave $next_wave" >&2
    return 1
  fi

  return 0
}

# Check if A3 (build) is fully complete — all waves done.
# Returns 0 if complete, 1 if not.
is_a3_complete() {
  local current_wave
  current_wave="$(state_get '.currentWave // 1')"
  current_wave=$(require_int "$current_wave" "currentWave")
  local total_waves
  total_waves="$(state_get '.totalWaves // 1')"
  total_waves=$(require_int "$total_waves" "totalWaves")

  [[ "$current_wave" -ge "$total_waves" ]]
}

# ===========================================================================
# A4 Verdict Parsing
# ===========================================================================

# Parse and validate a queen verdict JSON file.
# Sets VERDICT (clean|issues_found) and TOTAL_ISSUES in the caller's scope.
# Usage: parse_queen_verdict "/path/to/A4-queen-verdict.json"
parse_queen_verdict() {
  local verdict_file="${1:?parse_queen_verdict requires a file path}"

  VERDICT=$(jq -r '.verdict // empty' "$verdict_file") || {
    echo "ERROR: Failed to read verdict from $verdict_file." >&2
    exit 2
  }
  TOTAL_ISSUES=$(jq -r '.total_issues // 0 | floor | tostring' "$verdict_file") || TOTAL_ISSUES="0"

  # Sanitize total_issues to integer
  if ! [[ "$TOTAL_ISSUES" =~ ^[0-9]+$ ]]; then
    TOTAL_ISSUES="0"
  fi

  # Fail-safe: issue counts take precedence over declared verdict
  if [[ "$VERDICT" == "clean" && "$TOTAL_ISSUES" -gt 0 ]]; then
    echo "WARNING: Queen reports clean with ${TOTAL_ISSUES} issues. Forcing issues_found." >&2
    VERDICT="issues_found"
  fi

  if [[ "$VERDICT" != "clean" && "$VERDICT" != "issues_found" ]]; then
    if [[ "$TOTAL_ISSUES" -gt 0 ]]; then
      echo "WARNING: Unexpected verdict '${VERDICT}'. Inferred issues_found from issue count." >&2
      VERDICT="issues_found"
    else
      echo "ERROR: Unexpected verdict '$VERDICT' and no issues in $verdict_file." >&2
      exit 2
    fi
  fi
}

# ===========================================================================
# Pool-Aware Prompt Generation
# ===========================================================================

# Generate a prompt listing available tasks from the task pool.
# Used during A3 when taskPool exists in state.json.
# Usage: prompt_fragment=$(generate_pool_prompt)
generate_pool_prompt() {
  local available
  available=$(jq '[.taskPool[] | select(.status == "ready" and .claimed_by == null)]' "$STATE_FILE" 2>/dev/null || echo "[]")

  local count
  count=$(echo "$available" | jq 'length')

  if [[ "$count" == "0" ]]; then
    # Check if all tasks are done
    local remaining
    remaining=$(jq '[.taskPool[] | select(.status == "pending" or .status == "ready" or .status == "claimed")] | length' "$STATE_FILE" 2>/dev/null || echo "0")
    if [[ "$remaining" == "0" ]]; then
      echo "All tasks in the pool are complete. Aggregate results into A3-build.json."
    else
      echo "No tasks are currently available (${remaining} still in progress or blocked by dependencies). Wait for running workers to complete."
    fi
    return 0
  fi

  local task_list
  task_list=$(echo "$available" | jq -r '.[] | "- Task \(.id): \(.description) [files: \(.files_owned | join(", "))]"')

  cat <<EOF
${count} task(s) available for claiming from the task pool:

${task_list}

For each available task, dispatch an ants:worker with:
- The task ID and description
- The list of files_owned (worker should only modify these files)
- Instructions to write output to .agents/tmp/phases/loop-{LOOP}/A3-worker-{TASK_ID}.json
EOF
}

# ===========================================================================
# Prompt Generation
# ===========================================================================

generate_swarm_prompt() {
  local phase="${1:?generate_swarm_prompt requires a phase ID}"

  local task
  task="$(state_get '.task' --required)"
  local loop
  loop="$(state_get '.loop // 1')"
  loop=$(require_int "$loop" "loop")
  local max_loops
  max_loops="$(state_get '.maxLoops // 5')"
  max_loops=$(require_int "$max_loops" "maxLoops")

  local all_agents
  all_agents="$(get_phase_agent "$phase")"
  # Primary agent is first in the list (used for dispatch instruction)
  local agent
  agent="${all_agents%% *}"
  local output_file
  output_file="$(get_phase_output "$phase")"
  local input_files
  input_files="$(get_phase_input "$phase")"
  # Substitute {LOOP} placeholders with actual loop number
  input_files="${input_files//\{LOOP\}/${loop}}"

  # A0 is top-level (not loop-scoped); all other phases use loop directories
  local phases_dir
  if [[ "$phase" == "A0" ]]; then
    phases_dir=".agents/tmp/phases"
  else
    phases_dir=".agents/tmp/phases/loop-${loop}"
  fi

  # Build previous-loop context for A1 when looping back
  local prev_context=""
  if [[ "$phase" == "A1" && "$loop" -gt 1 ]]; then
    local prev=$((loop - 1))
    prev_context="IMPORTANT: This is loop ${loop}. Read the previous loop's queen verdict:
- .agents/tmp/phases/loop-${prev}/A4-queen-verdict.json

Plan targeted fixes for the issues found. Do NOT re-plan the entire feature."
  fi

  cat <<PROMPT
## Ants Orchestrator — Phase ${phase} — Loop ${loop}/${max_loops}

Read .agents/tmp/state.json to confirm currentPhase is ${phase}.

Dispatch the **$(echo "$agent" | sed 's/ants://')** agent (subagent_type: ${agent}) with this prompt:

Task: ${task}
${prev_context:+
${prev_context}
}
Input files:
${input_files}

Output file: ${phases_dir}/${output_file}

Create the directory first: mkdir -p ${phases_dir}

## Phase-Specific Rules
PROMPT

  case "$phase" in
    A0)
      cat <<'RULES'

Explore the codebase to understand the project structure, existing patterns,
and relevant code. Write findings to the output file.
RULES
      ;;
    A1)
      cat <<'RULES'

Read the exploration output and create a detailed implementation plan.
Break the work into discrete tasks with acceptance criteria.
Write the plan to the output file.
RULES
      ;;
    A2)
      cat <<'RULES'

Review the plan for completeness, correctness, and feasibility.
Write a JSON review with verdict ("approved" or "needs_revision") and issues[].
RULES
      ;;
    A3)
      # Check if task pool exists for pool-aware prompt
      local has_pool
      has_pool=$(jq -r '.taskPool // empty | if type == "array" and length > 0 then "yes" else "no" end' "$STATE_FILE" 2>/dev/null || echo "no")
      if [[ "$has_pool" == "yes" ]]; then
        local pool_prompt
        pool_prompt="$(generate_pool_prompt)"
        cat <<RULES

## Task Pool Mode

${pool_prompt}

After all workers complete, dispatch the adversarial review team:
1. ants:sentinel-correctness, ants:sentinel-security, ants:sentinel-perf (in parallel)
2. Wait for all sentinels to complete (marker files: .sentinel-*.done)
3. ants:review-arbiter consolidates findings into A3-quality.json
4. If critical issues found, dispatch ants:review-fixer, then re-run sentinels

After all tasks and quality review complete, aggregate results into: ${phases_dir}/${output_file}

The aggregated file must contain:
{
  "tasks": [ ...each builder's output... ],
  "files_changed": [ ...deduplicated list... ],
  "all_complete": true
}
RULES
      else
        cat <<RULES

Read the plan and dispatch builder agents for each task.
Builders work in parallel within waves. After all builders complete,
aggregate results into: ${phases_dir}/${output_file}

The aggregated file must contain:
{
  "tasks": [ ...each builder's output... ],
  "files_changed": [ ...deduplicated list... ],
  "all_complete": true
}
RULES
      fi
      ;;
    A4)
      cat <<RULES

The queen reviews ALL changes against the original plan.
Read the build output and run git diff.
Write a verdict JSON to: ${phases_dir}/${output_file}

{
  "verdict": "clean" | "issues_found",
  "issues": [ ...list of issues... ],
  "total_issues": N,
  "recommendation": "ship" | "loop"
}

If verdict is "clean", the workflow advances to A5.
If verdict is "issues_found", the workflow loops back to A1.
RULES
      ;;
    A5)
      cat <<RULES

Ship the completed work: update documentation, create a git commit,
and finalize. Write output to: ${phases_dir}/${output_file}

{
  "commit_sha": "...",
  "docs_updated": true|false,
  "summary": "..."
}
RULES
      ;;
  esac

  # Standard rules footer
  cat <<'FOOTER'

## Rules

- Do NOT execute phase work directly — dispatch via Task tool
- Do NOT advance state — hooks handle this
- Do NOT stop or exit — hooks manage lifecycle
FOOTER
}
