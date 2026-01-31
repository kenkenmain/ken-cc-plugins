---
description: Start iterative 10-phase workflow for a task (brainstorm->plan->plan-review->implement->review->test->simplify->final-review->codex-final->completion)
argument-hint: [--lite] [--max-iterations N] <task-description>
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Iteration Workflow

Start a 10-phase iterative workflow for: **$ARGUMENTS**

## Arguments

- `<task description>`: Required. The task to execute
- `--lite`: Optional. Use lite mode (no Codex required, excludes Phase 9 from schedule)
- `--max-iterations N`: Optional. Maximum iterations before stopping (default: 10)

Parse from $ARGUMENTS to extract task description and flags.

## Modes

- **Full (default):** Uses Codex MCP for Phases 3, 5, 8, 9. Schedule includes 10 phases (1-9 + C).
- **Lite (`--lite`):** Uses Claude reviews, excludes Phase 9. Schedule includes 9 phases (1-8 + C).

## Step 1: Load Configuration

Use the `configuration` skill to load merged config (defaults -> global -> project).

## Step 2: Initialize State

Create directories and write initial state to `.agents/tmp/iterate/state.json`.

```bash
mkdir -p .agents/tmp/iterate/phases
```

Build the `schedule` array from the 10-phase list, filtering based on mode:

1. Start with the full 10-phase list (1-9 + C)
2. If `--lite` flag: remove Phase 9 from schedule
3. Build the `gates` map for stage transitions

Write initial state:

```json
{
  "version": 2,
  "plugin": "superpowers-iterate",
  "task": "<task description>",
  "status": "in_progress",
  "mode": "full",
  "maxIterations": 10,
  "currentIteration": 1,
  "currentPhase": "1",
  "currentStage": "PLAN",
  "loopIteration": 0,
  "schedule": [
    { "phase": "1", "stage": "PLAN", "name": "Brainstorm", "type": "dispatch" },
    { "phase": "2", "stage": "PLAN", "name": "Plan", "type": "dispatch" },
    { "phase": "3", "stage": "PLAN", "name": "Plan Review", "type": "review" },
    { "phase": "4", "stage": "IMPLEMENT", "name": "Implement", "type": "dispatch" },
    { "phase": "5", "stage": "IMPLEMENT", "name": "Review", "type": "review" },
    { "phase": "6", "stage": "TEST", "name": "Run Tests", "type": "command" },
    { "phase": "7", "stage": "IMPLEMENT", "name": "Simplify", "type": "subagent" },
    { "phase": "8", "stage": "REVIEW", "name": "Final Review", "type": "review" },
    { "phase": "9", "stage": "FINAL", "name": "Codex Final", "type": "review" },
    { "phase": "C", "stage": "FINAL", "name": "Completion", "type": "subagent" }
  ],
  "gates": {
    "PLAN->IMPLEMENT": {
      "required": ["2-plan.md", "3-plan-review.json"],
      "phase": "3"
    },
    "IMPLEMENT->TEST": {
      "required": ["4-tasks.json", "5-review.json"],
      "phase": "5"
    },
    "REVIEW->FINAL": {
      "required": ["8-final-review.json"],
      "phase": "8"
    },
    "FINAL->COMPLETE": {
      "required": ["9-codex-final.json"],
      "phase": "9"
    }
  },
  "stages": {
    "PLAN": { "status": "pending", "phases": {} },
    "IMPLEMENT": { "status": "pending", "phases": {} },
    "TEST": { "status": "pending", "phases": {} },
    "REVIEW": { "status": "pending", "phases": {} },
    "FINAL": { "status": "pending", "phases": {} }
  },
  "files": {},
  "failure": null,
  "startedAt": "<ISO timestamp>",
  "updatedAt": null,
  "stoppedAt": null
}
```

**Lite mode adjustments:**

- Set `"mode": "lite"`
- Remove Phase 9 entry from `schedule`
- Adjust `REVIEW->FINAL` gate: set `"phase": "8"` (Phase 8 advances directly to Completion)
- Adjust `FINAL->COMPLETE` gate: change `required` to `["8-final-review.json"]` and set `"phase": "8"`

**Max iterations:** Set `maxIterations` to the value from `--max-iterations N` flag, or 10 if not specified.

## Step 2.5: Display Schedule

Show the user the planned execution order and gate checkpoints:

```
Iteration Workflow Schedule ({N} phases, {mode} mode)
=====================================================
Phase 1 | PLAN      | Brainstorm    | dispatch
Phase 2 | PLAN      | Plan          | dispatch
Phase 3 | PLAN      | Plan Review   | review   <- GATE: PLAN->IMPLEMENT
Phase 4 | IMPLEMENT | Implement     | dispatch
Phase 5 | IMPLEMENT | Review        | review   <- GATE: IMPLEMENT->TEST
Phase 6 | TEST      | Run Tests     | command
Phase 7 | IMPLEMENT | Simplify      | subagent
Phase 8 | REVIEW    | Final Review  | review   <- GATE: REVIEW->FINAL
Phase 9 | FINAL     | Codex Final   | review        (omitted in lite mode)
Phase C | FINAL     | Completion    | subagent <- GATE: FINAL->COMPLETE

Iteration Loop: Phases 1-8 repeat until Phase 8 finds zero issues or max {maxIterations} iterations.

Stage Gates:
  PLAN -> IMPLEMENT:  requires 2-plan.md, 3-plan-review.json
  IMPLEMENT -> TEST:  requires 4-tasks.json, 5-review.json
  REVIEW -> FINAL:    requires 8-final-review.json
  FINAL -> COMPLETE:  requires 9-codex-final.json (or 8-final-review.json in lite mode)
```

If `--lite` mode, show Phase 9 as `(skipped)` and adjust gate display.

## Step 3: Execute Workflow

Use the `iteration-workflow` skill to dispatch the first phase as a subagent. Hook-driven auto-chaining handles progression:

```
Phase dispatched -> SubagentStop hook validates -> advances state -> exits silently
Claude tries to stop -> Stop hook re-injects full orchestrator prompt
Claude reads state -> dispatches next phase -> repeat
```

Each phase:

1. Reads prompt template from `prompts/phases/{phase}-*.md`
2. Reads input files from previous phases
3. Dispatches as subagent with `[PHASE {id}]` and `[ITERATION {n}]` tags
4. SubagentStop hook validates output and advances state
5. Stop hook re-injects orchestrator prompt
6. Orchestrator dispatches next phase

The iteration loop (Phases 1-8 repeating) is handled entirely by the SubagentStop hook at Phase 8. The orchestrator just dispatches whatever `currentPhase` the state file says.

## Step 4: Display Progress

Use TaskCreate/TaskUpdate for visual progress tracking:

- Create task for overall workflow
- Update task as phases complete
- Show current iteration/phase in task description
