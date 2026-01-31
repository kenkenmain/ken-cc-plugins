---
description: Start a kenken iterative development workflow
argument-hint: <task description> [--no-test] [--stage STAGE] [--plan PATH]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# kenken Iterate Workflow

Start a 4-stage iterative development workflow with 14 phases, hook-driven auto-chaining, and stage gates.

## Arguments

- `<task description>`: Required. The task to execute
- `--no-test`: Optional. Skip the TEST stage (phases 3.1-3.5)
- `--stage STAGE`: Optional. Start from specific stage (PLAN, IMPLEMENT, TEST, FINAL)
- `--plan PATH`: Optional. Specify plan file path (for starting at IMPLEMENT with external plan)

Parse from $ARGUMENTS to extract task description and flags.

## Step 1: Load Configuration

Use the `iterate-configure` skill to load merged config (defaults -> global -> project).

Config sources:
1. Hardcoded defaults
2. Global: `~/.claude/kenken-config.json`
3. Project: `.claude/kenken-config.json`

## Step 2: Initialize State

Create `.agents/tmp/kenken/state.json` and `.agents/tmp/kenken/phases/` directory.

Build the `schedule` array from the full 14-phase list, filtering out disabled stages:

1. Start with the full 14-phase list (see schema below)
2. If `--no-test` or `config.stages.test.enabled: false`: remove phases 3.1, 3.2, 3.3, 3.4, 3.5
3. Build the `gates` map, adjusting for disabled stages:
   - If TEST disabled: replace `IMPLEMENT->TEST` and `TEST->FINAL` with a single `IMPLEMENT->FINAL` gate requiring `2.1-tasks.json` and `2.3-impl-review.json`
   - Gate `required` files always reference key output artifacts from the source stage

```json
{
  "version": 2,
  "plugin": "kenken",
  "task": "<task description>",
  "status": "in_progress",
  "currentStage": "PLAN",
  "currentPhase": "1.1",
  "schedule": [
    { "phase": "1.1", "stage": "PLAN",      "name": "Brainstorm",       "type": "dispatch" },
    { "phase": "1.2", "stage": "PLAN",      "name": "Plan",             "type": "dispatch" },
    { "phase": "1.3", "stage": "PLAN",      "name": "Plan Review",      "type": "review" },
    { "phase": "2.1", "stage": "IMPLEMENT", "name": "Implementation",   "type": "dispatch" },
    { "phase": "2.2", "stage": "IMPLEMENT", "name": "Simplify",         "type": "subagent" },
    { "phase": "2.3", "stage": "IMPLEMENT", "name": "Impl Review",      "type": "review" },
    { "phase": "3.1", "stage": "TEST",      "name": "Test Plan",        "type": "subagent" },
    { "phase": "3.2", "stage": "TEST",      "name": "Write Tests",      "type": "subagent" },
    { "phase": "3.3", "stage": "TEST",      "name": "Coverage",         "type": "command" },
    { "phase": "3.4", "stage": "TEST",      "name": "Run Tests",        "type": "command" },
    { "phase": "3.5", "stage": "TEST",      "name": "Test Review",      "type": "review" },
    { "phase": "4.1", "stage": "FINAL",     "name": "Final Review",     "type": "review" },
    { "phase": "4.2", "stage": "FINAL",     "name": "Extensions",       "type": "subagent" },
    { "phase": "4.3", "stage": "FINAL",     "name": "Completion",       "type": "subagent" }
  ],
  "gates": {
    "PLAN->IMPLEMENT": {
      "required": ["1.2-plan.md", "1.3-plan-review.json"],
      "phase": "1.3"
    },
    "IMPLEMENT->TEST": {
      "required": ["2.1-tasks.json", "2.3-impl-review.json"],
      "phase": "2.3"
    },
    "TEST->FINAL": {
      "required": ["3.4-test-results.json", "3.5-test-review.json"],
      "phase": "3.5"
    },
    "FINAL->COMPLETE": {
      "required": ["4.1-final-review.json"],
      "phase": "4.1"
    }
  },
  "stages": {
    "PLAN":      { "status": "pending", "phases": {}, "restartCount": 0, "blockReason": null },
    "IMPLEMENT": { "status": "pending", "phases": {}, "restartCount": 0, "blockReason": null },
    "TEST":      { "status": "pending", "enabled": true, "phases": {}, "restartCount": 0, "blockReason": null },
    "FINAL":     { "status": "pending", "phases": {}, "restartCount": 0, "blockReason": null }
  },
  "files": {},
  "failure": null,
  "loopIteration": 0,
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
kenken Workflow Schedule (14 phases)
=====================================
Phase 1.1 | PLAN      | Brainstorm       | dispatch
Phase 1.2 | PLAN      | Plan             | dispatch
Phase 1.3 | PLAN      | Plan Review      | review    <- GATE: PLAN->IMPLEMENT
Phase 2.1 | IMPLEMENT | Implementation   | dispatch
Phase 2.2 | IMPLEMENT | Simplify         | subagent
Phase 2.3 | IMPLEMENT | Impl Review      | review    <- GATE: IMPLEMENT->TEST
Phase 3.1 | TEST      | Test Plan        | subagent
Phase 3.2 | TEST      | Write Tests      | subagent
Phase 3.3 | TEST      | Coverage         | command
Phase 3.4 | TEST      | Run Tests        | command
Phase 3.5 | TEST      | Test Review      | review    <- GATE: TEST->FINAL
Phase 4.1 | FINAL     | Final Review     | review    <- GATE: FINAL->COMPLETE
Phase 4.2 | FINAL     | Extensions       | subagent
Phase 4.3 | FINAL     | Completion       | subagent

Stage Gates:
  PLAN -> IMPLEMENT:  requires 1.2-plan.md, 1.3-plan-review.json
  IMPLEMENT -> TEST:  requires 2.1-tasks.json, 2.3-impl-review.json
  TEST -> FINAL:      requires 3.4-test-results.json, 3.5-test-review.json
  FINAL -> COMPLETE:  requires 4.1-final-review.json
```

If TEST stage is disabled, show `(skipped)` for those phases and omit the `IMPLEMENT->TEST` and `TEST->FINAL` gates; show `IMPLEMENT->FINAL` instead.

## Step 3: Handle --stage and --plan

If `--stage` provided:

1. Validate stage name (PLAN, IMPLEMENT, TEST, FINAL)
2. Check if required prior state exists:
   - IMPLEMENT requires plan file (see below)
   - TEST requires completed IMPLEMENT stage
   - FINAL requires completed TEST stage (or TEST disabled)
3. Set currentStage and currentPhase appropriately:
   - PLAN -> phase 1.1
   - IMPLEMENT -> phase 2.1
   - TEST -> phase 3.1
   - FINAL -> phase 4.1

**If --stage IMPLEMENT or later:**

1. If `--plan PATH` provided: use that path, copy to `.agents/tmp/kenken/phases/1.2-plan.md`
2. Else if `.agents/tmp/kenken/phases/1.2-plan.md` exists: use existing plan
3. Else: use AskUserQuestion to request plan file path from user
4. Validate the plan file exists before proceeding

## Step 4: Execute Workflow

Use `iterate` skill to dispatch the first phase as a subagent. Hook-driven auto-chaining handles progression:

```
Phase dispatched -> SubagentStop hook validates -> advances state -> exits silently
Claude tries to stop -> Stop hook re-injects full orchestrator prompt -> repeat
```

Each phase:

1. Reads prompt template from `prompts/phases/{phase}-*.md`
2. Reads input files from previous phases
3. Dispatches as subagent with `[PHASE {id}]` tag
4. SubagentStop hook validates output and advances state
5. Stop hook blocks exit and re-injects orchestrator prompt
6. Orchestrator reads updated state and dispatches next phase

### Phase 4.2 Extension Loop-Back

Phase 4.2 (Extensions) can loop back to phase 1.1 if the user accepts a suggested extension. The SubagentStop hook detects this and resets the schedule to restart from PLAN stage with the new extension task.

## Step 5: Display Progress

Use TaskCreate/TaskUpdate for visual progress tracking:

- Create task for overall workflow
- Update task as stages complete
- Show current stage/phase in task description
