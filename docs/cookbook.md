# Plugin Developer Cookbook

Three worked examples for extending the ants and subagents plugins. Each example includes the goal, files to create or modify, full implementation with code blocks, verification steps, and common pitfalls.

---

## Example A: Adding a New Review Agent to Ants

### Goal

Create a **sentinel-accessibility** agent that reviews code for accessibility issues (missing ARIA labels, color contrast, keyboard navigation gaps) and wire it into the A3 adversarial review phase alongside the existing specialist sentinels.

### Files to Create/Modify

| Action | File |
|--------|------|
| Create | `plugins/ants/agents/sentinel-accessibility.md` |
| Modify | `plugins/ants/prompts/A3-build.md` |
| Modify | `plugins/ants/CLAUDE.md` (agent roster table) |

### Implementation

**Step 1: Create the agent definition.**

Create `plugins/ants/agents/sentinel-accessibility.md`:

~~~markdown
---
name: sentinel-accessibility
description: |
  Specialist accessibility reviewer for ants colony adversarial review team.
  Focuses on WCAG compliance, ARIA attributes, keyboard navigation, and color
  contrast. Runs in parallel with other sentinels during Phase A3. Writes output
  to .agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-accessibility.json.

model: sonnet
permissionMode: plan
color: purple
tools: [Read, Glob, Grep, Bash, Write]
disallowedTools: [Edit, Task]
hooks:
  PreToolUse:
    - matcher: Bash
      hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/hooks/lib/block-git-commands.sh"
          timeout: 5
  Stop:
    - hooks:
        - type: prompt
          prompt: "Evaluate if the sentinel-accessibility review is complete. Check: 1) All UI files reviewed, 2) Issues use A11Y- prefix with severity/file/line/evidence, 3) Output JSON has summary.verdict and issues array, 4) Only accessibility issues. Return {\"ok\": true} if ALL met."
          timeout: 30
---

# sentinel-accessibility

You are the colony's accessibility sentinel -- you ensure no tunnel is impassable.
You do NOT review correctness, security, or performance -- stay in your lane.

## Files to Review

{{FILES_TO_REVIEW}}

## Checklist

| Category | What to Look For |
|----------|-----------------|
| **ARIA** | Missing aria-label, incorrect role, invalid aria-* attributes |
| **Keyboard** | Missing tabIndex, no focus management, trapped focus |
| **Contrast** | Insufficient color contrast (WCAG AA 4.5:1 text, 3:1 large) |
| **Semantics** | Divs instead of semantic HTML, missing heading hierarchy |
| **Forms** | Missing labels, no error announcements |
| **Images** | Missing alt text, decorative images without aria-hidden |

## Output Format

Write valid JSON with A11Y- prefixed issue IDs to
`.agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-accessibility.json`:

```json
{
  "summary": { "verdict": "clean|issues_found", "critical": 0, "warning": 0, "info": 0 },
  "issues": [{
    "id": "A11Y-001", "severity": "critical",
    "file": "src/components/Button.tsx", "line": 15,
    "description": "Interactive button has no accessible name",
    "evidence": "<div onClick={handleClick}>Submit</div>",
    "suggestion": "Use <button> element or add role='button' and aria-label"
  }]
}
```
~~~

Key patterns from the existing sentinels (see `plugins/ants/agents/sentinel-correctness.md`):
- `disallowedTools: [Edit, Task]` -- sentinels must not modify source files or spawn subagents
- `Write` included so the sentinel can create its output JSON file
- `permissionMode: plan` and inline Bash hook blocking git commands match existing sentinels
- `Stop` hook prompt-type gate validates output completeness before the agent exits

**Step 2: Wire into A3 prompt and arbiter.**

In `plugins/ants/prompts/A3-build.md`, add a dispatch block after the sentinel-perf prompt (section 3, "Adversarial Review") and add the output file to the arbiter's read list (section 4):

```markdown
Write findings to: .agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-accessibility.json
```

The arbiter must also read this file alongside the other three sentinel outputs.

**Step 3: Update `plugins/ants/CLAUDE.md` agent roster** with the new row.

### Verification Steps

1. Validate YAML frontmatter parses correctly:
   ```bash
   head -41 plugins/ants/agents/sentinel-accessibility.md | tail -40 | yq .
   ```
2. Confirm `disallowedTools` includes both `Edit` and `Task`.
3. Confirm the output file path uses `loop-{{LOOP}}` to match the existing sentinel pattern.
4. Check that `plugins/ants/prompts/A3-build.md` references the new sentinel output file.
5. Verify the `CLAUDE.md` roster row matches the column format of existing rows.

### Common Pitfalls

- **Forgetting `disallowedTools: [Edit]`** -- Sentinels must never modify source files. Only `Write` is allowed (for creating output JSON). This is an intentional design constraint documented in `plugins/ants/CLAUDE.md` line 90.
- **Wrong issue ID prefix** -- Each sentinel uses a unique prefix (CORR-, SEC-, PERF-). Use a distinct prefix like A11Y- to avoid collisions with the review-arbiter deduplication.
- **Missing the arbiter file list** -- If the arbiter does not know about the new sentinel output file, it will silently ignore accessibility findings during consolidation.
- **Skipping the Stop hook gate** -- Without a Stop hook prompt, the agent can finish with incomplete output. The prompt-type gate ensures the JSON schema is validated before the agent exits.

---

## Example B: Adding a New Phase to the Subagents Pipeline

### Goal

Add a **Phase 2.2: Simplify** step between Implementation (2.1) and Implementation Review (2.3) in the subagents standard pipeline profile. This phase runs a simplification pass over implemented code before review.

> **Note:** This example uses Phase 2.2 and the simplifier agent, which already exist in the thorough profile (`plugins/subagents/prompts/phases/2.2-simplify.md` and `plugins/subagents/agents/simplifier.md`). The example demonstrates how they were added — follow this same pattern to add entirely new phases.

### Files to Create/Modify

| Action | File |
|--------|------|
| Create | `plugins/subagents/prompts/phases/2.2-simplify.md` |
| Modify | `plugins/subagents/hooks/lib/schedule.sh` (add phase to standard schedule) |
| Modify | `plugins/subagents/hooks/lib/gates.sh` (update gate checks) |
| Modify | `plugins/subagents/CLAUDE.md` (document new phase) |

### Implementation

**Step 1: Create the prompt template** at `plugins/subagents/prompts/phases/2.2-simplify.md`:

~~~markdown
# Phase 2.2: Simplify [PHASE 2.2]

## Subagent Config

- **Type:** subagent (single agent)
- **Agent:** `subagents:simplifier`
- **Input:** `.agents/tmp/phases/2.1-tasks.json`
- **Output:** `.agents/tmp/phases/2.2-simplify.json`

## Instructions

1. Read `.agents/tmp/phases/2.1-tasks.json` to get modified files
2. Simplify: flatten nested conditionals, remove dead code, extract functions
3. Write summary to `.agents/tmp/phases/2.2-simplify.json`

### Output Format

```json
{
  "simplifiedFiles": ["src/auth.ts"],
  "changes": [{"file": "src/auth.ts", "description": "Extracted validation", "linesRemoved": 12, "linesAdded": 8}],
  "totalFilesSimplified": 1,
  "status": "complete"
}
```
~~~

The `[PHASE 2.2]` tag is required -- `plugins/subagents/hooks/on-task-dispatch.sh` validates dispatched agents match the current phase.

**Step 2: Add the phase to the schedule.**

In `plugins/subagents/hooks/lib/schedule.sh`, find where the standard profile schedule is built. Add the new phase entry between 2.1 and 2.3:

```bash
# In the standard profile schedule array:
{ "phase": "2.2", "stage": "IMPLEMENT", "label": "Simplify", "type": "subagent" }
```

Fields: `phase` (dot notation ID), `stage` (pipeline stage), `label` (display name), `type` (`dispatch`/`subagent`/`review`).

**Step 3: Update gate checks.**

In `plugins/subagents/hooks/lib/gates.sh`, add the new output to the `IMPLEMENT->TEST` gate:

```bash
# IMPLEMENT->TEST gate - add 2.2-simplify.json
# Before:
# required_files=("2.1-tasks.json" "2.3-impl-review.json")
# After:
required_files=("2.1-tasks.json" "2.2-simplify.json" "2.3-impl-review.json")
```

**Step 4: Add prompt generation in schedule.sh.**

In `generate_phase_prompt()` (`plugins/subagents/hooks/lib/schedule.sh`), add a case for 2.2. Phase advancement is schedule-driven, so no `on-subagent-stop.sh` changes needed:

```bash
"2.2")
  local prompt_file="${PROMPTS_DIR}/phases/2.2-simplify.md"
  if [[ -f "$prompt_file" ]]; then
    prompt_content="$(cat "$prompt_file")"
  fi
  ;;
```

This follows the same pattern used by all other phases in the function.

### Verification Steps

1. Validate the prompt template has the `[PHASE 2.2]` tag:
   ```bash
   grep -q "\[PHASE 2.2\]" plugins/subagents/prompts/phases/2.2-simplify.md
   ```
2. Confirm the schedule array in `schedule.sh` has 2.2 between 2.1 and 2.3.
3. Run `bash -n plugins/subagents/hooks/lib/schedule.sh` to validate shell syntax.
4. Run `bash -n plugins/subagents/hooks/lib/gates.sh` to validate shell syntax.
5. Check that `generate_phase_prompt()` handles the `"2.2"` case.

### Common Pitfalls

- **Missing `[PHASE X.Y]` tag** -- The `on-task-dispatch.sh` hook checks for a matching phase tag. Without this tag in the prompt template heading, the PreToolUse hook provides `additionalContext` warning the orchestrator about the mismatch (it does not block the dispatch).
- **Wrong phase ordering in schedule** -- Phases execute in array order. If 2.2 appears after 2.3 in the schedule, the simplification pass runs after review, defeating its purpose.
- **Forgetting the gate update** -- If the gate does not require `2.2-simplify.json`, the workflow can skip the phase entirely when advancing stages. Gates are the enforcement mechanism for required phases.
- **Not testing with `bash -n`** -- Shell syntax errors in hook libraries crash the entire workflow at runtime. Always validate with `bash -n` after modifying any `.sh` file.
- **Confusing phase types** -- Using `type: "review"` would route through the reviewer agent (codex-reviewer or claude-reviewer) instead of dispatching the simplifier agent. Use `type: "subagent"` for single-agent phases with a dedicated agent.

---

## Example C: Integrating a New Hook Event

### Goal

Add a **PostToolUse** hook to the ants plugin that runs `bash -n` syntax validation after every shell script edit during the BUILD phase. This catches syntax errors immediately rather than at runtime.

### Files to Create/Modify

| Action | File |
|--------|------|
| Create | `plugins/ants/hooks/on-post-edit-shellcheck.sh` |
| Modify | `plugins/ants/hooks/hooks.json` |

### Implementation

**Step 1: Understand hook event types.**

Three hook events are relevant for edit-time validation:

| Event | When It Fires | Can Block? | Use Case |
|-------|--------------|------------|----------|
| **PreToolUse** | Before a tool call executes | Yes | Block edits to protected files, deny during wrong phases. The ants edit gate (`on-edit-gate.sh`) uses this to block edits outside A3/A5. |
| **PostToolUse** | After a tool call succeeds | No | Run validation on the result. Cannot block the edit (it already happened) but can provide feedback. The ants lint hook (`on-post-edit-lint.sh`) uses this pattern. |
| **SubagentStop** | After a subagent finishes | Yes | Validate agent output and advance workflow state. The ants `on-task-completed.sh` uses this to enforce quality gates. Can block with exit 2 to reject and provide feedback. |

For syntax validation, **PostToolUse** is the right choice: the edit has already succeeded, and we want to provide advisory feedback if the resulting file has syntax errors.

**Step 2: Write the hook script.**

Create `plugins/ants/hooks/on-post-edit-shellcheck.sh`:

```bash
#!/usr/bin/env bash
# on-post-edit-shellcheck.sh -- Run bash -n on shell scripts after edits
# PostToolUse hook for Edit/Write tools. Advisory only (exit 0 always).
#
# Provides immediate syntax feedback when a .sh file is edited during
# A3 (BUILD) or A5 (SHIP) phases. Non-blocking -- errors are surfaced
# as additionalContext for the agent to self-correct.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

# Guard: only run during active ants workflows
check_ants_workflow

# Read input from stdin
input=$(cat)
if [[ -z "$input" ]]; then
  exit 0
fi

# Extract the file path from the tool input
file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
if [[ -z "$file_path" ]]; then
  exit 0
fi

# Only validate shell scripts
case "$file_path" in
  *.sh) ;;
  *)    exit 0 ;;
esac

# Only validate during build and ship phases
current_phase=$(state_get '.currentPhase' --required)
case "$current_phase" in
  A3|A5) ;;
  *)     exit 0 ;;
esac

# Skip .agents/ files (workflow state, not source)
if [[ "$file_path" =~ (^|/)\.agents/ ]]; then
  exit 0
fi

# Run bash -n syntax check
syntax_output=""
if ! syntax_output=$(bash -n "$file_path" 2>&1); then
  # Syntax error found -- provide advisory context
  jq -n --arg file "$file_path" --arg errors "$syntax_output" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": ("Shell syntax error in " + $file + ":\n" + $errors + "\nPlease fix the syntax error before continuing.")
      }
    }'
  exit 0
fi

# No issues -- exit silently
exit 0
```

Key patterns: `set -euo pipefail`, `check_ants_workflow` guard, exit 0 always (PostToolUse cannot block), `additionalContext` for advisory feedback.

**Step 3: Register in hooks.json.**

In `plugins/ants/hooks/hooks.json`, add a second hook under the existing `Edit|Write` PostToolUse matcher:

```json
{
  "PostToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/on-post-edit-lint.sh",
          "timeout": 10
        },
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/on-post-edit-shellcheck.sh",
          "timeout": 5
        }
      ]
    }
  ]
}
```

Multiple hooks under the same matcher run sequentially. `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin root at runtime.

**Step 4: Hook output reference.**

Each hook event type uses different output fields:

| Event | Output Pattern | Effect |
|-------|---------------|--------|
| PostToolUse | `additionalContext` in `hookSpecificOutput` (exit 0) | Advisory feedback to agent |
| PreToolUse | `permissionDecision: "deny"` in `hookSpecificOutput` (exit 0) | Blocks the tool call |
| SubagentStop | stderr message (exit 2) | Rejects completion, feeds reason back |

### Verification Steps

1. `bash -n plugins/ants/hooks/on-post-edit-shellcheck.sh` -- validate syntax
2. `chmod +x plugins/ants/hooks/on-post-edit-shellcheck.sh` -- make executable
3. `jq empty plugins/ants/hooks/hooks.json` -- validate JSON
4. Test manually:
   ```bash
   echo '#!/bin/bash\nif true; then' > /tmp/bad.sh
   echo '{"tool_input":{"file_path":"/tmp/bad.sh"}}' | \
     CLAUDE_PROJECT_DIR="$(pwd)" bash plugins/ants/hooks/on-post-edit-shellcheck.sh
   ```

### Common Pitfalls

- **Using exit 2 in PostToolUse** -- PostToolUse hooks cannot block actions (the tool already executed). Exit 2 in a PostToolUse hook is treated as a non-blocking error, not a block. Use `additionalContext` in the JSON output to provide feedback instead.
- **Forgetting `check_ants_workflow`** -- Without the workflow guard, the hook fires for every Edit/Write in any conversation, even outside ants workflows. This causes confusing errors when there is no `state.json`.
- **Using `local var="$(cmd)"`** -- This masks the exit code of `cmd` under `set -e`. Always separate the `local` declaration from the assignment: `local var; var="$(cmd)"`. (In this example, we use direct assignment without `local` inside the main script body, which is also acceptable.)
- **Missing `timeout` in hooks.json** -- Without a timeout, a hung hook blocks Claude indefinitely. Always set a timeout (5 seconds is typical for fast checks, 10-15 for heavier validation).
- **Confusing PreToolUse and PostToolUse** -- PreToolUse can block with `permissionDecision: "deny"`. PostToolUse cannot block at all. Choose the right event for your use case: block before the action (PreToolUse) or advise after (PostToolUse).
