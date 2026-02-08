#!/usr/bin/env bash
# cursor.sh — Shared library for cursor pipeline hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/cursor.sh"
#
# Provides:
#   get_cursor_agent_phases()       — Maps agent→allowed phases
#   is_cursor_agent_allowed()       — Check if agent can run in phase
#   generate_cursor_prompt()        — Build orchestrator prompt for each phase

set -euo pipefail

# ===========================================================================
# Agent-to-Phase Mapping
# ===========================================================================

get_cursor_agent_phases() {
  local agent_type="${1:?get_cursor_agent_phases requires an agent type}"
  case "$agent_type" in
    sub-scout|minions:sub-scout)                     echo "C1" ;;
    cursor-builder|minions:cursor-builder)            echo "C2 C2.5" ;;
    judge|minions:judge)                              echo "C3" ;;
    shipper|minions:shipper)                          echo "C4" ;;
    explorer-files|minions:explorer-files)            echo "PRE" ;;
    explorer-architecture|minions:explorer-architecture) echo "PRE" ;;
    explorer-tests|minions:explorer-tests)            echo "PRE" ;;
    explorer-patterns|minions:explorer-patterns)      echo "PRE" ;;
    *) echo "" ;;
  esac
}

is_cursor_agent_allowed() {
  local agent_type="${1:?is_cursor_agent_allowed requires agent_type}"
  local current_phase="${2:?is_cursor_agent_allowed requires current_phase}"

  local allowed_phases
  allowed_phases="$(get_cursor_agent_phases "$agent_type")"
  [[ -z "$allowed_phases" ]] && return 1

  local phase
  for phase in $allowed_phases; do
    if [[ "$phase" == "$current_phase" ]]; then
      return 0
    fi
  done
  return 1
}

# ===========================================================================
# Prompt Generation
# ===========================================================================

generate_cursor_prompt() {
  local phase="${1:?generate_cursor_prompt requires a phase ID}"

  local task
  task="$(state_get '.task' --required)"
  local loop
  loop="$(state_get '.loop')"
  loop="$(require_int "$loop" "loop")"
  local max_loops
  max_loops="$(state_get '.maxLoops')"
  max_loops="$(require_int "$max_loops" "maxLoops")"
  local fix_cycle
  fix_cycle="$(state_get '.fixCycle // 0')"
  fix_cycle="$(require_int "$fix_cycle" "fixCycle")"
  local max_fix_cycles
  max_fix_cycles="$(state_get '.maxFixCycles // 5')"
  max_fix_cycles="$(require_int "$max_fix_cycles" "maxFixCycles")"

  local phases_dir
  phases_dir=".agents/tmp/phases/loop-${loop}"

  case "$phase" in
    C1)
      local explorer_context=""
      if [[ -s ".agents/tmp/phases/f0-explorer-context.md" ]]; then
        explorer_context="Pre-gathered codebase context is available from parallel explorer agents. Read .agents/tmp/phases/f0-explorer-context.md before exploring. Use this context to skip redundant exploration and focus on planning."
      fi

      local prev_context=""
      if [[ "$loop" -gt 1 ]]; then
        local prev
        prev=$((loop - 1))
        prev_context="IMPORTANT: This is loop ${loop} (replan). Read the previous loop's judge output:
- .agents/tmp/phases/loop-${prev}/c3-judge.json

The judge determined the previous approach was fundamentally flawed. Read replan_reason carefully.
Plan a NEW approach that addresses the judge's concerns."
      fi

      cat <<PROMPT
## Cursor Orchestrator — Phase C1 (Plan) — Loop ${loop}/${max_loops}

Read .agents/tmp/state.json to confirm currentPhase is C1.

Analyze the task and split it into 2-3 domains (e.g., backend/frontend, core/tests, data/api/ui).

For each domain, dispatch a **sub-scout** agent (subagent_type: minions:sub-scout) in parallel with:
- The full task description
- The assigned domain name
- A domain prefix for task numbering (e.g., B for backend, F for frontend)

Task: ${task}

${explorer_context}

${prev_context}

Each sub-scout writes its partial plan to: ${phases_dir}/c1-sub-scout.{domain-slug}.md

Create the directory first: mkdir -p ${phases_dir}

After ALL sub-scouts complete, read all c1-sub-scout.*.md files, merge their task tables into a unified plan, renumber tasks sequentially (1, 2, 3, ...), resolve cross-domain dependencies, and write the final plan to: ${phases_dir}/c1-plan.md
PROMPT
      ;;

    C2)
      cat <<PROMPT
## Cursor Orchestrator — Phase C2 (Build) — Loop ${loop}/${max_loops}

Read .agents/tmp/state.json to confirm currentPhase is C2.
Read the plan at ${phases_dir}/c1-plan.md.

Parse the task table from the plan. For each task, dispatch a **cursor-builder** agent (subagent_type: minions:cursor-builder) in parallel.

Each cursor-builder receives:
- Task description and acceptance criteria from the plan
- Task ID (the task number)
- Instruction to commit after completing: git add <files> && git commit -m "task(N): description"

After ALL cursor-builders complete, aggregate their outputs into:
${phases_dir}/c2-tasks.json

The aggregated file should be a JSON object with:
{
  "tasks": [ ...each builder's output JSON... ],
  "files_changed": [ ...deduplicated list of all changed files... ],
  "all_complete": true
}
PROMPT
      ;;

    C2.5)
      cat <<PROMPT
## Cursor Orchestrator — Phase C2.5 (Fix) — Fix Cycle ${fix_cycle}/${max_fix_cycles}

Read .agents/tmp/state.json to confirm currentPhase is C2.5.
Read the judge's verdict at ${phases_dir}/c3-judge.json.

For each issue with severity "critical" or "warning", dispatch a **cursor-builder** agent (subagent_type: minions:cursor-builder) to fix it.

Group issues by file to avoid parallel edit conflicts — one cursor-builder per file group.

Each cursor-builder receives:
- The specific issue(s) to fix (description, file, line, fix_hint)
- Instruction to commit after fixing: git add <files> && git commit -m "fix(N): description"

After ALL fix-builders complete, aggregate into:
${phases_dir}/c2.5-fixes.json

{
  "fixes": [ ...each builder's output... ],
  "files_changed": [ ...deduplicated list... ],
  "all_complete": true
}
PROMPT
      ;;

    C3)
      local source_file="c2-tasks.json"
      if [[ "$fix_cycle" -gt 0 && -f "${phases_dir}/c2.5-fixes.json" ]]; then
        source_file="c2.5-fixes.json"
      fi

      local fix_context=""
      if [[ "$fix_cycle" -gt 0 ]]; then
        fix_context="This is fix cycle ${fix_cycle}/${max_fix_cycles}. The previous judge verdict requested fixes.
Read ${phases_dir}/c2.5-fixes.json for what was fixed.
Focus your review on whether the fixes are correct and complete."
      fi

      cat <<PROMPT
## Cursor Orchestrator — Phase C3 (Judge) — Loop ${loop}/${max_loops}

Read .agents/tmp/state.json to confirm currentPhase is C3.
Read ${phases_dir}/${source_file} for the list of changed files.

Dispatch the **judge** agent (subagent_type: minions:judge) with this prompt:

Task: ${task}
Loop: ${loop}/${max_loops}
Fix cycle: ${fix_cycle}/${max_fix_cycles}

Changed files are listed in ${phases_dir}/${source_file}.
Read each changed file and review across 5 dimensions.

${fix_context}

Write your verdict to: ${phases_dir}/c3-judge.json
PROMPT
      ;;

    C4)
      cat <<PROMPT
## Cursor Orchestrator — Phase C4 (Ship) — Loop ${loop}

Read .agents/tmp/state.json to confirm currentPhase is C4.

Dispatch the **shipper** agent (subagent_type: minions:shipper) with this prompt:

Task: ${task}

The feature branch has per-task commits from cursor-builders.
Squash-merge all commits into a single clean commit before opening the PR:

1. Read ${phases_dir}/c2-tasks.json for the summary of all tasks
2. Update documentation if needed
3. Create a squash commit: git reset --soft \$(git merge-base HEAD main) && git commit -m "feat: <task summary>"
4. Push and open a PR

Shipper must write its output to: ${phases_dir}/c4-ship.json
PROMPT
      ;;

    DONE|STOPPED)
      return 0
      ;;

    *)
      echo "generate_cursor_prompt: unknown phase $phase" >&2
      return 1
      ;;
  esac
}
