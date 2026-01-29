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

Read `.agents/tmp/state.json`. If not found, display:

```
No active workflow found.
Start a new workflow with: /subagents:dispatch <task>
```

## Step 2: Display Standard Status

```
Subagents Workflow Status
=========================
Task: <task description>
Status: <in_progress | stopped | completed | failed>
Started: <startedAt formatted>
Current: <STAGE> Stage → Phase <X.X>

Progress:
✓ EXPLORE Stage (completed)
  ✓ 0 Explore (5 agents)

✓ PLAN Stage (completed)
  ✓ 1.1 Brainstorm
  ✓ 1.2 Plan (3 agents)
  ✓ 1.3 Plan Review (0 issues)

⟳ IMPLEMENT Stage (in_progress)
  ⟳ 2.1 Tasks (Wave 2: 2/5 tasks)
  ○ 2.2 Simplify (pending)
  ○ 2.3 Implementation Review (pending)

○ TEST Stage (pending)
○ FINAL Stage (pending)
```

## Step 3: Display Verbose Details (if --verbose)

If `--verbose` flag present, include task-level details:

```
Task Details:
-------------
Phase 2.1 Tasks (Wave 2):
  Wave 1 (completed):
    ✓ task-1: Create User model (sonnet-4.5, easy) - 45s
    ✓ task-3: Add config (sonnet-4.5, easy) - 30s

  Wave 2 (in_progress):
    ⟳ task-2: Implement OAuth flow (opus-4.5, medium) - running
    ○ task-4: Create auth routes (sonnet-4.5, easy) - pending

Active Task Agents: 1
```

## Step 4: Display Stopped Info (if applicable)

If `status` is `stopped`:

```
Workflow paused at: <stoppedAt formatted>
To resume: /subagents:resume
```

## Step 5: Display Failed Info (if applicable)

If `status` is `failed`:

```
Workflow failed at Phase <failure.phase>: <failure.error>
Failed at: <failure.failedAt>

To retry: /subagents:resume --retry-failed
To skip: /subagents:resume --from-phase <next phase>
```
