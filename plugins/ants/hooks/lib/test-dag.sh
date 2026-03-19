#!/usr/bin/env bash
# test-dag.sh -- Unit tests for dag.sh (v6 schema)
# Usage: bash plugins/ants/hooks/lib/test-dag.sh
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
  "version": 6,
  "status": "in_progress",
  "currentPhase": "A1",
  "loop": 1,
  "teamCreated": true,
  "teammateCount": 3,
  "taskGraphVersion": 1,
  "needsA3Tasks": false,
  "needsA5Tasks": false,
  "needsLoopReset": false,
  "needsPswarmReset": false,
  "phases": {
    "A0": {"status": "complete"},
    "A1": {"status": "in_progress"},
    "A2": {"status": "complete"},
    "A3": {"status": "in_progress"},
    "A4": {"status": "complete"},
    "A5": {"status": "pending"}
  }
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
}

# Setup with signal flags set to true (simulates mid-workflow state)
setup_with_signals() {
  setup
  # Set signal flags to true to verify they get cleared
  jq '.needsA3Tasks = true | .needsA5Tasks = true | .needsLoopReset = true | .needsPswarmReset = true' \
    "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
}

source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/dag.sh"
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

assert_exit() {
  local label="$1" expected_rc="$2"
  shift 2
  local rc=0
  ( "$@" ) 2>/dev/null || rc=$?
  if [[ "$rc" -eq "$expected_rc" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label (exit=$rc)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $label (expected exit=$expected_rc, actual=$rc)"
  fi
}

# =========================================================================
echo "=== reset_phases_for_loop ==="

setup

# Before reset: A0=complete, A1=in_progress, A2=complete, A3=in_progress, A4=complete, A5=pending
result=$(jq -r '.phases.A0.status' "$STATE_FILE")
assert_eq "A0 before reset is complete" "complete" "$result"

result=$(jq -r '.phases.A1.status' "$STATE_FILE")
assert_eq "A1 before reset is in_progress" "in_progress" "$result"

# Reset A1-A4 to pending
reset_phases_for_loop

# A0 should be preserved (exploration persists across loops)
result=$(jq -r '.phases.A0.status' "$STATE_FILE")
assert_eq "A0 preserved after reset" "complete" "$result"

# A1-A4 should all be pending
result=$(jq -r '.phases.A1.status' "$STATE_FILE")
assert_eq "A1 reset to pending" "pending" "$result"

result=$(jq -r '.phases.A2.status' "$STATE_FILE")
assert_eq "A2 reset to pending" "pending" "$result"

result=$(jq -r '.phases.A3.status' "$STATE_FILE")
assert_eq "A3 reset to pending" "pending" "$result"

result=$(jq -r '.phases.A4.status' "$STATE_FILE")
assert_eq "A4 reset to pending" "pending" "$result"

# A5 should be preserved (only runs after clean verdict)
result=$(jq -r '.phases.A5.status' "$STATE_FILE")
assert_eq "A5 preserved after reset" "pending" "$result"

# taskGraphVersion should be incremented (1 -> 2)
result=$(jq -r '.taskGraphVersion' "$STATE_FILE")
assert_eq "taskGraphVersion incremented after loop reset" "2" "$result"

# teamCreated should be preserved (loop reset does not reset team)
result=$(jq -r '.teamCreated' "$STATE_FILE")
assert_eq "teamCreated preserved after loop reset" "true" "$result"

# =========================================================================
echo "=== reset_phases_for_loop clears signal flags ==="

setup_with_signals

reset_phases_for_loop

result=$(jq -r '.needsA3Tasks' "$STATE_FILE")
assert_eq "needsA3Tasks cleared after loop reset" "false" "$result"

result=$(jq -r '.needsA5Tasks' "$STATE_FILE")
assert_eq "needsA5Tasks cleared after loop reset" "false" "$result"

result=$(jq -r '.needsLoopReset' "$STATE_FILE")
assert_eq "needsLoopReset cleared after loop reset" "false" "$result"

# needsPswarmReset is NOT cleared by loop reset (only pswarm reset clears it)
# but the current implementation does not touch it -- verify it stays true
result=$(jq -r '.needsPswarmReset' "$STATE_FILE")
assert_eq "needsPswarmReset not touched by loop reset" "true" "$result"

# =========================================================================
echo "=== reset_phases_for_loop idempotency ==="

setup

# Reset twice should be safe
reset_phases_for_loop
reset_phases_for_loop

result=$(jq -r '.phases.A1.status' "$STATE_FILE")
assert_eq "A1 still pending after double reset" "pending" "$result"

result=$(jq -r '.phases.A0.status' "$STATE_FILE")
assert_eq "A0 still complete after double reset" "complete" "$result"

# taskGraphVersion should be 3 (1 -> 2 -> 3)
result=$(jq -r '.taskGraphVersion' "$STATE_FILE")
assert_eq "taskGraphVersion incremented twice" "3" "$result"

# =========================================================================
echo "=== reset_phases_for_pswarm ==="

setup_with_signals

reset_phases_for_pswarm

# All phases A0-A5 should be pending
result=$(jq -r '.phases.A0.status' "$STATE_FILE")
assert_eq "A0 reset to pending (pswarm)" "pending" "$result"

result=$(jq -r '.phases.A1.status' "$STATE_FILE")
assert_eq "A1 reset to pending (pswarm)" "pending" "$result"

result=$(jq -r '.phases.A2.status' "$STATE_FILE")
assert_eq "A2 reset to pending (pswarm)" "pending" "$result"

result=$(jq -r '.phases.A3.status' "$STATE_FILE")
assert_eq "A3 reset to pending (pswarm)" "pending" "$result"

result=$(jq -r '.phases.A4.status' "$STATE_FILE")
assert_eq "A4 reset to pending (pswarm)" "pending" "$result"

result=$(jq -r '.phases.A5.status' "$STATE_FILE")
assert_eq "A5 reset to pending (pswarm)" "pending" "$result"

# taskGraphVersion should be incremented (1 -> 2)
result=$(jq -r '.taskGraphVersion' "$STATE_FILE")
assert_eq "taskGraphVersion incremented after pswarm reset" "2" "$result"

# teamCreated should be reset to false
result=$(jq -r '.teamCreated' "$STATE_FILE")
assert_eq "teamCreated reset to false (pswarm)" "false" "$result"

# teammateCount should be reset to 0
result=$(jq -r '.teammateCount' "$STATE_FILE")
assert_eq "teammateCount reset to 0 (pswarm)" "0" "$result"

# All signal flags should be cleared
result=$(jq -r '.needsA3Tasks' "$STATE_FILE")
assert_eq "needsA3Tasks cleared (pswarm)" "false" "$result"

result=$(jq -r '.needsA5Tasks' "$STATE_FILE")
assert_eq "needsA5Tasks cleared (pswarm)" "false" "$result"

result=$(jq -r '.needsLoopReset' "$STATE_FILE")
assert_eq "needsLoopReset cleared (pswarm)" "false" "$result"

result=$(jq -r '.needsPswarmReset' "$STATE_FILE")
assert_eq "needsPswarmReset cleared (pswarm)" "false" "$result"

# =========================================================================
echo "=== reset_phases_for_pswarm idempotency ==="

setup

reset_phases_for_pswarm
reset_phases_for_pswarm

result=$(jq -r '.phases.A0.status' "$STATE_FILE")
assert_eq "A0 still pending after double pswarm reset" "pending" "$result"

result=$(jq -r '.phases.A5.status' "$STATE_FILE")
assert_eq "A5 still pending after double pswarm reset" "pending" "$result"

# taskGraphVersion should be 3 (1 -> 2 -> 3)
result=$(jq -r '.taskGraphVersion' "$STATE_FILE")
assert_eq "taskGraphVersion incremented twice (pswarm)" "3" "$result"

result=$(jq -r '.teamCreated' "$STATE_FILE")
assert_eq "teamCreated still false after double pswarm reset" "false" "$result"

result=$(jq -r '.teammateCount' "$STATE_FILE")
assert_eq "teammateCount still 0 after double pswarm reset" "0" "$result"

# =========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
