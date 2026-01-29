---
description: Checkpoint and pause the current subagent workflow
argument-hint:
allowed-tools: Read, Write, Bash, Skill
---

# Stop Subagent Workflow

Checkpoint the current workflow and pause execution. The workflow can be resumed later with `/subagents:resume`.

## Step 1: Check Active Workflow

Read state file. If not found or not in_progress, display error and exit.

## Step 2: Wait for Current Phase

Wait for current phase to complete. Display waiting message.

## Step 3: Save Checkpoint

Update state (status=stopped, set stoppedAt timestamp, save completed phase outputs).

## Step 4: Display Summary

```
Subagent Workflow Stopped
=========================
Task: <task description>
Stopped at: <timestamp>
Position: <STAGE> Stage → Phase <X.X> (<phase name>)

Completed:
✓ PLAN Stage
  ✓ 1.1 Brainstorm
  ✓ 1.2 Write Plan
  ✓ 1.3 Plan Review

Next: <next phase description>

To resume: /subagents:resume
```
