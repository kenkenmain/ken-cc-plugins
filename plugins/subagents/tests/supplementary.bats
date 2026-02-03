#!/usr/bin/env bats
# supplementary.bats -- Tests for dynamic supplementary agent dispatch.

load test_helper/common

setup() {
  setup_temp_state
  source_libs
}

teardown() {
  teardown_temp_state
}

# ===========================================================================
# Supplementary Policy
# ===========================================================================

@test "get_supplementary_policy: defaults to on-issues" {
  write_state '.'
  local policy
  policy="$(get_supplementary_policy)"
  [ "$policy" = "on-issues" ]
}

@test "get_supplementary_policy: reads from state" {
  write_state '.supplementaryPolicy = "always"'
  local policy
  policy="$(get_supplementary_policy)"
  [ "$policy" = "always" ]
}

# ===========================================================================
# Raw Supplementary Agents (policy-independent)
# ===========================================================================

@test "_raw_supplementary_agents: phase 2.3 returns 3 agents" {
  local agents
  agents="$(_raw_supplementary_agents "2.3")"
  local count
  count="$(echo "$agents" | grep -c .)"
  [ "$count" -eq 3 ]
}

@test "_raw_supplementary_agents: phase 4.2 returns 3 agents" {
  local agents
  agents="$(_raw_supplementary_agents "4.2")"
  local count
  count="$(echo "$agents" | grep -c .)"
  [ "$count" -eq 3 ]
}

@test "_raw_supplementary_agents: phase 4.3 returns retrospective-analyst" {
  local agents
  agents="$(_raw_supplementary_agents "4.3")"
  [[ "$agents" == *"retrospective-analyst"* ]]
}

@test "_raw_supplementary_agents: phase 0 returns deep-explorer" {
  local agents
  agents="$(_raw_supplementary_agents "0")"
  [[ "$agents" == *"deep-explorer"* ]]
}

@test "_raw_supplementary_agents: unknown phase returns empty" {
  local agents
  agents="$(_raw_supplementary_agents "99" || true)"
  [ -z "$agents" ]
}

# ===========================================================================
# Policy-Aware get_supplementary_agents
# ===========================================================================

@test "get_supplementary_agents: always policy returns agents for review phases" {
  write_state '.supplementaryPolicy = "always"'
  local agents
  agents="$(get_supplementary_agents "2.3")"
  [ -n "$agents" ]
  [[ "$agents" == *"code-quality-reviewer"* ]]
}

@test "get_supplementary_agents: on-issues policy returns empty for review phases (first pass)" {
  write_state '.supplementaryPolicy = "on-issues"'
  local agents
  agents="$(get_supplementary_agents "2.3")"
  [ -z "$agents" ]
}

@test "get_supplementary_agents: on-issues policy returns agents after supplementaryRun set" {
  write_state '.supplementaryPolicy = "on-issues" | .supplementaryRun = {"2.3": true}'
  local agents
  agents="$(get_supplementary_agents "2.3")"
  [ -n "$agents" ]
  [[ "$agents" == *"code-quality-reviewer"* ]]
}

@test "get_supplementary_agents: on-issues policy returns agents for non-review phases" {
  write_state '.supplementaryPolicy = "on-issues"'
  # Phase 0 is type "dispatch", not "review"
  local agents
  agents="$(get_supplementary_agents "0")"
  [ -n "$agents" ]
  [[ "$agents" == *"deep-explorer"* ]]
}

@test "get_supplementary_agents: on-issues only affects the specific review phase" {
  write_state '.supplementaryPolicy = "on-issues" | .supplementaryRun = {"2.3": true}'
  # 4.2 should still return empty (supplementaryRun only set for 2.3)
  local agents
  agents="$(get_supplementary_agents "4.2")"
  [ -z "$agents" ]
}

# ===========================================================================
# Unified Codex Reviewer (F3)
# ===========================================================================

@test "_raw_supplementary_agents: F3 with codexAvailable=true returns empty (unified reviewer)" {
  write_state '.codexAvailable = true'
  local agents
  agents="$(_raw_supplementary_agents "F3")"
  [ -z "$agents" ]
}

@test "_raw_supplementary_agents: F3 with codexAvailable=false returns 4 Claude agents" {
  write_state '.codexAvailable = false'
  local agents
  agents="$(_raw_supplementary_agents "F3")"
  local count
  count="$(echo "$agents" | grep -c .)"
  [ "$count" -eq 4 ]
  [[ "$agents" == *"error-handling-reviewer"* ]]
  [[ "$agents" == *"type-reviewer"* ]]
  [[ "$agents" == *"test-coverage-reviewer"* ]]
  [[ "$agents" == *"comment-reviewer"* ]]
}

@test "_raw_supplementary_agents: F3 respects explicit empty f3Supplementary from state" {
  write_state '.agents = { f3Supplementary: [] }'
  local agents
  agents="$(_raw_supplementary_agents "F3")"
  [ -z "$agents" ]
}

@test "is_supplementary_agent: old codex reviewer names still recognized" {
  is_supplementary_agent "subagents:codex-code-quality-reviewer"
  is_supplementary_agent "subagents:codex-error-handling-reviewer"
  is_supplementary_agent "subagents:codex-type-reviewer"
  is_supplementary_agent "subagents:codex-test-coverage-reviewer"
  is_supplementary_agent "subagents:codex-comment-reviewer"
}

@test "get_phase_subagent: F3 returns codex-unified-reviewer when codexAvailable" {
  write_state '.codexAvailable = true'
  local agent
  agent="$(get_phase_subagent "F3")"
  [ "$agent" = "subagents:codex-unified-reviewer" ]
}

@test "get_phase_subagent: F3 returns code-quality-reviewer when not codexAvailable" {
  write_state '.codexAvailable = false'
  local agent
  agent="$(get_phase_subagent "F3")"
  [ "$agent" = "subagents:code-quality-reviewer" ]
}

# ===========================================================================
# Supplementary Run State
# ===========================================================================

@test "supplementaryRun: cleared on stage restart" {
  write_state '
    .currentPhase = "2.3" |
    .currentStage = "IMPLEMENT" |
    .supplementaryRun = {"2.3": true} |
    .stages.IMPLEMENT.stageRestarts = 0
  '

  restart_stage "IMPLEMENT" "2.3" "test restart"

  local supp_run
  supp_run="$(state_get '.supplementaryRun // null')"
  [ "$supp_run" = "null" ]
}
