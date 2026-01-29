---
description: Show current subagent workflow progress and status
argument-hint: [--verbose]
allowed-tools: Read
---

# Subagent Workflow Status

Display the current status and progress of the subagent workflow.

## Arguments

- `--verbose`: Show detailed task-level information

Parse from $ARGUMENTS.

## Step 1: Load State

Read state file. If not found, display error and exit.

## Step 2: Display Standard Status

```
Subagents Workflow Status
=========================
Task: <task description>
Status: <in_progress | stopped | completed | failed>
Started: <startedAt formatted>
Current: <STAGE> Stage → Phase <X.X> (<phase name>)

Progress:
✓ PLAN Stage (completed)
  ✓ 1.1 Brainstorm
  ✓ 1.2 Write Plan
  ✓ 1.3 Plan Review (0 issues)

⟳ IMPLEMENT Stage (in_progress)
  ✓ 2.0 Classification (3 tasks classified)
  ⟳ 2.1 Implementation (2/5 tasks)
  ○ 2.2 Simplify (pending)
  ○ 2.3 Implement Review (pending)

○ TEST Stage (pending)
○ FINAL Stage (pending)
```

## Step 3: Display Verbose Details (if --verbose)

If `--verbose` flag present, include task-level details:

```
Task Details:
-------------
Phase 2.1 Implementation:
  ✓ task-1: Create User model (sonnet, easy) - 45s
  ⟳ task-2: Implement OAuth flow (opus, hard) - running
  ○ task-3: Add JWT middleware (opus, medium) - pending
  ○ task-4: Create auth routes (sonnet, easy) - pending
  ○ task-5: Add session management (opus, medium) - pending

Active Subagents: 2
  - stage-agent-abc123 (IMPLEMENT Stage)
  - task-agent-xyz789 (task-2, opus)
```

## Step 4: Display Stopped Info (if applicable)

If `status` is `stopped`:

```
Workflow paused at: <stoppedAt formatted>
To resume: /subagents:resume
```
