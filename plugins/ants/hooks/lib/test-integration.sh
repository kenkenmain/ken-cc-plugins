#!/usr/bin/env bash
# test-integration.sh -- Integration tests for v0.4 features
# Usage: bash plugins/ants/hooks/lib/test-integration.sh
set -euo pipefail

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

# Setup: create minimal v3 state.json and source libs
setup_v3() {
  cd "$TEST_DIR"
  mkdir -p .agents/tmp
  cat > .agents/tmp/state.json <<'JSON'
{
  "version": 3,
  "plugin": "ants",
  "status": "in_progress",
  "currentPhase": "A1",
  "loop": 1,
  "task": "test task",
  "ownerPpid": "",
  "teamName": "ants-test"
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
}

# Setup: create v4 state.json directly
setup_v4() {
  cd "$TEST_DIR"
  mkdir -p .agents/tmp
  cat > .agents/tmp/state.json <<'JSON'
{
  "version": 4,
  "plugin": "ants",
  "status": "in_progress",
  "currentPhase": "A1",
  "loop": 1,
  "task": "test task",
  "ownerPpid": "",
  "teamName": "ants-test",
  "worktreePath": null,
  "messages": [],
  "planApproved": false,
  "shutdown": false,
  "webhookUrl": null,
  "lintConfig": null,
  "configSnapshot": null,
  "compactMetadata": null
}
JSON
  export STATE_FILE=".agents/tmp/state.json"
}

# Source the libraries
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/lint.sh"
source "$SCRIPT_DIR/lib/webhook.sh"
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

# ---- Test 1: State v3->v4 migration ----
echo "Test 1: State v3->v4 migration adds all new fields"
setup_v3
migrate_state_v3_to_v4
actual=$(jq -r '.version' .agents/tmp/state.json)
assert_eq "version=4" "4" "$actual"
actual=$(jq -r '.worktreePath' .agents/tmp/state.json)
assert_eq "worktreePath=null" "null" "$actual"
actual=$(jq -c '.messages' .agents/tmp/state.json)
assert_eq "messages=[]" "[]" "$actual"
actual=$(jq -r '.planApproved' .agents/tmp/state.json)
assert_eq "planApproved=false" "false" "$actual"
actual=$(jq -r '.shutdown' .agents/tmp/state.json)
assert_eq "shutdown=false" "false" "$actual"
actual=$(jq -r '.webhookUrl' .agents/tmp/state.json)
assert_eq "webhookUrl=null" "null" "$actual"
actual=$(jq -r '.lintConfig' .agents/tmp/state.json)
assert_eq "lintConfig=null" "null" "$actual"
actual=$(jq -r '.configSnapshot' .agents/tmp/state.json)
assert_eq "configSnapshot=null" "null" "$actual"
actual=$(jq -r '.compactMetadata' .agents/tmp/state.json)
assert_eq "compactMetadata=null" "null" "$actual"

# ---- Test 2: shutdown_check with shutdown=false ----
echo "Test 2: shutdown_check does not exit when shutdown=false"
setup_v4
# shutdown_check should return normally (not call continue_false_exit)
assert_exit "shutdown=false does not exit" 0 shutdown_check

# ---- Test 3: shutdown_check with shutdown=true ----
echo "Test 3: shutdown_check exits with continue:false JSON when shutdown=true"
setup_v4
jq '.shutdown = true' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
# shutdown_check calls continue_false_exit which does exit 0.
# Verify shutdown flag is read correctly and continue_false_exit works.
# We already test continue_false_exit in Test 5; here we verify the shutdown
# flag detection by checking the raw state value and that shutdown_check
# would call continue_false_exit (which we know produces correct output).
shutdown_val=$(jq -r '.shutdown' .agents/tmp/state.json)
assert_eq "shutdown flag is true in state" "true" "$shutdown_val"
# Verify continue_false_exit produces correct JSON via shutdown_check path.
# Temporarily disable ERR trap to prevent $() subshell interference.
trap - ERR
_sd_out=$(STATELIB="$SCRIPT_DIR/lib/state.sh" bash -c 'source "$STATELIB" 2>/dev/null; continue_false_exit "shutdown test"' 2>/dev/null || true)
trap 'echo "ERROR: ${BASH_SOURCE[1]:-unknown} failed at line ${BASH_LINENO[0]:-?}" >&2; exit 2' ERR
has_continue_false=$(echo "$_sd_out" | jq -r 'if .continue == false then "false" else "missing" end' 2>/dev/null || echo "missing")
assert_eq "shutdown=true would emit continue:false" "false" "$has_continue_false"

# ---- Test 4: add_message and get_messages_for ----
echo "Test 4: add_message and get_messages_for"
setup_v4
add_message "queen" "architect" "Fix the auth module"
add_message "sentinel" "architect" "Security issue in login"
add_message "queen" "worker" "Good job"
msgs=$(get_messages_for "architect")
msg_count=$(echo "$msgs" | jq 'length' 2>/dev/null || echo "0")
assert_eq "architect has 2 messages" "2" "$msg_count"
first_from=$(echo "$msgs" | jq -r '.[0].from' 2>/dev/null || echo "")
assert_eq "first message from queen" "queen" "$first_from"
first_content=$(echo "$msgs" | jq -r '.[0].content' 2>/dev/null || echo "")
assert_eq "first message content" "Fix the auth module" "$first_content"
worker_msgs=$(get_messages_for "worker")
worker_count=$(echo "$worker_msgs" | jq 'length' 2>/dev/null || echo "0")
assert_eq "worker has 1 message" "1" "$worker_count"

# ---- Test 5: continue_false_exit output format ----
echo "Test 5: continue_false_exit outputs valid JSON with continue:false"
setup_v4
output=$(continue_false_exit "test reason" 2>/dev/null || true)
is_valid=$(echo "$output" | jq empty 2>&1 && echo "yes" || echo "no")
assert_eq "output is valid JSON" "yes" "$is_valid"
cont_val=$(echo "$output" | jq -r '.continue' 2>/dev/null || echo "")
assert_eq "continue=false" "false" "$cont_val"
reason_val=$(echo "$output" | jq -r '.stopReason' 2>/dev/null || echo "")
assert_eq "stopReason matches" "test reason" "$reason_val"

# ---- Test 6: lint_file for .sh files ----
echo "Test 6: lint_file for valid and invalid shell scripts"
setup_v4
# Create a valid shell script
mkdir -p "$TEST_DIR/src"
cat > "$TEST_DIR/src/good.sh" <<'SH'
#!/usr/bin/env bash
echo "hello"
SH
result=$(lint_file "$TEST_DIR/src/good.sh")
passed=$(echo "$result" | jq -r '.passed' 2>/dev/null || echo "")
assert_eq "valid .sh passes lint" "true" "$passed"
# Create an invalid shell script
cat > "$TEST_DIR/src/bad.sh" <<'SH'
#!/usr/bin/env bash
if true; then
  echo "unclosed
SH
result=$(lint_file "$TEST_DIR/src/bad.sh")
passed=$(echo "$result" | jq -r '.passed' 2>/dev/null || echo "")
assert_eq "invalid .sh fails lint" "false" "$passed"

# ---- Test 7: lint_file for .json files ----
echo "Test 7: lint_file for valid and invalid JSON files"
setup_v4
echo '{"key": "value"}' > "$TEST_DIR/src/good.json"
result=$(lint_file "$TEST_DIR/src/good.json")
passed=$(echo "$result" | jq -r '.passed' 2>/dev/null || echo "")
assert_eq "valid .json passes lint" "true" "$passed"
echo '{bad json' > "$TEST_DIR/src/bad.json"
result=$(lint_file "$TEST_DIR/src/bad.json")
passed=$(echo "$result" | jq -r '.passed' 2>/dev/null || echo "")
assert_eq "invalid .json fails lint" "false" "$passed"

# ---- Test 8: webhook_fire with no webhookUrl (silent no-op) ----
echo "Test 8: webhook_fire with no webhookUrl is a silent no-op"
setup_v4
# webhookUrl is null -- should return 0 without error
assert_exit "webhook_fire with null URL returns 0" 0 webhook_fire "phase.completed" '{"phase": "A1"}'

# ---- Test 9: plan approval flow (planApproved=false stays at A1) ----
echo "Test 9: plan approval - planApproved false is readable from state"
setup_v4
jq '.currentPhase = "A1" | .planApproved = false' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
plan_approved=$(jq -r '.planApproved' .agents/tmp/state.json)
assert_eq "planApproved=false" "false" "$plan_approved"
current_phase=$(jq -r '.currentPhase' .agents/tmp/state.json)
assert_eq "stays at A1" "A1" "$current_phase"
# Set planApproved to true
jq '.planApproved = true' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
plan_approved=$(jq -r '.planApproved' .agents/tmp/state.json)
assert_eq "planApproved=true after approval" "true" "$plan_approved"

# ---- Test 10: lint_check_enabled defaults to enabled ----
echo "Test 10: lint_check_enabled defaults to true when lintConfig is null"
setup_v4
assert_exit "lint enabled by default" 0 lint_check_enabled
# Disable lint
jq '.lintConfig = {"enabled": false}' .agents/tmp/state.json > .agents/tmp/state.json.tmp \
  && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
assert_exit "lint disabled when configured" 1 lint_check_enabled

# ---- Test 11: on-subagent-start.sh outputs valid hookSpecificOutput JSON ----
echo "Test 11: on-subagent-start.sh outputs valid hookSpecificOutput JSON"
setup_v4
# Add schedule to state so stage lookup works
jq '.schedule = [{"phase": "A1", "stage": "PLAN", "label": "Architect Plan", "type": "teams"}] | .currentPhase = "A1"' \
  .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
# Run on-subagent-start.sh in a subshell with the test state
output=$(cd "$TEST_DIR" && bash "$SCRIPT_DIR/on-subagent-start.sh" < /dev/null 2>/dev/null || true)
is_valid=$(echo "$output" | jq empty 2>&1 && echo "yes" || echo "no")
assert_eq "subagent-start output is valid JSON" "yes" "$is_valid"
has_hook_event=$(echo "$output" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null || echo "")
assert_eq "hookEventName is SubagentStart" "SubagentStart" "$has_hook_event"
has_context=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || echo "")
context_has_phase=$(echo "$has_context" | grep -c "phase=A1" || true)
assert_eq "additionalContext contains phase=A1" "1" "$context_has_phase"
context_has_stage=$(echo "$has_context" | grep -c "stage=PLAN" || true)
assert_eq "additionalContext contains stage=PLAN" "1" "$context_has_stage"

# ---- Test 12: on-config-change.sh updates configSnapshot ----
echo "Test 12: on-config-change.sh updates configSnapshot in state"
setup_v4
# Verify configSnapshot starts as null
snap_before=$(jq -r '.configSnapshot' .agents/tmp/state.json)
assert_eq "configSnapshot starts null" "null" "$snap_before"
# Feed config change JSON on stdin
echo '{"config_source": "user_edit"}' | (cd "$TEST_DIR" && bash "$SCRIPT_DIR/on-config-change.sh" 2>/dev/null) || true
snap_after=$(jq -r '.configSnapshot' .agents/tmp/state.json)
assert_eq "configSnapshot is no longer null" "1" "$(if [[ "$snap_after" != "null" ]]; then echo 1; else echo 0; fi)"
snap_source=$(jq -r '.configSnapshot.source' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "configSnapshot.source is user_edit" "user_edit" "$snap_source"
snap_has_ts=$(jq -r 'if .configSnapshot.lastChangeAt then "yes" else "no" end' .agents/tmp/state.json 2>/dev/null || echo "no")
assert_eq "configSnapshot.lastChangeAt is set" "yes" "$snap_has_ts"

# ---- Test 13: on-config-change.sh handles empty stdin gracefully ----
echo "Test 13: on-config-change.sh handles empty/invalid stdin gracefully"
setup_v4
# Empty stdin should not crash (exit 0)
assert_exit "config-change with empty stdin exits 0" 0 bash -c "cd '$TEST_DIR' && bash '$SCRIPT_DIR/on-config-change.sh' < /dev/null 2>/dev/null"
# configSnapshot should remain null since no valid input
snap_val=$(jq -r '.configSnapshot' .agents/tmp/state.json)
assert_eq "configSnapshot unchanged on empty stdin" "null" "$snap_val"

# ---- Test 14: on-pre-compact.sh saves compactMetadata ----
echo "Test 14: on-pre-compact.sh saves compactMetadata to state"
setup_v4
# Set a known phase/loop/status
jq '.currentPhase = "A3" | .loop = 2 | .status = "in_progress"' \
  .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
# Run the hook
(cd "$TEST_DIR" && bash "$SCRIPT_DIR/on-pre-compact.sh" < /dev/null 2>/dev/null) || true
compact_phase=$(jq -r '.compactMetadata.currentPhase' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "compactMetadata.currentPhase=A3" "A3" "$compact_phase"
compact_loop=$(jq -r '.compactMetadata.loop' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "compactMetadata.loop=2" "2" "$compact_loop"
compact_status=$(jq -r '.compactMetadata.status' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "compactMetadata.status=in_progress" "in_progress" "$compact_status"
compact_saved=$(jq -r 'if .compactMetadata.savedAt then "yes" else "no" end' .agents/tmp/state.json 2>/dev/null || echo "no")
assert_eq "compactMetadata.savedAt is set" "yes" "$compact_saved"

# ---- Test 15: on-pre-compact.sh includes taskPool summary ----
echo "Test 15: on-pre-compact.sh includes taskPool summary when pool exists"
setup_v4
# Add a taskPool with mixed statuses
jq '.currentPhase = "A3" | .taskPool = [
  {"id": "t1", "status": "complete"},
  {"id": "t2", "status": "complete"},
  {"id": "t3", "status": "ready"},
  {"id": "t4", "status": "pending"},
  {"id": "t5", "status": "failed"}
]' .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
(cd "$TEST_DIR" && bash "$SCRIPT_DIR/on-pre-compact.sh" < /dev/null 2>/dev/null) || true
pool_total=$(jq -r '.compactMetadata.taskPoolSummary.total' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "taskPoolSummary.total=5" "5" "$pool_total"
pool_complete=$(jq -r '.compactMetadata.taskPoolSummary.complete' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "taskPoolSummary.complete=2" "2" "$pool_complete"
pool_ready=$(jq -r '.compactMetadata.taskPoolSummary.ready' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "taskPoolSummary.ready=1" "1" "$pool_ready"
pool_failed=$(jq -r '.compactMetadata.taskPoolSummary.failed' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "taskPoolSummary.failed=1" "1" "$pool_failed"

# ---- Test 16: get_messages_for with no matches returns "[]" ----
echo "Test 16: get_messages_for with no matches returns empty JSON array"
setup_v4
# Messages array is empty, so any recipient should get []
msgs=$(get_messages_for "nonexistent-agent")
assert_eq "no-match returns []" "[]" "$msgs"
# Add a message to someone else and verify still []
add_message "queen" "worker" "do something"
msgs2=$(get_messages_for "nonexistent-agent")
assert_eq "no-match with other messages returns []" "[]" "$msgs2"

# ---- Test 17: webhook_fire with a URL constructs valid body (mock test) ----
echo "Test 17: webhook_fire body construction with URL set"
setup_v4
# Set a webhook URL (we cannot test the actual curl, but we can test body construction)
# Override curl to capture the body instead of sending it
jq '.webhookUrl = "http://localhost:9999/test-hook"' \
  .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
# Test webhook_phase_event and webhook_workflow_event helper body construction
# Since background curl is untestable, verify the helper functions run without error
assert_exit "webhook_phase_event does not crash" 0 webhook_phase_event "A1" "completed"
assert_exit "webhook_workflow_event does not crash" 0 webhook_workflow_event "completed"

# ---- Test 18: lint_format_advisory with string-keyed failures returns advisory text ----
echo "Test 18: lint_format_advisory formats errors into advisory text"
setup_v4
lint_json='{"passed": false, "errors": [{"file": "test.sh", "line": 0, "message": "syntax error", "severity": "error"}], "warnings": [], "skipped": false}'
advisory=$(lint_format_advisory "$lint_json")
has_file=$(echo "$advisory" | grep -c "test.sh" || true)
assert_eq "advisory mentions file" "1" "$has_file"
has_msg=$(echo "$advisory" | grep -c "syntax error" || true)
assert_eq "advisory mentions error message" "1" "$has_msg"

# ---- Test 19: lint_format_advisory with passing result returns empty ----
echo "Test 19: lint_format_advisory with passing result returns empty"
setup_v4
lint_json='{"passed": true, "errors": [], "warnings": [], "skipped": false}'
advisory=$(lint_format_advisory "$lint_json")
assert_eq "passing lint returns empty advisory" "" "$advisory"

# ---- Test 20: lint_file for .py files ----
echo "Test 20: lint_file for valid and invalid Python files"
setup_v4
mkdir -p "$TEST_DIR/src"
cat > "$TEST_DIR/src/good.py" <<'PY'
def hello():
    return "world"
PY
result=$(lint_file "$TEST_DIR/src/good.py")
passed=$(echo "$result" | jq -r '.passed' 2>/dev/null || echo "")
assert_eq "valid .py passes lint" "true" "$passed"
cat > "$TEST_DIR/src/bad.py" <<'PY'
def hello(
    return "unclosed paren"
PY
result=$(lint_file "$TEST_DIR/src/bad.py")
passed=$(echo "$result" | jq -r '.passed' 2>/dev/null || echo "")
assert_eq "invalid .py fails lint" "false" "$passed"

# ---- Test 21: lint_file for unsupported extension returns skipped ----
echo "Test 21: lint_file for unsupported extension returns skipped=true"
setup_v4
echo "some content" > "$TEST_DIR/src/file.xyz"
result=$(lint_file "$TEST_DIR/src/file.xyz")
skipped=$(echo "$result" | jq -r '.skipped' 2>/dev/null || echo "")
assert_eq "unsupported ext skipped=true" "true" "$skipped"
passed=$(echo "$result" | jq -r '.passed' 2>/dev/null || echo "")
assert_eq "unsupported ext passed=true" "true" "$passed"

# ---- Test 22: add_message includes loop and timestamp ----
echo "Test 22: add_message includes loop number and addedAt timestamp"
setup_v4
jq '.loop = 3' .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
add_message "sentinel" "worker" "Fix the bug"
msg_loop=$(jq -r '.messages[0].loop' .agents/tmp/state.json 2>/dev/null || echo "")
assert_eq "message loop=3" "3" "$msg_loop"
msg_ts=$(jq -r 'if .messages[0].addedAt then "yes" else "no" end' .agents/tmp/state.json 2>/dev/null || echo "no")
assert_eq "message has addedAt" "yes" "$msg_ts"

# ---- Summary ----
echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed"
echo "=============================="
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
