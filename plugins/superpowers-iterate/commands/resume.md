---
description: Resume a stopped iteration workflow from checkpoint
argument-hint: [--from-phase N] [--retry-failed]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Resume Iteration Workflow

Resume a previously stopped or failed iteration workflow from the last checkpoint.

## Arguments

- `--from-phase N`: Optional. Override resume point to specific phase (e.g., `--from-phase 4`)
- `--retry-failed`: Optional. Retry the failed phase if workflow is in failed state

Parse from $ARGUMENTS.

## Step 1: Load State

Read `.agents/tmp/iterate/state.json` directly.

If not found:

```
No workflow state found at .agents/tmp/iterate/state.json
Start a new workflow with: /superpowers-iterate:iterate <task>
```

If corrupt or invalid version:

```
Invalid or corrupt state file. Version: {version}, expected: 2
Options:
1. Delete state and start fresh
2. Manually repair state file
```

If `state.schedule` is missing or empty:

```
State file missing schedule. This state was created before v2 schedule support.
Re-create with: /superpowers-iterate:iterate <task>
Or use: /superpowers-iterate:resume --from-phase N to continue without schedule
```

## Step 2: Check Workflow Status

Handle each status:

**status: "stopped"** -> Normal resume case. Proceed to Step 3.

**status: "in_progress"**

```
Workflow is already running (status: in_progress).
If this is stale, use /superpowers-iterate:stop first, then resume.
```

**status: "pending"**

```
Workflow has not started yet. Use /superpowers-iterate:iterate <task> to begin.
```

**status: "completed"**

```
Workflow already completed at {updatedAt}.
Nothing to resume. Start a new workflow with: /superpowers-iterate:iterate <task>
```

**status: "failed"**

```
Workflow failed at Phase {failure.phase}: {failure.error}
Failed at: {failure.failedAt}

Options:
1. Retry failed phase (--retry-failed)
2. Skip to next phase (--from-phase N)
3. Abort and start fresh
```

Use AskUserQuestion if `--retry-failed` not specified.

## Step 3: Handle --from-phase

If provided:

1. Validate phase exists in the schedule (1, 2, 3, 4, 5, 6, 7, 8, 9, C)
2. Check if required prior outputs exist in `.agents/tmp/iterate/phases/`
3. Warn about skipped phases
4. Confirm with user via AskUserQuestion
5. Update state with new `currentPhase` and `currentStage` (look up stage from schedule)

## Step 4: Reload Configuration

Use `configuration` skill to reload merged config (defaults -> global -> project).
Config may have changed since workflow started.

## Step 5: Display Resume Point

Read `state.schedule` and display per-phase progress:

```
Resuming Iteration Workflow
============================
Task: {task}
Mode: {mode}
Iteration: {currentIteration} of {maxIterations}
Originally started: {startedAt}
Last updated: {updatedAt}

Schedule Progress:
  * Phase 1 | PLAN      | Brainstorm    | completed
  * Phase 2 | PLAN      | Plan          | completed
  x Phase 3 | PLAN      | Plan Review   | BLOCKED      [GATE]
  . Phase 4 | IMPLEMENT | Implement     | pending
  . Phase 5 | IMPLEMENT | Review        | pending      [GATE]
  . Phase 6 | TEST      | Run Tests     | pending
  . Phase 7 | IMPLEMENT | Simplify      | pending
  . Phase 8 | REVIEW    | Final Review  | pending      [GATE]
  . Phase 9 | FINAL     | Codex Final   | pending
  . Phase C | FINAL     | Completion    | pending      [GATE]

Gate Status:
  PLAN -> IMPLEMENT:  x missing 3-plan-review.json
  IMPLEMENT -> TEST:  . pending
  REVIEW -> FINAL:    . pending
  FINAL -> COMPLETE:  . pending

Resuming from: Phase {currentPhase} ({schedule entry name})
```

Status symbols: `*` completed, `>` in_progress, `x` failed/blocked, `.` pending
Show `[GATE]` marker on phases that produce gate artifacts (type: "review").
Show actual gate file status (`*` file exists, `x` missing, `.` pending).

## Step 6: Continue Workflow

1. Update state directly:
   - Set `status: "in_progress"`
   - Clear `stoppedAt`
   - Clear `failure` if retrying
   - Set `updatedAt: now()`

2. Use `iteration-workflow` skill to dispatch the current phase as a subagent:
   - Read prompt template from `prompts/phases/{phase}-*.md`
   - Build subagent prompt with `[PHASE {id}]` and `[ITERATION {n}]` tags
   - Dispatch as Task tool call
   - SubagentStop hook handles validation, advancement, and auto-chaining
   - Stop hook re-injects orchestrator prompt for subsequent phases
