---
name: ants:swarm
description: Launch a 6-phase swarm workflow using Agent Teams with delegate mode
argument-hint: <task description>
---

# Ants Swarm (Agent Teams)

You are launching a 6-phase ant-colony swarm workflow using Agent Teams delegate mode. Teammates self-claim tasks from a shared task list with dependency chains. TeammateIdle hooks assign work, TaskCompleted hooks enforce quality gates.

Use the `swarm` skill for workflow reference documentation.

## Arguments

- `<task description>`: Required. The task to execute.
- `--worktree`: Optional. Create a git worktree for isolated development.

Parse from $ARGUMENTS to extract the task description and any flags.

## Pipeline

```
Phase A0  │ EXPLORE     │ Forage         │ 3-5 parallel foragers + cartographer → aggregator
Phase A1  │ PLAN        │ Architect      │ single planner → A1-plan.md + A1-tasks.json
Phase A2  │ PLAN-REVIEW │ Blueprint      │ reviewer → A2-review.json
Phase A3  │ BUILD+QUAL  │ Dual-Track     │ workers (task pool) + sentinels + guardians
Phase A4  │ SYNC        │ Queen          │ merge build+quality → ship/loop verdict
Phase A5  │ SHIP        │ Ship           │ nurse (docs) → drone (commit + PR)

Loop: If A4 verdict is "loop" → back to A1 (max 5 loops)
All clean → A5 ships the work
```

## Step 1: Auto-Enable Agent Teams

Set the environment variable to enable Agent Teams:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

This is required. The ants workflow uses Agent Teams exclusively.

## Step 2: Initialize State

Create directories and write state file inline.

### 2a. Create directories

```bash
mkdir -p .agents/tmp/phases
rm -rf .agents/tmp/phases
mkdir -p .agents/tmp/phases
```

### 2b. Create feature branch

```bash
BRANCH_SLUG=$(echo "<task description>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40 | sed 's/-$//')
BRANCH_NAME="feat/ants-${BRANCH_SLUG}"

git checkout main 2>/dev/null || git checkout master
git pull --ff-only origin HEAD 2>/dev/null || true
git checkout -b "$BRANCH_NAME"

# If --worktree flag was provided:
WORKTREE_PATH="../.worktrees/ants-${BRANCH_SLUG}"
git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
cd "$WORKTREE_PATH"
```

Store `BRANCH_NAME` for state.json. If `--worktree` was provided, store `WORKTREE_PATH`; otherwise set it to `null`.

### 2c. Write state.json

Write `.agents/tmp/state.json` with the following structure. Use Bash with jq for atomic write:

```json
{
  "version": 4,
  "plugin": "ants",
  "pipeline": "swarm",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "A0",
  "ownerPpid": "<PPID>",
  "sessionId": "<random hex>",
  "branch": "<BRANCH_NAME>",
  "worktreePath": "<WORKTREE_PATH or null>",
  "teamName": "ants-<BRANCH_SLUG>",
  "maxLoops": 5,
  "loop": 1,
  "schedule": [
    {"phase":"A0","stage":"EXPLORE","label":"Colony Exploration","type":"teams"},
    {"phase":"A1","stage":"PLAN","label":"Architect Plan","type":"teams"},
    {"phase":"A2","stage":"PLAN","label":"Blueprint Review","type":"teams"},
    {"phase":"A3","stage":"BUILD","label":"Dual-Track Execution","type":"teams"},
    {"phase":"A4","stage":"SYNC","label":"Queen Synchronization","type":"teams"},
    {"phase":"A5","stage":"SHIP","label":"Documentation + Ship","type":"teams"}
  ],
  "phases": {
    "A0": {"status": "pending"},
    "A1": {"status": "pending"},
    "A2": {"status": "pending"},
    "A3": {"status": "pending"},
    "A4": {"status": "pending"},
    "A5": {"status": "pending"}
  },
  "circuitBreaker": {
    "consecutiveFailures": 0,
    "maxConsecutiveFailures": 5,
    "maxFixAttempts": 5,
    "maxStageRestarts": 2,
    "fixAttempts": {},
    "stageRestarts": 0
  },
  "taskPool": [],
  "failure": null,
  "messages": [],
  "planApproved": false,
  "shutdown": false,
  "webhookUrl": null,
  "lintConfig": null,
  "configSnapshot": null,
  "compactMetadata": null
}
```

## Step 3: Display Schedule

```
Ants Swarm — 6-Phase Agent Teams Pipeline
==========================================
Phase A0  │ EXPLORE │ Colony Exploration    │ teams → foragers + cartographer + aggregator
Phase A1  │ PLAN    │ Architect Plan        │ teams → architect
Phase A2  │ PLAN    │ Blueprint Review      │ teams → blueprint-reviewer
Phase A3  │ BUILD   │ Dual-Track Execution  │ teams → workers + sentinels + guardians (task pool)
Phase A4  │ SYNC    │ Queen Synchronization │ teams → queen (ship/loop verdict)
Phase A5  │ SHIP    │ Documentation + Ship  │ teams → nurse (docs) + drone (commit + PR)

Dispatch: Agent Teams delegate mode
Hooks: TeammateIdle (task router) + TaskCompleted (quality gate)
Circuit breaker: 5 consecutive failures → halt
```

## Step 4: Create Team and Phase Tasks

**Worktree note:** When `--worktree` is active, all file paths in task descriptions should be relative to the worktree path. The working directory is already set to the worktree from Step 2b, so `.agents/tmp/phases/` paths resolve correctly within the worktree.

### 4a. Create team

Create an Agent Teams team:

```
Teammate({ operation: "spawnTeam", team_name: "ants-<BRANCH_SLUG>" })
```

### 4b. Create phase tasks with dependencies

Use TaskCreate to create the phase task chain. Each phase blocks on its predecessor:

1. **TaskCreate:** subject: "A0: Colony Exploration", description: "Explore the codebase for task: <task>. Dispatch forager and cartographer agents. Write output to .agents/tmp/phases/A0-explore.md", activeForm: "Exploring codebase", blockedBy: []
2. **TaskCreate:** subject: "A1: Architect Plan", description: "Create implementation plan. Read A0-explore.md. Write plan to .agents/tmp/phases/loop-1/A1-plan.md and task descriptors to A1-tasks.json", activeForm: "Planning implementation", addBlockedBy: [A0 task ID]
3. **TaskCreate:** subject: "A2: Blueprint Review", description: "Review the architect plan for completeness and feasibility. Write review JSON to .agents/tmp/phases/loop-1/A2-review.json", activeForm: "Reviewing plan", addBlockedBy: [A1 task ID]
4. **TaskCreate:** subject: "A3: Dual-Track Build", description: "Execute the build: workers implement tasks, sentinels review, arbiter consolidates. Write output to .agents/tmp/phases/loop-1/A3-build.json and A3-quality.json", activeForm: "Building implementation", addBlockedBy: [A2 task ID]
5. **TaskCreate:** subject: "A4: Queen Synchronization", description: "Synchronize build and quality track results. Render clean/issues_found verdict. Write to .agents/tmp/phases/loop-1/A4-queen-verdict.json", activeForm: "Reviewing verdict", addBlockedBy: [A3 task ID]
6. **TaskCreate:** subject: "A5: Ship", description: "Update documentation, create git commit, and open PR. Write output to .agents/tmp/phases/loop-1/A5-ship.json", activeForm: "Shipping implementation", addBlockedBy: [A4 task ID]

### 4c. Spawn teammates

Spawn 3-5 general-purpose teammates:

```
Teammate({ operation: "addTeammate", team_name: "ants-<BRANCH_SLUG>" })
```

Repeat 3-5 times based on task complexity.

## Step 5: Enter Delegate Mode

Instruct the lead to enter delegate mode. In delegate mode, the lead coordinates but does not write code directly. Teammates self-claim tasks from the shared task list.

The TeammateIdle hook (`on-teammate-idle.sh`) automatically assigns phase-appropriate work to idle teammates. The TaskCompleted hook (`on-task-completed.sh`) validates output and advances state.

Press **Shift+Tab** to enter delegate mode, or the workflow will manage it automatically.

## Phase Agent Mapping

| Phase | Agent | subagent_type |
|-------|-------|---------------|
| A0 | forager (batch) | `ants:forager` |
| A0 | cartographer | `ants:cartographer` |
| A0 | explore-aggregator | `ants:explore-aggregator` |
| A1 | architect | `ants:architect` |
| A2 | blueprint-reviewer | `ants:blueprint-reviewer` |
| A3 | worker (task pool) | `ants:worker` |
| A3 | sentinel-correctness | `ants:sentinel-correctness` |
| A3 | sentinel-security | `ants:sentinel-security` |
| A3 | sentinel-perf | `ants:sentinel-perf` |
| A3 | review-arbiter | `ants:review-arbiter` |
| A3 | review-fixer | `ants:review-fixer` |
| A3 | guardian | `ants:guardian` |
| A4 | queen | `ants:queen` |
| A5 | nurse | `ants:nurse` |
| A5 | drone | `ants:drone` |
