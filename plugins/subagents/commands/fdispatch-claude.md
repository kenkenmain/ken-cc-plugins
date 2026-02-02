---
description: Fast dispatch - streamlined 4-phase workflow with combined plan+implement+review (Claude-only, no Codex MCP)
argument-hint: <task description> [--no-worktree] [--no-web-search]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Fast Dispatch Subagent Workflow (Claude-Only)

Streamlined workflow that collapses 13 phases into 4 for faster execution. Uses Claude agents only — no Codex MCP dependency.

## Arguments

- `<task description>`: Required. The task to execute
- `--no-worktree`: Optional. Skip git worktree creation
- `--no-web-search`: Optional. Disable web search for libraries

Parse from $ARGUMENTS to extract task description and flags.

## Step 1: Load Configuration

Use the `configuration` skill to load merged config (defaults → global → project).

## Step 2: Initialize State Inline

fdispatch-claude does NOT use `subagents:init-claude`. All initialization is done inline to avoid wasting an opus-level dispatch on work that gets immediately overwritten.

### 2a. Create directories

```bash
mkdir -p .agents/tmp/phases
rm -f .agents/tmp/phases/*.tmp   # Clean stale temp files from previous runs
```

### 2b. Capture session PID

```bash
echo $PPID
```

Store the output as `ownerPpid`.

### 2c. Create git worktree (unless `--no-worktree`)

```bash
# Slugify task: lowercase, strip non-alphanum, spaces→hyphens, truncate 50 chars
SLUG=$(echo "<task>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 -]//g' | tr ' ' '-' | cut -c1-50)
BRANCH="subagents/${SLUG}"
REPO_NAME=$(basename "$(pwd)")
WORKTREE_PATH="../${REPO_NAME}--subagent"
git worktree add -b "$BRANCH" "$WORKTREE_PATH"
```

If creation fails (branch exists, path occupied), log a warning and continue without worktree. Store the absolute worktree path if successful.

### 2d. Write `state.json` directly

Write `.agents/tmp/state.json` with **only** the fields F-phases and hooks actually read. Use Bash with jq for atomic write (write to `.agents/tmp/state.json.tmp`, then `mv` into place).

```json
{
  "version": 2,
  "plugin": "subagents",
  "pipeline": "fdispatch",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "stoppedAt": null,
  "currentPhase": "F1",
  "currentStage": "PLAN",
  "ownerPpid": "<PPID value>",
  "codexAvailable": false,
  "worktree": "<{ path, branch, createdAt } if created, omit if --no-worktree or failed>",
  "schedule": [
    { "phase": "F1", "stage": "PLAN", "name": "Fast Plan", "type": "subagent" },
    { "phase": "F2", "stage": "IMPLEMENT", "name": "Implement + Test", "type": "dispatch" },
    { "phase": "F3", "stage": "REVIEW", "name": "Parallel Review", "type": "dispatch" },
    { "phase": "F4", "stage": "COMPLETE", "name": "Completion", "type": "subagent" }
  ],
  "gates": {
    "PLAN->IMPLEMENT": { "required": ["f1-plan.md"], "phase": "F1" },
    "IMPLEMENT->REVIEW": { "required": ["f2-tasks.json"], "phase": "F2" },
    "REVIEW->COMPLETE": { "required": ["f3-review.json"], "phase": "F3" },
    "COMPLETE->DONE": { "required": ["f4-completion.json"], "phase": "F4" }
  },
  "stages": {
    "PLAN": { "status": "pending" },
    "IMPLEMENT": { "status": "pending" },
    "REVIEW": { "status": "pending" },
    "COMPLETE": { "status": "pending" }
  },
  "webSearch": true,
  "supplementaryPolicy": "on-issues",
  "coverageThreshold": 90,
  "reviewPolicy": {
    "maxFixAttempts": 3,
    "maxStageRestarts": 1
  },
  "restartHistory": [],
  "files": [],
  "failure": null,
  "compaction": null
}
```

If `--no-web-search` flag is set, set `"webSearch": false`.

**Note:** No `codexTimeout` block — not needed without Codex MCP.

## Step 2.5: Display Schedule

Show the user the planned execution order:

```
Fast Dispatch Schedule (4 phases) [Claude-only mode]
======================================================
Phase F1   │ PLAN      │ Fast Plan (explore+brainstorm+plan)  │ subagent   ← GATE: PLAN→IMPLEMENT
Phase F2   │ IMPLEMENT │ Implement + Test                     │ dispatch   ← GATE: IMPLEMENT→REVIEW
Phase F3   │ REVIEW    │ Parallel Review (5 reviewers)        │ dispatch   ← GATE: REVIEW→COMPLETE
           │           │ (fix cycle runs within F3 if needed) │
Phase F4   │ COMPLETE  │ Completion (commit + PR)             │ subagent

Stage Gates:
  PLAN → IMPLEMENT:  requires f1-plan.md
  IMPLEMENT → REVIEW: requires f2-tasks.json
  REVIEW → COMPLETE:  requires f3-review.json
```

## Step 3: Execute Workflow

Use `workflow` skill to dispatch the first phase (F1) as a subagent. Hook-driven auto-chaining handles progression.

## Step 4: Display Progress

Use TaskCreate/TaskUpdate for visual progress tracking.
