---
name: plan-writer
description: Write implementation plans with required schema for phase execution
---

# Plan Writer Skill

Creates implementation plans with the required schema for task-dispatcher to parse tasks.

## When to Use

Invoked during Phase 1.2 (Write Plan) to create the plan file.

## Plan File Schema

The plan file MUST use markdown format that task-dispatcher can parse:

```markdown
# Implementation Plan

## Overview

{summary of what this plan builds}

## Tasks

### Task 1: Create User model

- **Files:** src/models/user.ts
- **Dependencies:** none
- **Complexity:** easy
- **Instructions:**
  Create a User model with:
  - email: string (unique, validated)
  - passwordHash: string
  - createdAt: Date
  - updatedAt: Date

### Task 2: Implement OAuth flow

- **Files:** src/auth/oauth.ts, src/routes/auth.ts
- **Dependencies:** Task 1
- **Complexity:** medium
- **Instructions:**
  Implement OAuth 2.0 with Google:
  - Authorization URL generation
  - Token exchange
  - User info retrieval

## Dependency Graph

Task 1 → Task 2
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

Write plan to `.agents/tmp/phases/1.2-plan.md` and update state:

```json
{
  "phaseId": "1.2",
  "status": "completed",
  "planFilePath": ".agents/tmp/phases/1.2-plan.md",
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

The workflow updates `state.files.plan` with the plan path. The task-dispatcher reads this path to load tasks for wave-based execution.
