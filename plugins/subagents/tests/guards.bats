#!/usr/bin/env bats
# guards.bats -- Tests for PreToolUse guard hooks (codex-guard,
# orchestrator-guard, task-dispatch transcript capture).
#
# Verifies that the orchestrator-vs-subagent distinction works:
#  - Calls from the orchestrator's transcript apply the guard
#  - Calls from a subagent's transcript bypass the guard
#  - on-task-dispatch.sh captures ownerTranscriptPath on first Task dispatch

load test_helper/common

setup() {
  setup_temp_state
  source_libs
  HOOKS_DIR="$(cd "$BATS_TEST_DIRNAME/../hooks" && pwd)"
  ORCH_TRANSCRIPT="/tmp/test-orchestrator-transcript.jsonl"
  SUB_TRANSCRIPT="/tmp/test-subagent-transcript.jsonl"
}

teardown() {
  teardown_temp_state
}

# Helper: write a hook input JSON
hook_input() {
  local tool="$1" transcript="$2" extra_fields="${3:-}"
  if [[ -n "$extra_fields" ]]; then
    jq -n --arg t "$tool" --arg tp "$transcript" --argjson extra "$extra_fields" \
      '{tool_name: $t, transcript_path: $tp, tool_input: $extra}'
  else
    jq -n --arg t "$tool" --arg tp "$transcript" \
      '{tool_name: $t, transcript_path: $tp, tool_input: {}}'
  fi
}

# ===========================================================================
# on-task-dispatch.sh: ownerTranscriptPath capture
# ===========================================================================

@test "task-dispatch: captures ownerTranscriptPath on first Task dispatch" {
  write_state ".currentPhase = \"1.1\" | del(.ownerPpid)"

  # Before: ownerTranscriptPath should be empty
  local before
  before="$(jq -r '.ownerTranscriptPath // "EMPTY"' "$STATE_FILE")"
  [ "$before" = "EMPTY" ]

  local input
  input="$(hook_input "Task" "$ORCH_TRANSCRIPT" '{"subagent_type":"subagents:planner","prompt":"[PHASE 1.1]","run_in_background":false}')"
  run bash -c "echo '$input' | bash '$HOOKS_DIR/on-task-dispatch.sh'"
  [ "$status" -eq 0 ]

  # After: ownerTranscriptPath should match the orchestrator transcript
  local after
  after="$(jq -r '.ownerTranscriptPath // "EMPTY"' "$STATE_FILE")"
  [ "$after" = "$ORCH_TRANSCRIPT" ]
}

@test "task-dispatch: does NOT overwrite ownerTranscriptPath once set" {
  write_state ".currentPhase = \"1.1\" | .ownerTranscriptPath = \"$ORCH_TRANSCRIPT\" | del(.ownerPpid)"

  local input
  # Simulate a (hypothetical) Task dispatch coming from a different transcript.
  # The capture should be idempotent — first writer wins.
  input="$(hook_input "Task" "$SUB_TRANSCRIPT" '{"subagent_type":"subagents:planner","prompt":"[PHASE 1.1]","run_in_background":false}')"
  run bash -c "echo '$input' | bash '$HOOKS_DIR/on-task-dispatch.sh'"
  [ "$status" -eq 0 ]

  local after
  after="$(jq -r '.ownerTranscriptPath' "$STATE_FILE")"
  [ "$after" = "$ORCH_TRANSCRIPT" ]
}

# ===========================================================================
# on-codex-guard.sh: subagent bypass
# ===========================================================================

@test "codex-guard: blocks orchestrator-level Codex MCP call" {
  write_state ".currentPhase = \"1.3\" | .ownerTranscriptPath = \"$ORCH_TRANSCRIPT\" | del(.ownerPpid)"

  local input
  input="$(hook_input "mcp__codex-high__codex" "$ORCH_TRANSCRIPT")"
  run bash -c "echo '$input' | bash '$HOOKS_DIR/on-codex-guard.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "decision"
  echo "$output" | grep -q "block"
  echo "$output" | grep -q "background Task"
}

@test "codex-guard: allows Codex MCP call from subagent (different transcript)" {
  write_state ".currentPhase = \"1.3\" | .ownerTranscriptPath = \"$ORCH_TRANSCRIPT\" | del(.ownerPpid)"

  local input
  input="$(hook_input "mcp__codex-high__codex" "$SUB_TRANSCRIPT")"
  run bash -c "echo '$input' | bash '$HOOKS_DIR/on-codex-guard.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "codex-guard: allows when ownerTranscriptPath not yet captured" {
  # Before the orchestrator has dispatched anything (early in workflow),
  # ownerTranscriptPath is empty. The guard falls back to blocking
  # orchestrator-style calls (legacy behavior).
  write_state ".currentPhase = \"1.3\" | del(.ownerPpid)"

  local input
  input="$(hook_input "mcp__codex-high__codex" "$ORCH_TRANSCRIPT")"
  run bash -c "echo '$input' | bash '$HOOKS_DIR/on-codex-guard.sh'"
  [ "$status" -eq 0 ]
  # With empty ownerTranscriptPath, the guard CANNOT prove this is a subagent
  # call, so it applies the conservative block (legacy behavior preserved).
  echo "$output" | grep -q "decision"
}

# ===========================================================================
# on-orchestrator-guard.sh: subagent bypass
# ===========================================================================

@test "orchestrator-guard: blocks orchestrator-level Write to code file" {
  write_state ".currentPhase = \"2.1\" | .ownerTranscriptPath = \"$ORCH_TRANSCRIPT\" | del(.ownerPpid)"

  local input
  input="$(hook_input "Write" "$ORCH_TRANSCRIPT" '{"file_path":"/tmp/src/Foo.swift","content":"x"}')"
  run bash -c "echo '$input' | bash '$HOOKS_DIR/on-orchestrator-guard.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "decision"
  echo "$output" | grep -q "block"
}

@test "orchestrator-guard: allows Write from subagent (task agent)" {
  write_state ".currentPhase = \"2.1\" | .ownerTranscriptPath = \"$ORCH_TRANSCRIPT\" | del(.ownerPpid)"

  local input
  input="$(hook_input "Write" "$SUB_TRANSCRIPT" '{"file_path":"/tmp/src/Foo.swift","content":"x"}')"
  run bash -c "echo '$input' | bash '$HOOKS_DIR/on-orchestrator-guard.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "orchestrator-guard: always allows Write to .agents/tmp regardless of caller" {
  write_state ".currentPhase = \"2.1\" | .ownerTranscriptPath = \"$ORCH_TRANSCRIPT\" | del(.ownerPpid)"

  local input
  input="$(hook_input "Write" "$ORCH_TRANSCRIPT" '{"file_path":"/tmp/.agents/tmp/phases/0-explore.md","content":"x"}')"
  run bash -c "echo '$input' | bash '$HOOKS_DIR/on-orchestrator-guard.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
