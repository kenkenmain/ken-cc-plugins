# Phase F2: Build

Dispatch **builder** agents to implement tasks from scout's plan.

## Agents

- **Type:** `minions:builder`
- **Mode:** Parallel dispatch (one per task from the plan)

## Process

1. Read the plan at `.agents/tmp/phases/loop-{{LOOP}}/f1-plan.md`
2. Parse the task table
3. For each task, dispatch a builder agent with:
   - Task ID (number from the table)
   - Task description
   - Acceptance criteria
   - Files to create/modify
4. After ALL builders complete, aggregate outputs into `f2-tasks.json`

## Prompt Template (per builder)

```
You are builder. Implement this task.

Task {{TASK_ID}}: {{TASK_DESCRIPTION}}

Acceptance Criteria:
{{ACCEPTANCE_CRITERIA}}

Files: {{FILE_LIST}}

Output your result as JSON at the end of your work.
```

## Aggregation

After all builders complete, write:

`.agents/tmp/phases/loop-{{LOOP}}/f2-tasks.json`

```json
{
  "tasks": [ ...each builder's output JSON... ],
  "files_changed": [ ...deduplicated list of all changed files... ],
  "all_complete": true
}
```

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/f2-tasks.json`

Next phase: F3 (Review)
