---
description: Checkpoint and pause the current iteration workflow
argument-hint:
allowed-tools: Read, Write, Bash
---

# Stop Iteration Workflow

Checkpoint the current workflow and pause execution. The workflow can be resumed later with `/superpowers-iterate:resume`.

## Step 1: Check Active Workflow

Read `.agents/tmp/iterate/state.json`.

If not found:

```
No active iteration workflow found.
Start a new workflow with: /superpowers-iterate:iterate <task>
```

If status is not `in_progress`:

```
Workflow is not running (status: {status}).
Nothing to stop.
```

Exit in both cases.

## Step 2: Wait for Current Phase

If a subagent is currently executing, wait for it to complete. Display waiting message:

```
Waiting for current phase to complete before checkpointing...
```

## Step 3: Save Checkpoint

Update state file `.agents/tmp/iterate/state.json`:

- Set `status` to `"stopped"`
- Set `stoppedAt` to current ISO-8601 timestamp
- Preserve all other state (currentPhase, currentIteration, schedule, etc.)

Read current state, update the fields, and write back:

```bash
jq --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  '.status = "stopped" | .stoppedAt = $ts | .updatedAt = $ts' \
  .agents/tmp/iterate/state.json > .agents/tmp/iterate/state.json.tmp \
  && mv .agents/tmp/iterate/state.json.tmp .agents/tmp/iterate/state.json
```

## Step 4: Display Summary

Read the updated state and display:

```
Iteration Workflow Stopped
===========================
Task: {task}
Mode: {mode}
Stopped at: {stoppedAt}
Position: Iteration {currentIteration} -> Phase {currentPhase} ({phase name})

Completed phases this iteration:
  * Phase 1 | Brainstorm    | completed
  * Phase 2 | Plan          | completed
  * Phase 3 | Plan Review   | completed

Next: Phase {currentPhase} ({phase name from schedule})

Iteration history: {currentIteration - 1} previous iteration(s) completed

To resume: /superpowers-iterate:resume
```

Show completed phases by checking `stages[stage].phases[phase].status` for each entry in the schedule up to the current phase.
