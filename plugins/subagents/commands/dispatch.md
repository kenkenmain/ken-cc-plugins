---
description: Start a subagent workflow for complex task execution
argument-hint: <task description> [--no-test] [--stage STAGE] [--plan PATH]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Dispatch Subagent Workflow

Start a workflow for complex task execution with parallel subagents and file-based state.

## Arguments

- `<task description>`: Required. The task to execute
- `--no-test`: Optional. Skip the TEST stage
- `--stage STAGE`: Optional. Start from specific stage (EXPLORE, PLAN, IMPLEMENT, TEST, FINAL)
- `--plan PATH`: Optional. Specify plan file path (for starting at IMPLEMENT with external plan)

Parse from $ARGUMENTS to extract task description and flags.

## Step 1: Load Configuration

Use the `configuration` skill to load merged config (defaults → global → project).

## Step 2: Initialize State

Use `state-manager` skill to create `.agents/tmp/state.json`:

```json
{
  "version": 2,
  "task": "<task description>",
  "status": "in_progress",
  "currentStage": "EXPLORE",
  "currentPhase": "0",
  "stages": {
    "EXPLORE": { "status": "pending", "agentCount": 0 },
    "PLAN": { "status": "pending", "phases": {}, "restartCount": 0 },
    "IMPLEMENT": { "status": "pending", "phases": {}, "restartCount": 0 },
    "TEST": { "status": "pending", "enabled": true, "restartCount": 0 },
    "FINAL": { "status": "pending", "restartCount": 0 }
  },
  "files": {},
  "failure": null,
  "compaction": { "lastCompactedAt": null, "history": [] },
  "startedAt": "<ISO timestamp>",
  "updatedAt": null,
  "stoppedAt": null
}
```

Set `stages.TEST.enabled: false` if `--no-test`.

## Step 3: Handle --stage and --plan

If `--stage` provided:

1. Validate stage name (EXPLORE, PLAN, IMPLEMENT, TEST, FINAL)
2. Check if required prior state exists:
   - IMPLEMENT requires plan file (see below)
   - TEST requires completed IMPLEMENT stage
   - FINAL requires completed TEST stage (or TEST disabled)
3. Set currentStage and currentPhase appropriately

**If --stage IMPLEMENT or later:**

1. If `--plan PATH` provided: use that path, copy to `.agents/tmp/phases/1.2-plan.md`
2. Else if `.agents/tmp/phases/1.2-plan.md` exists: use existing plan
3. Else: use AskUserQuestion to request plan file path from user
4. Validate the plan file exists before proceeding

## Step 4: Execute Workflow

Use `workflow` skill to execute stages sequentially:

```
EXPLORE → PLAN → IMPLEMENT → TEST → FINAL
```

Each stage:

1. Reads required files from previous stages
2. Dispatches parallel subagents as needed
3. Writes output to `.agents/tmp/phases/`
4. Updates state via `state-manager`
5. Compacts context (if configured)

## Step 5: Display Progress

Use TaskCreate/TaskUpdate for visual progress tracking:

- Create task for overall workflow
- Update task as stages complete
- Show current stage/phase in task description
