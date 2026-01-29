---
name: stage-coordinator
description: Tier 2 coordinator - executes phases within a stage sequentially
---

# Stage Coordinator Skill

Tier 2 in the hierarchy. Coordinates phases within a stage, dispatching phase agents sequentially.

## Tier 2: Stage Agent Role

Receive minimal context (stage name, config, previous summary), execute phases sequentially, dispatch one phase at a time, return stage summary.

## Input Context

Receive from orchestrator:

```json
{
  "task": "Brief task description (max 200 chars)",
  "stageName": "IMPLEMENT",
  "stageConfig": {
    /* config for this stage only */
  },
  "previousStageSummary": "One paragraph summary of previous stage",
  "planFilePath": "docs/plans/2026-01-28-feature-plan.md"
}
```

## Stage Phases

### PLAN Stage (Phases 1.1 - 1.3)

```
1.1 Brainstorm → 1.2 Write Plan → 1.3 Plan Review
```

**Phase 1.2 MUST invoke `plan-writer` skill** to create a plan with the required `tasks:` YAML schema. The phase output includes `planFilePath` which is persisted to state.

### IMPLEMENT Stage (Phases 2.0 - 2.3)

```
2.0 Classification → 2.1 Implementation → 2.2 Simplify → 2.3 Implement Review
```

Note: Classification (2.0) is not a separate phase - it happens INLINE during 2.1. In state tracking, mark 2.0 as "completed" when 2.1 begins.

### TEST Stage (Phases 3.1 - 3.3)

```
3.1 Test Plan → 3.2 Write Tests → 3.3 Test Review
```

### FINAL Stage (Phases 4.0 - 4.3)

```
4.0 Document Updates → 4.1 Codex Final → 4.2 Suggest Extensions → 4.3 Completion
```

## Step 1: Initialize

Parse input, determine phases, set current phase to first.

## Step 2: Execute Phases Sequentially

For each phase in stage:

### Prepare Phase Context (MINIMAL)

```json
{
  "phaseName": "implementation",
  "phaseId": "2.1",
  "phaseConfig": {
    /* config for this phase only */
  },
  "previousPhaseSummary": "One paragraph summary",
  "taskList": ["task-1", "task-2", "task-3"],
  "planFilePath": "docs/plans/2026-01-28-feature-plan.md"
}
```

### Dispatch Phase Agent

Use Task tool:

```
Task(
  description: "Execute phase 2.1 implementation",
  prompt: "<phase context JSON>",
  subagent_type: "subagents:phase-agent",
  model: phaseConfig.model || "inherit"
)
```

### Wait for Phase Completion

Phase agent returns:

```json
{
  "phaseId": "2.1",
  "status": "completed",
  "summary": "Implemented 5 tasks: User model, OAuth flow, JWT middleware...",
  "tasksCompleted": 5,
  "errors": []
}
```

### Check Exit Criteria

Each phase has exit criteria (see plan). If not met:

- For review phases: retry up to maxRetries
- For implementation: continue or ask user

### Update State

Save phase completion to state before proceeding.

## Step 3: Handle Review Phases

For review phases (1.3, 2.3, 3.3, 4.1): invoke MCP tool, check for blocking issues, use bugFixer and retry (up to maxRetries), continue when approved or retries exhausted.

## Step 4: Return Stage Summary

After all phases complete, return to orchestrator:

```json
{
  "stageName": "IMPLEMENT",
  "status": "completed",
  "summary": "Implementation complete: 5 tasks executed, code simplified, review passed",
  "phases": {
    "2.0": { "status": "completed", "classifications": 5 },
    "2.1": { "status": "completed", "tasksCompleted": 5 },
    "2.2": { "status": "completed" },
    "2.3": { "status": "completed", "issues": [] }
  }
}
```

**PLAN stage output:** Include `planFilePath` in return:

```json
{
  "stageName": "PLAN",
  "status": "completed",
  "planFilePath": "docs/plans/2026-01-28-feature-plan.md",
  "summary": "...",
  "phases": { ... }
}
```

The orchestrator persists this to state for subsequent stages.

## Context Isolation

**Receive from orchestrator:** Task summary (max 200), stage config, previous stage summary.

**Send to phases:** Phase name/config, previous phase summary, task IDs only.

**Never send:** Full task descriptions, previous stage details, other phase outputs.

**Receive from phases:** Status, summary, task/error counts.
