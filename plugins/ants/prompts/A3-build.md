# [PHASE A3] Build — Dual-Track Dispatch

Execute the architect's plan using dual-track parallel dispatch: **build track** (workers) and **quality track** (guardian + sentinel).

## Agents

- **Build Track:**
  - `ants:worker` — one per task within a wave, dispatched in parallel
- **Quality Track:**
  - `ants:guardian` — one per wave, writes tests for completed work
  - `ants:sentinel` — one per wave, reviews correctness/quality/security

## Dual-Track Architecture

```
Wave 1:  [worker-1] [worker-2] [worker-3]  (parallel build)
              |           |           |
              +-----+-----+
                    |
         [guardian] + [sentinel]  (parallel quality, after wave completes)
                    |
              Pass/Fail gate
                    |
Wave 2:  [worker-4] [worker-5]  (next wave, only if wave 1 passed)
              |           |
              +-----+-----+
                    |
         [guardian] + [sentinel]
                    |
              Pass/Fail gate
```

Workers within a wave run in parallel. Guardian and sentinel run in parallel after all workers in a wave complete. The next wave starts only after the current wave's quality gate passes.

## Process

### 1. Read the Plan

Read the plan from `.agents/tmp/phases/loop-{{LOOP}}/A1-plan.md` (loop-scoped path).

Expected plan structure:
```json
{
  "waves": [
    {
      "waveNumber": 1,
      "tasks": [
        {
          "taskId": "wave-1-task-1",
          "description": "Task description",
          "acceptanceCriteria": ["criterion 1", "criterion 2"],
          "files": ["src/file.ts"],
          "dependencies": []
        }
      ]
    }
  ]
}
```

### 2. Execute Each Wave

For each wave in order:

#### Build Track (parallel within wave)

For each task in the wave, dispatch a `worker` agent with:

```
You are worker. Implement this task.

Wave: {{WAVE_NUMBER}}
Task ID: {{TASK_ID}}
Description: {{TASK_DESCRIPTION}}

Acceptance Criteria:
{{ACCEPTANCE_CRITERIA}}

Files: {{FILE_LIST}}

Dependency outputs from prior waves/tasks:
{{DEPENDENCY_OUTPUTS}}

Output your result as JSON at the end of your work.
```

Wait for ALL workers in the wave to complete.

#### Quality Track (parallel after wave completes)

After all workers in the wave complete, dispatch guardian and sentinel in parallel:

**Guardian prompt:**
```
Write tests for the implementation from wave {{WAVE_NUMBER}}.

Files implemented by workers:
{{FILES_CHANGED}}

Worker outputs (for context):
{{WORKER_OUTPUTS_SUMMARY}}

Discover test conventions, write focused tests, run them, report results as JSON.
```

**Sentinel prompt:**
```
Review wave {{WAVE_NUMBER}} output for correctness, quality, and security.

Changed files:
{{FILES_CHANGED}}

Worker outputs (for context):
{{WORKER_OUTPUTS_SUMMARY}}

Review all files with correctness, quality, and security lenses. Report results as JSON.
```

Wait for both guardian and sentinel to complete.

### 3. Wave Gate

After quality track completes, evaluate the wave:

| Condition | Action |
|-----------|--------|
| Sentinel status = `clean` | Advance to next wave |
| Sentinel has critical issues | Block — log issues, do NOT advance |
| Sentinel has warnings only | Advance with warnings logged |
| Guardian tests fail | Block — tests must pass before advancing |

### 4. Aggregate Results

After all waves complete, write:

`.agents/tmp/phases/loop-{{LOOP}}/A3-build.json`

```json
{
  "completedAt": "ISO timestamp",
  "waves": [
    {
      "waveNumber": 1,
      "workers": [
        {
          "taskId": "wave-1-task-1",
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
      "sentinel": {
        "status": "clean",
        "criticalCount": 0,
        "warningCount": 1,
        "issues": []
      },
      "waveStatus": "passed"
    }
  ],
  "allFilesChanged": ["src/auth.ts", "src/auth/types.ts", "test/auth.test.ts"],
  "totalTasks": 3,
  "totalTasksComplete": 3,
  "totalTests": 5,
  "overallStatus": "complete"
}
```

## Error Handling

### Worker Failure

If a worker reports `blocked` or fails:
- Log the failure in the wave output
- Continue other workers in the wave (they are independent)
- Report the blocked task in the wave gate evaluation

### Quality Track Failure

If guardian or sentinel fails to complete:
- Treat the wave as blocked
- Include partial results in output
- Do not advance to the next wave

### Partial Wave Completion

If some but not all tasks in a wave complete:
- Run quality track on completed work only
- Report incomplete tasks
- Let the orchestrator decide whether to retry or advance

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json` with `overallStatus: "complete"`

All waves must pass their quality gates for the phase to succeed.
