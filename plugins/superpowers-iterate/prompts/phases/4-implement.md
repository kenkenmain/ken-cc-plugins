# Phase 4: Implement [PHASE 4]

## Subagent Config

- **Type:** dispatch (wave-based parallel task agents)
- **Input:** `.agents/tmp/iterate/phases/2-plan.md`
- **Output:** `.agents/tmp/iterate/phases/4-tasks.json`

## Instructions

Execute implementation tasks from the plan in dependency-ordered waves using `superpowers-iterate:task-agent`.

### Process

1. Read `.agents/tmp/iterate/phases/2-plan.md`
2. Parse tasks and build dependency graph
3. Score each task complexity (easy/medium/hard)
4. Dispatch tasks in waves:
   - Wave 1: tasks with no dependencies (parallel)
   - Wave 2: tasks whose deps are complete (parallel)
   - Continue until all done
5. For each task, follow TDD:
   a. Write failing test first
   b. Run to verify it fails
   c. Write minimal code to pass
   d. Run to verify it passes
   e. Self-review and commit
6. Run `make lint && make test` after all waves complete
7. Write results to output file

### Complexity Scoring

| Level  | Criteria                     | Execution                                              |
| ------ | ---------------------------- | ------------------------------------------------------ |
| Easy   | 1 file, <50 LOC              | superpowers-iterate:task-agent (sonnet)                 |
| Medium | 2-3 files, 50-200 LOC        | superpowers-iterate:task-agent (opus)                   |
| Hard   | 4+ files, >200 LOC, security | superpowers-iterate:codex-reviewer (codex-xhigh)        |

### Task Agent Payload (easy/medium)

```json
{
  "taskId": "task-N",
  "description": "...",
  "targetFiles": ["..."],
  "instructions": "...",
  "tddSteps": {
    "testFile": "...",
    "testCommand": "...",
    "sourceFile": "..."
  },
  "dependencyOutputs": ["..."],
  "constraints": {
    "maxReadFiles": 10,
    "maxWriteFiles": 3,
    "allowBashCommands": true
  }
}
```

### Implementer Modes

Based on config `phases.4.implementer`:

**Claude Mode (default):**
- Dispatch `superpowers-iterate:task-agent` per task
- Implementation subagents run sequentially (to avoid file conflicts)
- Reviewer subagents can run in parallel
- Each subagent has access to LSP tools for code intelligence

**Codex Mode (codex-high or codex-xhigh):**
- Invoke the configured Codex MCP tool with implementation prompt
- Include full task details and TDD requirements
- Run `make lint && make test` after implementation

### Output Format

Write to `.agents/tmp/iterate/phases/4-tasks.json`:

```json
{
  "waves": [
    {
      "waveNumber": 1,
      "tasks": [
        {
          "id": "task-1",
          "description": "...",
          "complexity": "easy",
          "status": "completed",
          "testsPassed": true,
          "filesModified": ["..."],
          "summary": "..."
        }
      ]
    }
  ],
  "completedTasks": ["task-1"],
  "failedTasks": [],
  "lintResult": { "exitCode": 0, "passed": true },
  "testResult": { "exitCode": 0, "passed": true }
}
```

### Error Handling

Failed tasks: mark as failed, skip blocked dependents, continue with others. Record failure details in the task's status entry.
