#!/usr/bin/env bash
# test-teams.sh -- Unit tests for teams.sh (v0.6 Agent Teams delegate mode)
# Usage: bash plugins/ants/hooks/lib/test-teams.sh
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$SCRIPT_DIR"
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
# v0.6: returns phaseId\ttaskType (tab-separated)
result_phase=$(printf '%s' "$result" | cut -f1)
result_type=$(printf '%s' "$result" | cut -f2)
assert_eq "returns current phase when pending" "A0" "$result_phase"
assert_eq "returns task type 'phase' for sequential phases" "phase" "$result_type"

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
assert_eq "creates 6 phase tasks (A0-A5)" "6" "$count"

# Verify phaseId values A0-A5
a0_phase=$(echo "$tasks" | jq -r '.[0].phaseId')
assert_eq "first task is A0" "A0" "$a0_phase"

a1_phase=$(echo "$tasks" | jq -r '.[1].phaseId')
assert_eq "second task is A1" "A1" "$a1_phase"

a5_phase=$(echo "$tasks" | jq -r '.[5].phaseId')
assert_eq "sixth task is A5" "A5" "$a5_phase"

# Verify blockedBy chains
a0_blocked=$(echo "$tasks" | jq -r '.[0].blockedBy | length')
assert_eq "A0 has no blockedBy" "0" "$a0_blocked"

a1_blocked=$(echo "$tasks" | jq -r '.[1].blockedBy[0]')
assert_eq "A1 blockedBy A0" "A0" "$a1_blocked"

a5_blocked=$(echo "$tasks" | jq -r '.[5].blockedBy[0]')
assert_eq "A5 blockedBy A4" "A4" "$a5_blocked"

# Verify subjects contain phase context
a3_subject=$(echo "$tasks" | jq -r '.[3].subject')
if echo "$a3_subject" | grep -q "A3"; then
  PASS=$((PASS + 1)); echo "  PASS: A3 subject contains phase prefix"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: A3 subject missing phase prefix"
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
# 2 workers + 4 sentinels (correctness, security, perf, style) + 1 guardian + 1 simplifier + 1 arbiter + 1 review-fixer = 10
assert_eq "creates 10 subtasks: 2 workers + 4 sentinels + guardian + simplifier + arbiter + review-fixer" "10" "$subtask_count"

# Check worker tasks
worker_count=$(echo "$subtasks" | jq '[.[] | select(.phaseId | startswith("A3-worker"))] | length')
assert_eq "2 worker tasks" "2" "$worker_count"

# Check sentinel tasks (4 specialist sentinels: correctness, security, perf, style)
sentinel_count=$(echo "$subtasks" | jq '[.[] | select(.phaseId | startswith("A3-sentinel"))] | length')
assert_eq "4 sentinel tasks (correctness, security, perf, style)" "4" "$sentinel_count"

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

# Check simplifier task is present (T1: added to known subtask set)
simplifier_count=$(echo "$subtasks" | jq '[.[] | select(.phaseId == "A3-simplifier")] | length')
assert_eq "1 simplifier task" "1" "$simplifier_count"

# Check sentinel-style is one of the four sentinels (T1: sentinel-style added)
style_count=$(echo "$subtasks" | jq '[.[] | select(.phaseId == "A3-sentinel-style")] | length')
assert_eq "A3-sentinel-style task present" "1" "$style_count"

# Arbiter blockedBy must include A3-sentinel-style (T1: sentinel-style wired in)
arbiter_blocked=$(echo "$subtasks" | jq -r '.[] | select(.phaseId == "A3-arbiter") | .blockedBy | join(",")')
if echo "$arbiter_blocked" | grep -q "A3-sentinel-style"; then
  PASS=$((PASS + 1)); echo "  PASS: arbiter blocked by A3-sentinel-style"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: arbiter missing A3-sentinel-style dependency (got: $arbiter_blocked)"
fi

# Arbiter blockedBy must include A3-simplifier (T1: simplifier wired in)
if echo "$arbiter_blocked" | grep -q "A3-simplifier"; then
  PASS=$((PASS + 1)); echo "  PASS: arbiter blocked by A3-simplifier"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: arbiter missing A3-simplifier dependency (got: $arbiter_blocked)"
fi

# =========================================================================
echo "=== known_agents allowlist in teams_build_teammate_prompt (T1) ==="

setup
# Add a message from sentinel-style and explore-aggregator to test allowlist
jq '.messages = [
  {"from": "sentinel-style",     "to": "architect", "loop": 1, "content": "Style OK"},
  {"from": "explore-aggregator", "to": "architect", "loop": 1, "content": "Explored"},
  {"from": "unknown-bot",        "to": "architect", "loop": 1, "content": "Spam"}
]' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

prompt=$(teams_build_teammate_prompt "A1")

# sentinel-style should appear by name (it is in known_agents)
if echo "$prompt" | grep -q "From sentinel-style"; then
  PASS=$((PASS + 1)); echo "  PASS: sentinel-style appears as named sender"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: sentinel-style missing from prompt messages"
fi

# explore-aggregator should appear by name (it is in known_agents)
if echo "$prompt" | grep -q "From explore-aggregator"; then
  PASS=$((PASS + 1)); echo "  PASS: explore-aggregator appears as named sender"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: explore-aggregator missing from prompt messages"
fi

# unknown sender should be redacted to 'unknown'
if echo "$prompt" | grep -q "From unknown"; then
  PASS=$((PASS + 1)); echo "  PASS: unknown sender redacted to 'unknown'"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: unknown sender not redacted"
fi

# =========================================================================
echo "=== bash -n syntax check on modified scripts ==="

# HOOKS_DIR is captured at the top of the file (before any setup() cd calls)
for script in \
    "$HOOKS_DIR/lib/teams.sh" \
    "$HOOKS_DIR/on-task-completed.sh"; do
  if bash -n "$script" 2>/dev/null; then
    PASS=$((PASS + 1)); echo "  PASS: bash -n $(basename "$script")"
  else
    FAIL=$((FAIL + 1)); echo "  FAIL: syntax error in $(basename "$script")"
  fi
done

# =========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
