---
description: Resume a stopped subagent workflow from checkpoint
argument-hint: [--from-phase X.X] [--retry-failed] [--restart-stage] [--restart-previous]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Resume Subagent Workflow

Resume a previously stopped or failed workflow from the last checkpoint.

## Arguments

- `--from-phase X.X`: Optional. Override resume point to specific phase (e.g., `--from-phase 2.1`)
- `--retry-failed`: Optional. Retry the failed phase/task if workflow is in failed state
- `--restart-stage`: Optional. Restart current stage from first phase
- `--restart-previous`: Optional. Restart previous stage (for fixing root cause errors)

Parse from $ARGUMENTS.

## Step 1: Load State

Read `.agents/tmp/state.json` using `state-manager` skill.

If not found:

```
No workflow state found at .agents/tmp/state.json
Start a new workflow with: /subagents:dispatch <task>
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
State file missing schedule. This state was created before schedule support.
Re-create with: /subagents:dispatch <task>
Or use: /subagents:resume --from-phase X.X to continue without schedule
```

## Step 2: Check Workflow Status

Handle each status:

**status: "stopped"** → Normal resume case. Proceed to Step 3.

**status: "in_progress"**

```
Workflow is already running (status: in_progress).
If this is stale, use /subagents:stop first, then resume.
```

**status: "pending"**

```
Workflow has not started yet. Use /subagents:dispatch <task> to begin.
```

**status: "completed"**

```
Workflow already completed at {updatedAt}.
Nothing to resume. Start a new workflow with: /subagents:dispatch <task>
```

**status: "blocked"**

```
Workflow is blocked at {currentStage} Stage → Phase {currentPhase}.
Reason: {stages[currentStage].blockReason}

Options:
1. Restart current stage (--restart-stage)
2. Restart previous stage (--restart-previous)
3. Abort and start fresh
```

Use AskUserQuestion to choose option.

**status: "restarting"** → Stage restart was interrupted. Continue the restart from Step 3.

**status: "failed"**

```
Workflow failed at Phase {failure.phase}: {failure.error}
Failed at: {failure.failedAt}

Context:
- Completed tasks: {failure.context.completedTasks}
- Failed task: {failure.context.failedTask}
- Pending tasks: {failure.context.pendingTasks}

Options:
1. Retry failed phase (--retry-failed)
2. Skip to next phase (--from-phase X.X)
3. Abort and start fresh
```

Use AskUserQuestion if `--retry-failed` not specified.

## Step 3: Handle --from-phase

If provided:

1. Validate phase exists (0, 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 4.1, 4.2, 4.3)
2. Check if required prior outputs exist
3. Warn about skipped phases
4. Confirm with user via AskUserQuestion
5. Update state with new currentStage/currentPhase

## Step 4: Reload Configuration

Use `configuration` skill to reload merged config (defaults → global → project).
Config may have changed since workflow started.

## Step 5: Display Resume Point

Read `state.schedule` and display per-phase progress:

```
Resuming Subagent Workflow
==========================
Task: {task}
Originally started: {startedAt}
Last updated: {updatedAt}

Schedule Progress:
  ✓ Phase 0   │ EXPLORE   │ Explore                 │ completed
  ✓ Phase 1.1 │ PLAN      │ Brainstorm              │ completed
  ✓ Phase 1.2 │ PLAN      │ Plan                    │ completed
  ✗ Phase 1.3 │ PLAN      │ Plan Review             │ BLOCKED     [GATE]
  · Phase 2.1 │ IMPLEMENT │ Task Execution          │ pending
  · Phase 2.2 │ IMPLEMENT │ Simplify                │ pending
  · Phase 2.3 │ IMPLEMENT │ Implementation Review   │ pending     [GATE]
  · Phase 3.1 │ TEST      │ Run Tests               │ pending
  · Phase 3.2 │ TEST      │ Analyze Failures        │ pending
  · Phase 3.3 │ TEST      │ Test Review             │ pending     [GATE]
  · Phase 4.1 │ FINAL     │ Documentation           │ pending
  · Phase 4.2 │ FINAL     │ Final Review            │ pending     [GATE]
  · Phase 4.3 │ FINAL     │ Completion              │ pending

Gate Status:
  PLAN → IMPLEMENT:  ✗ missing 1.3-plan-review.json
  IMPLEMENT → TEST:  · pending
  TEST → FINAL:      · pending
  FINAL → COMPLETE:  · pending

Resuming from: Phase {currentPhase} ({schedule entry name})
```

Status symbols: ✓ completed, ▶ in_progress, ✗ failed/blocked, · pending
Show `[GATE]` marker on phases that produce gate artifacts (type: "review").
Show actual gate file status (✓ file exists, ✗ missing, · pending).

## Step 6: Continue Workflow

1. Update state via `state-manager`:
   - Set `status: "in_progress"`
   - Clear `failure` if retrying
   - Set `updatedAt: now()`

2. Use `workflow` skill to continue from current position:
   - Read phase output files from `state.files`
   - Continue stage execution
   - Handle compaction settings
