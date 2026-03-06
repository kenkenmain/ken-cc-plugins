#!/usr/bin/env bash
# test-teams.sh -- Unit tests for teams.sh
# Usage: bash plugins/ants/hooks/lib/test-teams.sh
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
ORIG_DIR="$(pwd)"
PASS=0
FAIL=0

cleanup() {
  cd "$ORIG_DIR"
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

setup() {
  cd "$TEST_DIR"
  mkdir -p .agents/tmp
  cat > .agents/tmp/state.json <<'JSON'
{
  "plugin": "ants",
  "version": 2,
  "status": "in_progress",
  "currentPhase": "A0",
  "loop": 1
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
  # Reset TEAMS_AVAILABLE
  TEAMS_AVAILABLE=false
  unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS 2>/dev/null || true
}

source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/teams.sh"
set +u

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $label (expected='$expected', actual='$actual')"
  fi
}

# =========================================================================
echo "=== teams_detect ==="

setup
teams_detect 2>/dev/null
assert_eq "teams not available by default" "false" "$TEAMS_AVAILABLE"

setup
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"
teams_detect 2>/dev/null
assert_eq "teams available when env=1" "true" "$TEAMS_AVAILABLE"

setup
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="0"
teams_detect 2>/dev/null
assert_eq "teams not available when env=0" "false" "$TEAMS_AVAILABLE"

setup
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=""
teams_detect 2>/dev/null
assert_eq "teams not available when env empty" "false" "$TEAMS_AVAILABLE"

# =========================================================================
echo "=== teams_get_dispatch_mode ==="

setup
result=$(teams_get_dispatch_mode)
assert_eq "dispatch mode is subagent by default" "subagent" "$result"

# Even with teams detected, currently always returns subagent
setup
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="1"
teams_detect 2>/dev/null
result=$(teams_get_dispatch_mode)
assert_eq "dispatch mode still subagent even with teams detected" "subagent" "$result"

# =========================================================================
echo "=== teams_log ==="

setup
output=$(teams_log "test message" 2>&1)
assert_eq "log has TEAMS prefix" "[TEAMS] test message" "$output"

# =========================================================================
echo "=== teams_build_task_descriptor ==="

setup
descriptor=$(teams_build_task_descriptor "ants:worker" "Build the auth module" "sonnet" "T1")

# Validate JSON fields
tid=$(echo "$descriptor" | jq -r '.taskId')
assert_eq "taskId" "T1" "$tid"

agent=$(echo "$descriptor" | jq -r '.agentType')
assert_eq "agentType" "ants:worker" "$agent"

prompt=$(echo "$descriptor" | jq -r '.prompt')
assert_eq "prompt" "Build the auth module" "$prompt"

model=$(echo "$descriptor" | jq -r '.model')
assert_eq "model" "sonnet" "$model"

dispatch=$(echo "$descriptor" | jq -r '.dispatch')
assert_eq "dispatch mode in descriptor" "subagent" "$dispatch"

created=$(echo "$descriptor" | jq -r '.createdAt')
if [[ -n "$created" && "$created" != "null" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: createdAt is set"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: createdAt not set"
fi

# Test with special characters in prompt
descriptor2=$(teams_build_task_descriptor "ants:sentinel-correctness" 'Review "all" files & check $vars' "inherit" "R1")
prompt2=$(echo "$descriptor2" | jq -r '.prompt')
assert_eq "special chars in prompt preserved" 'Review "all" files & check $vars' "$prompt2"

# =========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
