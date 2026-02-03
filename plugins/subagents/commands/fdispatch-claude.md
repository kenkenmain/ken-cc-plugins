---
description: Fast dispatch - streamlined 4-phase workflow with combined plan+implement+review (Claude-only, no Codex MCP)
argument-hint: <task description> [--worktree] [--no-web-search]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Fast Dispatch Subagent Workflow (Claude-Only)

Streamlined workflow that collapses 13 phases into 4 for faster execution. Uses Claude agents only — no Codex MCP dependency.

## Arguments

- `<task description>`: Required. The task to execute
- `--worktree`: Optional. Create a git worktree for isolated development
- `--no-worktree`: Accepted for backward compatibility (no-op — no worktree is the default)
- `--no-web-search`: Optional. Disable web search for libraries

Parse from $ARGUMENTS to extract task description and flags.

## Step 0: Check for Pre-Initialized State

A `UserPromptSubmit` hook (`on-fdispatch-init.sh`) runs BEFORE this command and may have already completed state initialization. Check for the marker:

- If you see "FDISPATCH STATE PRE-INITIALIZED" in the context:
  - **Skip Steps 1, 2a, 2b, 2d** (config, dirs, PID, state.json — already done by hook).
  - **If `--worktree` was requested**, still execute Step 2c (worktree creation) and update `state.json` with the worktree field.
  - Then proceed to Step 2.5 (display schedule).
- If no pre-initialization marker is present (hook failed or was disabled), continue with Steps 1-2 below as normal.

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

### 2c. Create git worktree (only if `--worktree`)

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
  "agents": {
    "f1": "subagents:fast-planner",
    "f3Primary": "subagents:code-quality-reviewer",
    "f3Supplementary": [
      "subagents:error-handling-reviewer",
      "subagents:type-reviewer",
      "subagents:test-coverage-reviewer",
      "subagents:comment-reviewer"
    ],
    "f4": "subagents:completion-handler"
  },
  "worktree": "<{ path, branch, createdAt } if --worktree and creation succeeded, omit otherwise>",
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

## Step 3: Initialize Task List

Create tasks for each phase using TaskCreate so the user can track progress visually. Create all 4 tasks, then set dependencies so they reflect the workflow order:

1. **TaskCreate:** "Execute F1: Fast Plan" (activeForm: "Planning implementation")
2. **TaskCreate:** "Execute F2: Implement + Test" (activeForm: "Implementing tasks")
3. **TaskCreate:** "Execute F3: Parallel Review" (activeForm: "Reviewing implementation")
4. **TaskCreate:** "Execute F4: Completion" (activeForm: "Completing workflow")

After creating all tasks, use TaskUpdate to set `addBlockedBy` dependencies:
- F2 task is blocked by F1 task
- F3 task is blocked by F2 task
- F4 task is blocked by F3 task

As each phase starts, mark its task `in_progress`. When a phase completes, mark its task `completed`.

**Resume handling:** Before creating tasks, check if tasks already exist via TaskList. If they do (e.g., after a restart), skip creation and reuse existing task IDs.

## Step 4: Execute Workflow

Use `workflow` skill to dispatch the first phase (F1) as a subagent. Mark the F1 task as `in_progress` before dispatching. Hook-driven auto-chaining handles progression.

If hooks do not auto-chain (context compaction, manual orchestration), dispatch phases manually.

**Before manual dispatch:** Verify `state.currentPhase` has NOT already advanced (read `.agents/tmp/state.json`). If the phase already advanced, the hook already chained — do not double-dispatch.

### Phase Agent Selection

**Read agent names from `state.agents`** in `.agents/tmp/state.json`. Never hardcode or guess agent names.

- **F1:** dispatch `state.agents.f1`
- **F2:** dispatch `opus-task-agent` for all tasks
- **F3 primary:** dispatch `state.agents.f3Primary`
- **F3 supplementary:** dispatch each agent in `state.agents.f3Supplementary[]`
- **F4:** dispatch `state.agents.f4`

**F3 supplementary policy:** Check `state.supplementaryPolicy`. If `"on-issues"` (default), dispatch only `state.agents.f3Primary` first. Dispatch `state.agents.f3Supplementary` only if the primary finds issues. If `"always"`, dispatch all in parallel.

Each phase has a prompt template in `prompts/phases/` (e.g., `f3-parallel-review.md`). Read the template before dispatching.

### Task Progress Tracking

When dispatching each phase, update the corresponding task:
- Mark `in_progress` before dispatching
- Mark `completed` after the phase output file is written and validated
