---
description: Resume a stopped subagent workflow from checkpoint
argument-hint: [--from-phase X.X] [--retry-failed]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, mcp__codex-high__codex, mcp__codex-xhigh__codex
---

# Resume Subagent Workflow

Resume a previously stopped or failed workflow from the last checkpoint.

## Arguments

- `--from-phase X.X`: Optional. Override resume point to specific phase (e.g., `--from-phase 2.1`)
- `--retry-failed`: Optional. Retry the failed phase/task if workflow is in failed state

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

## Step 2: Check Workflow Status

Handle different statuses:

**status: "completed"**

```
Workflow already completed at {updatedAt}.
Nothing to resume. Start a new workflow with: /subagents:dispatch <task>
```

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

```
Resuming Subagent Workflow
==========================
Task: {task}
Originally started: {startedAt}
Last updated: {updatedAt}

Resuming from: {currentStage} Stage → Phase {currentPhase}

Stage Progress:
- EXPLORE: {stages.EXPLORE.status}
- PLAN: {stages.PLAN.status}
- IMPLEMENT: {stages.IMPLEMENT.status}
- TEST: {stages.TEST.status} {stages.TEST.enabled ? '' : '(disabled)'}
- FINAL: {stages.FINAL.status}
```

## Step 6: Continue Workflow

1. Update state via `state-manager`:
   - Set `status: "in_progress"`
   - Clear `failure` if retrying
   - Set `updatedAt: now()`

2. Use `workflow` skill to continue from current position:
   - Read phase output files from `state.files`
   - Continue stage execution
   - Handle compaction settings
