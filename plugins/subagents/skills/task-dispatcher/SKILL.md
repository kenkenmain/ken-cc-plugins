---
name: task-dispatcher
description: Dispatch task agents in waves based on dependencies, with complexity-based model selection
---

# Task Dispatcher

Dispatch task agents in dependency-ordered waves with complexity scoring.

## When to Use

Phase 2.1 of workflow, for parallel task execution.

## Wave-Based Execution

Tasks are dispatched in waves based on dependencies:

1. Parse plan file for tasks and dependencies
2. Build dependency graph
3. Identify Wave 1: tasks with no dependencies
4. Dispatch Wave 1 in parallel
5. Wait for Wave 1 completion
6. Identify Wave 2: tasks whose dependencies are all complete
7. Repeat until all tasks complete

## Complexity Scoring

For each task, determine complexity and model:

| Complexity | Criteria                                 | Model       |
| ---------- | ---------------------------------------- | ----------- |
| Easy       | Single file, <50 LOC                     | sonnet-4.5  |
| Medium     | 2-3 files, 50-200 LOC                    | opus-4.5    |
| Hard       | 4+ files, >200 LOC, security/concurrency | codex-xhigh |

Override with `config.stages.IMPLEMENT.tasks.complexityModels`.

## Input

Read tasks from `.agents/tmp/phases/1.2-plan.md`:

```markdown
### Task 1: Create User model

- **Files:** src/models/user.ts
- **Dependencies:** none
- **Complexity:** easy

### Task 2: Add auth middleware

- **Files:** src/middleware/auth.ts, src/types/auth.ts
- **Dependencies:** Task 1
- **Complexity:** medium
```

## Task Agent Dispatch

```
Task(
  description: "Task: {task name}",
  prompt: "{task details from plan}",
  subagent_type: "subagents:task-agent",
  model: {complexity-based model}
)
```

For `codex-xhigh` complexity:

```
mcp__codex-xhigh__codex(
  prompt: "{task details}",
  cwd: "{working directory}"
)
```

## Parallel Dispatch

Dispatch all tasks in a wave with a single message containing multiple Task tool calls:

```
// Wave 1: All independent tasks
Task(description: "Task 1", ..., run_in_background: true)
Task(description: "Task 3", ..., run_in_background: true)
Task(description: "Task 5", ..., run_in_background: true)
```

Respect `config.stages.IMPLEMENT.tasks.maxParallelAgents` (default: 10).

## Output Format

Write results to `.agents/tmp/phases/2.1-tasks.json`:

```json
{
  "waves": [
    {
      "waveNumber": 1,
      "tasks": [
        {
          "id": "task-1",
          "status": "completed",
          "summary": "Created User model"
        },
        { "id": "task-3", "status": "completed", "summary": "Added config" }
      ]
    },
    {
      "waveNumber": 2,
      "tasks": [
        {
          "id": "task-2",
          "status": "completed",
          "summary": "Added auth middleware"
        }
      ]
    }
  ],
  "completedTasks": ["task-1", "task-2", "task-3"],
  "failedTasks": []
}
```

## Update State

After each wave:

- Update `stages.IMPLEMENT.phases["2.1"].waves` with wave results
- Update `stages.IMPLEMENT.phases["2.1"].status`

After all waves complete:

- Set `files.tasks: ".agents/tmp/phases/2.1-tasks.json"`

## Error Handling

**Task failure:**

1. Mark task as failed in wave results
2. Check if dependent tasks can still proceed
3. If blocking dependencies failed, mark dependent tasks as blocked
4. Continue with non-blocked tasks
5. Report failures to user with retry option

**Timeout:** 10 minutes default per task. Mark as failed, continue with others.
