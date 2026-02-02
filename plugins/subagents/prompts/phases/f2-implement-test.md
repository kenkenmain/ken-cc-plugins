# Phase F2: Implement + Test [PHASE F2]

## Subagent Config

- **Type:** complexity-routed task agents (wave-based parallel batch)
  - Easy: `sonnet-task-agent` (direct execution, model=sonnet)
  - Medium: `opus-task-agent` (direct execution, model=opus)
  - Hard: `codex-task-agent` (Codex) or `opus-task-agent` (Claude)
- **Input:** `.agents/tmp/phases/f1-plan.md`
- **Output:** `.agents/tmp/phases/f2-tasks.json`

## Instructions

Execute implementation tasks from the fast plan. Each task agent implements code AND writes tests.

### Process

1. Read `.agents/tmp/phases/f1-plan.md`
2. Parse tasks and build dependency graph
3. Score each task complexity (easy/medium/hard)
4. Dispatch tasks in waves:
   - Wave 1: tasks with no dependencies (parallel)
   - Wave 2: tasks whose deps are complete (parallel)
   - Continue until all done
5. After all waves complete, aggregate results

### Complexity Scoring

| Level  | Criteria                     | Agent               |
| ------ | ---------------------------- | ------------------- |
| Easy   | 1 file, <50 LOC              | sonnet-task-agent   |
| Medium | 2-3 files, 50-200 LOC        | opus-task-agent     |
| Hard   | 4+ files, >200 LOC, security | codex-task-agent    |

Check `state.codexAvailable` to determine hard task routing.

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
