---
description: Show current iteration workflow progress and status
argument-hint: [--verbose]
allowed-tools: Read, Bash
---

# Iteration Workflow Status

Display the current status and progress of the iteration workflow.

## Arguments

- `--verbose`: Show detailed phase-level information and iteration history

Parse from $ARGUMENTS.

## Step 1: Load State

Read `.agents/tmp/iterate/state.json`. If not found, display:

```
No active iteration workflow found.
Start a new workflow with: /superpowers-iterate:iterate <task>
```

## Step 2: Display Status

### Schedule-based display (when `state.schedule` exists)

Count completed and total phases from `state.schedule` array to show progress.

```
Iteration Workflow Status
==========================
Task: {task}
Status: {status}
Mode: {mode}
Iteration: {currentIteration} of {maxIterations}
Started: {startedAt}

Schedule ({completed}/{total} phases):
  * Phase 1 | PLAN      | Brainstorm    | completed
  * Phase 2 | PLAN      | Plan          | completed
  > Phase 3 | PLAN      | Plan Review   | in_progress  [GATE]
  . Phase 4 | IMPLEMENT | Implement     | pending
  . Phase 5 | IMPLEMENT | Review        | pending      [GATE]
  . Phase 6 | TEST      | Run Tests     | pending
  . Phase 7 | IMPLEMENT | Simplify      | pending
  . Phase 8 | REVIEW    | Final Review  | pending      [GATE]
  . Phase 9 | FINAL     | Codex Final   | pending
  . Phase C | FINAL     | Completion    | pending      [GATE]

Gates:
  PLAN -> IMPLEMENT:  . pending (requires 2-plan.md, 3-plan-review.json)
  IMPLEMENT -> TEST:  . pending (requires 4-tasks.json, 5-review.json)
  REVIEW -> FINAL:    . pending (requires 8-final-review.json)
  FINAL -> COMPLETE:  . pending (requires 9-codex-final.json)
```

Status symbols: `*` completed, `>` in_progress, `x` failed/blocked, `.` pending

Show `[GATE]` marker on phases that produce gate artifacts (check `state.gates` for any gate where `.phase` matches the entry's phase).

For each entry in `state.schedule` (a flat array), display one row using:

- **symbol**: derive from `stages[entry.stage].phases[entry.phase].status` -- `*` completed, `>` in_progress, `x` failed/blocked, `.` pending
- **phase id**: from `entry.phase` (e.g., `1`, `2`, `C`)
- **stage**: from `entry.stage` (e.g., `PLAN`, `IMPLEMENT`)
- **name**: from `entry.name`
- **status**: looked up from `stages[entry.stage].phases[entry.phase].status`
- **[GATE]**: append if this phase triggers a gate

For the Gates section, iterate `state.gates` (a top-level map keyed by transition name like `"PLAN->IMPLEMENT"`):

- Gate label: the key itself (e.g., `PLAN -> IMPLEMENT`)
- `*` if the gate's `required` file(s) all exist in `.agents/tmp/iterate/phases/`
- `x` if the gate phase has been reached but a file is missing
- `.` if the gate phase has not been reached yet
- Required filenames from `gate.required`

### Legacy display (when `state.schedule` does not exist)

Fall back to the old iteration-based display for v1 state files:

```
Phase Progress:
  Phase 1 (Brainstorm):    {status}
  Phase 2 (Plan):          {status}
  Phase 3 (Plan Review):   {status}
  Phase 4 (Implement):     {status}
  Phase 5 (Review):        {status}
  Phase 6 (Test):          {status}
  Phase 7 (Simplify):      {status}
  Phase 8 (Final Review):  {status}
  Phase 9 (Codex Final):   {status}
```

## Step 3: Display Verbose Details (if --verbose)

If `--verbose` flag present, include iteration history:

```
Iteration History:
------------------
Iteration 1 (completed):
  Phase 8 decision: issues found (3 HIGH, 1 MEDIUM)
  Phase files archived to: .agents/tmp/iterate/phases/iter-1/

Iteration 2 (in_progress):
  Phases completed: 1, 2, 3
  Current phase: 4 (Implement)
```

## Step 4: Display Stopped Info (if applicable)

If `status` is `stopped`:

```
Workflow paused at: {stoppedAt}
To resume: /superpowers-iterate:resume
```

## Step 5: Display Failed Info (if applicable)

If `status` is `failed`:

```
Workflow failed at Phase {failure.phase}: {failure.error}
Failed at: {failure.failedAt}

To retry: /superpowers-iterate:resume --retry-failed
To skip: /superpowers-iterate:resume --from-phase {next phase}
```

## Phase Reference

| Phase | Stage     | Name         | Type     | Integration                            |
| ----- | --------- | ------------ | -------- | -------------------------------------- |
| 1     | PLAN      | Brainstorm   | dispatch | Explore + general-purpose subagents    |
| 2     | PLAN      | Plan         | dispatch | Plan subagents                         |
| 3     | PLAN      | Plan Review  | review   | Codex MCP (codex-high)                 |
| 4     | IMPLEMENT | Implement    | dispatch | Task agents in dependency waves        |
| 5     | IMPLEMENT | Review       | review   | Codex MCP (codex-high)                 |
| 6     | TEST      | Run Tests    | command  | `make lint && make test`               |
| 7     | IMPLEMENT | Simplify     | subagent | code-simplifier                        |
| 8     | REVIEW    | Final Review | review   | Codex MCP (codex-high), decision point |
| 9     | FINAL     | Codex Final  | review   | Codex MCP (codex-xhigh), full only     |
| C     | FINAL     | Completion   | subagent | Summary and cleanup                    |
