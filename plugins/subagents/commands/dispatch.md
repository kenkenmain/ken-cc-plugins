---
description: Start a hierarchical subagent workflow for complex task execution
argument-hint: <task description> [--no-test] [--stage STAGE] [--plan PATH]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Dispatch Subagent Workflow

Start a 4-tier hierarchical agent workflow for complex task execution with context isolation.

## Arguments

- `<task description>`: Required. The task to execute (e.g., "Add user authentication with OAuth")
- `--no-test`: Optional. Skip the TEST stage
- `--stage STAGE`: Optional. Start from a specific stage (PLAN, IMPLEMENT, TEST, FINAL)
- `--plan PATH`: Optional. Specify plan file path (required when --stage skips PLAN and no prior state exists)

Parse from $ARGUMENTS to extract task description and flags.

## Step 1: Load Configuration

Use the `configuration` skill to load merged config (defaults → global → project).

## Step 2: Initialize State

Create `.agents/subagents-state.json`:

```json
{
  "task": "<task description>",
  "currentStage": "PLAN",
  "currentPhase": "1.1",
  "planFilePath": null,
  "stages": { "PLAN": { "status": "pending" }, ... }
}
```

Set `TEST.enabled: false` if `--no-test`. Note: `planFilePath` is null until Phase 1.2 creates the plan file.

## Step 3: Handle --stage

Validate stage name, set currentStage and currentPhase to specified stage's first phase.

**If --stage skips PLAN (IMPLEMENT/TEST/FINAL):**

1. If `--plan PATH` provided: use that path
2. Else if `.agents/subagents-state.json` exists with non-null `planFilePath`: use existing state
3. Else: use AskUserQuestion to request plan file path from user
4. Validate the provided path exists before proceeding
5. Set `planFilePath` in initial state

## Step 4: Invoke Orchestration

Invoke `orchestration` skill with task, current stage/phase, and config. Orchestrator dispatches stage → phase → task agents, with results aggregating upward.

## Step 5: Display Progress

Use TaskCreate/TaskUpdate for progress tracking. Show task, mode, and current stage/phase.
