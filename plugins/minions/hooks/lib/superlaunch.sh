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

set -euo pipefail

# ===========================================================================
# Phase Output Files
# ===========================================================================

get_sl_phase_output() {
  local phase="${1:?get_sl_phase_output requires a phase ID}"
  case "$phase" in
    0)   echo "0-explore.md" ;;
    1.1) echo "1.1-brainstorm.md" ;;
    1.2) echo "1.2-plan.md" ;;
    1.3) echo "1.3-plan-review.json" ;;
    2.1) echo "2.1-tasks.json" ;;
    2.2) echo "2.2-simplify.md" ;;
    2.3) echo "2.3-impl-review.json" ;;
    3.1) echo "3.1-test-results.json" ;;
    3.2) echo "3.2-analysis.md" ;;
    3.3) echo "3.3-test-dev.json" ;;
    3.4) echo "3.4-test-dev-review.json" ;;
    3.5) echo "3.5-test-review.json" ;;
    4.1) echo "4.1-docs.md" ;;
    4.2) echo "4.2-final-review.json" ;;
    4.3) echo "4.3-completion.json" ;;
    *)   echo "" ;;
  esac
}

# ===========================================================================
# Phase Input Files
# ===========================================================================

get_sl_phase_input() {
  local phase="${1:?get_sl_phase_input requires a phase ID}"
  case "$phase" in
    0)
      echo "- Task description from state.json \`.task\` field"
      ;;
    1.1)
      echo "- \`.agents/tmp/phases/0-explore.md\`"
      ;;
    1.2)
      echo "- \`.agents/tmp/phases/0-explore.md\`"
      echo "- \`.agents/tmp/phases/1.1-brainstorm.md\`"
      ;;
    1.3)
      echo "- \`.agents/tmp/phases/1.2-plan.md\`"
      ;;
    2.1)
      echo "- \`.agents/tmp/phases/1.2-plan.md\`"
      ;;
    2.2)
      echo "- \`.agents/tmp/phases/2.1-tasks.json\`"
      echo "- Run \`git diff\` for current changes"
      ;;
    2.3)
      echo "- \`.agents/tmp/phases/1.2-plan.md\`"
      echo "- Run \`git diff\` for current changes"
      ;;
    3.1)
      echo "- Test commands from project config (Makefile, package.json, etc.)"
      ;;
    3.2)
      echo "- \`.agents/tmp/phases/3.1-test-results.json\`"
      ;;
    3.3)
      echo "- \`.agents/tmp/phases/3.1-test-results.json\`"
      echo "- \`.agents/tmp/phases/3.2-analysis.md\` (may not exist if tests passed)"
      echo "- \`.agents/tmp/phases/2.1-tasks.json\` (check \`testsWritten\` — skip already-tested code)"
      ;;
    3.4)
      echo "- \`.agents/tmp/phases/3.3-test-dev.json\`"
      echo "- \`.agents/tmp/phases/3.1-test-results.json\`"
      ;;
    3.5)
      echo "- \`.agents/tmp/phases/3.1-test-results.json\`"
      echo "- \`.agents/tmp/phases/3.2-analysis.md\`"
      echo "- \`.agents/tmp/phases/3.3-test-dev.json\`"
      ;;
    4.1)
      echo "- \`.agents/tmp/phases/1.2-plan.md\`"
      echo "- \`.agents/tmp/phases/2.1-tasks.json\`"
      ;;
    4.2)
      echo "- All \`.agents/tmp/phases/*.json\` files"
      ;;
    4.3)
      echo "- \`.agents/tmp/phases/4.2-final-review.json\`"
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
  phase_type="$(jq -r --arg p "$phase" '.schedule[] | select(.phase == $p) | .type // empty' "$STATE_FILE" 2>/dev/null || echo "")"

  # Review phases use state.reviewer
  if [[ "$phase_type" == "review" ]]; then
    state_get '.reviewer // "minions:claude-reviewer"'
    return
  fi

  case "$phase" in
    0)   echo "minions:explorer" ;;
    1.1) echo "minions:brainstormer" ;;
    1.2) echo "minions:planner" ;;
    2.1) echo "minions:sonnet-task-agent" ;;
    2.2) echo "minions:simplifier" ;;
    3.1) state_get '.testDeveloper // "minions:test-developer"' ;;
    3.2) state_get '.failureAnalyzer // "minions:failure-analyzer"' ;;
    3.3) state_get '.testDeveloper // "minions:test-developer"' ;;
    4.1) state_get '.docUpdater // "minions:doc-updater"' ;;
    4.3) echo "minions:completion-handler" ;;
    *)   echo "" ;;
  esac
}

# ===========================================================================
# Phase Model
# ===========================================================================

get_sl_phase_model() {
  local phase="${1:?get_sl_phase_model requires a phase ID}"

  local phase_type
  phase_type="$(jq -r --arg p "$phase" '.schedule[] | select(.phase == $p) | .type // empty' "$STATE_FILE" 2>/dev/null || echo "")"

  if [[ "$phase_type" == "review" ]]; then
    echo "opus"
    return
  fi

  case "$phase" in
    0|1.1|1.2) echo "inherit" ;;
    2.1)       echo "per-task" ;;
    2.2)       echo "sonnet" ;;
    *)         echo "sonnet" ;;
  esac
}

# ===========================================================================
# Supplementary Agents
# ===========================================================================

_raw_sl_supplementary() {
  local phase="${1:?_raw_sl_supplementary requires a phase ID}"
  case "$phase" in
    0)
      echo "minions:deep-explorer"
      ;;
    1.2)
      echo "minions:architecture-analyst"
      ;;
    2.3)
      echo "minions:code-quality-reviewer"
      echo "minions:error-handling-reviewer"
      echo "minions:type-reviewer"
      ;;
    4.1)
      echo "minions:claude-md-updater"
      ;;
    4.2)
      echo "minions:code-quality-reviewer"
      echo "minions:test-coverage-reviewer"
      echo "minions:comment-reviewer"
      ;;
    4.3)
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
  phase_type="$(jq -r --arg p "$phase" '.schedule[] | select(.phase == $p) | .type // empty' "$STATE_FILE" 2>/dev/null || echo "")"

  if [[ "$phase_type" == "review" ]]; then
    local policy
    policy="$(state_get '.supplementaryPolicy // "on-issues"' 2>/dev/null || echo "on-issues")"
    if [[ "$policy" == "on-issues" ]]; then
      local supp_run
      supp_run="$(state_get ".supplementaryRun[\"$phase\"] // false" 2>/dev/null || echo "false")"
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
    0|1.2) return 0 ;;
    *)     return 1 ;;
  esac
}

get_sl_phase_aggregator() {
  local phase="${1:?get_sl_phase_aggregator requires a phase ID}"
  case "$phase" in
    0)   echo "minions:explore-aggregator" ;;
    1.2) echo "minions:plan-aggregator" ;;
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
    minions:code-quality-reviewer|\
    minions:error-handling-reviewer|\
    minions:type-reviewer|\
    minions:test-coverage-reviewer|\
    minions:comment-reviewer|\
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
  required_files="$(jq -r --arg g "$gate_name" '.gates[$g].required // [] | .[]' "$STATE_FILE" 2>/dev/null)"

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
    minions:explorer)             echo "0" ;;
    minions:deep-explorer)        echo "0" ;;
    minions:explore-aggregator)   echo "0" ;;
    minions:brainstormer)         echo "1.1" ;;
    minions:planner)              echo "1.2" ;;
    minions:architecture-analyst) echo "1.2" ;;
    minions:plan-aggregator)      echo "1.2" ;;
    minions:claude-reviewer)      echo "1.3 2.3 3.4 3.5 4.2" ;;
    minions:sonnet-task-agent)    echo "2.1" ;;
    minions:opus-task-agent)      echo "2.1" ;;
    minions:fix-dispatcher)       echo "1.3 2.3 3.4 3.5 4.2" ;;
    minions:simplifier)           echo "2.2" ;;
    minions:code-quality-reviewer)   echo "2.3 4.2" ;;
    minions:error-handling-reviewer) echo "2.3" ;;
    minions:type-reviewer)           echo "2.3" ;;
    minions:test-developer)       echo "3.1 3.3" ;;
    minions:failure-analyzer)     echo "3.2" ;;
    minions:test-coverage-reviewer)  echo "4.2" ;;
    minions:comment-reviewer)        echo "4.2" ;;
    minions:doc-updater)          echo "4.1" ;;
    minions:claude-md-updater)    echo "4.1" ;;
    minions:completion-handler)   echo "4.3" ;;
    minions:retrospective-analyst) echo "4.3" ;;
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
2. **Check for review-fix cycle:** If \`state.reviewFix\` exists, dispatch \`minions:fix-dispatcher\` instead.
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
      0)   agg_glob="0-explore.*.tmp" ;;
      1.2) agg_glob="1.2-plan.*.tmp" ;;
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

When `state.reviewFix` exists, dispatch `minions:fix-dispatcher` instead of the reviewer.
The SubagentStop hook tracks fix completion and clears `reviewFix` when done.
REVIEW
  fi

  # Coverage loop (phase 3.5)
  if [[ "$phase" == "3.5" ]]; then
    cat <<'COVERAGE'

## Coverage Loop

After this phase, the SubagentStop hook checks coverage against `state.coverageThreshold`.
If below threshold, it resets `currentPhase` to `"3.3"` for another test development cycle.
COVERAGE
  fi

  # Model selection for per-task phases
  if [[ "$model" == "per-task" ]]; then
    cat <<'PERTASK'

## Model Selection (Complexity-Routed)

Pick `subagent_type` based on each task's complexity:

| Level  | subagent_type                | Execution                       |
| ------ | ---------------------------- | ------------------------------- |
| Easy   | `minions:sonnet-task-agent` | Direct execution (model=sonnet) |
| Medium | `minions:opus-task-agent`   | Direct execution (model=opus)   |
| Hard   | `minions:opus-task-agent`   | Direct execution (model=opus)   |
PERTASK
  fi

  # Standard rules footer
  cat <<'RULES'

## Rules

- Do NOT execute phase work directly — dispatch via Task tool
- Do NOT advance state — hooks handle this
- Do NOT stop or exit — hooks manage lifecycle
RULES
}
