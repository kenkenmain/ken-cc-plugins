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
  "currentPhase": "0|1.1|1.2|1.3|2.1|2.2|2.3|3.1|3.2|3.3|4.1|4.2|4.3",
  "stages": {
    "EXPLORE": { "status": "pending", "agentCount": 0 },
    "PLAN": { "status": "pending", "phases": {}, "restartCount": 0 },
    "IMPLEMENT": { "status": "pending", "phases": {}, "restartCount": 0 },
    "TEST": { "status": "pending", "enabled": true, "restartCount": 0 },
    "FINAL": { "status": "pending", "restartCount": 0 }
  },
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

1. Write output to `.agents/tmp/phases/{phase}-output.{ext}`
2. Update `state.files` with path
3. Save state

### Record Failure

1. Set `status: "failed"`
2. Set `failure` object with phase, error, context
3. Save state

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
