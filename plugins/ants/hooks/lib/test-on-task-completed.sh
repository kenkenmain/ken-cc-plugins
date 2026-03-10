#!/usr/bin/env bash
# test-on-task-completed.sh -- Integration tests for on-task-completed.sh A2 handler
# Focuses on changes introduced in the current batch:
#   T4: A2 handle_a2() reads .status (not .verdict) as the canonical verdict field
#
# Usage: bash plugins/ants/hooks/lib/test-on-task-completed.sh
set -eo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$HOOKS_DIR/on-task-completed.sh"
TEST_DIR="$(mktemp -d)"
ORIG_DIR="$(pwd)"
PASS=0
FAIL=0

cleanup() {
  cd "$ORIG_DIR"
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# setup — creates a minimal valid state.json for A2 tests
# ---------------------------------------------------------------------------
setup() {
  cd "$TEST_DIR"
  mkdir -p .agents/tmp/phases/loop-1
  # Use a stable ownerPpid so check_ants_workflow passes
  local ppid="$$"
  cat > .agents/tmp/state.json <<JSON
{
  "plugin": "ants",
  "version": 5,
  "ownerPpid": "$ppid",
  "status": "in_progress",
  "currentPhase": "A2",
  "loop": 1,
  "maxLoops": 5,
  "task": "Add auth module",
  "teamName": "ants-add-auth",
  "planApproved": true,
  "shutdown": false,
  "circuitBreaker": {
    "consecutiveFailures": 0,
    "maxConsecutiveFailures": 5,
    "maxFixAttempts": 5,
    "maxStageRestarts": 2,
    "fixAttempts": {},
    "stageRestarts": 0
  },
  "phases": {
    "A0": {"status": "complete"},
    "A1": {"status": "complete"},
    "A2": {"status": "in_progress"},
    "A3": {"status": "pending"},
    "A4": {"status": "pending"},
    "A5": {"status": "pending"}
  }
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
}

# run_hook — invoke on-task-completed.sh with a JSON task subject via stdin.
# Prints combined stdout+stderr.  Returns the hook exit code.
run_hook() {
  local subject="$1"
  local rc=0
  printf '{"task_subject":"%s","output":{}}' "$subject" \
    | bash "$HOOK" 2>&1 || rc=$?
  return "$rc"
}

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
echo "=== A2 handle_a2: missing A2-review.json rejected (T4) ==="

setup
# Do not write A2-review.json — hook must reject with exit 2
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "missing A2-review.json exits 2" "2" "$rc"

# =========================================================================
echo "=== A2 handle_a2: .status=approved accepted (T4) ==="

setup
cat > .agents/tmp/phases/loop-1/A2-review.json <<'JSON'
{
  "status": "approved",
  "issues": [],
  "summary": "Plan looks good"
}
JSON
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "A2-review.json with .status=approved accepted (exit 0)" "0" "$rc"

# =========================================================================
echo "=== A2 handle_a2: .status=needs_revision accepted by checkpoint gate (T4) ==="

setup
cat > .agents/tmp/phases/loop-1/A2-review.json <<'JSON'
{
  "status": "needs_revision",
  "issues": [{"id": "I1", "severity": "warning", "description": "Missing error handling"}],
  "summary": "Needs fixes"
}
JSON
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "A2-review.json with .status=needs_revision accepted (exit 0)" "0" "$rc"

# =========================================================================
echo "=== A2 handle_a2: only .verdict field (no .status) rejected (T4) ==="
# Before T4, the hook had a .verdict fallback.  After T4 that fallback is gone.
# A review JSON that only provides .verdict (old format) must now be rejected.

setup
cat > .agents/tmp/phases/loop-1/A2-review.json <<'JSON'
{
  "verdict": "approved",
  "issues": [],
  "summary": "Old-format review using .verdict instead of .status"
}
JSON
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "A2-review.json with only .verdict (no .status) rejected (exit 2)" "2" "$rc"

# =========================================================================
echo "=== A2 handle_a2: invalid JSON rejected (T4) ==="

setup
printf 'this is not json\n' > .agents/tmp/phases/loop-1/A2-review.json
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "A2-review.json invalid JSON rejected (exit 2)" "2" "$rc"

# =========================================================================
echo "=== A2 handle_a2: empty .status field rejected (T4) ==="

setup
cat > .agents/tmp/phases/loop-1/A2-review.json <<'JSON'
{
  "status": "",
  "issues": [],
  "summary": "Empty status"
}
JSON
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "A2-review.json with empty .status rejected (exit 2)" "2" "$rc"

# =========================================================================
echo "=== bash -n syntax check on modified scripts (T1, T4) ==="

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
