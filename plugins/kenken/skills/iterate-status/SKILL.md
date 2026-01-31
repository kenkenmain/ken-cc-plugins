---
name: iterate-status
description: Show current kenken iteration status
---

# kenken Status

> **For Claude:** Show the current status of an ongoing kenken iteration.

## Actions

1. Read `.agents/tmp/kenken/state.json`
2. If no state found:
   - Display: "No kenken iteration in progress. Use `/kenken:iterate` to start."
   - Exit
3. If state found, display formatted status:

```
Workflow Status: kenken
========================
Task: {task description}
Status: {status}
Stage: {currentStage}
Phase: {currentPhase}

Schedule Progress:
  {icon} Phase 1.1 │ PLAN      │ Brainstorm
  {icon} Phase 1.2 │ PLAN      │ Plan
  → Phase 1.3 │ PLAN      │ Plan Review     ← current
  {icon} Phase 2.1 │ IMPLEMENT │ Implementation
  {icon} Phase 2.2 │ IMPLEMENT │ Simplify
  {icon} Phase 2.3 │ IMPLEMENT │ Implementation Review
  {icon} Phase 3.1 │ TEST      │ Test Plan
  {icon} Phase 3.2 │ TEST      │ Write Tests
  {icon} Phase 3.3 │ TEST      │ Coverage Check
  {icon} Phase 3.4 │ TEST      │ Run Tests
  {icon} Phase 3.5 │ TEST      │ Test Review
  {icon} Phase 4.1 │ FINAL     │ Codex Final
  {icon} Phase 4.2 │ FINAL     │ Suggest Extensions

Stage Gates:
  {icon} PLAN → IMPLEMENT:    1.2-plan.md {icon}, 1.3-plan-review.json {icon}
  {icon} IMPLEMENT → TEST:    2.1-tasks.json {icon}, 2.3-impl-review.json {icon}
  {icon} TEST → FINAL:        3.4-test-results.json {icon}, 3.5-test-review.json {icon}
  {icon} FINAL → COMPLETE:    4.1-final-review.json {icon}

Stage Status:
  PLAN:      {status} (restarts: {restartCount})
  IMPLEMENT: {status} (restarts: {restartCount})
  TEST:      {status} [{enabled/disabled}] (restarts: {restartCount})
  FINAL:     {status} (restarts: {restartCount})

Started: {startedAt formatted}
Updated: {updatedAt formatted}
Elapsed: {elapsed time}
```

## Status Icons

- `✓` - completed/passed
- `→` - current position marker
- `○` - pending
- `✗` - failed/blocked/missing

## Phase Status Determination

For each phase in `state.schedule`:
1. If `phase == state.currentPhase`: Show `→` marker and `← current` annotation
2. If phase comes before current: Show `✓` (completed)
3. If phase comes after current: Show `○` (pending)

## Gate Status Determination

For each gate in `state.gates`:
1. Check if all `required` files exist in `.agents/tmp/kenken/phases/`
2. Show `✓` if gate passed (all files exist)
3. Show `○` if gate pending (phase not reached)
4. Show `✗` if gate failed (phase reached but files missing)

## Stage Status Display

Read from `state.stages[stageName]`:
- Display `status` field directly
- Display `restartCount` field
- For TEST stage: Show `enabled` field as `[enabled]` or `[disabled]`
- If `blockReason` is set: Display below stage status

## Example Output

```
Workflow Status: kenken
========================
Task: Add user authentication
Status: in_progress
Stage: IMPLEMENT
Phase: 2.1

Schedule Progress:
  ✓ Phase 1.1 │ PLAN      │ Brainstorm
  ✓ Phase 1.2 │ PLAN      │ Plan
  ✓ Phase 1.3 │ PLAN      │ Plan Review
  → Phase 2.1 │ IMPLEMENT │ Implementation     ← current
  ○ Phase 2.2 │ IMPLEMENT │ Simplify
  ○ Phase 2.3 │ IMPLEMENT │ Implementation Review
  ○ Phase 3.1 │ TEST      │ Test Plan
  ○ Phase 3.2 │ TEST      │ Write Tests
  ○ Phase 3.3 │ TEST      │ Coverage Check
  ○ Phase 3.4 │ TEST      │ Run Tests
  ○ Phase 3.5 │ TEST      │ Test Review
  ○ Phase 4.1 │ FINAL     │ Codex Final
  ○ Phase 4.2 │ FINAL     │ Suggest Extensions

Stage Gates:
  ✓ PLAN → IMPLEMENT:    1.2-plan.md ✓, 1.3-plan-review.json ✓
  ○ IMPLEMENT → TEST:    2.1-tasks.json ○, 2.3-impl-review.json ○
  ○ TEST → FINAL:        3.4-test-results.json ○, 3.5-test-review.json ○
  ○ FINAL → COMPLETE:    4.1-final-review.json ○

Stage Status:
  PLAN:      completed (restarts: 0)
  IMPLEMENT: in_progress (restarts: 0)
  TEST:      pending [enabled] (restarts: 0)
  FINAL:     pending (restarts: 0)

Started: 2026-01-31 10:30
Updated: 2026-01-31 10:45
Elapsed: 15 minutes
```
