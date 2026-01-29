---
description: Show current subagent workflow progress and status
argument-hint: [--verbose]
allowed-tools: Read
---

# Subagent Workflow Status

Display the current status and progress of the subagent workflow.

## Arguments

- `--verbose`: Show detailed task-level information

Parse from $ARGUMENTS.

## Step 1: Load State

Read `.agents/tmp/state.json`. If not found, display:

```
No active workflow found.
Start a new workflow with: /subagents:dispatch <task>
```

## Step 2: Display Status

### Schedule-based display (when `state.schedule` exists)

Count completed and total phases from `state.schedule` array to show progress.

```
Subagent Workflow Status
========================
Task: {task}
Status: {status}
Started: {startedAt}

Schedule ({completed}/{total} phases):
  ✓ Phase 0   │ EXPLORE   │ Explore                 │ completed   [GATE]
  ✓ Phase 1.1 │ PLAN      │ Brainstorm              │ completed
  ▶ Phase 1.2 │ PLAN      │ Plan                    │ in_progress
  · Phase 1.3 │ PLAN      │ Plan Review             │ pending     [GATE]
  · Phase 2.1 │ IMPLEMENT │ Task Execution          │ pending
  · Phase 2.2 │ IMPLEMENT │ Simplify                │ pending
  · Phase 2.3 │ IMPLEMENT │ Implementation Review   │ pending     [GATE]
  · Phase 3.1 │ TEST      │ Run Tests               │ pending
  · Phase 3.2 │ TEST      │ Analyze Failures        │ pending
  · Phase 3.3 │ TEST      │ Test Review             │ pending     [GATE]
  · Phase 4.1 │ FINAL     │ Documentation           │ pending
  · Phase 4.2 │ FINAL     │ Final Review            │ pending     [GATE]
  · Phase 4.3 │ FINAL     │ Completion              │ pending

Gates:
  EXPLORE → PLAN:    ✓ satisfied (requires 0-explore.md)
  PLAN → IMPLEMENT:  · pending (requires 1.2-plan.md, 1.3-plan-review.json)
  IMPLEMENT → TEST:  · pending (requires 2.1-tasks.json, 2.3-impl-review.json)
  TEST → FINAL:      · pending (requires 3.1-test-results.json, 3.3-test-review.json)
  FINAL → COMPLETE:  · pending (requires 4.2-final-review.json)
```

Status symbols: ✓ completed, ▶ in_progress, ✗ failed/blocked, · pending

Show `[GATE]` marker on review phases that produce gate artifacts.

Gate status: ✓ file exists (gate satisfied), ✗ missing (gate blocking), · pending (not yet reached).

For each entry in `state.schedule` (a flat array), display one row using:
- **symbol**: derive from `stages[entry.stage].phases[entry.phase].status` — ✓ completed, ▶ in_progress, ✗ failed/blocked, · pending
- **phase id**: from `entry.phase` (e.g., `0`, `1.1`, `2.3`)
- **stage**: from `entry.stage` (e.g., `EXPLORE`, `PLAN`)
- **name**: from `entry.name`
- **status**: looked up from `stages[entry.stage].phases[entry.phase].status`
- **[GATE]**: append if `entry.type === "review"`

For the Gates section, iterate `state.gates` (a top-level map keyed by transition name like `"PLAN->IMPLEMENT"`):
- Gate label: the key itself (e.g., `PLAN → IMPLEMENT`)
- ✓ if the gate's `required` file(s) exist in `.agents/tmp/phases/`
- ✗ if the gate phase has been reached but the file is missing
- · if the gate phase has not been reached yet
- Required filename from `gate.required[0]`

### Legacy display (when `state.schedule` does not exist)

Fall back to stage-level display for older state files:

```
Stage Progress:
  EXPLORE:   {status}
  PLAN:      {status}
  IMPLEMENT: {status}
  TEST:      {status} {enabled ? '' : '(disabled)'}
  FINAL:     {status}
```

## Step 3: Display Verbose Details (if --verbose)

If `--verbose` flag present, include task-level details:

```
Task Details:
-------------
Phase 2.1 Tasks (Wave 2):
  Wave 1 (completed):
    ✓ task-1: Create User model (sonnet-4.5, easy) - 45s
    ✓ task-3: Add config (sonnet-4.5, easy) - 30s

  Wave 2 (in_progress):
    ⟳ task-2: Implement OAuth flow (opus-4.5, medium) - running
    ○ task-4: Create auth routes (sonnet-4.5, easy) - pending

Active Task Agents: 1
```

## Step 4: Display Stopped Info (if applicable)

If `status` is `stopped`:

```
Workflow paused at: <stoppedAt formatted>
To resume: /subagents:resume
```

## Step 5: Display Failed Info (if applicable)

If `status` is `failed`:

```
Workflow failed at Phase <failure.phase>: <failure.error>
Failed at: <failure.failedAt>

To retry: /subagents:resume --retry-failed
To skip: /subagents:resume --from-phase <next phase>
```
