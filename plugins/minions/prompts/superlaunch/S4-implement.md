# Phase S4: Implement [PHASE S4]

## Subagent Config

- **Type:** `minions:task-agent` (wave-based parallel batch, model=inherit)
- **Input:** `.agents/tmp/phases/S2-plan.md`
- **Output:** `.agents/tmp/phases/S4-tasks.json`

## Instructions

Execute implementation tasks from the plan in dependency-ordered waves.

### Process

1. Read `.agents/tmp/phases/S2-plan.md`
2. Parse tasks and build dependency graph
3. Score each task complexity (easy/medium/hard)
4. Dispatch tasks in waves:
   - Wave 1: tasks with no dependencies (parallel)
   - Wave 2: tasks whose deps are complete (parallel)
   - Continue until all done
5. After all waves complete, aggregate test data:
   - Count total tests across all tasks (`testsTotal`)
   - Collect unique test file paths (`testFiles`)

### Task Agent Payload

For each task, dispatch `minions:task-agent` with:

```json
{"taskId":"task-N","description":"...","targetFiles":[...],"instructions":"...","dependencyOutputs":[...],"constraints":{"allowBashCommands":false}}
```

Task agents write unit tests alongside their implementation. The `testsWritten` array in each task's output tracks what tests were produced.

### Output Format

Write to `.agents/tmp/phases/S4-tasks.json`:

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
      ]
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
