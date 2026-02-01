#!/usr/bin/env bash
# common.bash -- Shared test helpers for bats tests.
# Source this from test files: load test_helper/common

# Create a temp directory for each test
setup_temp_state() {
  TEST_STATE_DIR="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$TEST_STATE_DIR"
  mkdir -p "$TEST_STATE_DIR/.agents/tmp/phases"

  # Re-export for state.sh
  export STATE_DIR="$TEST_STATE_DIR/.agents/tmp"
  export STATE_FILE="$STATE_DIR/state.json"
  export STATE_TMP="$STATE_DIR/state.json.tmp"
  export PHASES_DIR="$STATE_DIR/phases"
}

teardown_temp_state() {
  if [[ -n "${TEST_STATE_DIR:-}" && -d "$TEST_STATE_DIR" ]]; then
    rm -rf "$TEST_STATE_DIR"
  fi
}

# Write a state.json with the given jq expression applied to a base state
write_state() {
  local expr="${1:-.}"
  local base_state
  base_state='{
    "version": 2,
    "plugin": "subagents",
    "status": "in_progress",
    "task": "test task",
    "currentPhase": "0",
    "currentStage": "EXPLORE",
    "codexAvailable": false,
    "ownerPpid": "'"$PPID"'",
    "schedule": [
      {"phase":"0","stage":"EXPLORE","name":"Explore","type":"dispatch"},
      {"phase":"1.1","stage":"PLAN","name":"Brainstorm","type":"subagent"},
      {"phase":"1.2","stage":"PLAN","name":"Plan","type":"dispatch"},
      {"phase":"1.3","stage":"PLAN","name":"Plan Review","type":"review"},
      {"phase":"2.1","stage":"IMPLEMENT","name":"Task Execution","type":"dispatch"},
      {"phase":"2.3","stage":"IMPLEMENT","name":"Implementation Review","type":"review"},
      {"phase":"3.1","stage":"TEST","name":"Run Tests","type":"subagent"},
      {"phase":"3.3","stage":"TEST","name":"Develop Tests","type":"subagent"},
      {"phase":"3.4","stage":"TEST","name":"Test Dev Review","type":"review"},
      {"phase":"3.5","stage":"TEST","name":"Test Review","type":"review"},
      {"phase":"4.1","stage":"FINAL","name":"Documentation","type":"subagent"},
      {"phase":"4.2","stage":"FINAL","name":"Final Review","type":"review"},
      {"phase":"4.3","stage":"FINAL","name":"Completion","type":"subagent"}
    ],
    "gates": {
      "EXPLORE->PLAN": {"required":["0-explore.md"],"phase":"0"},
      "PLAN->IMPLEMENT": {"required":["1.1-brainstorm.md","1.2-plan.md","1.3-plan-review.json"],"phase":"1.3"},
      "IMPLEMENT->TEST": {"required":["2.1-tasks.json","2.3-impl-review.json"],"phase":"2.3"},
      "TEST->FINAL": {"required":["3.1-test-results.json","3.3-test-dev.json","3.5-test-review.json"],"phase":"3.5"},
      "FINAL->COMPLETE": {"required":["4.2-final-review.json"],"phase":"4.2"}
    },
    "stages": {
      "EXPLORE": {"status":"pending","phases":{}},
      "PLAN": {"status":"pending","phases":{},"restartCount":0,"blockReason":null},
      "IMPLEMENT": {"status":"pending","phases":{},"restartCount":0,"blockReason":null},
      "TEST": {"status":"pending","enabled":true,"phases":{},"restartCount":0,"blockReason":null},
      "FINAL": {"status":"pending","phases":{},"restartCount":0,"blockReason":null}
    },
    "reviewPolicy": {"minBlockSeverity":"LOW","maxFixAttempts":10,"maxStageRestarts":3},
    "coverageThreshold": 90,
    "webSearch": true,
    "files": {},
    "restartHistory": []
  }'
  echo "$base_state" | jq "$expr" > "$STATE_FILE"
}

# Write a minimal state with a specific profile schedule
write_state_with_profile() {
  local profile="${1:?write_state_with_profile requires a profile name}"
  local expr
  case "$profile" in
    minimal)
      expr='.pipelineProfile = "minimal" | .schedule = [
        {"phase":"0","stage":"EXPLORE","name":"Explore","type":"dispatch"},
        {"phase":"2.1","stage":"IMPLEMENT","name":"Task Execution","type":"dispatch"},
        {"phase":"2.3","stage":"IMPLEMENT","name":"Implementation Review","type":"review"},
        {"phase":"4.2","stage":"FINAL","name":"Final Review","type":"review"},
        {"phase":"4.3","stage":"FINAL","name":"Completion","type":"subagent"}
      ] | .gates = {
        "EXPLORE->IMPLEMENT": {"required":["0-explore.md"],"phase":"0"},
        "IMPLEMENT->FINAL": {"required":["2.1-tasks.json","2.3-impl-review.json"],"phase":"2.3"},
        "FINAL->COMPLETE": {"required":["4.2-final-review.json"],"phase":"4.2"}
      }'
      ;;
    standard)
      expr='.pipelineProfile = "standard"'
      ;;
    thorough)
      expr='.pipelineProfile = "thorough" | .schedule = (.schedule + [
        {"phase":"2.2","stage":"IMPLEMENT","name":"Simplify","type":"subagent"},
        {"phase":"3.2","stage":"TEST","name":"Analyze Failures","type":"subagent"}
      ] | sort_by(.phase))'
      ;;
    *)
      echo "Unknown profile: $profile" >&2
      return 1
      ;;
  esac
  write_state "$expr"
}

# Create a mock phase output file
create_phase_output() {
  local filename="${1:?create_phase_output requires a filename}"
  local content="${2:-{}}"
  echo "$content" > "$PHASES_DIR/$filename"
}

# Source the hook libraries (relative to plugin root)
source_libs() {
  local plugin_dir="${BATS_TEST_DIRNAME}/.."
  source "$plugin_dir/hooks/lib/state.sh"
  source "$plugin_dir/hooks/lib/gates.sh"
  source "$plugin_dir/hooks/lib/schedule.sh"
  source "$plugin_dir/hooks/lib/review.sh"
}
