# Phase C2: Build (Cursor-Builders with Per-Task Commits)

Dispatch **cursor-builder** agents in parallel to implement tasks from the plan. Each builder commits its changes immediately.

## Agent

- **Type:** `minions:cursor-builder`
- **Mode:** Parallel dispatch (one per task)

## Process

1. Read the plan at `.agents/tmp/phases/loop-{{LOOP}}/c1-plan.md`
2. Parse the task table
3. For each task, dispatch a cursor-builder with:
   - Task description and acceptance criteria
   - Task ID (the task number)
   - Instruction to commit after completing
4. After ALL builders complete, aggregate outputs

## Prompt Template (per task)

```
You are cursor-builder. Implement task {{TASK_ID}}.

Task: {{TASK_DESCRIPTION}}
Acceptance Criteria: {{ACCEPTANCE_CRITERIA}}
Files: {{FILES}}

After implementing and self-verifying, commit your changes:
  git add <your-changed-files>
  git commit -m "task({{TASK_ID}}): {{brief description}}"

Write your output JSON at the end of your work.
```

## Aggregation

After all builders complete, write:

`.agents/tmp/phases/loop-{{LOOP}}/c2-tasks.json`

```json
{
  "tasks": [ ...each builder's output JSON... ],
  "files_changed": [ ...deduplicated list of all changed files... ],
  "all_complete": true
}
```

## Gate

Input required: `.agents/tmp/phases/loop-{{LOOP}}/c1-plan.md`

Output required: `.agents/tmp/phases/loop-{{LOOP}}/c2-tasks.json`

Next phase: C3 (Judge)
