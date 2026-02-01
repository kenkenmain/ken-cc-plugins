---
name: state-manager
description: Manage workflow state in .agents/tmp/state.json with atomic writes
---

# State Manager

Manage subagents workflow state with file-based persistence.

## State Location

`.agents/tmp/state.json` - All workflow state persisted here.

## State Schema (v2)

```json
{
  "version": 2,
  "task": "<task description>",
  "status": "pending|in_progress|stopped|completed|failed|blocked|restarting|skipped",
  "currentStage": "EXPLORE|PLAN|IMPLEMENT|TEST|FINAL",
  "currentPhase": "0|1.1|1.2|1.3|2.1|2.2|2.3|3.1|3.2|3.3|3.4|3.5|4.1|4.2|4.3",
  "pipelineProfile": "minimal|standard|thorough",
  "codexAvailable": true,
  "ownerPpid": "<session PID for scoping>",
  "worktree": {
    "path": "/absolute/path/to/repo--subagent",
    "branch": "subagents/task-slug",
    "createdAt": "<ISO timestamp>"
  },
  "reviewer": "subagents:codex-reviewer|subagents:claude-reviewer",
  "failureAnalyzer": "subagents:codex-failure-analyzer|subagents:failure-analyzer",
  "difficultyEstimator": "subagents:codex-difficulty-estimator|subagents:difficulty-estimator",
  "testDeveloper": "subagents:codex-test-developer|subagents:test-developer",
  "docUpdater": "subagents:codex-doc-updater|subagents:doc-updater",
  "taskAnalysis": {
    "complexity": "simple|medium|complex",
    "needsTests": true,
    "needsDocs": true,
    "reasoning": "..."
  },
  "schedule": [
    { "phase": "0", "stage": "EXPLORE", "name": "Explore", "type": "dispatch" },
    {
      "phase": "1.1",
      "stage": "PLAN",
      "name": "Brainstorm",
      "type": "subagent"
    },
    { "phase": "1.2", "stage": "PLAN", "name": "Plan", "type": "dispatch" },
    {
      "phase": "1.3",
      "stage": "PLAN",
      "name": "Plan Review",
      "type": "review"
    },
    {
      "phase": "2.1",
      "stage": "IMPLEMENT",
      "name": "Task Execution",
      "type": "dispatch"
    },
    {
      "phase": "2.2",
      "stage": "IMPLEMENT",
      "name": "Simplify",
      "type": "subagent"
    },
    {
      "phase": "2.3",
      "stage": "IMPLEMENT",
      "name": "Implementation Review",
      "type": "review"
    },
    { "phase": "3.1", "stage": "TEST", "name": "Run Tests & Analyze", "type": "subagent" },
    {
      "phase": "3.2",
      "stage": "TEST",
      "name": "Analyze Failures",
      "type": "subagent"
    },
    {
      "phase": "3.3",
      "stage": "TEST",
      "name": "Develop Tests",
      "type": "subagent"
    },
    {
      "phase": "3.4",
      "stage": "TEST",
      "name": "Test Dev Review",
      "type": "review"
    },
    {
      "phase": "3.5",
      "stage": "TEST",
      "name": "Test Review",
      "type": "review"
    },
    {
      "phase": "4.1",
      "stage": "FINAL",
      "name": "Documentation",
      "type": "subagent"
    },
    {
      "phase": "4.2",
      "stage": "FINAL",
      "name": "Final Review",
      "type": "review"
    },
    {
      "phase": "4.3",
      "stage": "FINAL",
      "name": "Completion",
      "type": "subagent"
    }
  ],
  "gates": {
    "EXPLORE->PLAN": { "required": ["0-explore.md"], "phase": "0" },
    "PLAN->IMPLEMENT": {
      "required": ["1.2-plan.md", "1.3-plan-review.json"],
      "phase": "1.3"
    },
    "IMPLEMENT->TEST": {
      "required": ["2.1-tasks.json", "2.3-impl-review.json"],
      "phase": "2.3"
    },
    "TEST->FINAL": {
      "required": ["3.1-test-results.json", "3.3-test-dev.json", "3.5-test-review.json"],
      "phase": "3.5"
    },
    "FINAL->COMPLETE": { "required": ["4.2-final-review.json"], "phase": "4.2" }
  },
  "stages": {
    "EXPLORE": { "status": "pending", "agentCount": 0 },
    "PLAN": {
      "status": "pending",
      "phases": {},
      "restartCount": 0,
      "blockReason": null
    },
    "IMPLEMENT": {
      "status": "pending",
      "phases": {},
      "restartCount": 0,
      "blockReason": null
    },
    "TEST": {
      "status": "pending",
      "enabled": true,
      "restartCount": 0,
      "blockReason": null
    },
    "FINAL": { "status": "pending", "restartCount": 0, "blockReason": null }
  },
  "codexTimeout": {
    "reviewPhases": 300000,
    "finalReviewPhases": null,
    "implementPhases": 1800000,
    "testPhases": 600000,
    "explorePhases": 600000,
    "maxRetries": 2
  },
  "supplementaryPolicy": "on-issues",
  "coverageThreshold": 90,
  "webSearch": true,
  "reviewPolicy": {
    "minBlockSeverity": "LOW",
    "maxFixAttempts": 10,
    "maxStageRestarts": 3
  },
  "restartHistory": [],
  "files": {},
  "failure": null,
  "compaction": { "lastCompactedAt": null, "history": [] },
  "startedAt": null,
  "updatedAt": null,
  "stoppedAt": null
}
```

## Operations

### Initialize State

Create new state file with task and default values:

1. Create `.agents/tmp/` directory if not exists
2. Write initial state with `status: "in_progress"`, `startedAt: now()`
3. Return state object

### Read State

1. Check if `.agents/tmp/state.json` exists
2. Parse JSON and validate version
3. Return state object or null if not found

### Update State

1. Read current state
2. Deep merge updates
3. Set `updatedAt: now()`
4. Write to temp file first
5. Atomic rename to state.json

### Record Phase Output

1. Write output to `.agents/tmp/phases/{phase}-{name}.{ext}` using descriptive names:
   - `0-explore.md`, `1.1-brainstorm.md`, `1.2-plan.md`, `1.3-plan-review.json`
   - `2.1-tasks.json`, `2.3-impl-review.json`
   - `3.1-test-results.json`, `3.3-test-dev.json`, `3.4-test-dev-review.json`, `3.5-test-review.json`
2. Update `state.files` with path
3. Save state

### Record Failure

1. Set `status: "failed"`
2. Set `failure` object with phase, error, context
3. Save state

### Validate Stage Gate

Before transitioning between stages, validate that the gate is satisfied:

1. Determine gate key: `{currentStage}->{nextStage}` (use `COMPLETE` for FINAL->done)
2. Look up gate in `state.gates`
3. For each file in `gate.required`:
   - Check if `.agents/tmp/phases/{file}` exists
   - Check if `state.files` has an entry for the corresponding phase
4. If ANY required file is missing:
   - Set `status: "blocked"`
   - Set `stages[currentStage].blockReason: "Gate check failed: missing {file}. Phase {gate.phase} must complete before transitioning to {nextStage}."`
   - Return `{ passed: false, missing: ["{file}"] }`
5. If all required files exist:
   - Return `{ passed: true }`

**Gate checks are mandatory.** The workflow MUST call this operation before every stage transition. Skipping a gate check is a protocol violation.

### Advance Phase

Move to the next phase in the schedule:

1. Read `state.schedule` to find current phase entry by `state.currentPhase`
2. Find the next entry in the array
3. If next entry's `stage` differs from current -> run "Validate Stage Gate" first
4. If gate passes (or same stage): update `currentPhase` and `currentStage`
5. If gate fails: halt and return gate failure
6. Save state

This replaces ad-hoc phase/stage advancement. The workflow calls `Advance Phase` after every phase completes instead of manually setting currentPhase.

## Failure Schema

```json
{
  "failure": {
    "phase": "2.1",
    "error": "Task agent timeout on task-3",
    "failedAt": "2026-01-29T10:15:00Z",
    "context": {
      "completedTasks": ["task-1", "task-2"],
      "failedTask": "task-3",
      "pendingTasks": ["task-4", "task-5"]
    }
  }
}
```

## Atomic Write Protocol

Always write to temp file first, then rename:

```
1. Write to .agents/tmp/state.json.tmp
2. Validate JSON is parseable
3. Rename to .agents/tmp/state.json
```

This prevents corrupted state if write is interrupted.

## Recovery

On load, if `.agents/tmp/state.json.tmp` exists:

1. Check if main `.agents/tmp/state.json` also exists:
   - If yes: Delete temp file (interrupted write), load main file
   - If no: Rename temp to main (write completed but rename failed), load it
2. If neither exists: Return null (no state)

## Hook Script Integration

State operations are also performed by hook shell scripts in `hooks/lib/state.sh`. The hook scripts implement the same atomic write protocol using jq for JSON manipulation. This skill documents the canonical schema and recovery procedures; hooks handle runtime state updates during workflow execution.
