---
description: Start a subagent workflow for complex task execution
argument-hint: <task description> [--no-test] [--stage STAGE]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList, mcp__codex-high__codex, mcp__codex-xhigh__codex
---

# Dispatch Subagent Workflow

Start a workflow for complex task execution with parallel subagents and file-based state.

## Arguments

- `<task description>`: Required. The task to execute
- `--no-test`: Optional. Skip the TEST stage
- `--stage STAGE`: Optional. Start from specific stage (EXPLORE, PLAN, IMPLEMENT, TEST, FINAL)

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
    "PLAN": { "status": "pending", "phases": {} },
    "IMPLEMENT": { "status": "pending", "phases": {} },
    "TEST": { "status": "pending", "enabled": true },
    "FINAL": { "status": "pending" }
  },
  "files": {},
  "failure": null,
  "compaction": { "lastCompactedAt": null, "history": [] },
  "startedAt": "<ISO timestamp>",
  "updatedAt": null
}
```

Set `stages.TEST.enabled: false` if `--no-test`.

## Step 3: Handle --stage

If `--stage` provided:

1. Validate stage name (EXPLORE, PLAN, IMPLEMENT, TEST, FINAL)
2. Check if required prior state exists:
   - IMPLEMENT requires `.agents/tmp/phases/1.2-plan.md`
   - TEST requires completed IMPLEMENT stage
   - FINAL requires completed TEST stage (or TEST disabled)
3. Set currentStage and currentPhase appropriately

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
