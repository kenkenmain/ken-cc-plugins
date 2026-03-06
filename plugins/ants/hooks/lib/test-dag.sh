#!/usr/bin/env bash
# test-dag.sh -- Unit tests for dag.sh
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
  "version": 2,
  "status": "in_progress",
  "currentPhase": "A1",
  "loop": 1,
  "phases": {
    "A0": {"status": "complete", "startedAt": "2026-01-01T00:00:00Z", "completedAt": "2026-01-01T00:01:00Z"},
    "A1": {"status": "pending"},
    "A2": {"status": "pending"},
    "A3": {"status": "pending"},
    "A4": {"status": "pending"},
    "A5": {"status": "pending"}
  }
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
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
echo "=== get_phase_status ==="

setup
result=$(get_phase_status "A0")
assert_eq "A0 is complete" "complete" "$result"

result=$(get_phase_status "A1")
assert_eq "A1 is pending" "pending" "$result"

# Invalid phase
assert_exit "invalid phase rejects" 2 get_phase_status "X9"

# =========================================================================
echo "=== is_phase_complete ==="

setup
if is_phase_complete "A0"; then
  PASS=$((PASS + 1)); echo "  PASS: A0 is complete returns true"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: A0 is complete should return true"
fi

if is_phase_complete "A1"; then
  FAIL=$((FAIL + 1)); echo "  FAIL: A1 pending should return false"
else
  PASS=$((PASS + 1)); echo "  PASS: A1 pending returns false"
fi

# =========================================================================
echo "=== mark_phase_in_progress ==="

setup
mark_phase_in_progress "A1"
result=$(get_phase_status "A1")
assert_eq "A1 marked in_progress" "in_progress" "$result"

# Verify startedAt was set
started=$(jq -r '.phases.A1.startedAt // empty' "$STATE_FILE")
if [[ -n "$started" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: startedAt was set"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: startedAt was not set"
fi

# Invalid phase
assert_exit "invalid phase rejects" 2 mark_phase_in_progress "Z1"

# =========================================================================
echo "=== mark_phase_complete ==="

setup
mark_phase_complete "A1"
result=$(get_phase_status "A1")
assert_eq "A1 marked complete" "complete" "$result"

# Verify completedAt was set
completed=$(jq -r '.phases.A1.completedAt // empty' "$STATE_FILE")
if [[ -n "$completed" ]]; then
  PASS=$((PASS + 1)); echo "  PASS: completedAt was set"
else
  FAIL=$((FAIL + 1)); echo "  FAIL: completedAt was not set"
fi

# =========================================================================
echo "=== reset_phases_for_loop ==="

setup
# First mark A1-A4 as various states
mark_phase_complete "A1"
mark_phase_in_progress "A2"
mark_phase_complete "A3"
mark_phase_in_progress "A4"

# Reset
reset_phases_for_loop

result=$(get_phase_status "A0")
assert_eq "A0 preserved after reset" "complete" "$result"

result=$(get_phase_status "A1")
assert_eq "A1 reset to pending" "pending" "$result"

result=$(get_phase_status "A2")
assert_eq "A2 reset to pending" "pending" "$result"

result=$(get_phase_status "A3")
assert_eq "A3 reset to pending" "pending" "$result"

result=$(get_phase_status "A4")
assert_eq "A4 reset to pending" "pending" "$result"

result=$(get_phase_status "A5")
assert_eq "A5 preserved after reset" "pending" "$result"

# =========================================================================
echo "=== v1 state fallback ==="

cd "$TEST_DIR"
# Create a v1 state without phases object
cat > .agents/tmp/state.json <<'JSON'
{
  "plugin": "ants",
  "version": 1,
  "status": "in_progress",
  "currentPhase": "A0",
  "loop": 1
}
JSON

result=$(get_phase_status "A0")
assert_eq "missing phases falls back to pending" "pending" "$result"

# mark_phase_in_progress should create the phases object
mark_phase_in_progress "A0"
result=$(get_phase_status "A0")
assert_eq "phases object created on write" "in_progress" "$result"

# =========================================================================
echo "=== constants ==="

assert_eq "DAG_STATUS_PENDING" "pending" "$DAG_STATUS_PENDING"
assert_eq "DAG_STATUS_IN_PROGRESS" "in_progress" "$DAG_STATUS_IN_PROGRESS"
assert_eq "DAG_STATUS_COMPLETE" "complete" "$DAG_STATUS_COMPLETE"

# =========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
