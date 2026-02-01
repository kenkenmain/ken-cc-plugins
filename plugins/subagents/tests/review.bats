#!/usr/bin/env bats
# review.bats -- Tests for issue grouping and parallel fix dispatch.

load test_helper/common

setup() {
  setup_temp_state
  source_libs
}

teardown() {
  teardown_temp_state
}

# ===========================================================================
# Issue Grouping
# ===========================================================================

@test "group_issues_by_file: single file produces 1 group" {
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-single-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":2,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  local groups
  groups="$(group_issues_by_file "$result")"
  local count
  count="$(echo "$groups" | jq 'length')"
  [ "$count" -eq 1 ]
}

@test "group_issues_by_file: single group has all issues" {
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-single-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":2,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  local groups
  groups="$(group_issues_by_file "$result")"
  local issue_count
  issue_count="$(echo "$groups" | jq '.[0].issues | length')"
  [ "$issue_count" -eq 2 ]
}

@test "group_issues_by_file: multi-file produces correct groups" {
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-multi-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":4,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  local groups
  groups="$(group_issues_by_file "$result")"
  local count
  count="$(echo "$groups" | jq 'length')"
  [ "$count" -eq 3 ]
}

@test "group_issues_by_file: groups have unique file lists" {
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-multi-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":4,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  local groups
  groups="$(group_issues_by_file "$result")"

  # Each group should have exactly one unique file
  local all_files
  all_files="$(echo "$groups" | jq -r '[.[].files[]] | sort | join(",")')"
  [[ "$all_files" == *"src/api/handler.ts"* ]]
  [[ "$all_files" == *"src/auth/oauth.ts"* ]]
  [[ "$all_files" == *"src/db/connection.ts"* ]]
}

@test "group_issues_by_file: auth group has 2 issues" {
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-multi-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":4,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  local groups
  groups="$(group_issues_by_file "$result")"

  # auth/oauth.ts group should have 2 issues
  local auth_count
  auth_count="$(echo "$groups" | jq '[.[] | select(.files[] == "src/auth/oauth.ts")] | .[0].issues | length')"
  [ "$auth_count" -eq 2 ]
}

@test "group_issues_by_file: null location grouped as unknown" {
  local result
  result='{"passed":false,"issueCount":2,"blockingIssues":[{"severity":"HIGH","location":null,"description":"issue1"},{"severity":"MEDIUM","location":"src/a.ts:10","description":"issue2"}]}'

  local groups
  groups="$(group_issues_by_file "$result")"
  local count
  count="$(echo "$groups" | jq 'length')"
  [ "$count" -eq 2 ]

  # One group should have "unknown" file
  local unknown_count
  unknown_count="$(echo "$groups" | jq '[.[] | select(.files[] == "unknown")] | length')"
  [ "$unknown_count" -eq 1 ]
}

@test "group_issues_by_file: Windows drive letter path preserved" {
  local result
  result='{"passed":false,"issueCount":2,"blockingIssues":[{"severity":"HIGH","location":"C:\\repo\\file.ts:12","description":"issue1"},{"severity":"MEDIUM","location":"C:\\repo\\file.ts:45","description":"issue2"}]}'

  local groups
  groups="$(group_issues_by_file "$result")"
  local count
  count="$(echo "$groups" | jq 'length')"
  [ "$count" -eq 1 ]

  # File should be the full path, not just "C"
  local file
  file="$(echo "$groups" | jq -r '.[0].files[0]')"
  [[ "$file" == *"file.ts"* ]]
}

@test "group_issues_by_file: empty string location grouped as unknown" {
  local result
  result='{"passed":false,"issueCount":2,"blockingIssues":[{"severity":"HIGH","location":"","description":"issue1"},{"severity":"MEDIUM","location":"src/a.ts:10","description":"issue2"}]}'

  local groups
  groups="$(group_issues_by_file "$result")"

  # Empty location should map to "unknown"
  local unknown_count
  unknown_count="$(echo "$groups" | jq '[.[] | select(.files[] == "unknown")] | length')"
  [ "$unknown_count" -eq 1 ]
}

# ===========================================================================
# Fix Cycle with Groups
# ===========================================================================

@test "start_fix_cycle: sets parallel=true for multi-file issues" {
  write_state '.currentPhase = "2.3" | .currentStage = "IMPLEMENT"'
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-multi-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":4,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  start_fix_cycle "2.3" "IMPLEMENT" "$result"

  local parallel
  parallel="$(state_get '.reviewFix.parallel')"
  [ "$parallel" = "true" ]
}

@test "start_fix_cycle: sets parallel=false for single-file issues" {
  write_state '.currentPhase = "2.3" | .currentStage = "IMPLEMENT"'
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-single-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":2,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  start_fix_cycle "2.3" "IMPLEMENT" "$result"

  local parallel
  parallel="$(state_get '.reviewFix.parallel')"
  [ "$parallel" = "false" ]
}

@test "start_fix_cycle: groupCount matches number of file groups" {
  write_state '.currentPhase = "2.3" | .currentStage = "IMPLEMENT"'
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-multi-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":4,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  start_fix_cycle "2.3" "IMPLEMENT" "$result"

  local group_count
  group_count="$(state_get '.reviewFix.groupCount')"
  [ "$group_count" -eq 3 ]
}

@test "start_fix_cycle: pendingGroups initialized to groupCount" {
  write_state '.currentPhase = "2.3" | .currentStage = "IMPLEMENT"'
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-multi-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":4,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  start_fix_cycle "2.3" "IMPLEMENT" "$result"

  local pending
  pending="$(state_get '.reviewFix.pendingGroups')"
  [ "$pending" -eq 3 ]
}

@test "start_fix_cycle: increments fixAttempts" {
  write_state '.currentPhase = "2.3" | .currentStage = "IMPLEMENT"'
  local fixture
  fixture="$(cat "$BATS_TEST_DIRNAME/fixtures/review-single-file-issues.json")"
  local result
  result='{"passed":false,"issueCount":2,"blockingIssues":'"$(echo "$fixture" | jq '.issues')"'}'

  start_fix_cycle "2.3" "IMPLEMENT" "$result"

  local attempts
  attempts="$(state_get '.stages.IMPLEMENT.phases["2.3"].fixAttempts')"
  [ "$attempts" -eq 1 ]
}

# ===========================================================================
# Review Output Validation
# ===========================================================================

@test "validate_review_output: approved review passes" {
  write_state '.currentPhase = "2.3" | .currentStage = "IMPLEMENT"'
  cp "$BATS_TEST_DIRNAME/fixtures/review-approved.json" "$PHASES_DIR/2.3-impl-review.json"

  local result
  result="$(validate_review_output "2.3")"
  local passed
  passed="$(echo "$result" | jq -r '.passed')"
  [ "$passed" = "true" ]
}

@test "validate_review_output: issues with blocking severity fail" {
  write_state '.currentPhase = "2.3" | .currentStage = "IMPLEMENT"'
  cp "$BATS_TEST_DIRNAME/fixtures/review-single-file-issues.json" "$PHASES_DIR/2.3-impl-review.json"

  local result
  result="$(validate_review_output "2.3")"
  local passed
  passed="$(echo "$result" | jq -r '.passed')"
  [ "$passed" = "false" ]
}

@test "validate_review_output: respects minBlockSeverity HIGH" {
  write_state '.currentPhase = "2.3" | .currentStage = "IMPLEMENT" | .reviewPolicy.minBlockSeverity = "HIGH"'
  # The single-file fixture has HIGH and MEDIUM issues
  cp "$BATS_TEST_DIRNAME/fixtures/review-single-file-issues.json" "$PHASES_DIR/2.3-impl-review.json"

  local result
  result="$(validate_review_output "2.3")"
  local count
  count="$(echo "$result" | jq -r '.issueCount')"
  # Only HIGH should block (1 of 2 issues)
  [ "$count" -eq 1 ]
}
