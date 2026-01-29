---
name: phase-executor
description: Tier 3 executor - manages task execution within a phase, dispatches task agents with complexity scoring
---

# Phase Executor Skill

Tier 3 in the hierarchy. Executes tasks within a phase, dispatching task agents with dynamic complexity scoring.

## Phase-Specific Behavior

- **Phase 1.2 (Write Plan):** Invoke `plan-writer` skill to create plan with `tasks:` YAML schema. Return `planFilePath` in output.
- **Phase 2.1+ (Implementation):** Use this skill's task dispatch workflow below.

## Tier 3: Phase Agent Role

For implementation phases: receive minimal context (phase name, config, task list), read task details, classify complexity, dispatch task agents, aggregate results.

## Input Context

Receive from stage agent:

```json
{
  "phaseName": "implementation",
  "phaseId": "2.1",
  "phaseConfig": {
    /* config for this phase */
  },
  "previousPhaseSummary": "Classification complete: 5 tasks assigned models",
  "taskList": ["task-1", "task-2", "task-3", "task-4", "task-5"],
  "planFilePath": "docs/plans/2026-01-28-feature-plan.md"
}
```

## Step 1: Load Task Details

Read plan file from `planFilePath` in context. Parse `tasks:` YAML block (see `plan-writer` skill for schema). Extract task id, description, targetFiles, instructions, dependencies.

## Step 2: Build Dependency Graph

Check task dependencies, group into execution waves (parallel tasks in same wave, sequential across waves).

## Step 3: Execute Tasks

For each wave:

### For Each Task in Wave

#### 3a. Classify Complexity (Dynamic)

Invoke `complexity-scorer` skill for THIS task:

```
Input: {
  "taskId": "task-2",
  "description": "Implement OAuth flow with Google and GitHub",
  "targetFiles": ["src/auth/oauth.ts", "src/routes/auth.ts"],
  "instructions": "Full OAuth 2.0 implementation..."
}

Output: {
  "taskId": "task-2",
  "complexity": "hard",
  "model": "opus",
  "needsCodexReview": true,
  "reasoning": "Multiple files, external API integration, security concern"
}
```

#### 3b. Prepare Task Context (MINIMAL)

```json
{
  "taskId": "task-2",
  "description": "Implement OAuth flow (max 100 chars)",
  "targetFiles": ["src/auth/oauth.ts", "src/routes/auth.ts"],
  "instructions": "Specific instructions (max 2000 chars)",
  "dependencyOutputs": [
    { "taskId": "task-1", "summary": "Created User model... (max 500 chars)" }
  ],
  "constraints": {
    "maxReadFiles": 10,
    "maxWriteFiles": 3,
    "allowBashCommands": false
  }
}
```

#### 3c. Dispatch Task Agent

Use Task tool with model from complexity scorer:

```
Task(
  description: "Implement OAuth flow",
  prompt: "<task context JSON>",
  subagent_type: "subagents:task-agent",
  model: classification.model,  // "opus" for hard tasks
  run_in_background: isParallel  // true for parallel waves
)
```

#### 3d. Collect Result

Task agent returns:

```json
{
  "taskId": "task-2",
  "status": "completed",
  "summary": "Implemented OAuth with Google/GitHub providers (max 500 chars)",
  "filesModified": ["src/auth/oauth.ts", "src/routes/auth.ts"],
  "errors": []
}
```

#### 3e. Run Codex Review (if hard task)

If `needsCodexReview: true`:

```
Invoke mcp__codex-xhigh__codex to review task-2 output
If issues found, use bugFixer to fix
```

### Wait for Wave Completion

If parallel execution, wait for all tasks in wave to complete before starting next wave.

## Step 4: Handle Errors

Log error, check retry logic, re-dispatch if retryable, otherwise mark phase failed.

## Step 5: Return Phase Summary

After all tasks complete:

```json
{
  "phaseId": "2.1",
  "status": "completed",
  "summary": "Implemented 5 tasks: User model, OAuth flow, JWT middleware, auth routes, session mgmt",
  "tasksCompleted": 5,
  "taskResults": {
    "task-1": { "status": "completed", "complexity": "easy" },
    "task-2": {
      "status": "completed",
      "complexity": "hard",
      "codexReviewed": true
    },
    "task-3": { "status": "completed", "complexity": "medium" }
  },
  "errors": []
}
```

## Context Isolation

**Receive from stage:** Phase name/config, task IDs, previous phase summary.

**Send to tasks:** Task description (max 100), target files, instructions (max 2000), dependency summaries (max 500 each), constraints.

**Never send:** Full plan, other tasks, stage context, conversation history.

**Receive from tasks:** Status, summary (max 500), modified files, errors.

## Parallel vs Sequential

**Parallel** (within wave): research, read-only reviews, no file conflicts. Use `run_in_background: true`.

**Sequential**: implementation with file conflicts, strict ordering. Use `run_in_background: false`.

## Entry/Exit Criteria

**Entry:** Previous phase complete, plan readable, task list non-empty (except inline phases).

**Exit:** All tasks complete/failed with reason, results aggregated, summary generated, no pending tasks.

## Phase 2.0 Classification Note

Classification happens inline during Phase 2.1 (not standalone). For each task, invoke `complexity-scorer` before dispatch. State shows 2.0 complete when 2.1 starts.

## Constraint Enforcement

**Content:** Truncate description (>100), instructions (>2000), dependencies (>500) with `[TRUNCATED]` marker.

**Files:** Enforce maxReadFiles/maxWriteFiles limits.

**Bash:** Block if `allowBashCommands: false`.

Violations cause task failure.
