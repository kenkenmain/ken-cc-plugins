---
description: Resume a stopped subagent workflow from checkpoint
argument-hint: [--from-phase X.X]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Resume Subagent Workflow

Resume a previously stopped workflow from the last checkpoint.

## Arguments

- `--from-phase X.X`: Optional. Override resume point to specific phase (e.g., `--from-phase 2.1`)

Parse from $ARGUMENTS.

## Step 1: Load State

Read `.agents/subagents-state.json`. If not found or corrupt, display error and exit.

## Step 2: Handle --from-phase

Validate phase, update state, confirm with user (warn about lost progress).

## Step 3: Reload Configuration

Reload merged config (defaults → global → project).

## Step 4: Display Resume Point

```
Resuming Subagent Workflow
==========================
Task: <task description>
Originally started: <startedAt>
Stopped at: <stoppedAt>

Resuming from: <STAGE> Stage → Phase <X.X> (<phase name>)
```

## Step 5: Continue Workflow

Update state (status=in_progress, clear stoppedAt). Invoke `orchestration` skill with current position, config, and previous stage outputs.
