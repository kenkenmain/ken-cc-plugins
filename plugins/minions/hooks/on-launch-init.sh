#!/usr/bin/env bash
# on-launch-init.sh -- UserPromptSubmit hook for minions:launch, minions:superlaunch, and minions:review commands.
# Detects existing workflow state and injects resume/clean prompts when appropriate.
set -euo pipefail

STATE_FILE=".agents/tmp/state.json"

# ── Guard: require jq ────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  exit 0  # Can't parse input; let the command prompt handle it
fi

# ── Read hook input ──────────────────────────────────────────────────────────
INPUT="$(cat)"

# Validate stdin is non-empty JSON before extracting
if [[ -z "$INPUT" ]] || ! echo "$INPUT" | jq empty 2>/dev/null; then
  exit 0
fi

PROMPT="$(echo "$INPUT" | jq -r '.prompt // ""')"

# ── Only act on minions:launch, minions:superlaunch, and minions:review ──────
# Match /minions:launch, /minions:superlaunch, or /minions:review at prompt start.
# Anchored to avoid triggering on prompts that merely mention the command in text.
if ! echo "$PROMPT" | grep -qiE '^\s*/?minions:(launch|superlaunch|review)\b'; then
  exit 0
fi

# ── No existing state file: allow launch to proceed ──────────────────────────
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# ── Validate state file is valid JSON ────────────────────────────────────────
if ! jq -e 'type == "object"' "$STATE_FILE" >/dev/null 2>&1; then
  # Corrupt state file — inject warning and let launch decide
  CONTEXT="WARNING: Existing .agents/tmp/state.json is corrupt (not valid JSON).
Consider running: rm -rf .agents/tmp/phases && mkdir -p .agents/tmp/phases
Then retry your minions command."

  jq -n --arg ctx "$CONTEXT" '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": $ctx
    }
  }'
  exit 0
fi

# ── Extract state fields ─────────────────────────────────────────────────────
EXISTING_STATUS="$(jq -r '.status // empty' "$STATE_FILE" 2>/dev/null)" || true
EXISTING_PPID="$(jq -r '.ownerPpid // empty' "$STATE_FILE" 2>/dev/null)" || true
EXISTING_PLUGIN="$(jq -r '.plugin // empty' "$STATE_FILE" 2>/dev/null)" || true
EXISTING_TASK="$(jq -r '.task // empty' "$STATE_FILE" 2>/dev/null)" || true
EXISTING_LOOP="$(jq -r '.loop // .iteration // 1' "$STATE_FILE" 2>/dev/null)" || true
EXISTING_PHASE="$(jq -r '.currentPhase // empty' "$STATE_FILE" 2>/dev/null)" || true

# ── Non-minions plugin: warn but allow ───────────────────────────────────────
if [[ -n "$EXISTING_PLUGIN" && "$EXISTING_PLUGIN" != "minions" ]]; then
  CONTEXT="WARNING: Existing workflow state belongs to plugin '$EXISTING_PLUGIN'.
Launching this minions workflow will overwrite this state.
If you want to preserve the other workflow, cancel and rename/backup .agents/tmp/state.json first."

  jq -n --arg ctx "$CONTEXT" '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": $ctx
    }
  }'
  exit 0
fi

# ── Status is not in_progress: safe to overwrite ─────────────────────────────
if [[ "$EXISTING_STATUS" != "in_progress" ]]; then
  exit 0
fi

# ── Check if ownerPpid process is still alive ────────────────────────────────
is_process_alive() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    return 1
  fi
  [[ ! "$pid" =~ ^[0-9]+$ ]] && return 1
  # Use /proc (Linux) or ps (macOS) since kill -0 requires signal permission
  if [[ -d "/proc/$pid" ]] || ps -p "$pid" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if [[ -n "$EXISTING_PPID" ]]; then
  if is_process_alive "$EXISTING_PPID"; then
    # Active workflow in another session — warn user
    CONTEXT="WARNING: An active minions workflow is already in progress in another session.
- Task: ${EXISTING_TASK}
- Current phase: ${EXISTING_PHASE}
- Loop: ${EXISTING_LOOP}
- Owner PID: ${EXISTING_PPID}

Options:
1. CANCEL this launch and let the other session complete
2. STOP the other session first, then resume or clean here
3. PROCEED anyway (will overwrite — data loss risk)

Recommendation: Cancel this launch and check the other session."

    jq -n --arg ctx "$CONTEXT" '{
      "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": $ctx
      }
    }'
    exit 0
  fi
fi

# ── Stale workflow: owner process is dead ────────────────────────────────────
# The ownerPpid process is not running — this is an orphaned workflow
CONTEXT="NOTICE: Found stale workflow state from a previous session that did not complete.
- Task: ${EXISTING_TASK}
- Current phase: ${EXISTING_PHASE}
- Loop: ${EXISTING_LOOP}
- Original owner PID: ${EXISTING_PPID} (no longer running)

Options:
1. RESUME: Continue from ${EXISTING_PHASE} by updating ownerPpid to current session
   (Read state, analyze progress, dispatch current phase)
2. CLEAN: Remove stale phase outputs and start fresh with new task
   (rm -rf .agents/tmp/phases && mkdir -p .agents/tmp/phases)

Ask the user which option they prefer before proceeding."

jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
