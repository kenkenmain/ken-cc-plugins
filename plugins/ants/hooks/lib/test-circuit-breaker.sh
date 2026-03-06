#!/usr/bin/env bash
# test-circuit-breaker.sh -- Unit tests for circuit-breaker.sh
# Usage: bash plugins/ants/hooks/lib/test-circuit-breaker.sh
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

# Setup: create minimal state.json and source libs
setup() {
  cd "$TEST_DIR"
  mkdir -p .agents/tmp
  cat > .agents/tmp/state.json <<'JSON'
{
  "plugin": "ants",
  "status": "in_progress",
  "currentPhase": "A2",
  "loop": 1
}
JSON
  # Override STATE_FILE for test isolation
  export STATE_FILE=".agents/tmp/state.json"
}

# Source the libraries (state.sh sets STATE_FILE, we override after).
# Note: state.sh sets -u but _update_state_inner's RETURN trap leaks to
# the caller scope where $tmp_file is unbound. Disable -u for test compat.
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
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
  "$@" || rc=$?
  if [[ "$rc" -eq "$expected_rc" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $label (exit=$rc)"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $label (expected exit=$expected_rc, got exit=$rc)"
  fi
}

# ---- Test 1: cb_init populates missing fields ----
echo "Test 1: cb_init populates missing fields"
setup
cb_init
actual=$(jq -r '.circuitBreaker.maxConsecutiveFailures' .agents/tmp/state.json)
assert_eq "maxConsecutiveFailures=5" "5" "$actual"
actual=$(jq -r '.circuitBreaker.maxFixAttempts' .agents/tmp/state.json)
assert_eq "maxFixAttempts=5" "5" "$actual"
actual=$(jq -r '.circuitBreaker.maxStageRestarts' .agents/tmp/state.json)
assert_eq "maxStageRestarts=2" "2" "$actual"
actual=$(jq -r '.circuitBreaker.consecutiveFailures' .agents/tmp/state.json)
assert_eq "consecutiveFailures=0" "0" "$actual"
actual=$(jq -r '.circuitBreaker.stageRestarts' .agents/tmp/state.json)
assert_eq "stageRestarts=0" "0" "$actual"
actual=$(jq -c '.circuitBreaker.fixAttempts' .agents/tmp/state.json)
assert_eq "fixAttempts={}" "{}" "$actual"

# ---- Test 2: cb_init is idempotent ----
echo "Test 2: cb_init is idempotent (does not overwrite existing)"
setup
# Pre-set a non-default value
jq '.circuitBreaker = {"consecutiveFailures": 3, "maxConsecutiveFailures": 10, "maxFixAttempts": 5, "maxStageRestarts": 2, "fixAttempts": {"A2": 1}, "stageRestarts": 1}' \
  .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
cb_init
actual=$(jq -r '.circuitBreaker.consecutiveFailures' .agents/tmp/state.json)
assert_eq "consecutiveFailures preserved=3" "3" "$actual"
actual=$(jq -r '.circuitBreaker.maxConsecutiveFailures' .agents/tmp/state.json)
assert_eq "maxConsecutiveFailures preserved=10" "10" "$actual"
actual=$(jq -r '.circuitBreaker.fixAttempts.A2' .agents/tmp/state.json)
assert_eq "fixAttempts.A2 preserved=1" "1" "$actual"

# ---- Test 3: cb_record_failure increments ----
echo "Test 3: cb_record_failure increments consecutiveFailures"
setup
cb_init
cb_record_failure || true
actual=$(jq -r '.circuitBreaker.consecutiveFailures' .agents/tmp/state.json)
assert_eq "after 1 failure = 1" "1" "$actual"
cb_record_failure || true
actual=$(jq -r '.circuitBreaker.consecutiveFailures' .agents/tmp/state.json)
assert_eq "after 2 failures = 2" "2" "$actual"

# ---- Test 4: cb_record_success resets ----
echo "Test 4: cb_record_success resets consecutiveFailures"
setup
cb_init
cb_record_failure || true
cb_record_failure || true
cb_record_success
actual=$(jq -r '.circuitBreaker.consecutiveFailures' .agents/tmp/state.json)
assert_eq "after success = 0" "0" "$actual"

# ---- Test 5: cb_is_tripped triggers at threshold ----
echo "Test 5: cb_is_tripped triggers at threshold"
setup
cb_init
assert_exit "not tripped at 0" 1 cb_is_tripped
# Set to max-1
jq '.circuitBreaker.consecutiveFailures = 4' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
assert_exit "not tripped at 4" 1 cb_is_tripped
jq '.circuitBreaker.consecutiveFailures = 5' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
assert_exit "tripped at 5" 0 cb_is_tripped

# ---- Test 6: cb_record_failure returns 1 when tripped ----
echo "Test 6: cb_record_failure returns 1 (tripped) after reaching max"
setup
cb_init
jq '.circuitBreaker.consecutiveFailures = 4' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
# This failure should push to 5 and trip
assert_exit "trips on 5th failure" 0 cb_record_failure

# ---- Test 7: fix attempts per phase ----
echo "Test 7: cb_get/increment_fix_attempts per phase"
setup
cb_init
actual=$(cb_get_fix_attempts "A2")
assert_eq "A2 starts at 0" "0" "$actual"
cb_increment_fix_attempts "A2"
actual=$(cb_get_fix_attempts "A2")
assert_eq "A2 after 1 increment = 1" "1" "$actual"
# A4 is independent
actual=$(cb_get_fix_attempts "A4")
assert_eq "A4 still 0" "0" "$actual"

# ---- Test 8: fix attempts budget exhaustion ----
echo "Test 8: cb_increment_fix_attempts returns 1 when budget exceeded"
setup
cb_init
jq '.circuitBreaker.fixAttempts.A2 = 5' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
# Next increment (to 6) should exceed max of 5
assert_exit "budget exceeded at 6" 1 cb_increment_fix_attempts "A2"

# ---- Test 9: stage restart tracking ----
echo "Test 9: cb_get/increment_stage_restarts"
setup
cb_init
actual=$(cb_get_stage_restarts)
assert_eq "starts at 0" "0" "$actual"
cb_increment_stage_restarts
actual=$(cb_get_stage_restarts)
assert_eq "after 1 restart = 1" "1" "$actual"
cb_increment_stage_restarts
actual=$(cb_get_stage_restarts)
assert_eq "after 2 restarts = 2" "2" "$actual"

# ---- Test 10: stage restart budget exceeded ----
echo "Test 10: cb_increment_stage_restarts returns 1 when max exceeded"
setup
cb_init
jq '.circuitBreaker.stageRestarts = 2' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
assert_exit "max restarts exceeded at 3" 1 cb_increment_stage_restarts

# ---- Test 11: cb_reset_for_loop clears fixAttempts ----
echo "Test 11: cb_reset_for_loop clears fixAttempts but preserves other counters"
setup
cb_init
cb_increment_fix_attempts "A2"
cb_increment_fix_attempts "A2"
cb_increment_fix_attempts "A4"
cb_record_failure || true
cb_record_failure || true
cb_increment_stage_restarts
cb_reset_for_loop
actual=$(cb_get_fix_attempts "A2")
assert_eq "A2 fix attempts reset to 0" "0" "$actual"
actual=$(cb_get_fix_attempts "A4")
assert_eq "A4 fix attempts reset to 0" "0" "$actual"
actual=$(jq -r '.circuitBreaker.consecutiveFailures' .agents/tmp/state.json)
assert_eq "consecutiveFailures preserved=2" "2" "$actual"
actual=$(cb_get_stage_restarts)
assert_eq "stageRestarts preserved=1" "1" "$actual"

# ---- Summary ----
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
