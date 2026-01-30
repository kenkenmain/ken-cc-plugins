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

Use `state-manager` skill to create `.agents/tmp/state.json`.

Build the `schedule` array from the full phase list, filtering out disabled stages:

1. Start with the full 13-phase list (see state-manager skill for schema)
2. If `--no-test` or `config.stages.TEST.enabled: false`: remove phases 3.1, 3.2, 3.3
3. If any other stage is disabled in config: remove its phases
4. Build the `gates` map, adjusting for disabled stages:
   - If TEST disabled: replace `IMPLEMENT->TEST` and `TEST->FINAL` with a single `IMPLEMENT->FINAL` gate requiring `2.1-tasks.json` and `2.3-impl-review.json`
   - Gate `required` files always reference key output artifacts from the source stage

```json
{
  "version": 2,
  "task": "<task description>",
  "status": "in_progress",
  "currentStage": "EXPLORE",
  "currentPhase": "0",
  "schedule": [
    { "phase": "0", "stage": "EXPLORE", "name": "Explore", "type": "dispatch" },
    {
      "phase": "1.1",
      "stage": "PLAN",
      "name": "Brainstorm",
      "type": "subagent"
    },
    { "phase": "1.2", "stage": "PLAN", "name": "Plan", "type": "dispatch" },
    {
      "phase": "1.3",
      "stage": "PLAN",
      "name": "Plan Review",
      "type": "review"
    },
    {
      "phase": "2.1",
      "stage": "IMPLEMENT",
      "name": "Task Execution",
      "type": "dispatch"
    },
    {
      "phase": "2.2",
      "stage": "IMPLEMENT",
      "name": "Simplify",
      "type": "subagent"
    },
    {
      "phase": "2.3",
      "stage": "IMPLEMENT",
      "name": "Implementation Review",
      "type": "review"
    },
    { "phase": "3.1", "stage": "TEST", "name": "Run Tests", "type": "command" },
    {
      "phase": "3.2",
      "stage": "TEST",
      "name": "Analyze Failures",
      "type": "subagent"
    },
    {
      "phase": "3.3",
      "stage": "TEST",
      "name": "Test Review",
      "type": "review"
    },
    {
      "phase": "4.1",
      "stage": "FINAL",
      "name": "Documentation",
      "type": "subagent"
    },
    {
      "phase": "4.2",
      "stage": "FINAL",
      "name": "Final Review",
      "type": "review"
    },
    { "phase": "4.3", "stage": "FINAL", "name": "Completion", "type": "subagent" }
  ],
  "gates": {
    "EXPLORE->PLAN": { "required": ["0-explore.md"], "phase": "0" },
    "PLAN->IMPLEMENT": {
      "required": ["1.2-plan.md", "1.3-plan-review.json"],
      "phase": "1.3"
    },
    "IMPLEMENT->TEST": {
      "required": ["2.1-tasks.json", "2.3-impl-review.json"],
      "phase": "2.3"
    },
    "TEST->FINAL": {
      "required": ["3.1-test-results.json", "3.3-test-review.json"],
      "phase": "3.3"
    },
    "FINAL->COMPLETE": { "required": ["4.2-final-review.json"], "phase": "4.2" }
  },
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

## Step 2.5: Display Schedule

Show the user the planned execution order and gate checkpoints:

```
Workflow Schedule ({N} phases)
==============================
Phase 0   │ EXPLORE   │ Explore                 │ dispatch  ← GATE: EXPLORE→PLAN
Phase 1.1 │ PLAN      │ Brainstorm              │ subagent
Phase 1.2 │ PLAN      │ Plan                    │ dispatch
Phase 1.3 │ PLAN      │ Plan Review             │ review    ← GATE: PLAN→IMPLEMENT
Phase 2.1 │ IMPLEMENT │ Task Execution          │ dispatch
Phase 2.2 │ IMPLEMENT │ Simplify                │ subagent
Phase 2.3 │ IMPLEMENT │ Implementation Review   │ review    ← GATE: IMPLEMENT→TEST
Phase 3.1 │ TEST      │ Run Tests               │ command
Phase 3.2 │ TEST      │ Analyze Failures        │ subagent
Phase 3.3 │ TEST      │ Test Review             │ review    ← GATE: TEST→FINAL
Phase 4.1 │ FINAL     │ Documentation           │ subagent
Phase 4.2 │ FINAL     │ Final Review            │ review    ← GATE: FINAL→COMPLETE
Phase 4.3 │ FINAL     │ Completion              │ subagent

Stage Gates:
  EXPLORE → PLAN:    requires 0-explore.md
  PLAN → IMPLEMENT:  requires 1.2-plan.md, 1.3-plan-review.json
  IMPLEMENT → TEST:  requires 2.1-tasks.json, 2.3-impl-review.json
  TEST → FINAL:      requires 3.1-test-results.json, 3.3-test-review.json
  FINAL → COMPLETE:  requires 4.2-final-review.json
```

If any stages are disabled, show `(skipped)` for those phases and omit their gates.

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

Use `workflow` skill to dispatch the first phase as a subagent. Hook-driven auto-chaining handles progression:

```
Phase dispatched → SubagentStop hook validates → advances state → injects next phase → repeat
```

Each phase:

1. Reads prompt template from `prompts/phases/{phase}-*.md`
2. Reads input files from previous phases
3. Dispatches as subagent with `[PHASE {id}]` tag
4. SubagentStop hook validates output and advances state
5. Hook blocks stop and injects next-phase instruction
6. Orchestrator dispatches next phase

## Step 5: Display Progress

Use TaskCreate/TaskUpdate for visual progress tracking:

- Create task for overall workflow
- Update task as stages complete
- Show current stage/phase in task description
