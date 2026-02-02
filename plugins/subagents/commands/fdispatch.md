---
description: Fast dispatch - streamlined 4-phase workflow with combined plan+implement+review (Codex MCP defaults)
argument-hint: <task description> [--no-worktree] [--no-web-search]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Fast Dispatch Subagent Workflow

Streamlined workflow that collapses 13 phases into 4 for faster execution.

## Arguments

- `<task description>`: Required. The task to execute
- `--no-worktree`: Optional. Skip git worktree creation
- `--no-web-search`: Optional. Disable web search for libraries

Parse from $ARGUMENTS to extract task description and flags.

## Step 1: Load Configuration

Use the `configuration` skill to load merged config (defaults → global → project).

## Step 1.5: Capture Session PID

```bash
echo $PPID
```

Pass this value as `ownerPpid` to the init agent.

## Step 2: Initialize State

Use `state-manager` skill to create `.agents/tmp/state.json`.

Dispatch `subagents:init-claude` with task description, ownerPpid, `codexMode: true`, and parsed flags (including `--no-worktree` if set). Additionally pass `pipeline: "fdispatch"` so the init agent knows to use the fast pipeline.

**IMPORTANT:** After the init agent writes state, **overwrite** the schedule, gates, and stages with the fdispatch-specific values below. The init agent creates the worktree and analyzes the task, but the fdispatch command controls the pipeline structure.

Update `.agents/tmp/state.json` with these values:

```json
{
  "pipeline": "fdispatch",
  "codexAvailable": true,
  "reviewer": "subagents:code-quality-reviewer",
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
  "currentPhase": "F1",
  "currentStage": "PLAN",
  "stages": {
    "PLAN": { "status": "pending" },
    "IMPLEMENT": { "status": "pending" },
    "REVIEW": { "status": "pending" },
    "COMPLETE": { "status": "pending" }
  },
  "reviewPolicy": {
    "maxFixAttempts": 3,
    "maxStageRestarts": 1
  }
}
```

## Step 2.5: Display Schedule

Show the user the planned execution order:

```
Fast Dispatch Schedule (4 phases)
===================================
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

## Step 3: Execute Workflow

Use `workflow` skill to dispatch the first phase (F1) as a subagent. Hook-driven auto-chaining handles progression:

```
Phase dispatched → SubagentStop hook validates → advances state → injects next phase → repeat
```

## Step 4: Display Progress

Use TaskCreate/TaskUpdate for visual progress tracking.
