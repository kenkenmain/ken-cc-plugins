---
name: plan-writer
description: Write implementation plans with required schema for phase execution
---

# Plan Writer Skill

Creates implementation plans with the required schema for task-dispatcher to parse tasks.

## When to Use

Invoked during Phase 1.2 (Write Plan) to create the plan file.

## Plan File Schema

The plan file MUST contain a `tasks:` YAML block that task-dispatcher can parse:

```yaml
# docs/plans/YYYY-MM-DD-feature-plan.md
---
tasks:
  - id: task-1
    description: "Create User model with email and password fields"
    targetFiles:
      - src/models/user.ts
    instructions: |
      Create a User model with:
      - email: string (unique, validated)
      - passwordHash: string
      - createdAt: Date
      - updatedAt: Date
    dependencies: []

  - id: task-2
    description: "Implement OAuth flow with Google provider"
    targetFiles:
      - src/auth/oauth.ts
      - src/routes/auth.ts
    instructions: |
      Implement OAuth 2.0 with Google:
      - Authorization URL generation
      - Token exchange
      - User info retrieval
    dependencies:
      - task-1
---
## Implementation Details

[Prose description of the feature...]
```

## Required Fields Per Task

| Field        | Type     | Max Length | Description                                   |
| ------------ | -------- | ---------- | --------------------------------------------- |
| id           | string   | 20 chars   | Unique task identifier (task-1, task-2, etc.) |
| description  | string   | 100 chars  | Brief task summary                            |
| targetFiles  | string[] | 10 files   | Files this task will modify                   |
| instructions | string   | 2000 chars | Detailed implementation guidance              |
| dependencies | string[] | -          | Task IDs that must complete first             |

## Output

Return the plan file path to the stage agent:

```json
{
  "phaseId": "1.2",
  "status": "completed",
  "planFilePath": "docs/plans/2026-01-28-feature-plan.md",
  "summary": "Created plan with 5 tasks",
  "taskCount": 5
}
```

## Validation

Before returning, validate:

1. All tasks have required fields
2. Dependencies reference valid task IDs
3. No circular dependencies
4. targetFiles paths are reasonable

## Integration

The orchestrator persists `planFilePath` to state. Subsequent stages read from state and pass to phase agents for task loading.
