---
name: workflow
description: Main workflow orchestration - executes stages sequentially with file-based state
---

# Workflow Orchestration

Main workflow skill that coordinates all stages. Replaces the old orchestrator agent.

## Workflow Stages

```
EXPLORE → PLAN → IMPLEMENT → TEST → FINAL
```

## Execution Flow

### EXPLORE Stage (Phase 0)

1. Use `explore-dispatcher` skill
2. Dispatch parallel Explore agents
3. Write findings to `.agents/tmp/phases/0-explore.md`
4. Update state, compact context

### PLAN Stage

**Phase 1.1: Brainstorm (inline)**

1. Read explore findings
2. Analyze and determine approach
3. Write decisions to `.agents/tmp/phases/1.1-brainstorm.md`

**Phase 1.2: Parallel Plan**

1. Use `plan-dispatcher` skill
2. Dispatch parallel Plan agents
3. Write merged plan to `.agents/tmp/phases/1.2-plan.md`

**Phase 1.3: Plan Review**

1. Use Codex MCP (codex-high) to review plan
2. If issues found, iterate or ask user
3. Write review to `.agents/tmp/phases/1.3-plan-review.json`
4. Update state, compact context

### IMPLEMENT Stage

**Phase 2.1: Task Execution**

1. Use `task-dispatcher` skill
2. Dispatch tasks in waves based on dependencies
3. Write results to `.agents/tmp/phases/2.1-tasks.json`

**Phase 2.2: Simplify**

1. Review implemented code for simplification
2. Write notes to `.agents/tmp/phases/2.2-simplify.md`

**Phase 2.3: Implementation Review**

1. Use Codex MCP to review implementation
2. Write review to `.agents/tmp/phases/2.3-impl-review.json`
3. Update state, compact context

### TEST Stage

**Phase 3.1: Run Tests**

1. Run configured test commands (lint, test)
2. Write results to `.agents/tmp/phases/3.1-test-results.json`

**Phase 3.2: Analyze Failures**

1. If tests failed, analyze and suggest fixes
2. Optionally dispatch fix agents

**Phase 3.3: Test Review**

1. Use Codex MCP to review test coverage
2. Update state, compact context

### FINAL Stage

**Phase 4.1: Documentation Updates**

1. Update relevant documentation

**Phase 4.2: Final Review**

1. Use Codex MCP (codex-xhigh) for final review

**Phase 4.3: Completion**

1. Create git branch and PR (if configured)
2. Set state to completed

## Context Compaction

Between stages (when `compaction.betweenStages: true`):

1. Write stage summary to file
2. Update state with file pointer
3. Clear conversation of stage details
4. Next stage reads only needed files

Between phases (when `compaction.betweenPhases: true`):

1. Same process but after each phase
2. More aggressive context management

## State Updates

After each phase:

```json
{
  "currentStage": "IMPLEMENT",
  "currentPhase": "2.1",
  "stages": {
    "IMPLEMENT": {
      "status": "in_progress",
      "phases": {
        "2.1": { "status": "in_progress" }
      }
    }
  }
}
```

## Error Handling

On failure:

1. Record failure in state using `state-manager` skill
2. Offer retry/skip/abort options via AskUserQuestion
3. If retry, reload state and continue from failure point

## Skip Stages

If stage disabled in config (e.g., `stages.TEST.enabled: false`):

1. Skip all phases in that stage
2. Update state to mark as skipped
3. Continue to next stage
