#!/usr/bin/env bats
# gates.bats -- Tests for gate validation across pipeline profiles.

load test_helper/common

setup() {
  setup_temp_state
  source_libs
}

teardown() {
  teardown_temp_state
}

# ===========================================================================
# Gate Lookup Per Profile
# ===========================================================================

@test "get_gate_for_phase: minimal profile phase 0 triggers EXPLORE->IMPLEMENT" {
  write_state_with_profile "minimal"
  local gate
  gate="$(get_gate_for_phase "0")"
  [ "$gate" = "EXPLORE->IMPLEMENT" ]
}

@test "get_gate_for_phase: minimal profile phase 2.3 triggers IMPLEMENT->FINAL" {
  write_state_with_profile "minimal"
  local gate
  gate="$(get_gate_for_phase "2.3")"
  [ "$gate" = "IMPLEMENT->FINAL" ]
}

@test "get_gate_for_phase: standard profile phase 0 triggers EXPLORE->PLAN" {
  write_state_with_profile "standard"
  local gate
  gate="$(get_gate_for_phase "0")"
  [ "$gate" = "EXPLORE->PLAN" ]
}

@test "get_gate_for_phase: standard profile phase 1.3 triggers PLAN->IMPLEMENT" {
  write_state_with_profile "standard"
  local gate
  gate="$(get_gate_for_phase "1.3")"
  [ "$gate" = "PLAN->IMPLEMENT" ]
}

@test "get_gate_for_phase: standard profile phase 3.5 triggers TEST->FINAL" {
  write_state_with_profile "standard"
  local gate
  gate="$(get_gate_for_phase "3.5")"
  [ "$gate" = "TEST->FINAL" ]
}

@test "get_gate_for_phase: non-gate phase returns empty" {
  write_state_with_profile "standard"
  local gate
  gate="$(get_gate_for_phase "2.1")"
  [ -z "$gate" ]
}

# ===========================================================================
# Gate Validation
# ===========================================================================

@test "validate_gate: passes when all required files exist" {
  write_state_with_profile "standard"
  create_phase_output "0-explore.md" "# Explore results"

  local result
  result="$(validate_gate "EXPLORE->PLAN")"
  local passed
  passed="$(echo "$result" | jq -r '.passed')"
  [ "$passed" = "true" ]
}

@test "validate_gate: fails when required file missing" {
  write_state_with_profile "standard"
  # Don't create any files

  local result
  result="$(validate_gate "EXPLORE->PLAN")"
  local passed
  passed="$(echo "$result" | jq -r '.passed')"
  [ "$passed" = "false" ]
}

@test "validate_gate: minimal EXPLORE->IMPLEMENT requires 0-explore.md" {
  write_state_with_profile "minimal"
  create_phase_output "0-explore.md" "# Explore"

  local result
  result="$(validate_gate "EXPLORE->IMPLEMENT")"
  local passed
  passed="$(echo "$result" | jq -r '.passed')"
  [ "$passed" = "true" ]
}

@test "validate_gate: minimal IMPLEMENT->FINAL requires tasks + review" {
  write_state_with_profile "minimal"
  create_phase_output "2.1-tasks.json" '{"tasks":[]}'
  # Missing 2.3-impl-review.json

  local result
  result="$(validate_gate "IMPLEMENT->FINAL")"
  local passed
  passed="$(echo "$result" | jq -r '.passed')"
  [ "$passed" = "false" ]

  local missing
  missing="$(echo "$result" | jq -r '.missing[0]')"
  [ "$missing" = "2.3-impl-review.json" ]
}

@test "validate_gate: PLAN->IMPLEMENT requires brainstorm, plan, and review" {
  write_state_with_profile "standard"
  create_phase_output "1.1-brainstorm.md" "# Brainstorm"
  create_phase_output "1.2-plan.md" "# Plan"
  # Missing 1.3-plan-review.json

  local result
  result="$(validate_gate "PLAN->IMPLEMENT")"
  local passed
  passed="$(echo "$result" | jq -r '.passed')"
  [ "$passed" = "false" ]
}

@test "validate_gate: PLAN->IMPLEMENT passes with all files" {
  write_state_with_profile "standard"
  create_phase_output "1.1-brainstorm.md" "# Brainstorm"
  create_phase_output "1.2-plan.md" "# Plan"
  create_phase_output "1.3-plan-review.json" '{"status":"approved"}'

  local result
  result="$(validate_gate "PLAN->IMPLEMENT")"
  local passed
  passed="$(echo "$result" | jq -r '.passed')"
  [ "$passed" = "true" ]
}
