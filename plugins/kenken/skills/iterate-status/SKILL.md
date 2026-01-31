---
name: iterate-status
description: Show current kenken iteration status
---

# kenken Status

> **For Claude:** Show the current status of an ongoing kenken iteration.

## Actions

1. Read `.agents/kenken-state.json`
2. If no state found:
   - Display: "No kenken iteration in progress. Use `/kenken:iterate` to start."
   - Exit
3. If state found, display formatted status:

```
kenken Status

Task: {task description}
Stage: {current stage} ({stage number}/4)
Phase: {current phase number} {phase name}

Progress:
{status icon} PLAN
  {status icon} 1.1 Brainstorm
  {status icon} 1.2 Write Plan
  {status icon} 1.3 Plan Review
{status icon} IMPLEMENT
  {status icon} 2.1 Implementation {(task progress if available)}
  {status icon} 2.2 Code Simplify
  {status icon} 2.3 Implement Review
{status icon} TEST [{enabled/disabled}]
  {status icon} 3.1 Test Plan
  {status icon} 3.2 Write Tests
  {status icon} 3.3 Coverage Check
  {status icon} 3.4 Run Tests
  {status icon} 3.5 Test Review
{status icon} FINAL
  {status icon} 4.1 Codex Final
  {status icon} 4.2 Suggest Extensions

Retries: {retryCount}/{maxRetries}
Started: {startedAt formatted}
Elapsed: {elapsed time}
```

## Status Icons

- `✓` - completed
- `◐` - in_progress
- `○` - pending
- `✗` - failed/blocked

## Example Output

```
kenken Status

Task: Add user authentication
Stage: IMPLEMENT (2/4)
Phase: 2.1 Implementation

Progress:
✓ PLAN
  ✓ 1.1 Brainstorm
  ✓ 1.2 Write Plan
  ✓ 1.3 Plan Review
◐ IMPLEMENT
  ◐ 2.1 Implementation (3/5 tasks)
  ○ 2.2 Code Simplify
  ○ 2.3 Implement Review
○ TEST [disabled]
○ FINAL

Retries: 0/3
Started: 2026-01-24 10:30
Elapsed: 45 minutes
```
