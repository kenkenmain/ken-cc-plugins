#!/usr/bin/env bash
# test-teams.sh -- Unit tests for teams.sh (v0.3 Agent Teams)
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
  "version": 3,
  "status": "in_progress",
  "currentPhase": "A0",
  "loop": 1,
  "maxLoops": 5,
  "task": "Add auth module",
  "teamName": "ants-add-auth"
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
}

source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/swarm.sh"
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
echo "=== teams_log ==="

setup
output=$(teams_log "test message" 2>&1)
assert_eq "log has TEAMS prefix" "[TEAMS] test message" "$output"

# =========================================================================
echo "=== teams_get_next_ready_task ==="

setup
result=$(teams_get_next_ready_task)
assert_eq "returns current phase when in_progress" "A0" "$result"

setup
jq '.status = "complete" | .currentPhase = "DONE"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
result=$(teams_get_next_ready_task)
assert_eq "returns empty when complete" "" "$result"

setup
jq '.status = "blocked" | .currentPhase = "A3"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
result=$(teams_get_next_ready_task)
assert_eq "returns empty when blocked" "" "$result"

setup
jq '.currentPhase = "STOPPED"' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
result=$(teams_get_next_ready_task)
assert_eq "returns empty when STOPPED" "" "$result"

# =========================================================================
echo "=== teams_create_phase_tasks ==="

setup
tasks=$(teams_create_phase_tasks)
count=$(echo "$tasks" | jq 'length')
assert_eq "creates 1 queen pipeline task" "1" "$count"

pipeline_phase=$(echo "$tasks" | jq -r '.[0].phaseId')
assert_eq "single task is queen-pipeline" "queen-pipeline" "$pipeline_phase"

pipeline_blocked=$(echo "$tasks" | jq -r '.[0].blockedBy | length')
assert_eq "queen-pipeline has no blockedBy" "0" "$pipeline_blocked"

pipeline_desc=$(echo "$tasks" | jq -r '.[0].description')
if echo "$pipeline_desc" | grep -q "SendMessage"; then
  PASS=$((PASS + 1)); echo "  PASS: description mentions SendMessage"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: description should mention SendMessage"
fi

# =========================================================================
echo "=== teams_reject_completion ==="

setup
output=$(teams_reject_completion "Output file missing" 2>&1)
if echo "$output" | grep -q "Task completion rejected"; then
  PASS=$((PASS + 1)); echo "  PASS: reject message contains prefix"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: reject message missing prefix"
fi

# =========================================================================
echo "=== teams_build_teammate_prompt ==="

setup
prompt=$(teams_build_teammate_prompt "A0")
if echo "$prompt" | grep -q "Phase A0"; then
  PASS=$((PASS + 1)); echo "  PASS: prompt contains phase ID"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: prompt missing phase ID"
fi

if echo "$prompt" | grep -q "Add auth module"; then
  PASS=$((PASS + 1)); echo "  PASS: prompt contains task description"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: prompt missing task description"
fi

# =========================================================================
echo "=== teams_add_a3_subtasks ==="

setup
mkdir -p .agents/tmp/phases/loop-1
cat > .agents/tmp/phases/loop-1/A1-tasks.json <<'TASKS'
[
  {"id": "T1", "description": "Create auth module", "files_owned": ["src/auth.ts"], "dependencies": [], "acceptance_criteria": "Module exports login()"},
  {"id": "T2", "description": "Add middleware", "files_owned": ["src/middleware.ts"], "dependencies": ["T1"], "acceptance_criteria": "Middleware validates tokens"}
]
TASKS

subtasks=$(teams_add_a3_subtasks ".agents/tmp/phases/loop-1/A1-tasks.json")
subtask_count=$(echo "$subtasks" | jq 'length')
assert_eq "creates worker + sentinel + guardian + arbiter tasks" "7" "$subtask_count"

# Check worker tasks
worker_count=$(echo "$subtasks" | jq '[.[] | select(.phaseId | startswith("A3-worker"))] | length')
assert_eq "2 worker tasks" "2" "$worker_count"

# Check sentinel tasks
sentinel_count=$(echo "$subtasks" | jq '[.[] | select(.phaseId | startswith("A3-sentinel"))] | length')
assert_eq "3 sentinel tasks" "3" "$sentinel_count"

# Check guardian task
guardian_count=$(echo "$subtasks" | jq '[.[] | select(.phaseId == "A3-guardian")] | length')
assert_eq "1 guardian task" "1" "$guardian_count"

# Check arbiter task
arbiter_count=$(echo "$subtasks" | jq '[.[] | select(.phaseId == "A3-arbiter")] | length')
assert_eq "1 arbiter task" "1" "$arbiter_count"

# Check worker T2 depends on T1
t2_deps=$(echo "$subtasks" | jq -r '.[] | select(.phaseId == "A3-worker-T2") | .blockedBy | join(",")')
if echo "$t2_deps" | grep -q "A3-worker-T1"; then
  PASS=$((PASS + 1)); echo "  PASS: T2 depends on T1"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: T2 missing T1 dependency (got: $t2_deps)"
fi

# Check sentinels depend on all workers
s_deps=$(echo "$subtasks" | jq -r '.[] | select(.phaseId == "A3-sentinel-correctness") | .blockedBy | length')
assert_eq "sentinel depends on 2 workers" "2" "$s_deps"

# Check arbiter depends on 4 sentinels + guardian + simplifier
a_deps=$(echo "$subtasks" | jq -r '.[] | select(.phaseId == "A3-arbiter") | .blockedBy | length')
assert_eq "arbiter depends on 4 sentinels + guardian + simplifier" "6" "$a_deps"

# Test with missing file
if teams_add_a3_subtasks "/nonexistent/file.json" 2>/dev/null; then
  FAIL=$((FAIL + 1)); echo "  FAIL: should reject missing file"
else
  PASS=$((PASS + 1)); echo "  PASS: rejects missing file"
fi

# =========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
