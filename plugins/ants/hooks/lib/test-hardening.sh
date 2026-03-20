#!/usr/bin/env bash
# test-hardening.sh -- Standalone validation tests for critical jq filters
# used in the ants swarm pipeline hardening logic.
#
# Tests the EXACT jq expressions from source files without sourcing the
# hook libraries (which require the full Claude Code environment).
#
# Covers:
#   1. Cycle detection (Kahn's algorithm) from task-pool.sh
#   2. Orphan recovery filter from task-pool.sh
#   3. Atomic circuit breaker fix-attempt filter from circuit-breaker.sh
#   4. Case-insensitive severity counting from on-task-completed.sh
#
# Usage: bash plugins/ants/hooks/lib/test-hardening.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------
TMPDIR_BASE="$(mktemp -d)"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

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
# 1. CYCLE DETECTION (Kahn's algorithm)
#    Source: task-pool.sh pool_init(), lines 153-170
#    The jq filter detects circular dependencies in the task graph.
# =========================================================================

echo "=== 1. Cycle Detection (Kahn's algorithm) ==="

# --- 1a. Valid acyclic graph: A->B->C (linear chain) ---
echo "--- 1a. Acyclic linear chain ---"
ACYCLIC_FILE="$TMPDIR_BASE/acyclic.json"
cat > "$ACYCLIC_FILE" <<'EOF'
[
  {"id": "A", "description": "task A", "dependencies": [], "status": "ready"},
  {"id": "B", "description": "task B", "dependencies": ["A"], "status": "pending"},
  {"id": "C", "description": "task C", "dependencies": ["B"], "status": "pending"}
]
EOF

has_cycle=$(jq '
  {remaining: ., removed: []} |
  until(
    (.remaining | length) == 0 or .cycle == true;
    .remaining as $rem | .removed as $done |
    ([$rem[] | select(
      (.dependencies | all(. as $d | $done | index($d) | . != null))
    )] | map(.id)) as $ready |
    if ($ready | length) == 0 then
      . + {cycle: true}
    else
      {
        removed: ($done + $ready),
        remaining: [$rem[] | select(.id as $id | $ready | index($id) | not)]
      }
    end
  ) | .cycle // false
' "$ACYCLIC_FILE")

assert_eq "acyclic linear chain returns false" "false" "$has_cycle"

# --- 1b. Circular dependency: A->B->C->A ---
echo "--- 1b. Circular dependency A->B->C->A ---"
CYCLIC_FILE="$TMPDIR_BASE/cyclic.json"
cat > "$CYCLIC_FILE" <<'EOF'
[
  {"id": "A", "description": "task A", "dependencies": ["C"], "status": "pending"},
  {"id": "B", "description": "task B", "dependencies": ["A"], "status": "pending"},
  {"id": "C", "description": "task C", "dependencies": ["B"], "status": "pending"}
]
EOF

has_cycle=$(jq '
  {remaining: ., removed: []} |
  until(
    (.remaining | length) == 0 or .cycle == true;
    .remaining as $rem | .removed as $done |
    ([$rem[] | select(
      (.dependencies | all(. as $d | $done | index($d) | . != null))
    )] | map(.id)) as $ready |
    if ($ready | length) == 0 then
      . + {cycle: true}
    else
      {
        removed: ($done + $ready),
        remaining: [$rem[] | select(.id as $id | $ready | index($id) | not)]
      }
    end
  ) | .cycle // false
' "$CYCLIC_FILE")

assert_eq "circular A->B->C->A returns true" "true" "$has_cycle"

# --- 1c. Self-dependency: A->A ---
echo "--- 1c. Self-dependency A->A ---"
SELF_DEP_FILE="$TMPDIR_BASE/self-dep.json"
cat > "$SELF_DEP_FILE" <<'EOF'
[
  {"id": "A", "description": "task A", "dependencies": ["A"], "status": "pending"}
]
EOF

has_cycle=$(jq '
  {remaining: ., removed: []} |
  until(
    (.remaining | length) == 0 or .cycle == true;
    .remaining as $rem | .removed as $done |
    ([$rem[] | select(
      (.dependencies | all(. as $d | $done | index($d) | . != null))
    )] | map(.id)) as $ready |
    if ($ready | length) == 0 then
      . + {cycle: true}
    else
      {
        removed: ($done + $ready),
        remaining: [$rem[] | select(.id as $id | $ready | index($id) | not)]
      }
    end
  ) | .cycle // false
' "$SELF_DEP_FILE")

assert_eq "self-dependency A->A returns true" "true" "$has_cycle"

# --- 1d. Valid acyclic diamond: A->B, A->C, B->D, C->D ---
echo "--- 1d. Acyclic diamond graph ---"
DIAMOND_FILE="$TMPDIR_BASE/diamond.json"
cat > "$DIAMOND_FILE" <<'EOF'
[
  {"id": "A", "description": "task A", "dependencies": [], "status": "ready"},
  {"id": "B", "description": "task B", "dependencies": ["A"], "status": "pending"},
  {"id": "C", "description": "task C", "dependencies": ["A"], "status": "pending"},
  {"id": "D", "description": "task D", "dependencies": ["B", "C"], "status": "pending"}
]
EOF

has_cycle=$(jq '
  {remaining: ., removed: []} |
  until(
    (.remaining | length) == 0 or .cycle == true;
    .remaining as $rem | .removed as $done |
    ([$rem[] | select(
      (.dependencies | all(. as $d | $done | index($d) | . != null))
    )] | map(.id)) as $ready |
    if ($ready | length) == 0 then
      . + {cycle: true}
    else
      {
        removed: ($done + $ready),
        remaining: [$rem[] | select(.id as $id | $ready | index($id) | not)]
      }
    end
  ) | .cycle // false
' "$DIAMOND_FILE")

assert_eq "acyclic diamond returns false" "false" "$has_cycle"

# --- 1e. Empty task list ---
echo "--- 1e. Empty task list ---"
EMPTY_FILE="$TMPDIR_BASE/empty.json"
echo '[]' > "$EMPTY_FILE"

has_cycle=$(jq '
  {remaining: ., removed: []} |
  until(
    (.remaining | length) == 0 or .cycle == true;
    .remaining as $rem | .removed as $done |
    ([$rem[] | select(
      (.dependencies | all(. as $d | $done | index($d) | . != null))
    )] | map(.id)) as $ready |
    if ($ready | length) == 0 then
      . + {cycle: true}
    else
      {
        removed: ($done + $ready),
        remaining: [$rem[] | select(.id as $id | $ready | index($id) | not)]
      }
    end
  ) | .cycle // false
' "$EMPTY_FILE")

assert_eq "empty task list returns false" "false" "$has_cycle"

# =========================================================================
# 2. ORPHAN RECOVERY
#    Source: task-pool.sh pool_recover_orphans(), lines 206-216
#    The jq filter recovers tasks stuck in "claimed" beyond a threshold.
# =========================================================================

echo ""
echo "=== 2. Orphan Recovery ==="

NOW=$(date +%s)

# --- 2a. Stale claimed task (claimed_at = now - 400s, threshold = 300s) ---
echo "--- 2a. Stale claimed task (400s old, threshold 300s) ---"
STALE_FILE="$TMPDIR_BASE/stale-orphan.json"
STALE_TS=$((NOW - 400))
cat > "$STALE_FILE" <<EOF
{
  "taskPool": [
    {
      "id": "T1",
      "status": "claimed",
      "claimed_by": "worker-1",
      "claimed_at": $STALE_TS,
      "dependencies": []
    },
    {
      "id": "T2",
      "status": "ready",
      "claimed_by": null,
      "claimed_at": null,
      "dependencies": []
    }
  ]
}
EOF

result=$(jq --argjson threshold 300 --argjson now "$NOW" '
  .taskPool |= map(
    if .status == "claimed" and
       ((.claimed_at // 0) > 0) and
       (($now - (.claimed_at // 0)) > $threshold)
    then
      .status = "ready" | .claimed_by = null | .claimed_at = null |
      .recovery_count = ((.recovery_count // 0) + 1)
    else . end
  )
' "$STALE_FILE")

t1_status=$(echo "$result" | jq -r '.taskPool[] | select(.id == "T1") | .status')
t1_claimer=$(echo "$result" | jq -r '.taskPool[] | select(.id == "T1") | .claimed_by')
t1_recovery=$(echo "$result" | jq -r '.taskPool[] | select(.id == "T1") | .recovery_count')
t2_status=$(echo "$result" | jq -r '.taskPool[] | select(.id == "T2") | .status')

assert_eq "stale T1 status changed to ready" "ready" "$t1_status"
assert_eq "stale T1 claimer cleared to null" "null" "$t1_claimer"
assert_eq "stale T1 recovery_count is 1" "1" "$t1_recovery"
assert_eq "T2 status unchanged (ready)" "ready" "$t2_status"

# --- 2b. Fresh claimed task (claimed_at = now - 100s, threshold = 300s) ---
echo "--- 2b. Fresh claimed task (100s old, threshold 300s) ---"
FRESH_FILE="$TMPDIR_BASE/fresh-orphan.json"
FRESH_TS=$((NOW - 100))
cat > "$FRESH_FILE" <<EOF
{
  "taskPool": [
    {
      "id": "T1",
      "status": "claimed",
      "claimed_by": "worker-1",
      "claimed_at": $FRESH_TS,
      "dependencies": []
    }
  ]
}
EOF

result=$(jq --argjson threshold 300 --argjson now "$NOW" '
  .taskPool |= map(
    if .status == "claimed" and
       ((.claimed_at // 0) > 0) and
       (($now - (.claimed_at // 0)) > $threshold)
    then
      .status = "ready" | .claimed_by = null | .claimed_at = null |
      .recovery_count = ((.recovery_count // 0) + 1)
    else . end
  )
' "$FRESH_FILE")

t1_status=$(echo "$result" | jq -r '.taskPool[] | select(.id == "T1") | .status')
t1_claimer=$(echo "$result" | jq -r '.taskPool[] | select(.id == "T1") | .claimed_by')

assert_eq "fresh T1 status stays claimed" "claimed" "$t1_status"
assert_eq "fresh T1 claimer stays worker-1" "worker-1" "$t1_claimer"

# --- 2c. Claimed task with null claimed_at (should not be recovered) ---
echo "--- 2c. Claimed task with null claimed_at ---"
NULL_TS_FILE="$TMPDIR_BASE/null-ts-orphan.json"
cat > "$NULL_TS_FILE" <<'EOF'
{
  "taskPool": [
    {
      "id": "T1",
      "status": "claimed",
      "claimed_by": "worker-1",
      "claimed_at": null,
      "dependencies": []
    }
  ]
}
EOF

result=$(jq --argjson threshold 300 --argjson now "$NOW" '
  .taskPool |= map(
    if .status == "claimed" and
       ((.claimed_at // 0) > 0) and
       (($now - (.claimed_at // 0)) > $threshold)
    then
      .status = "ready" | .claimed_by = null | .claimed_at = null |
      .recovery_count = ((.recovery_count // 0) + 1)
    else . end
  )
' "$NULL_TS_FILE")

t1_status=$(echo "$result" | jq -r '.taskPool[] | select(.id == "T1") | .status')
assert_eq "null claimed_at task stays claimed" "claimed" "$t1_status"

# =========================================================================
# 3. ATOMIC CIRCUIT BREAKER (fix attempt budget)
#    Source: circuit-breaker.sh cb_increment_fix_attempts(), lines 120-125
#    The jq filter atomically checks and increments fix attempts.
# =========================================================================

echo ""
echo "=== 3. Atomic Circuit Breaker (fix attempt budget) ==="

# --- 3a. fixAttempts.A2 = 4, max = 5 -> should increment to 5 ---
echo "--- 3a. Below budget (4/5) -> increment to 5 ---"
CB_BELOW_FILE="$TMPDIR_BASE/cb-below.json"
cat > "$CB_BELOW_FILE" <<'EOF'
{
  "circuitBreaker": {
    "fixAttempts": {"A2": 4},
    "maxFixAttempts": 5
  }
}
EOF

rc=0
result=$(jq --arg phase "A2" --argjson max 5 '
  if (.circuitBreaker.fixAttempts[$phase] // 0) >= $max then
    error("fix attempt budget exhausted for phase " + $phase)
  else
    .circuitBreaker.fixAttempts[$phase] = ((.circuitBreaker.fixAttempts[$phase] // 0) + 1)
  end
' "$CB_BELOW_FILE" 2>/dev/null) || rc=$?

assert_eq "below-budget increment succeeds (exit 0)" "0" "$rc"
new_count=$(echo "$result" | jq -r '.circuitBreaker.fixAttempts.A2')
assert_eq "fixAttempts.A2 incremented to 5" "5" "$new_count"

# --- 3b. fixAttempts.A2 = 5, max = 5 -> should error (budget exhausted) ---
echo "--- 3b. At budget (5/5) -> error ---"
CB_AT_FILE="$TMPDIR_BASE/cb-at.json"
cat > "$CB_AT_FILE" <<'EOF'
{
  "circuitBreaker": {
    "fixAttempts": {"A2": 5},
    "maxFixAttempts": 5
  }
}
EOF

rc=0
result=$(jq --arg phase "A2" --argjson max 5 '
  if (.circuitBreaker.fixAttempts[$phase] // 0) >= $max then
    error("fix attempt budget exhausted for phase " + $phase)
  else
    .circuitBreaker.fixAttempts[$phase] = ((.circuitBreaker.fixAttempts[$phase] // 0) + 1)
  end
' "$CB_AT_FILE" 2>/dev/null) || rc=$?

assert_eq "at-budget increment fails (exit != 0)" "1" "$(if [[ "$rc" -ne 0 ]]; then echo 1; else echo 0; fi)"

# --- 3c. fixAttempts.A2 = 0, max = 5 -> should increment to 1 ---
echo "--- 3c. Fresh phase (0/5) -> increment to 1 ---"
CB_ZERO_FILE="$TMPDIR_BASE/cb-zero.json"
cat > "$CB_ZERO_FILE" <<'EOF'
{
  "circuitBreaker": {
    "fixAttempts": {},
    "maxFixAttempts": 5
  }
}
EOF

rc=0
result=$(jq --arg phase "A2" --argjson max 5 '
  if (.circuitBreaker.fixAttempts[$phase] // 0) >= $max then
    error("fix attempt budget exhausted for phase " + $phase)
  else
    .circuitBreaker.fixAttempts[$phase] = ((.circuitBreaker.fixAttempts[$phase] // 0) + 1)
  end
' "$CB_ZERO_FILE" 2>/dev/null) || rc=$?

assert_eq "fresh phase increment succeeds (exit 0)" "0" "$rc"
new_count=$(echo "$result" | jq -r '.circuitBreaker.fixAttempts.A2')
assert_eq "fixAttempts.A2 initialized to 1" "1" "$new_count"

# --- 3d. fixAttempts.A2 = 6, max = 5 -> should error (over budget) ---
echo "--- 3d. Over budget (6/5) -> error ---"
CB_OVER_FILE="$TMPDIR_BASE/cb-over.json"
cat > "$CB_OVER_FILE" <<'EOF'
{
  "circuitBreaker": {
    "fixAttempts": {"A2": 6},
    "maxFixAttempts": 5
  }
}
EOF

rc=0
result=$(jq --arg phase "A2" --argjson max 5 '
  if (.circuitBreaker.fixAttempts[$phase] // 0) >= $max then
    error("fix attempt budget exhausted for phase " + $phase)
  else
    .circuitBreaker.fixAttempts[$phase] = ((.circuitBreaker.fixAttempts[$phase] // 0) + 1)
  end
' "$CB_OVER_FILE" 2>/dev/null) || rc=$?

assert_eq "over-budget increment fails (exit != 0)" "1" "$(if [[ "$rc" -ne 0 ]]; then echo 1; else echo 0; fi)"

# =========================================================================
# 4. CASE-INSENSITIVE SEVERITY COUNTING
#    Source: on-task-completed.sh handle_a3_arbiter(), lines 411-415
#    The jq filter counts critical/warning issues case-insensitively.
# =========================================================================

echo ""
echo "=== 4. Case-Insensitive Severity Counting ==="

# --- 4a. Mixed-case severities ---
# NOTE: The A3 arbiter filter (on-task-completed.sh lines 411-415) uses EXACT
# string matching: "critical", "HIGH", "high" for critical_count and "warning",
# "WARNING" for warning_count. It does NOT use ascii_downcase, so title-case
# "High" and uppercase "CRITICAL" are NOT matched by the critical selector.
# This test validates the actual source behavior.
echo "--- 4a. Mixed-case severities (exact match: critical, HIGH, high) ---"
SEVERITY_FILE="$TMPDIR_BASE/severity-mixed.json"
cat > "$SEVERITY_FILE" <<'EOF'
{
  "issues": [
    {"id": 1, "severity": "HIGH", "description": "uppercase HIGH - matched"},
    {"id": 2, "severity": "High", "description": "title case High - NOT matched by exact filter"},
    {"id": 3, "severity": "high", "description": "lowercase high - matched"},
    {"id": 4, "severity": "CRITICAL", "description": "uppercase CRITICAL - NOT matched by exact filter"},
    {"id": 5, "severity": "critical", "description": "lowercase critical - matched"},
    {"id": 6, "severity": "warning", "description": "lowercase warning - matched"},
    {"id": 7, "severity": "WARNING", "description": "uppercase WARNING - matched"},
    {"id": 8, "severity": "info", "description": "info severity - not counted"}
  ]
}
EOF

quality_meta=$(jq -r '{
  critical_count: ([.issues[]? | select(.severity == "critical" or .severity == "HIGH" or .severity == "high")] | length),
  warning_count: ([.issues[]? | select(.severity == "warning" or .severity == "WARNING")] | length),
  all_issues: ([.issues[]?] | length)
} | "\(.critical_count)\t\(.warning_count)\t\(.all_issues)"' "$SEVERITY_FILE")

IFS=$'\t' read -r critical_count warning_count all_issues <<< "$quality_meta"

# Exact match: "critical" (id5), "HIGH" (id1), "high" (id3) = 3
# "High" (id2) and "CRITICAL" (id4) are NOT matched by the exact-string filter
assert_eq "critical_count matches HIGH/high/critical exactly" "3" "$critical_count"
assert_eq "warning_count matches warning/WARNING exactly" "2" "$warning_count"
assert_eq "all_issues total is 8" "8" "$all_issues"

# --- 4b. No issues array ---
echo "--- 4b. No issues array ---"
NO_ISSUES_FILE="$TMPDIR_BASE/no-issues.json"
cat > "$NO_ISSUES_FILE" <<'EOF'
{
  "verdict": "clean"
}
EOF

quality_meta=$(jq -r '{
  critical_count: ([.issues[]? | select(.severity == "critical" or .severity == "HIGH" or .severity == "high")] | length),
  warning_count: ([.issues[]? | select(.severity == "warning" or .severity == "WARNING")] | length),
  all_issues: ([.issues[]?] | length)
} | "\(.critical_count)\t\(.warning_count)\t\(.all_issues)"' "$NO_ISSUES_FILE")

IFS=$'\t' read -r critical_count warning_count all_issues <<< "$quality_meta"

assert_eq "no issues array -> critical_count = 0" "0" "$critical_count"
assert_eq "no issues array -> warning_count = 0" "0" "$warning_count"
assert_eq "no issues array -> all_issues = 0" "0" "$all_issues"

# --- 4c. Empty issues array ---
echo "--- 4c. Empty issues array ---"
EMPTY_ISSUES_FILE="$TMPDIR_BASE/empty-issues.json"
cat > "$EMPTY_ISSUES_FILE" <<'EOF'
{
  "issues": []
}
EOF

quality_meta=$(jq -r '{
  critical_count: ([.issues[]? | select(.severity == "critical" or .severity == "HIGH" or .severity == "high")] | length),
  warning_count: ([.issues[]? | select(.severity == "warning" or .severity == "WARNING")] | length),
  all_issues: ([.issues[]?] | length)
} | "\(.critical_count)\t\(.warning_count)\t\(.all_issues)"' "$EMPTY_ISSUES_FILE")

IFS=$'\t' read -r critical_count warning_count all_issues <<< "$quality_meta"

assert_eq "empty issues -> critical_count = 0" "0" "$critical_count"
assert_eq "empty issues -> warning_count = 0" "0" "$warning_count"
assert_eq "empty issues -> all_issues = 0" "0" "$all_issues"

# --- 4d. Only info severities (no actionable issues) ---
echo "--- 4d. Only info severities ---"
INFO_ONLY_FILE="$TMPDIR_BASE/info-only.json"
cat > "$INFO_ONLY_FILE" <<'EOF'
{
  "issues": [
    {"id": 1, "severity": "info"},
    {"id": 2, "severity": "INFO"},
    {"id": 3, "severity": "Info"}
  ]
}
EOF

quality_meta=$(jq -r '{
  critical_count: ([.issues[]? | select(.severity == "critical" or .severity == "HIGH" or .severity == "high")] | length),
  warning_count: ([.issues[]? | select(.severity == "warning" or .severity == "WARNING")] | length),
  all_issues: ([.issues[]?] | length)
} | "\(.critical_count)\t\(.warning_count)\t\(.all_issues)"' "$INFO_ONLY_FILE")

IFS=$'\t' read -r critical_count warning_count all_issues <<< "$quality_meta"

assert_eq "info-only -> critical_count = 0" "0" "$critical_count"
assert_eq "info-only -> warning_count = 0" "0" "$warning_count"
assert_eq "info-only -> all_issues = 3" "3" "$all_issues"

# --- 4e. A2 review severity filter (ascii_downcase) ---
echo "--- 4e. A2 review HIGH/CRITICAL counting (ascii_downcase) ---"
A2_REVIEW_FILE="$TMPDIR_BASE/a2-review.json"
cat > "$A2_REVIEW_FILE" <<'EOF'
{
  "status": "needs_revision",
  "issues": [
    {"id": 1, "severity": "HIGH", "description": "uppercase HIGH"},
    {"id": 2, "severity": "High", "description": "title case High"},
    {"id": 3, "severity": "high", "description": "lowercase high"},
    {"id": 4, "severity": "CRITICAL", "description": "uppercase CRITICAL"},
    {"id": 5, "severity": "critical", "description": "lowercase critical"},
    {"id": 6, "severity": "warning", "description": "warning not counted"},
    {"id": 7, "severity": "info", "description": "info not counted"}
  ]
}
EOF

# This is the exact jq expression from on-task-completed.sh handle_a2() line 153
high_count=$(jq '[.issues[]? | select((.severity | ascii_downcase) == "high" or (.severity | ascii_downcase) == "critical")] | length' "$A2_REVIEW_FILE")

assert_eq "A2 HIGH/CRITICAL count with ascii_downcase" "5" "$high_count"

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
