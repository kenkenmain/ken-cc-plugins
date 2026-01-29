---
name: orchestration
description: Main orchestrator for 4-tier hierarchical agent workflow - coordinates stages sequentially
---

# Orchestration Skill

Top-level coordinator for the subagents workflow. Dispatches stage agents sequentially and aggregates results.

## Tier 1: Orchestrator Role

Only tier with full context. Receives task/config, dispatches stage agents sequentially with minimal context, aggregates results.

## Workflow

```
User Task → Orchestrator → PLAN Stage → IMPLEMENT Stage → TEST Stage → FINAL Stage → Complete
```

## Step 1: Load State and Config

Read state, load merged config, determine starting point.

## Step 2: Execute Stages Sequentially

For each stage (PLAN → IMPLEMENT → TEST → FINAL):

### Check if Stage is Enabled

```
if stage == "TEST" and not config.stages.TEST.enabled:
    skip to next stage
```

### Prepare Stage Context (MINIMAL)

Create context for stage agent - NO conversation history:

```json
{
  "task": "<max 200 chars summary of user task>",
  "stageName": "IMPLEMENT",
  "stageConfig": {
    /* only config for THIS stage */
  },
  "previousStageSummary": "<one paragraph summary of previous stage output>",
  "planFilePath": "docs/plans/2026-01-28-feature-plan.md"
}
```

### Dispatch Stage Agent

Use Task tool to dispatch stage agent:

```
Task(
  description: "Execute IMPLEMENT stage",
  prompt: "<stage context JSON>",
  subagent_type: "subagents:stage-agent",
  model: config.stages.IMPLEMENT.model || "inherit"
)
```

### Wait for Stage Completion

Stage agent returns structured result:

```json
{
  "stageName": "IMPLEMENT",
  "status": "completed",
  "summary": "<one paragraph summary>",
  "phases": {
    "2.0": { "status": "completed" },
    "2.1": { "status": "completed", "tasksCompleted": 5 },
    "2.2": { "status": "completed" },
    "2.3": { "status": "completed", "issues": [] }
  }
}
```

### Update State

After each stage completes:

1. Update `.agents/subagents-state.json`
2. Set `currentStage` to next stage
3. Store stage summary for next stage's context

## Steps 3-5: Stop, Errors, Completion

**Stop:** Wait for stage completion, save stopped state, return summary.

**Errors:** Log to state, set failed status, report with context.

**Completion:** Set completed status, return final summary.

## Context Isolation

**Send down:** Task summary (max 200 chars), stage config, previous stage summary.

**Never send:** Conversation history, raw files, verbose outputs, other stage details.

**Receive up:** Stage status, summary, phase status, errors.

## State Management

Update state after EVERY stage transition:

```json
{
  "currentStage": "IMPLEMENT",
  "planFilePath": "docs/plans/2026-01-28-feature-plan.md",
  "stages": {
    "PLAN": { "status": "completed", "summary": "..." },
    "IMPLEMENT": { "status": "in_progress" }
  }
}
```

**planFilePath source:** The PLAN stage (Phase 1.2) creates the plan file. The stage agent returns the path in its output, which the orchestrator persists to state. All subsequent stages read planFilePath from state.

### Atomic Write Protocol

Write to temp file, validate JSON, atomic rename. On load, if temp exists, delete it (interrupted write) and load from main file.

## Resumption

Load state to find position, reload config, continue from saved position with previous stage summaries.

## User Interaction

Use `AskUserQuestion` for stop confirmation, error recovery decisions, and clarifying ambiguous requirements. Not for routine updates, config decisions, or mid-task questions.
