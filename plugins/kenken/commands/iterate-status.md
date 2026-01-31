---
description: Show current kenken workflow progress and status
argument-hint: [--verbose]
allowed-tools: Read
---

# kenken Workflow Status

Display the current status and progress of the kenken workflow.

## Arguments

- `--verbose`: Show detailed phase-level information including output file sizes and timestamps

Parse from $ARGUMENTS.

## Step 1: Load State

Read `.agents/tmp/kenken/state.json`. If not found, display:

```
No active workflow found.
Start a new workflow with: /kenken:iterate <task>
```

## Step 2: Display Status

### Schedule-based display (when `state.schedule` exists)

Count completed and total phases from `state.schedule` array to show progress.

```
kenken Workflow Status
========================
Task: {task}
Status: {status}
Stage: {currentStage}
Phase: {currentPhase}
Started: {startedAt}

Schedule ({completed}/{total} phases):
  {sym} Phase 1.1 | PLAN      | Brainstorm       | {status}
  {sym} Phase 1.2 | PLAN      | Plan             | {status}
  {sym} Phase 1.3 | PLAN      | Plan Review      | {status}    [GATE]
  {sym} Phase 2.1 | IMPLEMENT | Implementation   | {status}
  {sym} Phase 2.2 | IMPLEMENT | Simplify         | {status}
  {sym} Phase 2.3 | IMPLEMENT | Impl Review      | {status}    [GATE]
  {sym} Phase 3.1 | TEST      | Test Plan        | {status}
  {sym} Phase 3.2 | TEST      | Write Tests      | {status}
  {sym} Phase 3.3 | TEST      | Coverage         | {status}
  {sym} Phase 3.4 | TEST      | Run Tests        | {status}
  {sym} Phase 3.5 | TEST      | Test Review      | {status}    [GATE]
  {sym} Phase 4.1 | FINAL     | Final Review     | {status}    [GATE]
  {sym} Phase 4.2 | FINAL     | Extensions       | {status}
  {sym} Phase 4.3 | FINAL     | Completion       | {status}

Gates:
  PLAN -> IMPLEMENT:  {sym} {status} (requires 1.2-plan.md, 1.3-plan-review.json)
  IMPLEMENT -> TEST:  {sym} {status} (requires 2.1-tasks.json, 2.3-impl-review.json)
  TEST -> FINAL:      {sym} {status} (requires 3.4-test-results.json, 3.5-test-review.json)
  FINAL -> COMPLETE:  {sym} {status} (requires 4.1-final-review.json)

Stage Status:
  PLAN:      {status} (restarts: {restartCount})
  IMPLEMENT: {status} (restarts: {restartCount})
  TEST:      {status} [{enabled/disabled}] (restarts: {restartCount})
  FINAL:     {status} (restarts: {restartCount})
```

### Status Symbols

- `✓` completed
- `->` in_progress (current phase)
- `x` failed/blocked
- `o` pending

Show `[GATE]` marker on phases that produce gate artifacts. Specifically, append `[GATE]` if any entry in `state.gates` has `.phase` matching the schedule entry's phase.

### Phase Status Determination

For each entry in `state.schedule`:

1. If `entry.phase == state.currentPhase`: Show `->` marker with `<- current` annotation
2. Look up `stages[entry.stage].phases[entry.phase].status`:
   - `completed` -> `✓`
   - `in_progress` -> `->`
   - `failed` or `blocked` -> `x`
   - `pending` or missing -> `o`

### Gate Status Determination

For each gate in `state.gates`:

- `✓` if all `required` files exist in `.agents/tmp/kenken/phases/`
- `x` if the gate phase has been reached but files are missing
- `o` if the gate phase has not been reached yet

## Step 3: Display Verbose Details (if --verbose)

If `--verbose` flag present, include phase output details:

```
Phase Output Files:
-------------------
  1.1-brainstorm.md      - 2.3 KB (2026-01-31 10:32)
  1.2-plan.md            - 8.1 KB (2026-01-31 10:35)
  1.3-plan-review.json   - 1.2 KB (2026-01-31 10:37)
  2.1-tasks.json         - 4.5 KB (2026-01-31 10:42)

Stage Restart History:
  PLAN:      0 restarts
  IMPLEMENT: 1 restart (blocked at 2.3 - severity HIGH)
```

List all files present in `.agents/tmp/kenken/phases/` with their sizes and timestamps.

## Step 4: Display Stopped Info (if applicable)

If `status` is `stopped`:

```
Workflow paused at: {stoppedAt formatted}
To resume: /kenken:iterate-resume
```

## Step 5: Display Failed Info (if applicable)

If `status` is `failed`:

```
Workflow failed at Phase {failure.phase}: {failure.error}
Failed at: {failure.failedAt}

To retry: /kenken:iterate-resume --retry-failed
To skip: /kenken:iterate-resume --from-phase {next phase}
```
