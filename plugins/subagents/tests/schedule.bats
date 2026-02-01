#!/usr/bin/env bats
# schedule.bats -- Tests for pipeline profiles and schedule functions.

load test_helper/common

setup() {
  setup_temp_state
  source_libs
}

teardown() {
  teardown_temp_state
}

# ===========================================================================
# Pipeline Profile: Schedule Generation
# ===========================================================================

@test "get_profile_schedule: minimal returns 5 phases" {
  local schedule
  schedule="$(get_profile_schedule "minimal")"
  local count
  count="$(echo "$schedule" | jq 'length')"
  [ "$count" -eq 5 ]
}

@test "get_profile_schedule: minimal includes only EXPLORE, IMPLEMENT, FINAL stages" {
  local stages
  stages="$(get_profile_schedule "minimal" | jq -r '[.[].stage] | unique | sort | join(",")')"
  [ "$stages" = "EXPLORE,FINAL,IMPLEMENT" ]
}

@test "get_profile_schedule: minimal skips PLAN and TEST" {
  local phases
  phases="$(get_profile_schedule "minimal" | jq -r '[.[].phase] | join(",")')"
  [ "$phases" = "0,2.1,2.3,4.2,4.3" ]
}

@test "get_profile_schedule: standard returns 13 phases" {
  local schedule
  schedule="$(get_profile_schedule "standard")"
  local count
  count="$(echo "$schedule" | jq 'length')"
  [ "$count" -eq 13 ]
}

@test "get_profile_schedule: standard includes all 5 stages" {
  local stages
  stages="$(get_profile_schedule "standard" | jq -r '[.[].stage] | unique | sort | join(",")')"
  [ "$stages" = "EXPLORE,FINAL,IMPLEMENT,PLAN,TEST" ]
}

@test "get_profile_schedule: standard excludes 2.2 and 3.2" {
  local phases
  phases="$(get_profile_schedule "standard" | jq -r '[.[].phase] | join(",")')"
  [[ "$phases" != *"2.2"* ]]
  [[ "$phases" != *"3.2"* ]]
}

@test "get_profile_schedule: thorough returns 15 phases" {
  local schedule
  schedule="$(get_profile_schedule "thorough")"
  local count
  count="$(echo "$schedule" | jq 'length')"
  [ "$count" -eq 15 ]
}

@test "get_profile_schedule: thorough includes 2.2 Simplify and 3.2 Analyze" {
  local phases
  phases="$(get_profile_schedule "thorough" | jq -r '[.[].phase] | join(",")')"
  [[ "$phases" == *"2.2"* ]]
  [[ "$phases" == *"3.2"* ]]
}

@test "get_profile_schedule: unknown profile returns error" {
  run get_profile_schedule "invalid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown profile"* ]]
}

# ===========================================================================
# Pipeline Profile: Gates
# ===========================================================================

@test "get_profile_gates: minimal has 3 gates" {
  local gates
  gates="$(get_profile_gates "minimal")"
  local count
  count="$(echo "$gates" | jq 'keys | length')"
  [ "$count" -eq 3 ]
}

@test "get_profile_gates: minimal skips PLAN gates" {
  local gates
  gates="$(get_profile_gates "minimal")"
  local has_plan
  has_plan="$(echo "$gates" | jq 'has("EXPLORE->PLAN")')"
  [ "$has_plan" = "false" ]
}

@test "get_profile_gates: minimal has EXPLORE->IMPLEMENT gate" {
  local gates
  gates="$(get_profile_gates "minimal")"
  local has_gate
  has_gate="$(echo "$gates" | jq 'has("EXPLORE->IMPLEMENT")')"
  [ "$has_gate" = "true" ]
}

@test "get_profile_gates: standard has 5 gates" {
  local gates
  gates="$(get_profile_gates "standard")"
  local count
  count="$(echo "$gates" | jq 'keys | length')"
  [ "$count" -eq 5 ]
}

@test "get_profile_gates: thorough has 5 gates" {
  local gates
  gates="$(get_profile_gates "thorough")"
  local count
  count="$(echo "$gates" | jq 'keys | length')"
  [ "$count" -eq 5 ]
}

# ===========================================================================
# Pipeline Profile: Stages
# ===========================================================================

@test "get_profile_stages: minimal returns 3 stages" {
  local stages
  stages="$(get_profile_stages "minimal")"
  [ "$stages" = "EXPLORE IMPLEMENT FINAL" ]
}

@test "get_profile_stages: standard returns 5 stages" {
  local stages
  stages="$(get_profile_stages "standard")"
  [ "$stages" = "EXPLORE PLAN IMPLEMENT TEST FINAL" ]
}

@test "get_profile_stages: thorough returns 5 stages" {
  local stages
  stages="$(get_profile_stages "thorough")"
  [ "$stages" = "EXPLORE PLAN IMPLEMENT TEST FINAL" ]
}

# ===========================================================================
# Schedule Navigation with Profiles
# ===========================================================================

@test "get_next_phase: minimal profile advances 0 -> 2.1" {
  write_state_with_profile "minimal"
  local next
  next="$(get_next_phase "0")"
  local phase
  phase="$(echo "$next" | jq -r '.phase')"
  [ "$phase" = "2.1" ]
}

@test "get_next_phase: minimal profile advances 2.3 -> 4.2" {
  write_state_with_profile "minimal"
  local next
  next="$(get_next_phase "2.3")"
  local phase
  phase="$(echo "$next" | jq -r '.phase')"
  [ "$phase" = "4.2" ]
}

@test "get_phase_input_files: minimal profile phase 2.1 uses explore not plan" {
  write_state_with_profile "minimal"
  local inputs
  inputs="$(get_phase_input_files "2.1")"
  [[ "$inputs" == *"0-explore.md"* ]]
  [[ "$inputs" != *"1.2-plan.md"* ]]
}

@test "get_phase_input_files: standard profile phase 2.1 uses plan" {
  write_state_with_profile "standard"
  local inputs
  inputs="$(get_phase_input_files "2.1")"
  [[ "$inputs" == *"1.2-plan.md"* ]]
}

@test "get_phase_input_files: minimal profile phase 2.3 uses explore not plan" {
  write_state_with_profile "minimal"
  local inputs
  inputs="$(get_phase_input_files "2.3")"
  [[ "$inputs" == *"0-explore.md"* ]]
  [[ "$inputs" != *"1.2-plan.md"* ]]
}

@test "get_phase_output: thorough-only phases have outputs" {
  local out_22
  out_22="$(get_phase_output "2.2")"
  [ "$out_22" = "2.2-simplify.md" ]

  local out_32
  out_32="$(get_phase_output "3.2")"
  [ "$out_32" = "3.2-analysis.md" ]
}

@test "get_phase_template: thorough-only phases have templates" {
  local tmpl_22
  tmpl_22="$(get_phase_template "2.2")"
  [ "$tmpl_22" = "2.2-simplify.md" ]

  local tmpl_32
  tmpl_32="$(get_phase_template "3.2")"
  [ "$tmpl_32" = "3.2-analyze.md" ]
}

@test "is_supplementary_agent: recognizes supplementary agents" {
  is_supplementary_agent "subagents:retrospective-analyst"
  is_supplementary_agent "subagents:code-quality-reviewer"
  is_supplementary_agent "subagents:deep-explorer"
}

@test "is_supplementary_agent: rejects primary agents" {
  ! is_supplementary_agent "subagents:task-agent"
  ! is_supplementary_agent "subagents:completion-handler"
  ! is_supplementary_agent "subagents:planner"
  ! is_supplementary_agent ""
}

@test "is_last_phase: 4.3 is last in all profiles" {
  write_state_with_profile "minimal"
  is_last_phase "4.3"

  write_state_with_profile "standard"
  is_last_phase "4.3"

  write_state_with_profile "thorough"
  is_last_phase "4.3"
}
