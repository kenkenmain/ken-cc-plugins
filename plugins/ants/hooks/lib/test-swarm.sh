#!/usr/bin/env bash
# test-swarm.sh -- Unit tests for swarm.sh (get_phase_output, parse_queen_verdict)
# Usage: bash plugins/ants/hooks/lib/test-swarm.sh
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
  "currentPhase": "A4",
  "loop": 1,
  "task": "test task",
  "maxLoops": 5,
  "phases": {}
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
}

source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/dag.sh"
source "$SCRIPT_DIR/lib/swarm.sh"
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
echo "=== get_phase_output ==="

result=$(get_phase_output "A0")
assert_eq "A0 output" "A0-explore.md" "$result"

result=$(get_phase_output "A1")
assert_eq "A1 output" "A1-plan.md" "$result"

result=$(get_phase_output "A2")
assert_eq "A2 output" "A2-review.json" "$result"

result=$(get_phase_output "A3")
assert_eq "A3 output" "A3-build.json" "$result"

result=$(get_phase_output "A4")
assert_eq "A4 output" "A4-queen-verdict.json" "$result"

result=$(get_phase_output "A5")
assert_eq "A5 output" "A5-ship.json" "$result"

assert_exit "unknown phase returns error" 1 get_phase_output "X9"

# =========================================================================
echo "=== parse_queen_verdict ==="

setup

# Clean verdict with 0 issues
cat > "$TEST_DIR/verdict-clean.json" <<'JSON'
{"verdict": "clean", "total_issues": 0, "issues": []}
JSON
VERDICT=""
parse_queen_verdict "$TEST_DIR/verdict-clean.json"
assert_eq "clean verdict" "clean" "$VERDICT"

# Issues found with count
cat > "$TEST_DIR/verdict-issues.json" <<'JSON'
{"verdict": "issues_found", "total_issues": 3, "issues": [{"id": 1}, {"id": 2}, {"id": 3}]}
JSON
VERDICT=""
parse_queen_verdict "$TEST_DIR/verdict-issues.json"
assert_eq "issues_found verdict" "issues_found" "$VERDICT"

# Clean verdict contradicted by total_issues > 0 -> forced to issues_found
cat > "$TEST_DIR/verdict-contradiction.json" <<'JSON'
{"verdict": "clean", "total_issues": 5}
JSON
VERDICT=""
parse_queen_verdict "$TEST_DIR/verdict-contradiction.json" 2>/dev/null
assert_eq "contradicted clean forced to issues_found" "issues_found" "$VERDICT"

# unresolvedIssues array instead of total_issues
cat > "$TEST_DIR/verdict-unresolved.json" <<'JSON'
{"verdict": "clean", "unresolvedIssues": [{"id": 1}, {"id": 2}]}
JSON
VERDICT=""
parse_queen_verdict "$TEST_DIR/verdict-unresolved.json" 2>/dev/null
assert_eq "unresolvedIssues array forces issues_found" "issues_found" "$VERDICT"

# Clean with unresolvedIssues empty array
cat > "$TEST_DIR/verdict-clean-empty.json" <<'JSON'
{"verdict": "clean", "unresolvedIssues": []}
JSON
VERDICT=""
parse_queen_verdict "$TEST_DIR/verdict-clean-empty.json"
assert_eq "clean with empty unresolvedIssues stays clean" "clean" "$VERDICT"

# Non-array unresolvedIssues (type guard)
cat > "$TEST_DIR/verdict-nonarray.json" <<'JSON'
{"verdict": "clean", "unresolvedIssues": "not an array"}
JSON
VERDICT=""
parse_queen_verdict "$TEST_DIR/verdict-nonarray.json"
assert_eq "non-array unresolvedIssues treated as 0 issues" "clean" "$VERDICT"

# Unknown verdict with issues -> inferred as issues_found
cat > "$TEST_DIR/verdict-unknown.json" <<'JSON'
{"verdict": "ship", "total_issues": 2}
JSON
VERDICT=""
parse_queen_verdict "$TEST_DIR/verdict-unknown.json" 2>/dev/null
assert_eq "unknown verdict with issues inferred as issues_found" "issues_found" "$VERDICT"

# Unknown verdict with 0 issues -> error
cat > "$TEST_DIR/verdict-bad.json" <<'JSON'
{"verdict": "ship", "total_issues": 0}
JSON
assert_exit "unknown verdict with 0 issues exits 2" 2 parse_queen_verdict "$TEST_DIR/verdict-bad.json"

# Missing verdict field -> error
cat > "$TEST_DIR/verdict-missing.json" <<'JSON'
{"total_issues": 0}
JSON
assert_exit "missing verdict field exits 2" 2 parse_queen_verdict "$TEST_DIR/verdict-missing.json"

# =========================================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
