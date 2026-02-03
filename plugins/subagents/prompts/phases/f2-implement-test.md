# Phase F2: Implement + Test [PHASE F2]

## Subagent Config

- **Agent:** `opus-task-agent` (direct execution, model=opus) for all tasks
- **Input:** `.agents/tmp/phases/f1-plan.md`
- **Output:** `.agents/tmp/phases/f2-tasks.json`

## Instructions

Execute implementation tasks from the fast plan. Each task agent implements code AND writes tests.

### Process

1. Read `.agents/tmp/phases/f1-plan.md`
2. Parse tasks and build dependency graph
3. Dispatch tasks in waves:
   - Wave 1: tasks with no dependencies (parallel)
   - Wave 2: tasks whose deps are complete (parallel)
   - Continue until all done
4. After all waves complete, aggregate results

### Task Agent Payload

Each task dispatch includes: taskId, description, targetFiles, instructions, dependencyOutputs, constraints.

Task agents write unit tests alongside implementation. `testsWritten` array tracks produced tests.

### Output Format

Write to `.agents/tmp/phases/f2-tasks.json`:

```json
{
  "waves": [
    {
      "waveNumber": 1,
      "tasks": [
        {
          "id": "task-1",
          "status": "completed",
          "summary": "...",
          "testsWritten": [
            { "file": "src/__tests__/example.test.ts", "targetFile": "src/example.ts", "testCount": 5 }
          ]
        }
      ],
      "waveSummary": { "tasksCompleted": 1, "tasksFailed": 0, "testsWritten": 1 }
    }
  ],
  "completedTasks": ["task-1"],
  "failedTasks": [],
  "testsTotal": 5,
  "testFiles": ["src/__tests__/example.test.ts"]
}
```

### Error Handling

Failed tasks: mark as failed, skip blocked dependents, continue with others.
