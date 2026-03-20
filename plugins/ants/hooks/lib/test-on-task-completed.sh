#!/usr/bin/env bash
# test-on-task-completed.sh -- Integration tests for on-task-completed.sh handlers
# Covers changes introduced in the current batch:
#   T4: A2 handle_a2() reads .status (not .verdict) as the canonical verdict field
#   T5: A2 handle_a2() normalises "needs-revision" -> "needs_revision" (hyphen -> underscore)
#   T6: A2 handle_a2() unknown status values fall back to "needs_revision"
#   T7: handle_a3_arbiter() idempotency guard (arbiterDone=true skips processing)
#   T8: handle_a5_nurse() idempotency guard (nurseDone=true skips processing)
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

# ---------------------------------------------------------------------------
# setup_a3 — state.json with currentPhase=A3 for arbiter/sentinel tests
# ---------------------------------------------------------------------------
setup_a3() {
  cd "$TEST_DIR"
  mkdir -p .agents/tmp/phases/loop-1
  local ppid="$$"
  cat > .agents/tmp/state.json <<JSON
{
  "plugin": "ants",
  "version": 5,
  "ownerPpid": "$ppid",
  "status": "in_progress",
  "currentPhase": "A3",
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
    "A2": {"status": "complete"},
    "A3": {"status": "in_progress"},
    "A4": {"status": "pending"},
    "A5": {"status": "pending"}
  },
  "taskPool": [
    {"id": "T1", "status": "complete", "dependencies": [], "description": "task 1",
     "files_owned": [], "acceptance_criteria": "done"}
  ]
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
}

# ---------------------------------------------------------------------------
# setup_a5 — state.json with currentPhase=A5 for nurse/drone tests
# ---------------------------------------------------------------------------
setup_a5() {
  cd "$TEST_DIR"
  mkdir -p .agents/tmp/phases/loop-1
  local ppid="$$"
  cat > .agents/tmp/state.json <<JSON
{
  "plugin": "ants",
  "version": 5,
  "ownerPpid": "$ppid",
  "status": "in_progress",
  "currentPhase": "A5",
  "pipeline": "swarm",
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
    "A2": {"status": "complete"},
    "A3": {"status": "complete"},
    "A4": {"status": "complete"},
    "A5": {"status": "in_progress"}
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
echo "=== A2 handle_a2: hyphenated status normalised to underscore (T5) ==="
# "needs-revision" must be accepted as equivalent to "needs_revision".
# The hook normalises hyphens to underscores before the allowlist check.

setup
cat > .agents/tmp/phases/loop-1/A2-review.json <<'JSON'
{
  "status": "needs-revision",
  "issues": [{"id": "I1", "severity": "warning", "description": "Minor style issue"}],
  "summary": "Hyphen-separated status"
}
JSON
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "A2-review.json with .status=needs-revision normalised and accepted (exit 0)" "0" "$rc"

# =========================================================================
echo "=== A2 handle_a2: UPPERCASE status ascii_downcase normalised (T5) ==="
# "NEEDS_REVISION" should be ascii_downcase-normalised to "needs_revision" and accepted.

setup
cat > .agents/tmp/phases/loop-1/A2-review.json <<'JSON'
{
  "status": "APPROVED",
  "issues": [],
  "summary": "Uppercase status"
}
JSON
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "A2-review.json with .status=APPROVED (uppercase) accepted via ascii_downcase (exit 0)" "0" "$rc"

# =========================================================================
echo "=== A2 handle_a2: unknown status falls back to needs_revision (T6) ==="
# An unrecognised status like "maybe" must be treated as needs_revision (no HIGH issues
# -> advances to A3, not loops back). The hook logs a WARNING but does not exit 2.

setup
cat > .agents/tmp/phases/loop-1/A2-review.json <<'JSON'
{
  "status": "maybe",
  "issues": [],
  "summary": "Unknown status with no HIGH issues"
}
JSON
rc=0; run_hook "A2 Blueprint review" >/dev/null 2>&1 || rc=$?
assert_eq "unknown A2 status falls back to needs_revision and advances to A3 (exit 0)" "0" "$rc"

# State should have advanced to A3 because there were no HIGH issues
current_phase=$(jq -r '.currentPhase' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "state advances to A3 after unknown status fallback" "A3" "$current_phase"

# =========================================================================
echo "=== A3 arbiter idempotency: arbiterDone=true skips processing (T7) ==="
# If arbiterDone is already true, handle_a3_arbiter must return 0 without
# re-reading A3-quality.json or re-writing A4-queen-verdict.json.

setup_a3
# Set arbiterDone=true in state, but do NOT write A3-quality.json
jq '.phases.A3.arbiterDone = true
  | .phases.A3.status = "in_progress"
  | .phases.A4 = {"status": "complete", "verdict": "clean"}
  | .phases.A5 = {"status": "in_progress"}
  | .currentPhase = "A5"' \
  .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
# A3-quality.json intentionally absent — if guard fails, hook would exit 2
rc=0; run_hook "A3 Review Arbiter: Consolidate findings" >/dev/null 2>&1 || rc=$?
assert_eq "arbiter with arbiterDone=true skips (exit 0, idempotency guard)" "0" "$rc"

# =========================================================================
echo "=== A3 arbiter: first call processes normally (no arbiterDone set) (T7) ==="
# Confirms the happy path: arbiterDone not set, quality.json present,
# arbiter processes and writes verdict, sets arbiterDone=true.

setup_a3
cat > .agents/tmp/phases/loop-1/A3-quality.json <<'JSON'
{
  "verdict": "clean",
  "issues": [],
  "summary": "All clean"
}
JSON
rc=0; run_hook "A3 Review Arbiter: Consolidate" >/dev/null 2>&1 || rc=$?
assert_eq "arbiter first call with quality.json succeeds (exit 0)" "0" "$rc"

# After processing, arbiterDone must be true in state
arbiter_done=$(jq -r '.phases.A3.arbiterDone // false' .agents/tmp/state.json 2>/dev/null || echo "false")
assert_eq "arbiterDone set to true after first arbiter call" "true" "$arbiter_done"

# =========================================================================
echo "=== A5 nurse idempotency: nurseDone=true skips processing (T8) ==="
# If nurseDone is already true, handle_a5_nurse must return 0 immediately
# without re-running any state transitions.

setup_a5
# Set nurseDone=true in state so the guard triggers
jq '.phases.A5.nurseDone = true' \
  .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
rc=0; run_hook "A5 Nurse: Update docs" >/dev/null 2>&1 || rc=$?
assert_eq "nurse with nurseDone=true skips (exit 0, idempotency guard)" "0" "$rc"

# State should remain in A5 (no additional transitions triggered)
phase_after=$(jq -r '.currentPhase' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "currentPhase unchanged after nurse idempotency guard" "A5" "$phase_after"

# =========================================================================
echo "=== A5 nurse: first call sets nurseDone in state (T8) ==="
# Happy path: nurseDone not set, nurse runs, sets nurseDone=true.

setup_a5
rc=0; run_hook "A5 Nurse: Update docs" >/dev/null 2>&1 || rc=$?
assert_eq "nurse first call succeeds (exit 0)" "0" "$rc"

nurse_done=$(jq -r '.phases.A5.nurseDone // false' .agents/tmp/state.json 2>/dev/null || echo "false")
assert_eq "nurseDone set to true after first nurse call" "true" "$nurse_done"

# =========================================================================
echo "=== bash -n syntax check on modified scripts (T1, T4-T8) ==="

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
