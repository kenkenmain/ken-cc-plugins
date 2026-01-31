---
description: Checkpoint and pause the current kenken workflow
argument-hint:
allowed-tools: Read, Write, Bash, Skill
---

# Stop kenken Workflow

Checkpoint the current workflow and pause execution. The workflow can be resumed later with `/kenken:iterate-resume`.

## Step 1: Check Active Workflow

Read `.agents/tmp/kenken/state.json`. If not found or not `in_progress`, display error and exit:

```
No active workflow found.
Start a new workflow with: /kenken:iterate <task>
```

If status is already `stopped`:

```
Workflow is already stopped.
To resume: /kenken:iterate-resume
```

If status is `completed`:

```
Workflow already completed. Nothing to stop.
```

## Step 2: Wait for Current Phase

If a subagent is currently executing, wait for it to complete. Display:

```
Waiting for current phase to complete before stopping...
```

## Step 3: Save Checkpoint

Update `.agents/tmp/kenken/state.json`:

- Set `status` to `"stopped"`
- Set `stoppedAt` to current ISO-8601 timestamp
- Set `updatedAt` to current ISO-8601 timestamp
- Preserve all other state (currentPhase, currentStage, schedule, etc.)

## Step 4: Display Summary

Show what was completed and what remains:

```
kenken Workflow Stopped
========================
Task: {task description}
Stopped at: {stoppedAt formatted}
Position: {currentStage} Stage -> Phase {currentPhase} ({phase name})

Completed:
  ✓ PLAN Stage
    ✓ 1.1 Brainstorm
    ✓ 1.2 Plan
    ✓ 1.3 Plan Review

Remaining:
  o IMPLEMENT Stage
    o 2.1 Implementation
    o 2.2 Simplify
    o 2.3 Impl Review
  ...

To resume: /kenken:iterate-resume
```

Build the completed/remaining display by iterating `state.schedule`:

- For each entry before `currentPhase`: show under "Completed" with `✓`
- For each entry at or after `currentPhase`: show under "Remaining" with `o`
- Group entries by stage for readability
