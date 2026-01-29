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

### Schedule-Driven Execution

The workflow iterates over `state.schedule` entries instead of hardcoded stage logic:

1. Read `state.schedule` from state
2. Find current position (first entry where phase matches `state.currentPhase`, or first `pending` phase)
3. For each schedule entry from current position:
   a. Execute the phase based on its `type` (see per-stage sections below)
   b. Mark phase as `completed` in state
   c. Call `Advance Phase` (state-manager) to move to next entry
   d. If `Advance Phase` returns gate failure → halt, report missing phases
4. After all entries complete → workflow is done

**CRITICAL: Never skip a schedule entry.** Every phase in the schedule must either complete or be explicitly handled (stage disabled/skipped). The schedule is the single source of truth for phase ordering.

### EXPLORE Stage (Phase 0)

1. Use `explore-dispatcher` skill
2. Dispatch parallel Explore agents
3. Write findings to `.agents/tmp/phases/0-explore.md`
4. Update state, compact context

**Gate enforcement:** Phase 0 output (`0-explore.md`) is a required gate artifact for the EXPLORE→PLAN transition. The workflow CANNOT proceed to Phase 1.1 without this file.

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

1. Dispatch codex-reviewer subagent:
   ```
   Task(
     description: "Review: plan",
     prompt: "Review the implementation plan at .agents/tmp/phases/1.2-plan.md. Use prompts/high-stakes/plan-review.md criteria. Tool: codex-high.",
     subagent_type: "subagents:codex-reviewer"
   )
   ```
2. If issues found (based on blockOnSeverity, default: low):
   - Dispatch bugFixer (default: codex-high) to fix issues
   - Re-run codex-reviewer
   - Repeat until approved or max retries
3. Write review to `.agents/tmp/phases/1.3-plan-review.json`
4. Update state, compact context

**Gate enforcement:** The PLAN→IMPLEMENT gate requires both `1.2-plan.md` and `1.3-plan-review.json`. The workflow CANNOT proceed to Phase 2.1 without both files. If codex-reviewer fails after max retries, the workflow blocks — it does NOT skip to IMPLEMENT.

### IMPLEMENT Stage

**Phase 2.1: Task Execution**

1. Use `task-dispatcher` skill
2. Dispatch tasks in waves based on dependencies:
   - Easy/Medium → Task agents (sonnet-4.5/opus-4.5)
   - Hard → Codex MCP (codex-xhigh) via codex-reviewer subagent
3. Write results to `.agents/tmp/phases/2.1-tasks.json`

**Phase 2.2: Simplify**

1. Review implemented code for simplification
2. Write notes to `.agents/tmp/phases/2.2-simplify.md`

**Phase 2.3: Implementation Review**

1. Dispatch codex-reviewer subagent:
   ```
   Task(
     description: "Review: implementation",
     prompt: "Review the implementation. Files: [modified files]. Use prompts/high-stakes/implementation.md criteria. Tool: codex-high.",
     subagent_type: "subagents:codex-reviewer"
   )
   ```
2. If issues found (based on blockOnSeverity, default: low):
   - Dispatch bugFixer (default: codex-high) to fix each issue
   - Re-run codex-reviewer
   - Repeat until no blocking issues or max retries
3. Write review to `.agents/tmp/phases/2.3-impl-review.json`
4. Update state, compact context

**Gate enforcement:** The IMPLEMENT→TEST gate requires both `2.1-tasks.json` and `2.3-impl-review.json`. The workflow CANNOT proceed to Phase 3.1 without both files. If codex-reviewer fails after max retries, the workflow blocks — it does NOT skip to TEST.

### TEST Stage

**Phase 3.1: Run Tests**

1. Run configured test commands (lint, test)
2. Write results to `.agents/tmp/phases/3.1-test-results.json`

**Phase 3.2: Analyze Failures**

1. If tests failed, analyze and suggest fixes
2. Optionally dispatch fix agents

**Phase 3.3: Test Review**

1. Dispatch codex-reviewer subagent:
   ```
   Task(
     description: "Review: tests",
     prompt: "Review test coverage and quality. Files: [test files]. Use prompts/high-stakes/test-review.md criteria. Tool: codex-high.",
     subagent_type: "subagents:codex-reviewer"
   )
   ```
2. If issues found (based on blockOnSeverity, default: low):
   - Dispatch bugFixer (default: codex-high) to fix each issue
   - Re-run codex-reviewer
   - Repeat until no blocking issues or max retries
3. Write review to `.agents/tmp/phases/3.3-test-review.json`
4. Update state, compact context

**Gate enforcement:** The TEST→FINAL gate requires both `3.1-test-results.json` and `3.3-test-review.json`. The workflow CANNOT proceed to Phase 4.1 without both files. If codex-reviewer fails after max retries, the workflow blocks — it does NOT skip to FINAL.

### FINAL Stage

**Phase 4.1: Documentation Updates**

1. Update relevant documentation

**Phase 4.2: Final Review**

1. Dispatch codex-reviewer subagent with high reasoning:
   ```
   Task(
     description: "Review: final",
     prompt: "Final review of all changes. Use prompts/high-stakes/final-review.md criteria. Tool: codex-xhigh. Files: [all modified files].",
     subagent_type: "subagents:codex-reviewer"
   )
   ```
2. If issues found (based on blockOnSeverity, default: low):
   - Dispatch bugFixer (default: codex-high) to fix each issue
   - Re-run codex-reviewer
   - Repeat until no blocking issues or max retries

**Gate enforcement:** Phase 4.2 output (`4.2-final-review.json`) is a required gate artifact for the FINAL→COMPLETE transition. The workflow CANNOT proceed to Phase 4.3 without this file. If codex-reviewer fails after max retries, the workflow blocks — it does NOT skip to Completion.

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

After each phase, use the `Advance Phase` operation from state-manager:

1. Mark current phase as completed in `stages[currentStage].phases[phaseId]`
2. Record output file in `state.files` if applicable
3. Call `Advance Phase` to determine and set the next phase
4. If `Advance Phase` triggers a gate check:
   - Gate passes → currentPhase/currentStage updated automatically
   - Gate fails → workflow halts with blocked status and missing file details

**Never manually set `currentPhase` or `currentStage`.** Always go through `Advance Phase` to ensure gate checks fire.

## Review Status Handling

Review status values differ by type:

- **Plan/Implementation/Test reviews:** `approved` or `needs_revision`
- **Final review:** `approved` or `blocked`

Handling logic:

1. If status is `approved` → proceed to next phase
2. If status is `needs_revision` → check `issues[]` against `blockOnSeverity`, dispatch bugFixer for matching issues, re-review
3. If status is `blocked` (final review only) → hard stop regardless of blockOnSeverity, ask user via AskUserQuestion

## Error Handling

On failure:

1. Record failure in state using `state-manager` skill
2. Classify error type:

| Error Type       | Location                   | Action                           |
| ---------------- | -------------------------- | -------------------------------- |
| Review failure   | Any review phase           | Run bugFixer, retry review       |
| Task failure     | Phase 2.1 task execution   | Retry task or skip with warning  |
| Test failure     | Phase 3.1 (in test file)   | Return to Phase 3.2 to fix tests |
| Code logic error | Phase 3.1 (in source file) | Restart IMPLEMENT stage          |
| Max retries      | Any phase                  | Ask user: retry/skip/abort       |

3. Auto-restart on stage failure:
   - If IMPLEMENT review fails after max retries → restart IMPLEMENT stage
   - If TEST fails with code logic error → restart IMPLEMENT stage
   - If FINAL review fails after max retries → restart TEST stage (or IMPLEMENT if TEST disabled)

4. User options via AskUserQuestion:
   - **Retry phase** - Try current phase again
   - **Restart stage** - Go back to start of current stage
   - **Restart previous stage** - Go back to fix root cause
   - **Skip** - Continue with warning
   - **Abort** - Stop workflow, save state

## Stage Restarts

A stage can be restarted at any point — automatically on classified errors, or manually via resume flags.

### When Restarts Happen

| Trigger                               | Restart Target                       |
| ------------------------------------- | ------------------------------------ |
| IMPLEMENT review fails (max retries)  | IMPLEMENT                            |
| TEST code logic error (source file)   | IMPLEMENT                            |
| FINAL review fails (max retries)      | TEST (or IMPLEMENT if TEST disabled) |
| User chooses "Restart stage"          | Current stage                        |
| User chooses "Restart previous stage" | Previous stage                       |

### Restart Procedure

When restarting a stage:

1. **Reset phase states** - Set all phases in that stage back to `pending`
2. **Preserve prior stage outputs** - EXPLORE/PLAN outputs remain (don't re-explore)
3. **Clear stage output files** - Delete `.agents/tmp/phases/{stage phases}` files:
   - PLAN restart: delete `1.1-brainstorm.md`, `1.2-plan.md`, `1.3-plan-review.json`
   - IMPLEMENT restart: delete `2.1-tasks.json`, `2.2-simplify.md`, `2.3-impl-review.json`
   - TEST restart: delete `3.1-test-results.json`, `3.2-*`, `3.3-test-review.json`
   - FINAL restart: delete `4.1-*`, `4.2-*` output files
4. **Update state** via `state-manager`:
   ```json
   {
     "currentStage": "IMPLEMENT",
     "currentPhase": "2.1",
     "stages": {
       "IMPLEMENT": {
         "status": "in_progress",
         "restartCount": 1,
         "phases": {
           "2.1": { "status": "pending" },
           "2.2": { "status": "pending" },
           "2.3": { "status": "pending" }
         }
       }
     }
   }
   ```
5. **Resume execution** from first phase of restarted stage
6. **Increment restartCount** - Track for max restart limits

### Max Restarts

Default: 3 restarts per stage (configurable via `retries.maxPerStage`).

After max restarts, ask user:

- **Force continue** - Proceed despite issues
- **Abort** - Stop workflow

### Cross-Stage Restarts

When restarting a previous stage (e.g., IMPLEMENT from TEST):

1. Mark current stage as `blocked` with reason
2. Mark target stage as `restarting`
3. Reset target stage phases
4. Clear output files from target stage AND current stage
5. Resume from target stage

## Skip Stages

If stage disabled in config (e.g., `stages.TEST.enabled: false`):

1. Skip all phases in that stage
2. Update state to mark as skipped
3. Continue to next stage
