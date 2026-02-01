#!/usr/bin/env bash
# schedule.sh -- Phase advancement logic for the subagents workflow.
# Requires state.sh to be sourced first (provides: read_state, state_get, STATE_FILE, etc.)
set -euo pipefail

# ---------------------------------------------------------------------------
# get_phase_output <phase> -- Return the expected output filename for a phase.
# ---------------------------------------------------------------------------
get_phase_output() {
  local phase="${1:?get_phase_output requires a phase ID}"

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
# Pipeline Profile Support
# ===========================================================================

# ---------------------------------------------------------------------------
# get_profile_schedule <profile> -- Return the JSON schedule array for a
#   pipeline profile. Profiles control which phases are included.
#   minimal: 5 phases (EXPLORE, IMPLEMENT, FINAL — skips PLAN + TEST)
#   standard: 13 phases (all except 2.2 Simplify and 3.2 Analyze Failures)
#   thorough: 15 phases (everything)
# ---------------------------------------------------------------------------
get_profile_schedule() {
  local profile="${1:?get_profile_schedule requires a profile name}"

  case "$profile" in
    minimal)
      cat <<'EOF'
[{"phase":"0","stage":"EXPLORE","name":"Explore","type":"dispatch"},{"phase":"2.1","stage":"IMPLEMENT","name":"Task Execution","type":"dispatch"},{"phase":"2.3","stage":"IMPLEMENT","name":"Implementation Review","type":"review"},{"phase":"4.2","stage":"FINAL","name":"Final Review","type":"review"},{"phase":"4.3","stage":"FINAL","name":"Completion","type":"subagent"}]
EOF
      ;;
    standard)
      cat <<'EOF'
[{"phase":"0","stage":"EXPLORE","name":"Explore","type":"dispatch"},{"phase":"1.1","stage":"PLAN","name":"Brainstorm","type":"subagent"},{"phase":"1.2","stage":"PLAN","name":"Plan","type":"dispatch"},{"phase":"1.3","stage":"PLAN","name":"Plan Review","type":"review"},{"phase":"2.1","stage":"IMPLEMENT","name":"Task Execution","type":"dispatch"},{"phase":"2.3","stage":"IMPLEMENT","name":"Implementation Review","type":"review"},{"phase":"3.1","stage":"TEST","name":"Run Tests & Analyze","type":"subagent"},{"phase":"3.3","stage":"TEST","name":"Develop Tests","type":"subagent"},{"phase":"3.4","stage":"TEST","name":"Test Dev Review","type":"review"},{"phase":"3.5","stage":"TEST","name":"Test Review","type":"review"},{"phase":"4.1","stage":"FINAL","name":"Documentation","type":"subagent"},{"phase":"4.2","stage":"FINAL","name":"Final Review","type":"review"},{"phase":"4.3","stage":"FINAL","name":"Completion","type":"subagent"}]
EOF
      ;;
    thorough)
      cat <<'EOF'
[{"phase":"0","stage":"EXPLORE","name":"Explore","type":"dispatch"},{"phase":"1.1","stage":"PLAN","name":"Brainstorm","type":"subagent"},{"phase":"1.2","stage":"PLAN","name":"Plan","type":"dispatch"},{"phase":"1.3","stage":"PLAN","name":"Plan Review","type":"review"},{"phase":"2.1","stage":"IMPLEMENT","name":"Task Execution","type":"dispatch"},{"phase":"2.2","stage":"IMPLEMENT","name":"Simplify","type":"subagent"},{"phase":"2.3","stage":"IMPLEMENT","name":"Implementation Review","type":"review"},{"phase":"3.1","stage":"TEST","name":"Run Tests & Analyze","type":"subagent"},{"phase":"3.2","stage":"TEST","name":"Analyze Failures","type":"subagent"},{"phase":"3.3","stage":"TEST","name":"Develop Tests","type":"subagent"},{"phase":"3.4","stage":"TEST","name":"Test Dev Review","type":"review"},{"phase":"3.5","stage":"TEST","name":"Test Review","type":"review"},{"phase":"4.1","stage":"FINAL","name":"Documentation","type":"subagent"},{"phase":"4.2","stage":"FINAL","name":"Final Review","type":"review"},{"phase":"4.3","stage":"FINAL","name":"Completion","type":"subagent"}]
EOF
      ;;
    *)
      echo "get_profile_schedule: unknown profile '$profile'" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# get_profile_gates <profile> -- Return the JSON gates map for a profile.
#   Gates define stage transition requirements.
# ---------------------------------------------------------------------------
get_profile_gates() {
  local profile="${1:?get_profile_gates requires a profile name}"

  case "$profile" in
    minimal)
      cat <<'EOF'
{"EXPLORE->IMPLEMENT":{"required":["0-explore.md"],"phase":"0"},"IMPLEMENT->FINAL":{"required":["2.1-tasks.json","2.3-impl-review.json"],"phase":"2.3"},"FINAL->COMPLETE":{"required":["4.2-final-review.json"],"phase":"4.2"}}
EOF
      ;;
    standard)
      cat <<'EOF'
{"EXPLORE->PLAN":{"required":["0-explore.md"],"phase":"0"},"PLAN->IMPLEMENT":{"required":["1.1-brainstorm.md","1.2-plan.md","1.3-plan-review.json"],"phase":"1.3"},"IMPLEMENT->TEST":{"required":["2.1-tasks.json","2.3-impl-review.json"],"phase":"2.3"},"TEST->FINAL":{"required":["3.1-test-results.json","3.3-test-dev.json","3.5-test-review.json"],"phase":"3.5"},"FINAL->COMPLETE":{"required":["4.2-final-review.json"],"phase":"4.2"}}
EOF
      ;;
    thorough)
      cat <<'EOF'
{"EXPLORE->PLAN":{"required":["0-explore.md"],"phase":"0"},"PLAN->IMPLEMENT":{"required":["1.1-brainstorm.md","1.2-plan.md","1.3-plan-review.json"],"phase":"1.3"},"IMPLEMENT->TEST":{"required":["2.1-tasks.json","2.3-impl-review.json"],"phase":"2.3"},"TEST->FINAL":{"required":["3.1-test-results.json","3.3-test-dev.json","3.5-test-review.json"],"phase":"3.5"},"FINAL->COMPLETE":{"required":["4.2-final-review.json"],"phase":"4.2"}}
EOF
      ;;
    *)
      echo "get_profile_gates: unknown profile '$profile'" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# get_profile_stages <profile> -- Return space-separated list of active stages.
# ---------------------------------------------------------------------------
get_profile_stages() {
  local profile="${1:?get_profile_stages requires a profile name}"

  case "$profile" in
    minimal)
      echo "EXPLORE IMPLEMENT FINAL"
      ;;
    standard|thorough)
      echo "EXPLORE PLAN IMPLEMENT TEST FINAL"
      ;;
    *)
      echo "get_profile_stages: unknown profile '$profile'" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# get_next_phase <current_phase> -- Return the next schedule entry as JSON,
#   or the string "null" if current_phase is the last entry.
# ---------------------------------------------------------------------------
get_next_phase() {
  local current_phase="${1:?get_next_phase requires a phase ID}"

  local result
  result="$(read_state | jq -r --arg cp "$current_phase" '
    .schedule as $sched |
    ($sched | to_entries | map(select(.value.phase == $cp)) | .[0].key) as $idx |
    if $idx == null then "null"
    elif ($idx + 1) >= ($sched | length) then "null"
    else $sched[$idx + 1] | tojson
    end
  ')"

  echo "$result"
}

# ---------------------------------------------------------------------------
# is_last_phase <phase> -- Return 0 (true) if phase is the last in the
#   schedule, 1 (false) otherwise.
# ---------------------------------------------------------------------------
is_last_phase() {
  local phase="${1:?is_last_phase requires a phase ID}"

  local next
  next="$(get_next_phase "$phase")"
  [[ "$next" == "null" ]]
}

# ---------------------------------------------------------------------------
# get_phase_input_files <phase> -- Return a human-readable description of
#   the input files or sources for a given phase.
# ---------------------------------------------------------------------------
get_phase_input_files() {
  local phase="${1:?get_phase_input_files requires a phase ID}"

  # Check if PLAN stage exists in the actual schedule (not just the profile name).
  # This handles cases where PLAN is disabled in config regardless of profile.
  local has_plan
  has_plan="$(read_state | jq -r '[.schedule[] | select(.phase == "1.2")] | if length > 0 then "true" else "false" end' 2>/dev/null || echo "true")"

  case "$phase" in
    0)
      echo "- None (use task description from state.json \`.task\` field)"
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
      if [[ "$has_plan" == "true" ]]; then
        echo "- \`.agents/tmp/phases/1.2-plan.md\`"
      else
        echo "- \`.agents/tmp/phases/0-explore.md\`"
        echo "- Task description from state.json \`.task\` field"
      fi
      ;;
    2.2)
      echo "- \`.agents/tmp/phases/2.1-tasks.json\`"
      echo "- Run \`git diff\` for current changes"
      ;;
    2.3)
      if [[ "$has_plan" == "true" ]]; then
        echo "- \`.agents/tmp/phases/1.2-plan.md\`"
      else
        echo "- \`.agents/tmp/phases/0-explore.md\`"
      fi
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
      echo "- \`.agents/tmp/phases/3.2-analysis.md\` (secondary output from phase 3.1 — may not exist if tests passed)"
      echo "- \`.agents/tmp/phases/2.1-tasks.json\` (check \`testsWritten\` entries — skip already-tested code)"
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
      if [[ "$has_plan" == "true" ]]; then
        echo "- \`.agents/tmp/phases/1.2-plan.md\`"
      fi
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

# ---------------------------------------------------------------------------
# get_phase_template <phase> -- Return the prompt template filename for a phase.
#   Uses a deterministic lookup (not slug generation) to avoid mismatches.
# ---------------------------------------------------------------------------
get_phase_template() {
  local phase="${1:?get_phase_template requires a phase ID}"

  case "$phase" in
    0)   echo "0-explore.md" ;;
    1.1) echo "1.1-brainstorm.md" ;;
    1.2) echo "1.2-plan.md" ;;
    1.3) echo "1.3-plan-review.md" ;;
    2.1) echo "2.1-implement.md" ;;
    2.2) echo "2.2-simplify.md" ;;
    2.3) echo "2.3-impl-review.md" ;;
    3.1) echo "3.1-run-tests.md" ;;
    3.2) echo "3.2-analyze.md" ;;
    3.3) echo "3.3-develop-tests.md" ;;
    3.4) echo "3.4-test-dev-review.md" ;;
    3.5) echo "3.5-test-review.md" ;;
    4.1) echo "4.1-documentation.md" ;;
    4.2) echo "4.2-final-review.md" ;;
    4.3) echo "4.3-completion.md" ;;
    *)   echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# build_chain_instruction <next_json> -- Build a human-readable instruction
#   string for the next phase from a JSON schedule entry.
#   Example output:
#     "Phase complete. Execute next: Phase 1.1 (PLAN) -- Brainstorm [subagent].
#      Read prompt template from prompts/phases/1.1-brainstorm.md.
#      Input files: .agents/tmp/phases/0-explore.md"
# ---------------------------------------------------------------------------
build_chain_instruction() {
  local next_json="${1:?build_chain_instruction requires a JSON string}"

  local phase name stage type
  phase="$(echo "$next_json" | jq -r '.phase')"
  name="$(echo "$next_json" | jq -r '.name')"
  stage="$(echo "$next_json" | jq -r '.stage')"
  type="$(echo "$next_json" | jq -r '.type')"

  local template_file
  template_file="$(get_phase_template "$phase")"

  local input_files
  input_files="$(get_phase_input_files "$phase")"

  echo "Phase complete. Execute next: Phase ${phase} (${stage}) -- ${name} [${type}]. Read prompt template from prompts/phases/${template_file}. Input files: ${input_files}"
}

# ---------------------------------------------------------------------------
# get_phase_type <phase> -- Return the phase type from the schedule.
# ---------------------------------------------------------------------------
get_phase_type() {
  local phase="${1:?get_phase_type requires a phase ID}"

  read_state | jq -r --arg p "$phase" \
    '.schedule[] | select(.phase == $p) | .type // empty'
}

# ---------------------------------------------------------------------------
# get_phase_subagent <phase> -- Return the subagent_type for a phase.
#   For review phases, reads state.reviewer. For test phases, reads
#   state.testRunner/failureAnalyzer. For others, uses hardcoded mapping.
# ---------------------------------------------------------------------------
get_phase_subagent() {
  local phase="${1:?get_phase_subagent requires a phase ID}"

  local phase_type
  phase_type="$(get_phase_type "$phase")"

  if [[ "$phase_type" == "review" ]]; then
    state_get '.reviewer // "subagents:claude-reviewer"'
    return
  fi

  case "$phase" in
    0)   echo "subagents:explorer" ;;
    1.1) echo "subagents:brainstormer" ;;
    1.2) echo "subagents:planner" ;;
    2.1) echo "subagents:task-agent" ;;
    2.2) echo "subagents:simplifier" ;;
    3.1) state_get '.testRunner // "subagents:test-runner"' ;;
    3.2) state_get '.failureAnalyzer // "subagents:failure-analyzer"' ;;
    3.3) echo "subagents:test-developer" ;;
    4.1) echo "subagents:doc-updater" ;;
    4.3) echo "subagents:completion-handler" ;;
    *)   echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# get_phase_model <phase> -- Return the model for a phase.
# ---------------------------------------------------------------------------
get_phase_model() {
  local phase="${1:?get_phase_model requires a phase ID}"

  local phase_type
  phase_type="$(get_phase_type "$phase")"

  if [[ "$phase_type" == "review" ]]; then
    local codex_available
    codex_available="$(state_get '.codexAvailable // false')"
    if [[ "$codex_available" == "true" ]]; then
      echo "sonnet"
    else
      echo "opus"
    fi
    return
  fi

  case "$phase" in
    0|1.1|1.2) echo "inherit" ;;   # EXPLORE + PLAN: inherit from parent
    2.1)   echo "per-task" ;;  # IMPLEMENT: complexity-based
    2.2)   echo "sonnet" ;;    # Simplify: sonnet
    *)     echo "sonnet" ;;    # TEST + FINAL: sonnet
  esac
}

# ===========================================================================
# Dynamic Supplementary Agent Support
# ===========================================================================

# ---------------------------------------------------------------------------
# get_supplementary_policy -- Read supplementary agent dispatch policy.
#   Returns "on-issues" (default) or "always".
#   "on-issues": for review phases, only dispatch supplementary on second pass
#     after primary finds issues (saves tokens when primary approves).
#   "always": dispatch supplementary alongside primary every time.
# ---------------------------------------------------------------------------
get_supplementary_policy() {
  local policy
  policy="$(state_get '.supplementaryPolicy // "on-issues"' 2>/dev/null || echo "on-issues")"
  echo "$policy"
}

# ---------------------------------------------------------------------------
# _raw_supplementary_agents <phase> -- Return supplementary agents for a phase
#   WITHOUT checking policy. Internal helper for policy-aware wrapper.
# ---------------------------------------------------------------------------
_raw_supplementary_agents() {
  local phase="${1:?_raw_supplementary_agents requires a phase ID}"

  case "$phase" in
    0)
      echo "subagents:deep-explorer"
      ;;
    1.2)
      echo "subagents:architecture-analyst"
      ;;
    2.3)
      echo "subagents:code-quality-reviewer"
      echo "subagents:error-handling-reviewer"
      echo "subagents:type-reviewer"
      ;;
    4.1)
      echo "subagents:claude-md-updater"
      ;;
    4.2)
      echo "subagents:code-quality-reviewer"
      echo "subagents:test-coverage-reviewer"
      echo "subagents:comment-reviewer"
      ;;
    4.3)
      echo "subagents:retrospective-analyst"
      ;;
    *)
      # No supplementary agents
      ;;
  esac
}

# ---------------------------------------------------------------------------
# get_supplementary_agents <phase> -- Return supplementary agents for a phase,
#   respecting the supplementary dispatch policy.
#
#   For review phases with "on-issues" policy: only returns agents on the
#   second pass (after state.supplementaryRun[phase] is set by the hook).
#   For non-review phases or "always" policy: returns agents unconditionally.
# ---------------------------------------------------------------------------
get_supplementary_agents() {
  local phase="${1:?get_supplementary_agents requires a phase ID}"

  # Check policy for review phases
  local phase_type
  phase_type="$(get_phase_type "$phase" 2>/dev/null || echo "")"

  if [[ "$phase_type" == "review" ]]; then
    local policy
    policy="$(get_supplementary_policy)"

    if [[ "$policy" == "on-issues" ]]; then
      # Only include supplementary on second pass (after primary found issues)
      local supp_run
      supp_run="$(state_get ".supplementaryRun[\"$phase\"] // false" 2>/dev/null || echo "false")"
      if [[ "$supp_run" != "true" ]]; then
        return 0
      fi
    fi
  fi

  _raw_supplementary_agents "$phase"
}

# ---------------------------------------------------------------------------
# is_supplementary_agent <agent_type> -- Return 0 if the agent type is a known
#   supplementary agent (not the primary phase agent). Used by the SubagentStop
#   hook to skip output validation when a supplementary agent finishes before
#   the primary agent has written the phase output file.
# ---------------------------------------------------------------------------
is_supplementary_agent() {
  local agent_type="${1:-}"
  [[ -z "$agent_type" ]] && return 1

  case "$agent_type" in
    subagents:deep-explorer|\
    subagents:architecture-analyst|\
    subagents:code-quality-reviewer|\
    subagents:error-handling-reviewer|\
    subagents:type-reviewer|\
    subagents:test-coverage-reviewer|\
    subagents:comment-reviewer|\
    subagents:claude-md-updater|\
    subagents:retrospective-analyst)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# _git_loc_changed -- Estimate total lines changed (insertions + deletions)
#   in the working tree. Tries merge-base against main/master first (captures
#   full branch changes), falls back to uncommitted diff against HEAD.
#   Returns 0 if git fails or no changes detected.
# ---------------------------------------------------------------------------
_git_loc_changed() {
  local dir="${1:-.}"
  local stat_line=""

  # Try diff against main's merge base (captures full branch changes)
  local base
  base="$(git -C "$dir" merge-base HEAD main 2>/dev/null \
       || git -C "$dir" merge-base HEAD master 2>/dev/null \
       || echo "")"
  if [[ -n "$base" ]]; then
    stat_line="$(git -C "$dir" diff "$base" --shortstat 2>/dev/null || echo "")"
  fi

  # Fallback: uncommitted changes against HEAD
  if [[ -z "$stat_line" ]]; then
    stat_line="$(git -C "$dir" diff HEAD --shortstat 2>/dev/null || echo "")"
  fi

  local ins
  ins="$(echo "$stat_line" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)"
  local del
  del="$(echo "$stat_line" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo 0)"
  echo $(( ${ins:-0} + ${del:-0} ))
}

# ---------------------------------------------------------------------------
# get_phase_timeout <phase> -- Return the phase-aware Codex timeout in ms.
#   Review phases get a short timeout (reviews should be fast).
#   Implementation phases get a long timeout (coding needs time).
#   Test phases get a medium timeout.
#   Final review (4.2) scales by code size: 10 min (<500 LOC) / 15 min (≥500).
# ---------------------------------------------------------------------------
get_phase_timeout() {
  local phase="${1:?get_phase_timeout requires a phase ID}"
  local phase_type
  phase_type="$(get_phase_type "$phase")"

  case "$phase_type" in
    review)
      if [[ "$phase" == "4.2" ]]; then
        # User override takes precedence
        local override
        override="$(state_get '.codexTimeout.finalReviewPhases // empty')"
        if [[ -n "$override" && "$override" != "null" ]]; then
          echo "$override"
          return
        fi
        # Scale by code size
        local code_dir
        code_dir="$(state_get '.worktree.path // empty')"
        [[ -z "$code_dir" || "$code_dir" == "null" ]] && code_dir="."
        local loc
        loc="$(_git_loc_changed "$code_dir")"
        if [[ "$loc" -ge 500 ]]; then
          echo 900000   # 15 min for large changes
        else
          echo 600000   # 10 min for small/medium changes
        fi
      else
        state_get '.codexTimeout.reviewPhases // 300000'
      fi
      ;;
    *)
      case "$phase" in
        2.1)
          state_get '.codexTimeout.implementPhases // 1800000'
          ;;
        3.1|3.3)
          state_get '.codexTimeout.testPhases // 600000'
          ;;
        *)
          state_get '.codexTimeout.reviewPhases // 300000'
          ;;
      esac
      ;;
  esac
}

# ---------------------------------------------------------------------------
# get_dispatch_rules <phase_type> -- Return type-specific dispatch rules.
# ---------------------------------------------------------------------------
get_dispatch_rules() {
  local phase_type="${1:?get_dispatch_rules requires a phase type}"

  case "$phase_type" in
    dispatch)
      cat <<'RULES'
Read the prompt template for batch instructions. Dispatch multiple parallel subagents as specified. Aggregate results into the output file. If supplementary agents are listed, dispatch them in the same Task tool message.
RULES
      ;;
    subagent)
      cat <<'RULES'
Dispatch a single subagent with the constructed prompt. If supplementary agents are listed, dispatch them in parallel in the same message.
RULES
      ;;
    review)
      cat <<'RULES'
Read `state.reviewer` to determine the subagent_type. Dispatch supplementary review agents in parallel. Merge all issues into a single `issues[]` array with `"source"` field per agent. If any supplementary agent fails, proceed with the primary agent's results only.
RULES
      ;;
    *)
      echo "Dispatch the phase agent with the constructed prompt."
      ;;
  esac
}

# ---------------------------------------------------------------------------
# generate_phase_prompt <phase> -- Build a minimal phase-specific orchestrator
#   prompt (~40 lines) instead of the full orchestrator-loop.md (~130 lines).
#   Reads phase metadata from state.json schedule and constructs the prompt.
# ---------------------------------------------------------------------------
generate_phase_prompt() {
  local phase="${1:?generate_phase_prompt requires a phase ID}"

  # Read phase metadata from schedule
  local phase_json
  phase_json="$(read_state | jq -c --arg p "$phase" '.schedule[] | select(.phase == $p)')"

  if [[ -z "$phase_json" || "$phase_json" == "null" ]]; then
    echo "generate_phase_prompt: phase $phase not found in schedule" >&2
    return 1
  fi

  local name stage phase_type
  name="$(echo "$phase_json" | jq -r '.name')"
  stage="$(echo "$phase_json" | jq -r '.stage')"
  phase_type="$(echo "$phase_json" | jq -r '.type')"

  local template subagent model output_file input_files
  template="$(get_phase_template "$phase")"
  subagent="$(get_phase_subagent "$phase")"
  model="$(get_phase_model "$phase")"
  output_file="$(get_phase_output "$phase")"
  input_files="$(get_phase_input_files "$phase")"

  local supplements
  supplements="$(get_supplementary_agents "$phase")"

  local dispatch_rules
  dispatch_rules="$(get_dispatch_rules "$phase_type")"

  # Build the prompt
  cat <<PROMPT
# Dispatch Phase ${phase} (${stage}) — ${name}

You are a workflow orchestrator. Dispatch this phase as a subagent.

## Instructions

1. Read \`.agents/tmp/state.json\` — extract \`.task\`, \`.worktree\`, \`.webSearch\`
2. **Check for review-fix cycle:** If \`state.reviewFix\` exists, dispatch \`subagents:fix-dispatcher\` instead (it reads issues and applies fixes directly).
3. Read the phase prompt template: \`prompts/phases/${template}\`
4. Build prompt with \`[PHASE ${phase}]\` tag using construction format below
5. Dispatch via Task tool: subagent_type=\`${subagent}\`, model=\`${model}\`
6. Write output to \`.agents/tmp/phases/${output_file}\`

**Do NOT read input files yourself.** The subagent reads them directly — just pass the paths.

## Prompt Construction

\`\`\`
[PHASE ${phase}]

{contents of the prompt template file}

## Task Context

Task: {value of state.json .task field}

{if state.worktree exists:
## Working Directory
Code directory: {state.worktree.path}
State directory: {absolute path to original .agents/tmp/}
All code operations must use the code directory.
All phase output files must use absolute paths to the state directory.
}

Web Search: {state.webSearch — true or false}

## Input Files

Read these files at the start of your work:
${input_files}
\`\`\`

The \`[PHASE ${phase}]\` tag is required — the PreToolUse hook validates it.

## Dispatch Type: ${phase_type}

${dispatch_rules}
PROMPT

  # Supplementary agents section
  if [[ -n "$supplements" ]]; then
    cat <<SUPP

## Supplementary Agents

Dispatch these agents **in parallel** (same Task tool message) alongside the primary agent:

SUPP
    local agent
    while IFS= read -r agent; do
      [[ -z "$agent" ]] && continue
      echo "- \`${agent}\`"
    done <<< "$supplements"

    if [[ "$phase_type" == "review" ]]; then
      cat <<'MERGE'

Merge issues from all agents into a single `issues[]` array. Each issue has a `"source"` field. If a supplementary agent fails, proceed with primary results only.
MERGE
    fi
  else
    cat <<'NONE'

## Supplementary Agents

None for this phase.
NONE
  fi

  # Review-fix cycle rules (for review phases)
  if [[ "$phase_type" == "review" ]]; then
    cat <<'REVIEW'

## Review-Fix Cycle

When `state.reviewFix` exists, dispatch `subagents:fix-dispatcher` instead:

- **If `state.reviewFix.parallel` is true:** dispatch one `subagents:fix-dispatcher` per group in `state.reviewFix.groups[]`. For each group, include `Fix Group: {group.id}` and the group's issues in the prompt. Dispatch all groups in parallel (same Task tool message).
- **If `state.reviewFix.parallel` is false or absent:** dispatch a single `subagents:fix-dispatcher` for all issues.

The SubagentStop hook tracks group completion and clears `reviewFix` when all groups finish.
REVIEW
  fi

  # Coverage loop rules (for phase 3.5)
  if [[ "$phase" == "3.5" ]]; then
    cat <<'COVERAGE'

## Coverage Loop

After this phase, the SubagentStop hook checks coverage against `state.coverageThreshold`. If below threshold, it resets `currentPhase` to `"3.3"` and deletes stale 3.3–3.5 output. Dispatch Phase 3.3 normally when you see `state.coverageLoop`.
COVERAGE
  fi

  # Codex timeout handling (for phases using Codex agents)
  if [[ "$subagent" == *"codex"* ]]; then
    local timeout_ms
    timeout_ms="$(get_phase_timeout "$phase")"
    local timeout_label
    timeout_label="$(( timeout_ms / 60000 )) min"
    cat <<TIMEOUT

## Codex Timeout Handling

This phase uses a Codex agent. Dispatch with timeout protection:

1. Dispatch via Task tool with \`run_in_background: true\` (MANDATORY — the PreToolUse hook blocks direct MCP calls and non-background Codex dispatches)
2. Call \`TaskOutput(task_id, block=true, timeout=${timeout_ms})\` (${timeout_label})
3. If result received: write to output file normally
4. If timeout: call \`TaskStop(task_id)\`, then write timeout error JSON to the output file:
   \`\`\`json
   {"status":"timeout","issues":[],"summary":"Codex MCP timed out after ${timeout_ms}ms. Automatic fallback to Claude reviewer.","codexTimeout":true}
   \`\`\`
TIMEOUT
  fi

  # Model selection note
  if [[ "$model" == "per-task" ]]; then
    cat <<'PERTASK'

## Model Selection

All tasks dispatched via task-agent (thin wrapper) to codex-high MCP. Complexity scoring used for tracking.
PERTASK
  elif [[ "$phase_type" == "review" ]]; then
    cat <<'REVIEWMODEL'

## Model Selection

Review tier: Codex available → `sonnet` (for supplementary agents); Codex unavailable → `opus`.
REVIEWMODEL
  fi

  # Standard rules footer
  cat <<'RULES'

## Rules

- Do NOT execute phase work directly — dispatch via Task tool
- Do NOT advance state — hooks handle this
- Do NOT stop or exit — hooks manage lifecycle
RULES
}
