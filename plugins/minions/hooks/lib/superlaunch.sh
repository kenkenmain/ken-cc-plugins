#!/usr/bin/env bash
# superlaunch.sh — Shared library for superlaunch 15-phase pipeline hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/superlaunch.sh"
#
# Provides:
#   get_sl_next_phase()         — Next phase from schedule
#   get_sl_phase_output()       — Expected output filename
#   get_sl_phase_input()        — Input file descriptions
#   get_sl_phase_agent()        — Primary agent for phase
#   get_sl_supplementary()      — Supplementary agents (respecting policy)
#   validate_sl_gate()          — Check gate requirements at stage boundary
#   generate_sl_prompt()        — Build orchestrator prompt from phase metadata
#   get_sl_editable_stages()    — Stages where Edit/Write are allowed
#   get_sl_task_progress_instruction()      — Stage-transition task updates
#   get_sl_fix_cycle_task_instruction()     — Review-fix sub-task creation
#   get_sl_stage_restart_task_instruction() — Stage-restart sub-task creation
#   get_sl_coverage_loop_task_instruction() — Coverage-loop sub-task creation

set -euo pipefail

# ===========================================================================
# Phase Output Files
# ===========================================================================

get_sl_phase_output() {
  local phase="${1:?get_sl_phase_output requires a phase ID}"
  case "$phase" in
    S0)  echo "S0-explore.md" ;;
    S1)  echo "S1-brainstorm.md" ;;
    S2)  echo "S2-plan.md" ;;
    S3)  echo "S3-plan-review.json" ;;
    S4)  echo "S4-tasks.json" ;;
    S5)  echo "S5-simplify.md" ;;
    S6)  echo "S6-impl-review.json" ;;
    S7)  echo "S7-test-results.json" ;;
    S8)  echo "S8-analysis.md" ;;
    S9)  echo "S9-test-dev.json" ;;
    S10) echo "S10-test-dev-review.json" ;;
    S11) echo "S11-test-review.json" ;;
    S12) echo "S12-docs.md" ;;
    S13) echo "S13-final-review.json" ;;
    S14) echo "S14-completion.json" ;;
    *)   echo "" ;;
  esac
}

# ===========================================================================
# Phase Input Files
# ===========================================================================

get_sl_phase_input() {
  local phase="${1:?get_sl_phase_input requires a phase ID}"
  case "$phase" in
    S0)
      echo "- Task description from state.json \`.task\` field"
      ;;
    S1)
      echo "- \`.agents/tmp/phases/S0-explore.md\`"
      ;;
    S2)
      echo "- \`.agents/tmp/phases/S0-explore.md\`"
      echo "- \`.agents/tmp/phases/S1-brainstorm.md\`"
      ;;
    S3)
      echo "- \`.agents/tmp/phases/S2-plan.md\`"
      ;;
    S4)
      echo "- \`.agents/tmp/phases/S2-plan.md\`"
      ;;
    S5)
      echo "- \`.agents/tmp/phases/S4-tasks.json\`"
      echo "- Run \`git diff\` for current changes"
      ;;
    S6)
      echo "- \`.agents/tmp/phases/S2-plan.md\`"
      echo "- Run \`git diff\` for current changes"
      ;;
    S7)
      echo "- Test commands from project config (Makefile, package.json, etc.)"
      ;;
    S8)
      echo "- \`.agents/tmp/phases/S7-test-results.json\`"
      ;;
    S9)
      echo "- \`.agents/tmp/phases/S7-test-results.json\`"
      echo "- \`.agents/tmp/phases/S8-analysis.md\` (may not exist if tests passed)"
      echo "- \`.agents/tmp/phases/S4-tasks.json\` (check \`testsWritten\` — skip already-tested code)"
      ;;
    S10)
      echo "- \`.agents/tmp/phases/S9-test-dev.json\`"
      echo "- \`.agents/tmp/phases/S7-test-results.json\`"
      ;;
    S11)
      echo "- \`.agents/tmp/phases/S7-test-results.json\`"
      echo "- \`.agents/tmp/phases/S8-analysis.md\`"
      echo "- \`.agents/tmp/phases/S9-test-dev.json\`"
      ;;
    S12)
      echo "- \`.agents/tmp/phases/S2-plan.md\`"
      echo "- \`.agents/tmp/phases/S4-tasks.json\`"
      ;;
    S13)
      echo "- All \`.agents/tmp/phases/*.json\` files"
      ;;
    S14)
      echo "- \`.agents/tmp/phases/S13-final-review.json\`"
      ;;
    *)
      echo "- None"
      ;;
  esac
}

# ===========================================================================
# Phase Agent Routing
# ===========================================================================

get_sl_phase_agent() {
  local phase="${1:?get_sl_phase_agent requires a phase ID}"

  # Read phase type from schedule
  local phase_type
  phase_type="$(jq -r --arg p "$phase" '.schedule[] | select(.phase == $p) | .type // empty' "$STATE_FILE")"

  # Review phases — each has a dedicated reviewer agent
  if [[ "$phase_type" == "review" ]]; then
    case "$phase" in
      S3)  echo "minions:plan-reviewer" ;;
      S6)  echo "minions:impl-reviewer" ;;
      S10) echo "minions:test-dev-reviewer" ;;
      S11) echo "minions:test-reviewer" ;;
      S13) echo "minions:final-reviewer" ;;
      *)   echo "minions:plan-reviewer" ;;  # fallback
    esac
    return
  fi

  case "$phase" in
    S0)  echo "minions:explorer" ;;
    S1)  echo "minions:brainstormer" ;;
    S2)  echo "minions:planner" ;;
    S4)  echo "minions:task-agent" ;;
    S5)  echo "minions:simplifier" ;;
    S7)  state_get '.testDeveloper // "minions:test-developer"' ;;
    S8)  state_get '.failureAnalyzer // "minions:failure-analyzer"' ;;
    S9)  state_get '.testDeveloper // "minions:test-developer"' ;;
    S12) state_get '.docUpdater // "minions:doc-updater"' ;;
    S14) echo "minions:shipper" ;;
    *)   echo "" ;;
  esac
}

# ===========================================================================
# Phase Model
# ===========================================================================

get_sl_phase_model() {
  local phase="${1:?get_sl_phase_model requires a phase ID}"
  # All phases use inherit — the parent conversation's model controls execution
  echo "inherit"
}

# ===========================================================================
# Supplementary Agents
# ===========================================================================

_raw_sl_supplementary() {
  local phase="${1:?_raw_sl_supplementary requires a phase ID}"
  case "$phase" in
    S0)
      echo "minions:deep-explorer"
      ;;
    S2)
      echo "minions:architecture-analyst"
      ;;
    S3)
      echo "minions:judgement-agent"
      ;;
    S6)
      echo "minions:judgement-agent"
      echo "minions:critic"
      echo "minions:silent-failure-hunter"
      echo "minions:type-reviewer"
      ;;
    S10)
      echo "minions:judgement-agent"
      ;;
    S11)
      echo "minions:judgement-agent"
      ;;
    S12)
      echo "minions:claude-md-updater"
      ;;
    S13)
      echo "minions:judgement-agent"
      echo "minions:pedant"
      echo "minions:security-reviewer"
      echo "minions:silent-failure-hunter"
      ;;
    S14)
      echo "minions:retrospective-analyst"
      ;;
    *)
      # No supplementary agents
      ;;
  esac
}

get_sl_supplementary() {
  local phase="${1:?get_sl_supplementary requires a phase ID}"

  local phase_type
  phase_type="$(jq -r --arg p "$phase" '.schedule[] | select(.phase == $p) | .type // empty' "$STATE_FILE")"

  if [[ "$phase_type" == "review" ]]; then
    local policy
    policy="$(state_get '.supplementaryPolicy // "on-issues"')"
    if [[ "$policy" == "on-issues" ]]; then
      local supp_run
      supp_run="$(state_get ".supplementaryRun[\"$phase\"] // false")"
      if [[ "$supp_run" != "true" ]]; then
        return 0
      fi
    fi
  fi

  _raw_sl_supplementary "$phase"
}

# ===========================================================================
# Aggregator Support
# ===========================================================================

sl_phase_has_aggregator() {
  local phase="${1:-}"
  case "$phase" in
    S0|S2) return 0 ;;
    *)     return 1 ;;
  esac
}

get_sl_phase_aggregator() {
  local phase="${1:?get_sl_phase_aggregator requires a phase ID}"
  case "$phase" in
    S0) echo "minions:explore-aggregator" ;;
    S2) echo "minions:plan-aggregator" ;;
    *)   echo "" ;;
  esac
}

# ===========================================================================
# Supplementary Agent Detection
# ===========================================================================

is_sl_supplementary_agent() {
  local agent_type="${1:-}"
  [[ -z "$agent_type" ]] && return 1
  case "$agent_type" in
    minions:deep-explorer|\
    minions:architecture-analyst|\
    minions:judgement-agent|\
    minions:critic|\
    minions:pedant|\
    minions:security-reviewer|\
    minions:silent-failure-hunter|\
    minions:type-reviewer|\
    minions:claude-md-updater|\
    minions:retrospective-analyst)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_sl_aggregator_agent() {
  local agent_type="${1:-}"
  [[ -z "$agent_type" ]] && return 1
  case "$agent_type" in
    minions:explore-aggregator|\
    minions:plan-aggregator)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ===========================================================================
# Phase Navigation
# ===========================================================================

get_sl_next_phase() {
  local current_phase="${1:?get_sl_next_phase requires a phase ID}"
  local result
  result="$(jq -r --arg cp "$current_phase" '
    .schedule as $sched |
    ($sched | to_entries | map(select(.value.phase == $cp)) | .[0].key) as $idx |
    if $idx == null then "null"
    elif ($idx + 1) >= ($sched | length) then "null"
    else $sched[$idx + 1] | tojson
    end
  ' "$STATE_FILE")"
  echo "$result"
}

is_sl_last_phase() {
  local phase="${1:?is_sl_last_phase requires a phase ID}"
  local next
  next="$(get_sl_next_phase "$phase")"
  [[ "$next" == "null" ]]
}

# ===========================================================================
# Gate Validation
# ===========================================================================

validate_sl_gate() {
  local gate_name="${1:?validate_sl_gate requires a gate name}"
  local phases_dir="${2:?validate_sl_gate requires phases_dir}"

  local required_files
  required_files="$(jq -r --arg g "$gate_name" '.gates[$g].required // [] | .[]' "$STATE_FILE")"

  if [[ -z "$required_files" ]]; then
    # No gate defined for this transition
    return 0
  fi

  local missing=""
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if [[ ! -f "${phases_dir}/${file}" ]]; then
      missing="${missing}${missing:+, }${file}"
    fi
  done <<< "$required_files"

  if [[ -n "$missing" ]]; then
    echo "Gate ${gate_name} failed: missing files: ${missing}" >&2
    return 1
  fi

  return 0
}

# ===========================================================================
# Editable Stages
# ===========================================================================

get_sl_editable_stages() {
  echo "IMPLEMENT TEST FINAL"
}

# ===========================================================================
# Agent-to-Phase Mapping (for task gate and subagent-stop)
# ===========================================================================

# Map a minions agent type to the superlaunch phases it's allowed in.
# Returns space-separated list of phase IDs.
get_sl_agent_phases() {
  local agent_type="${1:?get_sl_agent_phases requires an agent type}"
  case "$agent_type" in
    minions:explorer)             echo "S0" ;;
    minions:deep-explorer)        echo "S0" ;;
    minions:explore-aggregator)   echo "S0" ;;
    minions:brainstormer)         echo "S1" ;;
    minions:planner)              echo "S2" ;;
    minions:architecture-analyst) echo "S2" ;;
    minions:plan-aggregator)      echo "S2" ;;
    minions:plan-reviewer)        echo "S3" ;;
    minions:judgement-agent)      echo "S3 S6 S10 S11 S13" ;;
    minions:impl-reviewer)        echo "S6" ;;
    minions:test-dev-reviewer)    echo "S10" ;;
    minions:test-reviewer)        echo "S11" ;;
    minions:final-reviewer)       echo "S13" ;;
    minions:task-agent)           echo "S4" ;;
    minions:simplifier)           echo "S5" ;;
    minions:critic)                  echo "S6" ;;
    minions:silent-failure-hunter)   echo "S6 S13" ;;
    minions:type-reviewer)           echo "S6" ;;
    minions:test-developer)       echo "S7 S9" ;;
    minions:failure-analyzer)     echo "S8" ;;
    minions:pedant)                  echo "S13" ;;
    minions:security-reviewer)       echo "S13" ;;
    minions:doc-updater)          echo "S12" ;;
    minions:claude-md-updater)    echo "S12" ;;
    minions:shipper)              echo "S14" ;;
    minions:retrospective-analyst) echo "S14" ;;
    *) echo "" ;;
  esac
}

# Check if an agent is allowed in the current phase
is_sl_agent_allowed() {
  local agent_type="${1:?is_sl_agent_allowed requires agent_type}"
  local current_phase="${2:?is_sl_agent_allowed requires current_phase}"

  local allowed_phases
  allowed_phases="$(get_sl_agent_phases "$agent_type")"
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
# Task Progress Instructions
# ===========================================================================

# Returns task update instruction for stage-transition phases.
# These get embedded in the orchestrator prompt so Claude calls TaskUpdate.
get_sl_task_progress_instruction() {
  local phase="${1:-}"
  case "$phase" in
    S0)  echo 'Mark "Execute EXPLORE stage" task as **in_progress** (activeForm: "Exploring codebase").' ;;
    S1)  printf '%s\n%s' \
           'Mark "Execute EXPLORE stage" task as **completed**.' \
           'Mark "Execute PLAN stage" task as **in_progress** (activeForm: "Planning implementation").' ;;
    S4)  printf '%s\n%s' \
           'Mark "Execute PLAN stage" task as **completed**.' \
           'Mark "Execute IMPLEMENT stage" task as **in_progress** (activeForm: "Implementing tasks").' ;;
    S7)  printf '%s\n%s' \
           'Mark "Execute IMPLEMENT stage" task as **completed**.' \
           'Mark "Execute TEST stage" task as **in_progress** (activeForm: "Testing implementation").' ;;
    S12) printf '%s\n%s' \
           'Mark "Execute TEST stage" task as **completed**.' \
           'Mark "Execute FINAL stage" task as **in_progress** (activeForm: "Finalizing and shipping").' ;;
    S14) echo 'After dispatching the agent and it completes, mark "Execute FINAL stage" task as **completed**.' ;;
    *)   return 0 ;;
  esac
}

# Returns fix-cycle sub-task instruction when in a review-fix loop.
# The SubagentStop hook sets state.reviewFix and increments fixAttempts.
get_sl_fix_cycle_task_instruction() {
  local phase="${1:-}"

  local review_fix_phase
  review_fix_phase="$(state_get '.reviewFix.phase // empty')"
  [[ -z "$review_fix_phase" || "$review_fix_phase" != "$phase" ]] && return 0

  local stage
  stage="$(state_get '.currentStage // empty')"
  [[ -z "$stage" ]] && return 0

  local attempts
  attempts="$(state_get ".fixAttempts[\"$phase\"] // 1")"
  local max_attempts
  max_attempts="$(state_get '.reviewPolicy.maxFixAttempts // 10')"

  local stage_lower
  stage_lower="$(echo "$stage" | tr '[:upper:]' '[:lower:]')"

  printf 'TaskCreate: subject: "Fix %s review issues (attempt %s/%s)", description: "Apply fixes from %s review feedback", activeForm: "Fixing %s review issues"\n' \
    "$stage_lower" "$attempts" "$max_attempts" "$phase" "$stage_lower"
  printf 'Mark it **in_progress** immediately. After applying all fixes and re-dispatching the reviewer, mark it **completed**.\n'
}

# Returns stage-restart sub-task instruction when stage has been restarted.
# The SubagentStop hook resets to first phase and bumps restartCount.
get_sl_stage_restart_task_instruction() {
  local phase="${1:-}"

  local stage
  stage="$(state_get '.currentStage // empty')"
  [[ -z "$stage" ]] && return 0

  # Only at first phase of stage
  local first_phase
  first_phase="$(state_get ".stages[\"$stage\"].phases[0] // empty")"
  [[ "$phase" != "$first_phase" ]] && return 0

  local restart_count
  restart_count="$(state_get ".stages[\"$stage\"].restartCount // 0")"
  local max_restarts
  max_restarts="$(state_get '.reviewPolicy.maxStageRestarts // 3')"
  [[ "$restart_count" -le 0 ]] && return 0

  local stage_lower
  stage_lower="$(echo "$stage" | tr '[:upper:]' '[:lower:]')"

  printf 'TaskCreate: subject: "Restart %s stage (attempt %s/%s)", description: "Stage restarted after exhausting fix attempts — re-running from %s", activeForm: "Restarting %s stage"\n' \
    "$stage_lower" "$restart_count" "$max_restarts" "$phase" "$stage_lower"
  printf 'Mark it **in_progress** immediately. Mark **completed** when the stage review passes.\n'
}

# Returns coverage-loop sub-task instruction when in a coverage improvement loop.
# The SubagentStop hook resets to S9 and bumps coverageLoop.iteration.
get_sl_coverage_loop_task_instruction() {
  local phase="${1:-}"
  [[ "$phase" != "S9" ]] && return 0

  local iteration
  iteration="$(state_get '.coverageLoop.iteration // 0')"
  [[ "$iteration" -le 0 ]] && return 0

  printf 'TaskCreate: subject: "Improve test coverage (iteration %s)", description: "Coverage loop: re-running S9-S11 to meet threshold", activeForm: "Improving test coverage (iteration %s)"\n' \
    "$iteration" "$iteration"
  printf 'Mark it **in_progress** immediately. Mark **completed** when S11 test review passes.\n'
}

# ===========================================================================
# Prompt Generation
# ===========================================================================

generate_sl_prompt() {
  local phase="${1:?generate_sl_prompt requires a phase ID}"

  local phase_json
  phase_json="$(jq -c --arg p "$phase" '.schedule[] | select(.phase == $p)' "$STATE_FILE")"

  if [[ -z "$phase_json" || "$phase_json" == "null" ]]; then
    echo "generate_sl_prompt: phase $phase not found in schedule" >&2
    return 1
  fi

  local name stage phase_type
  name="$(echo "$phase_json" | jq -r '.name')"
  stage="$(echo "$phase_json" | jq -r '.stage')"
  phase_type="$(echo "$phase_json" | jq -r '.type')"

  local subagent model output_file input_files
  subagent="$(get_sl_phase_agent "$phase")"
  model="$(get_sl_phase_model "$phase")"
  output_file="$(get_sl_phase_output "$phase")"
  input_files="$(get_sl_phase_input "$phase")"

  local task
  task="$(state_get '.task' --required)"

  local supplements
  supplements="$(get_sl_supplementary "$phase")"

  # Dispatch rules by type
  local dispatch_rules
  case "$phase_type" in
    dispatch)
      dispatch_rules="Read the prompt template for batch instructions. Dispatch multiple parallel subagents as specified. If an Aggregator Agent section appears below, after all primary and supplementary agents complete, dispatch the aggregator agent."
      ;;
    subagent)
      dispatch_rules="Dispatch a single subagent with the constructed prompt. If supplementary agents are listed, dispatch them in parallel."
      ;;
    review)
      dispatch_rules="Dispatch the reviewer agent. If supplementary agents are listed, dispatch them in parallel. Merge all issues into a single issues[] array with source field per agent."
      ;;
    *)
      dispatch_rules="Dispatch the phase agent with the constructed prompt."
      ;;
  esac

  # Build prompt
  cat <<PROMPT
# Dispatch Phase ${phase} (${stage}) — ${name}

You are the superlaunch orchestrator. Dispatch this phase as a subagent.

## Instructions

1. Read \`.agents/tmp/state.json\` — extract \`.task\`, \`.webSearch\`
2. **Check for review-fix cycle:** If \`state.reviewFix.phase\` matches \`${phase}\`, apply the fixes directly (read the issues, fix each one, then clear \`state.reviewFix\`). The SubagentStop hook sets \`state.reviewFix\` and the Stop hook regenerates this prompt.
3. Read the prompt template at \`prompts/superlaunch/${phase}-$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-').md\` for phase-specific instructions.
4. Build a minimal dispatch prompt (format below)
5. Dispatch via Task tool: subagent_type=\`${subagent}\`, model=\`${model}\`

**The subagent has its own system prompt and reads inputs directly.**

## Dispatch Prompt Format

\`\`\`
[PHASE ${phase}]

Execute Phase ${phase}: ${name}

Task: ${task}

Input files:
${input_files}

Output file: .agents/tmp/phases/${output_file}

Web search: {state.webSearch}
\`\`\`

## Dispatch Type: ${phase_type}

${dispatch_rules}
PROMPT

  # Supplementary agents section
  if [[ -n "$supplements" ]]; then
    cat <<SUPP

## Supplementary Agents

Dispatch these agents **in parallel** alongside the primary agent:

SUPP
    local agent
    while IFS= read -r agent; do
      [[ -z "$agent" ]] && continue
      echo "- \`${agent}\`"
    done <<< "$supplements"

    if [[ "$phase_type" == "review" ]]; then
      echo ""
      echo "Merge issues from all agents into a single \`issues[]\` array with \`\"source\"\` field per agent."
    fi
  else
    cat <<'NONE'

## Supplementary Agents

None for this phase.
NONE
  fi

  # Aggregator section
  if sl_phase_has_aggregator "$phase"; then
    local aggregator
    aggregator="$(get_sl_phase_aggregator "$phase")"
    local agg_glob
    case "$phase" in
      S0) agg_glob="S0-explore.*.tmp" ;;
      S2) agg_glob="S2-plan.*.tmp" ;;
      *)   agg_glob="*.tmp" ;;
    esac
    cat <<AGG

## Aggregator Agent

After ALL primary and supplementary agents complete, dispatch the aggregator:

- **subagent_type:** \`${aggregator}\`
- **Temp file pattern:** \`.agents/tmp/phases/${agg_glob}\`
- **Output file:** \`.agents/tmp/phases/${output_file}\`
AGG
  fi

  # Review-fix cycle rules
  if [[ "$phase_type" == "review" ]]; then
    cat <<'REVIEW'

## Review-Fix Cycle

When `state.reviewFix.phase` matches the current phase, apply the fixes directly instead of dispatching the reviewer.
Read the issues from the review output, fix each one in the codebase, then clear `state.reviewFix`.
The SubagentStop hook sets `state.reviewFix` and the Stop hook regenerates this prompt.
REVIEW
  fi

  # Coverage loop (phase S11)
  if [[ "$phase" == "S11" ]]; then
    cat <<'COVERAGE'

## Coverage Loop

After this phase, the SubagentStop hook checks coverage against `state.coverageThreshold`.
If below threshold, it resets `currentPhase` to `"S9"` for another test development cycle.
COVERAGE
  fi

  # Task progress updates
  local task_instruction
  task_instruction="$(get_sl_task_progress_instruction "$phase")"
  local fix_instruction
  fix_instruction="$(get_sl_fix_cycle_task_instruction "$phase")"
  local restart_instruction
  restart_instruction="$(get_sl_stage_restart_task_instruction "$phase")"
  local coverage_instruction
  coverage_instruction="$(get_sl_coverage_loop_task_instruction "$phase")"

  if [[ -n "$task_instruction" || -n "$fix_instruction" || -n "$restart_instruction" || -n "$coverage_instruction" ]]; then
    printf '\n## Task Progress\n\n'
    [[ -n "$task_instruction" ]] && printf '%s\n\n' "$task_instruction"
    [[ -n "$restart_instruction" ]] && printf '%s\n\n' "$restart_instruction"
    [[ -n "$fix_instruction" ]] && printf '%s\n\n' "$fix_instruction"
    [[ -n "$coverage_instruction" ]] && printf '%s\n\n' "$coverage_instruction"
    printf 'Use **TaskList** to find tasks by subject, then **TaskUpdate** / **TaskCreate** as needed. Only create sub-tasks if they do not already exist.\n'
    printf 'Also mark any leftover fix-cycle or restart sub-tasks as **completed** when moving to a new stage or after a stage restart.\n'
  fi

  # Standard rules footer
  cat <<'RULES'

## Rules

- Do NOT execute phase work directly — dispatch via Task tool
- Do NOT advance state — hooks handle this
- Do NOT stop or exit — hooks manage lifecycle
RULES
}
