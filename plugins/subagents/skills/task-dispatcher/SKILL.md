---
name: task-dispatcher
description: Dispatch multiple task agents in parallel within a wave, managing concurrency and file locking
---

# Task Dispatcher Skill

Handles parallel dispatch of task agents within an execution wave, managing concurrency limits and file locking.

## When to Use

Invoked by phase-executor for waves with multiple parallel tasks.

## Input

```json
{
  "wave": 2,
  "tasks": [
    {
      "taskId": "task-2",
      "context": {
        /* task context */
      },
      "model": "opus",
      "needsCodexReview": true
    },
    {
      "taskId": "task-3",
      "context": {
        /* task context */
      },
      "model": "sonnet",
      "needsCodexReview": false
    }
  ],
  "maxParallel": 5
}
```

## Step 1: Check Concurrency Limit

Split into batches of maxParallel size if needed, execute batches sequentially.

## Step 2: Check File Conflicts

Validate no file overlaps. If conflict detected, move conflicting task to next batch and log warning.

## Step 3: Acquire File Locks

Lock target files for each task to prevent conflicts.

## Step 4: Dispatch Tasks in Parallel

Use Task tool with `run_in_background: true`:

```
// Dispatch all tasks in single message with multiple tool calls
Task(
  description: "task-2: Implement OAuth",
  prompt: "<context>",
  model: "opus",
  run_in_background: true
)
Task(
  description: "task-3: Create User model",
  prompt: "<context>",
  model: "sonnet",
  run_in_background: true
)
```

## Step 5: Wait for Completion

Dispatch all tasks with `run_in_background: true`, collect task_ids, use TaskOutput with `block: true` for each, collect results and track completion.

## Steps 6-7: Locks and Reviews

Release file locks after completion. For `needsCodexReview: true`, invoke codex-xhigh review (parallel allowed), queue for bugFixer if issues found.

## Step 8: Aggregate Results

Return combined results:

```json
{
  "wave": 2,
  "status": "completed",
  "tasks": {
    "task-2": { "status": "completed", "summary": "..." },
    "task-3": { "status": "completed", "summary": "..." }
  },
  "errors": []
}
```

## Error Handling

**Failure:** Mark failed, release locks, continue with other tasks, report to phase-executor.

**Timeout:** 10min default, mark failed, release locks.

**Mid-execution conflict:** Abort task, retry after wave (shouldn't happen with proper locking).

## Concurrency Limits

| Task Type         | Default Max Parallel |
| ----------------- | -------------------- |
| Research/planning | 10                   |
| Implementation    | 1 (sequential)       |
| Review            | 5                    |

Respect `config.parallelism.maxParallelTasks` global limit.
