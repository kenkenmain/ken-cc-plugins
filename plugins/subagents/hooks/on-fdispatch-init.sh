#!/usr/bin/env bash
# on-fdispatch-init.sh -- UserPromptSubmit hook for fdispatch commands.
# Performs state initialization in shell BEFORE Claude processes the command,
# so Claude can skip setup and dispatch the F1 subagent immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

# ── Guard: require jq ────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  exit 0  # Can't parse input; let the command prompt handle setup
fi

# ── Read hook input ──────────────────────────────────────────────────────────
INPUT="$(cat)"

# Validate stdin is non-empty JSON before extracting
if [[ -z "$INPUT" ]] || ! echo "$INPUT" | jq empty 2>/dev/null; then
  exit 0
fi

PROMPT="$(echo "$INPUT" | jq -r '.prompt // ""')"

# ── Only act on fdispatch commands ───────────────────────────────────────────
# Match /subagents:fdispatch or /subagents:fdispatch-claude at the start of the prompt.
# Anchored to avoid triggering on prompts that merely mention the command in text.
if ! echo "$PROMPT" | grep -qiE '^\s*/?subagents:(fdispatch-claude|fdispatch)\b'; then
  exit 0
fi

# ── Guard: don't clobber active workflow from another session ────────────────
if [[ -f "$STATE_FILE" ]]; then
  EXISTING_STATUS="$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null)" || true
  EXISTING_PPID="$(jq -r '.ownerPpid // empty' "$STATE_FILE" 2>/dev/null)" || true
  if [[ "$EXISTING_STATUS" == "in_progress" && -n "$EXISTING_PPID" && "$EXISTING_PPID" != "$PPID" ]]; then
    # Different session owns this workflow — check if it's still alive.
    # Use /proc (Linux) or ps (macOS) since kill -0 requires signal permission.
    if [[ -d "/proc/$EXISTING_PPID" ]] || ps -p "$EXISTING_PPID" >/dev/null 2>&1; then
      exit 0  # Active workflow in another session; let the command prompt handle it
    fi
  fi
fi

# ── Detect variant ───────────────────────────────────────────────────────────
# Anchored to start of prompt to avoid matching "fdispatch-claude" in task text.
CODEX_MODE=true
if echo "$PROMPT" | grep -qiE '^\s*/?subagents:fdispatch-claude\b'; then
  CODEX_MODE=false
fi

# ── Parse flags ──────────────────────────────────────────────────────────────
WORKTREE=false
NO_WORKTREE_COMPAT=false
WEB_SEARCH=true

# Use word-boundary matching to distinguish --worktree from --no-worktree
if echo "$PROMPT" | grep -qE '(^|\s)--worktree(\s|$)'; then
  WORKTREE=true
fi

# Detect deprecated --no-worktree for backward-compat acknowledgment
# Use word-boundary matching to avoid false positives from task text
if echo "$PROMPT" | grep -qE '(^|\s)--no-worktree(\s|$)'; then
  NO_WORKTREE_COMPAT=true
fi

if echo "$PROMPT" | grep -qE '(^|\s)--no-web-search(\s|$)'; then
  WEB_SEARCH=false
fi

# ── Extract task description ─────────────────────────────────────────────────
# Strip command prefix (anchored to start), then remove only recognized flags, then trim.
# Uses ~ as sed delimiter to avoid conflicts with / in the prompt.
TASK="$(echo "$PROMPT" | sed -E 's~^(\s|/)*subagents:(fdispatch-claude|fdispatch)~~i')"
TASK="$(echo "$TASK" | sed -E 's/(^|\s)--(worktree|no-worktree|no-web-search)(\s|$)/ /g' | xargs)"

if [[ -z "$TASK" ]]; then
  # No task description — let the command prompt handle the error
  exit 0
fi

# ── Create directories ───────────────────────────────────────────────────────
mkdir -p "$PHASES_DIR"
rm -f "$PHASES_DIR"/*.tmp

# ── Determine agents based on mode ───────────────────────────────────────────
if [[ "$CODEX_MODE" == "true" ]]; then
  F3_PRIMARY="subagents:codex-code-quality-reviewer"
  F3_SUPP='["subagents:codex-error-handling-reviewer","subagents:codex-type-reviewer","subagents:codex-test-coverage-reviewer","subagents:codex-comment-reviewer"]'
  CODEX_AVAILABLE=true
else
  F3_PRIMARY="subagents:code-quality-reviewer"
  F3_SUPP='["subagents:error-handling-reviewer","subagents:type-reviewer","subagents:test-coverage-reviewer","subagents:comment-reviewer"]'
  CODEX_AVAILABLE=false
fi

NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ── Write state.json atomically ──────────────────────────────────────────────
# If state_write fails (disk full, permissions), exit 0 silently —
# the command prompt will handle setup as a fallback.
NEW_STATE="$(jq -n \
  --arg task "$TASK" \
  --arg now "$NOW" \
  --arg ppid "$PPID" \
  --argjson codex "$CODEX_AVAILABLE" \
  --arg f3p "$F3_PRIMARY" \
  --argjson f3s "$F3_SUPP" \
  --argjson ws "$WEB_SEARCH" \
  '{
    version: 2,
    plugin: "subagents",
    pipeline: "fdispatch",
    status: "in_progress",
    task: $task,
    startedAt: $now,
    updatedAt: $now,
    stoppedAt: null,
    currentPhase: "F1",
    currentStage: "PLAN",
    ownerPpid: $ppid,
    codexAvailable: $codex,
    agents: {
      f1: "subagents:fast-planner",
      f3Primary: $f3p,
      f3Supplementary: $f3s,
      f4: "subagents:completion-handler"
    },
    schedule: [
      { phase: "F1", stage: "PLAN", name: "Fast Plan", type: "subagent" },
      { phase: "F2", stage: "IMPLEMENT", name: "Implement + Test", type: "dispatch" },
      { phase: "F3", stage: "REVIEW", name: "Parallel Review", type: "dispatch" },
      { phase: "F4", stage: "COMPLETE", name: "Completion", type: "subagent" }
    ],
    gates: {
      "PLAN->IMPLEMENT": { required: ["f1-plan.md"], phase: "F1" },
      "IMPLEMENT->REVIEW": { required: ["f2-tasks.json"], phase: "F2" },
      "REVIEW->COMPLETE": { required: ["f3-review.json"], phase: "F3" },
      "COMPLETE->DONE": { required: ["f4-completion.json"], phase: "F4" }
    },
    stages: {
      PLAN: { status: "pending" },
      IMPLEMENT: { status: "pending" },
      REVIEW: { status: "pending" },
      COMPLETE: { status: "pending" }
    },
    webSearch: $ws,
    supplementaryPolicy: "on-issues",
    coverageThreshold: 90,
    reviewPolicy: { maxFixAttempts: 3, maxStageRestarts: 1 },
    restartHistory: [],
    files: [],
    failure: null,
    compaction: null
  }')" || exit 0

state_write "$NEW_STATE" || exit 0

# ── Return additionalContext ─────────────────────────────────────────────────
# Injected BEFORE Claude processes the command prompt.
WS_LABEL="enabled"
if [[ "$WEB_SEARCH" == "false" ]]; then WS_LABEL="disabled"; fi
WT_LABEL="not requested"
if [[ "$WORKTREE" == "true" ]]; then
  WT_LABEL="requested — create worktree before Step 2.5"
elif [[ "$NO_WORKTREE_COMPAT" == "true" ]]; then
  WT_LABEL="--no-worktree accepted (no-op, worktree is not created by default)"
fi

CONTEXT="FDISPATCH STATE PRE-INITIALIZED by UserPromptSubmit hook.
- State file: .agents/tmp/state.json (already written)
- Directories: .agents/tmp/phases/ (already created)
- Task: ${TASK}
- Web search: ${WS_LABEL}
- Worktree: ${WT_LABEL}

SKIP Steps 1-2a/2b/2d (configuration loading, directory creation, PID capture, state.json writing).
If --worktree was requested, execute Step 2c (worktree creation) and update state.json with the worktree field.
Then proceed to: Step 2.5 (display schedule), Step 3 (task list), then Step 4 (dispatch F1 immediately)."

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
