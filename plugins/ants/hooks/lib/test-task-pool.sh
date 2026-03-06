#!/usr/bin/env bash
# test-task-pool.sh — Manual test script for task-pool.sh
# Exercises the full task pool lifecycle with mock state.
#
# Usage: bash plugins/ants/hooks/lib/test-task-pool.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
TEST_TMPDIR=""

setup() {
  TEST_TMPDIR=$(mktemp -d)
  # Override STATE_FILE used by state.sh and task-pool.sh
  STATE_FILE="$TEST_TMPDIR/state.json"
  export STATE_FILE

  # Create mock phases directory structure
  mkdir -p "$TEST_TMPDIR/phases/loop-1"
}

teardown() {
  rm -rf "$TEST_TMPDIR" 2>/dev/null || true
  # Clean up any leftover lock dirs (use current STATE_FILE)
  rm -rf "${STATE_FILE}.pool.lockdir" 2>/dev/null || true
  rm -rf ".agents/tmp/state.json.pool.lockdir" 2>/dev/null || true
}

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL: $label (expected='$expected', actual='$actual')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_ok() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL: $label (command failed: $*)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_fail() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL: $label (command succeeded but expected failure: $*)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "  PASS: $label"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Source libraries (state.sh first, then task-pool.sh)
# ---------------------------------------------------------------------------
# We need to source state.sh but override STATE_FILE afterward
source "$SCRIPT_DIR/state.sh"
source "$SCRIPT_DIR/task-pool.sh"

# Disable the ERR trap from state.sh — tests deliberately trigger failures
trap - ERR

# Workaround: state.sh's _update_state_inner sets a RETURN trap referencing
# local vars that go out of scope. Disable nounset to avoid crashes.
set +u

# ---------------------------------------------------------------------------
# Helper: write initial state.json and A1-tasks.json
# ---------------------------------------------------------------------------
write_mock_state() {
  cat > "$STATE_FILE" <<'EOF'
{
  "plugin": "ants",
  "status": "in_progress",
  "loop": 1,
  "currentPhase": "A3",
  "version": 2,
  "taskPool": []
}
EOF
}

write_mock_tasks() {
  local tasks_file="$TEST_TMPDIR/phases/loop-1/A1-tasks.json"
  cat > "$tasks_file" <<'EOF'
[
  {"id": "T1", "description": "Create base module", "dependencies": [], "files_owned": ["src/base.ts"]},
  {"id": "T2", "description": "Create utils", "dependencies": [], "files_owned": ["src/utils.ts"]},
  {"id": "T3", "description": "Extend base", "dependencies": ["T1"], "files_owned": ["src/extended.ts"]},
  {"id": "T4", "description": "Integration layer", "dependencies": ["T1", "T2"], "files_owned": ["src/integration.ts", "src/index.ts"]}
]
EOF
}

# Override the phases directory to point to our mock
# We need to override pool_init to use our temp dir
override_pool_init() {
  # Temporarily patch the tasks file path by symlinking
  local real_agents_dir=".agents/tmp/phases/loop-1"
  mkdir -p "$real_agents_dir"
  cp "$TEST_TMPDIR/phases/loop-1/A1-tasks.json" "$real_agents_dir/A1-tasks.json" 2>/dev/null || true
}

cleanup_override() {
  rm -f ".agents/tmp/phases/loop-1/A1-tasks.json" 2>/dev/null || true
  rmdir ".agents/tmp/phases/loop-1" 2>/dev/null || true
  rmdir ".agents/tmp/phases" 2>/dev/null || true
  rmdir ".agents/tmp" 2>/dev/null || true
  rmdir ".agents" 2>/dev/null || true
}

# ===========================================================================
# TEST 1: pool_init — Initialize from architect's plan
# ===========================================================================
echo "TEST 1: pool_init"
setup
write_mock_state
write_mock_tasks
override_pool_init

assert_ok "pool_init succeeds" pool_init

# Verify pool was written to state
POOL_LEN=$(jq '.taskPool | length' "$STATE_FILE")
assert_eq "pool has 4 tasks" "4" "$POOL_LEN"

# T1 and T2 should be ready (no deps), T3 and T4 should be pending
T1_STATUS=$(jq -r '.taskPool[] | select(.id == "T1") | .status' "$STATE_FILE")
T2_STATUS=$(jq -r '.taskPool[] | select(.id == "T2") | .status' "$STATE_FILE")
T3_STATUS=$(jq -r '.taskPool[] | select(.id == "T3") | .status' "$STATE_FILE")
T4_STATUS=$(jq -r '.taskPool[] | select(.id == "T4") | .status' "$STATE_FILE")
assert_eq "T1 is ready" "ready" "$T1_STATUS"
assert_eq "T2 is ready" "ready" "$T2_STATUS"
assert_eq "T3 is pending" "pending" "$T3_STATUS"
assert_eq "T4 is pending" "pending" "$T4_STATUS"

cleanup_override
teardown

# ===========================================================================
# TEST 2: pool_claim_task — Atomic claim
# ===========================================================================
echo "TEST 2: pool_claim_task"
setup
write_mock_state
write_mock_tasks
override_pool_init
pool_init 2>/dev/null

CLAIMED_ID=$(pool_claim_task "worker-A")
assert_eq "claimed first ready task" "T1" "$CLAIMED_ID"

# Verify status changed
T1_STATUS=$(jq -r '.taskPool[] | select(.id == "T1") | .status' "$STATE_FILE")
T1_CLAIMER=$(jq -r '.taskPool[] | select(.id == "T1") | .claimed_by' "$STATE_FILE")
assert_eq "T1 is claimed" "claimed" "$T1_STATUS"
assert_eq "T1 claimed by worker-A" "worker-A" "$T1_CLAIMER"

# Claim second ready task
CLAIMED_ID2=$(pool_claim_task "worker-B")
assert_eq "claimed second ready task" "T2" "$CLAIMED_ID2"

# No more ready tasks (T3, T4 are pending)
assert_fail "no more ready tasks" pool_claim_task "worker-C"

cleanup_override
teardown

# ===========================================================================
# TEST 3: pool_complete_task + recompute_ready
# ===========================================================================
echo "TEST 3: pool_complete_task and recompute"
setup
write_mock_state
write_mock_tasks
override_pool_init
pool_init 2>/dev/null

# Claim and complete T1
pool_claim_task "w1" >/dev/null
assert_ok "complete T1" pool_complete_task "T1"

# T3 depends on T1 only -> should be ready now
T3_STATUS=$(jq -r '.taskPool[] | select(.id == "T3") | .status' "$STATE_FILE")
assert_eq "T3 is ready after T1 complete" "ready" "$T3_STATUS"

# T4 depends on T1 AND T2 -> still pending
T4_STATUS=$(jq -r '.taskPool[] | select(.id == "T4") | .status' "$STATE_FILE")
assert_eq "T4 still pending (needs T2)" "pending" "$T4_STATUS"

# Now complete T2
pool_claim_task "w2" >/dev/null
assert_ok "complete T2" pool_complete_task "T2"

# T4 should now be ready
T4_STATUS=$(jq -r '.taskPool[] | select(.id == "T4") | .status' "$STATE_FILE")
assert_eq "T4 is ready after T1+T2 complete" "ready" "$T4_STATUS"

cleanup_override
teardown

# ===========================================================================
# TEST 4: pool_fail_task — Failure blocks dependents
# ===========================================================================
echo "TEST 4: pool_fail_task"
setup
write_mock_state
write_mock_tasks
override_pool_init
pool_init 2>/dev/null

# Claim and fail T1
pool_claim_task "w1" >/dev/null
assert_ok "fail T1" pool_fail_task "T1" "build error"

T1_STATUS=$(jq -r '.taskPool[] | select(.id == "T1") | .status' "$STATE_FILE")
assert_eq "T1 is failed" "failed" "$T1_STATUS"

FAIL_REASON=$(jq -r '.taskPool[] | select(.id == "T1") | .failure_reason' "$STATE_FILE")
assert_eq "failure reason recorded" "build error" "$FAIL_REASON"

# T3 depends on T1 (failed) -> should remain pending (not promoted)
T3_STATUS=$(jq -r '.taskPool[] | select(.id == "T3") | .status' "$STATE_FILE")
assert_eq "T3 stays pending (T1 failed)" "pending" "$T3_STATUS"

cleanup_override
teardown

# ===========================================================================
# TEST 5: pool_get_available
# ===========================================================================
echo "TEST 5: pool_get_available"
setup
write_mock_state
write_mock_tasks
override_pool_init
pool_init 2>/dev/null

AVAIL=$(pool_get_available | jq 'length')
assert_eq "2 tasks available initially" "2" "$AVAIL"

pool_claim_task "w1" >/dev/null
AVAIL=$(pool_get_available | jq 'length')
assert_eq "1 task available after claim" "1" "$AVAIL"

cleanup_override
teardown

# ===========================================================================
# TEST 6: pool_is_complete
# ===========================================================================
echo "TEST 6: pool_is_complete"
setup
write_mock_state
write_mock_tasks
override_pool_init
pool_init 2>/dev/null

assert_fail "pool not complete initially" pool_is_complete

# Complete all tasks
pool_claim_task "w1" >/dev/null  # T1
pool_claim_task "w2" >/dev/null  # T2
pool_complete_task "T1" 2>/dev/null
pool_complete_task "T2" 2>/dev/null
pool_claim_task "w3" >/dev/null  # T3
pool_claim_task "w4" >/dev/null  # T4
pool_complete_task "T3" 2>/dev/null
pool_complete_task "T4" 2>/dev/null

assert_ok "pool is complete" pool_is_complete

cleanup_override
teardown

# ===========================================================================
# TEST 7: pool_get_file_owner
# ===========================================================================
echo "TEST 7: pool_get_file_owner"
setup
write_mock_state
write_mock_tasks
override_pool_init
pool_init 2>/dev/null

# Claim T1 so it has an owner
pool_claim_task "worker-X" >/dev/null

OWNER_JSON=$(pool_get_file_owner "src/base.ts")
OWNER_TASK=$(echo "$OWNER_JSON" | jq -r '.task_id')
OWNER_CLAIMER=$(echo "$OWNER_JSON" | jq -r '.claimed_by')
assert_eq "src/base.ts owned by T1" "T1" "$OWNER_TASK"
assert_eq "src/base.ts claimer is worker-X" "worker-X" "$OWNER_CLAIMER"

# T4 owns src/integration.ts and src/index.ts (unclaimed)
OWNER_JSON2=$(pool_get_file_owner "src/integration.ts")
OWNER_TASK2=$(echo "$OWNER_JSON2" | jq -r '.task_id')
assert_eq "src/integration.ts owned by T4" "T4" "$OWNER_TASK2"

# Unknown file
assert_fail "unknown file has no owner" pool_get_file_owner "src/unknown.ts"

cleanup_override
teardown

# ===========================================================================
# TEST 8: pool_init rejects duplicate IDs
# ===========================================================================
echo "TEST 8: pool_init rejects bad input"
setup
write_mock_state

# Write tasks with duplicate IDs
mkdir -p ".agents/tmp/phases/loop-1"
cat > ".agents/tmp/phases/loop-1/A1-tasks.json" <<'EOF'
[
  {"id": "T1", "description": "A", "dependencies": []},
  {"id": "T1", "description": "B", "dependencies": []}
]
EOF

assert_fail "rejects duplicate IDs" pool_init

# Write tasks with bad dependency reference
cat > ".agents/tmp/phases/loop-1/A1-tasks.json" <<'EOF'
[
  {"id": "T1", "description": "A", "dependencies": ["T99"]}
]
EOF

assert_fail "rejects bad dependency refs" pool_init

cleanup_override
teardown

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "==============================="
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "==============================="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
