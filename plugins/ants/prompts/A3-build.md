# [PHASE A3] Build -- Dual-Track Dispatch

Execute the architect's plan using dual-track dispatch: **build track** (task pool workers) and **quality track** (adversarial review team + guardian).

## Agents

- **Build Track:**
  - `ants:worker` -- one per task, claimed from the task pool
- **Quality Track (Adversarial Review):**
  - `ants:sentinel-correctness` -- bugs, logic errors, error handling
  - `ants:sentinel-security` -- OWASP, injection, secrets, access control
  - `ants:sentinel-perf` -- N+1 queries, blocking I/O, complexity
  - `ants:review-arbiter` -- consolidates all sentinel findings
  - `ants:guardian` -- writes tests for completed work

## Task Pool Architecture

```
Task Pool:
  [T1: ready]  [T2: ready]  [T3: pending (deps: T1)]  [T4: pending (deps: T1, T2)]
       |             |
  [worker-1]    [worker-2]    (parallel -- claimed from pool)
       |             |
  T1 complete   T2 complete
       |             |
       +------+------+
              |
  [T3: ready]  [T4: ready]   (deps satisfied, promoted to ready)
       |             |
  [worker-3]    [worker-4]    (parallel -- claimed from pool)
       |             |
  pool drained ---------> Adversarial Review Team
                            sentinel-correctness  \
                            sentinel-security      } parallel
                            sentinel-perf         /
                                  |
                            review-arbiter (consolidate)
                                  |
                             A3-quality.json
```

Workers claim tasks as dependencies are satisfied. No rigid wave barriers -- the pool self-organizes based on the dependency graph.

## Process

### 1. Initialize Task Pool

Read task descriptors from `.agents/tmp/phases/loop-{{LOOP}}/A1-tasks.json`.

Expected format:
```json
[
  {
    "id": "T1",
    "description": "Implement auth module",
    "dependencies": [],
    "files_owned": ["src/auth.ts", "src/auth/types.ts"]
  },
  {
    "id": "T2",
    "description": "Add database migration",
    "dependencies": [],
    "files_owned": ["src/db/migrate.ts"]
  },
  {
    "id": "T3",
    "description": "Wire auth to API routes",
    "dependencies": ["T1", "T2"],
    "files_owned": ["src/routes/auth.ts"]
  }
]
```

Initialize the pool: tasks with no dependencies start as `ready`; others start as `pending`.

### 2. Dispatch Workers from Pool

For each ready task in the pool, dispatch a `worker` agent with:

```
You are worker. Implement this task.

Task ID: {{TASK_ID}}
Description: {{TASK_DESCRIPTION}}

Acceptance Criteria:
{{ACCEPTANCE_CRITERIA}}

Files you own (ONLY edit these files):
{{FILES_OWNED}}

Dependency outputs (context from completed tasks):
{{DEPENDENCY_OUTPUTS}}

Output your result as JSON at the end of your work.
```

File ownership: Each worker can ONLY edit files listed in its task's `files_owned` field. The edit gate enforces this via `pool_get_file_owner()`.

As workers complete:
1. Mark the task complete via `pool_complete_task()`
2. Recompute the ready set -- tasks whose dependencies are now all complete become ready
3. Dispatch new workers for newly ready tasks
4. Repeat until the pool is drained (all tasks complete or failed)

### 3. Adversarial Review (after pool drains)

After all workers complete, dispatch the adversarial review team. Three specialist sentinels run **in parallel**:

**Sentinel-correctness prompt:**
```
Review all changes for correctness issues: bugs, logic errors, missing error handling,
incorrect API usage, race conditions.

Changed files:
{{ALL_FILES_CHANGED}}

Worker outputs (for context):
{{WORKER_OUTPUTS_SUMMARY}}

Write findings to: .agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-correctness.json
```

**Sentinel-security prompt:**
```
Review all changes for security issues: OWASP top 10, injection attacks,
authentication flaws, secrets exposure, access control.

Changed files:
{{ALL_FILES_CHANGED}}

Worker outputs (for context):
{{WORKER_OUTPUTS_SUMMARY}}

Write findings to: .agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-security.json
```

**Sentinel-perf prompt:**
```
Review all changes for performance issues: N+1 queries, unnecessary allocations,
blocking I/O, missing caching opportunities, algorithmic complexity.

Changed files:
{{ALL_FILES_CHANGED}}

Worker outputs (for context):
{{WORKER_OUTPUTS_SUMMARY}}

Write findings to: .agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-perf.json
```

Wait for all three sentinels to complete.

### 4. Arbiter Consolidation

After all sentinels complete, dispatch the **review-arbiter**:

```
Consolidate findings from all three specialist sentinels.

Read:
- .agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-correctness.json
- .agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-security.json
- .agents/tmp/phases/loop-{{LOOP}}/A3-review.sentinel-perf.json

Cross-reference findings. Deduplicate overlapping issues. Resolve conflicts.
Produce unified verdict.

Write to: .agents/tmp/phases/loop-{{LOOP}}/A3-quality.json
```

### 5. Guardian (Test Writing)

Guardian agents write tests alongside the review. Dispatch after workers complete:

```
Write tests for the implementation.

Files implemented by workers:
{{FILES_CHANGED}}

Worker outputs (for context):
{{WORKER_OUTPUTS_SUMMARY}}

Discover test conventions, write focused tests, run them, report results as JSON.
```

### 6. Aggregate Results

After all tracks complete, write:

`.agents/tmp/phases/loop-{{LOOP}}/A3-build.json`

```json
{
  "completedAt": "ISO timestamp",
  "dispatchMode": "taskPool",
  "tasks": [
    {
      "taskId": "T1",
      "status": "complete",
      "filesModified": ["src/auth.ts"],
      "filesCreated": ["src/auth/types.ts"],
      "testsWritten": []
    }
  ],
  "guardian": {
    "status": "complete",
    "testsWritten": [
      { "file": "test/auth.test.ts", "targetFile": "src/auth.ts", "testCount": 5 }
    ],
    "testResults": { "totalTests": 5, "passed": 5, "failed": 0 }
  },
  "files_changed": ["src/auth.ts", "src/auth/types.ts", "test/auth.test.ts"],
  "totalTasks": 3,
  "totalTasksComplete": 3,
  "totalTasksFailed": 0,
  "totalTests": 5,
  "all_complete": true
}
```

## Legacy Fallback (v0.1 Wave-Based Dispatch)

If no `taskPool` exists in state (v0.1 state files or plans without `A1-tasks.json`), fall back to wave-based dispatch:

1. Read waves from `.agents/tmp/phases/loop-{{LOOP}}/A1-plan.md`
2. Execute Wave 1 workers in parallel
3. Wave 1 completion barrier
4. Execute Wave 2 workers in parallel
5. Wave 2 completion barrier
6. Dispatch generic `ants:sentinel` (not specialist sentinels) for review
7. Write results in the same A3-build.json / A3-quality.json format

This ensures backward compatibility with existing v0.1 plans.

## Error Handling

### Worker Failure

If a worker reports `blocked` or fails:
- Mark the task as failed via `pool_fail_task()`
- Failed tasks block their dependents (dependents stay `pending`)
- Continue dispatching other ready tasks (they are independent)
- Report the failed task in the aggregate output

### Sentinel Failure

If a sentinel fails to complete:
- Log the failure
- Arbiter consolidates from available sentinel outputs (partial review)
- If all three sentinels fail, treat as blocked

### Pool Stall

If the pool has pending tasks but no ready tasks (all remaining tasks depend on failed tasks):
- Report which tasks are blocked and why
- Include partial results in output
- Let the orchestrator decide whether to proceed or block

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json` with `all_complete: true`

Quality output required: `.agents/tmp/phases/loop-{{LOOP}}/A3-quality.json` (from arbiter)

Both files must exist for the phase to advance to A4.
