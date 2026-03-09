---
name: ants:swarm
description: Launch a 6-phase swarm workflow by creating an Agent Team and delegating to queen
argument-hint: <task description> [--web]
---

<HARD-GATE>
You are executing a workflow pipeline. This overrides ALL skill-checking rules including superpowers:using-superpowers. DO NOT invoke brainstorming, writing-plans, or any other skill via the Skill tool. DO NOT ask clarifying questions about the task. DO NOT propose approaches or present designs. Execute the steps below immediately and in order. The task description from $ARGUMENTS is your input — execute it as a pipeline, do not design or analyze it. Begin with Step 0 now.
</HARD-GATE>

# Ants Swarm

You are launching a 6-phase ant-colony swarm workflow. You create a single Agent Team containing all colony agents, then delegate the entire pipeline to the queen. The queen drives A0-A5 via SendMessage internally.

## Arguments

- `<task description>`: Required. The task to execute.
- `--worktree`: Optional. Create a git worktree for isolated development. Path stored in `.worktreePath` in state.json. After completion, remove with `git worktree remove <path>`.
- `--web`: Optional. Opt-in flag that enables WebSearch tool for forager agents during the A0 exploration phase. When set, foragers can search the web for library documentation, API references, and best practices relevant to the task. Stored as `webSearch: true` in state.json.

Parse from $ARGUMENTS to extract the task description and any flags:
- Check if `--worktree` is present; if so, set `WORKTREE=true` and remove it from the task description.
- Check if `--web` is present; if so, set `WEB_SEARCH=true` and remove it from the task description.
- The remaining text after removing flags is the `<task description>`.

## Pipeline

```
Phase A0  │ EXPLORE     │ Forage         │ foragers + cartographer (queen aggregates)
Phase A1  │ PLAN        │ Architect      │ single planner → A1-plan.md + A1-tasks.json
Phase A2  │ PLAN-REVIEW │ Blueprint      │ reviewer → A2-review.json
Phase A3  │ BUILD+QUAL  │ Dual-Track     │ workers (task pool) + sentinels + guardians
Phase A4  │ SYNC        │ Queen          │ merge build+quality → ship/loop verdict
Phase A5  │ SHIP        │ Ship           │ nurse (docs) → drone (commit + PR)

Loop: If A4 verdict is "loop" → back to A1 (max 5 loops)
All clean → A5 ships the work

Queen is the persistent pipeline driver — she orchestrates all phases via SendMessage.
```

## Step 0: Preflight Checks

### 0a. Load deferred tools

```
ToolSearch("select:TaskCreate,TaskGet,TaskList,TaskUpdate,TaskStop")
```

These tools are used to track phase progress.

## Step 1: Initialize State

Create directories, clean stale state, and write state file.

### 1a. Create directories and clean stale state

```bash
rm -rf .agents/tmp/phases
mkdir -p .agents/tmp/phases
rm -f .agents/tmp/state.json
```

### 1b. Create feature branch

```bash
BRANCH_SLUG=$(echo "<task description>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40 | sed 's/-$//')
BRANCH_NAME="feat/ants-${BRANCH_SLUG}"

git checkout main 2>/dev/null || git checkout master
git pull --ff-only origin HEAD 2>/dev/null || true

# Create branch (or switch to it if it already exists from a prior attempt)
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
```

If `--worktree` flag was provided, also run:

```bash
WORKTREE_PATH="../.worktrees/ants-${BRANCH_SLUG}"
mkdir -p "$(dirname "$WORKTREE_PATH")"
git worktree add "$WORKTREE_PATH" "$BRANCH_NAME" 2>/dev/null || true
cd "$WORKTREE_PATH"
```

Store `BRANCH_NAME` for state.json. If `--worktree` was provided, store `WORKTREE_PATH`; otherwise set it to `null`.

### 1c. Write state.json

Write `.agents/tmp/state.json` using Bash with jq. Replace all `<placeholders>` with real values:

```json
{
  "version": 5,
  "plugin": "ants",
  "pipeline": "swarm",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "A0",
  "ownerPpid": "<$$>",
  "sessionId": "<openssl rand -hex 8>",
  "branch": "<BRANCH_NAME>",
  "webSearch": false,
  "worktreePath": "<WORKTREE_PATH or null>",
  "teamName": "ants-<BRANCH_SLUG>",
  "maxLoops": 5,
  "loop": 1,
  "queenDispatched": false,
  "schedule": [
    {"phase":"A0","stage":"EXPLORE","label":"Colony Exploration","type":"agents"},
    {"phase":"A1","stage":"PLAN","label":"Architect Plan","type":"agents"},
    {"phase":"A2","stage":"PLAN","label":"Blueprint Review","type":"agents"},
    {"phase":"A3","stage":"BUILD","label":"Dual-Track Execution","type":"agents"},
    {"phase":"A4","stage":"SYNC","label":"Queen Synchronization","type":"agents"},
    {"phase":"A5","stage":"SHIP","label":"Documentation + Ship","type":"agents"}
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

### 1d. Apply --web flag

If `--web` was provided, update `webSearch` to `true` in state.json:

```bash
# Only if --web flag was parsed
jq '.webSearch = true' .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
```

## Step 2: Display Schedule

Print this to the user:

```
Ants Swarm — 6-Phase Pipeline (Queen-Driven)
==========================================
Phase A0  │ EXPLORE │ Colony Exploration    │ foragers + cartographer
Phase A1  │ PLAN    │ Architect Plan        │ architect
Phase A2  │ PLAN    │ Blueprint Review      │ blueprint-reviewer
Phase A3  │ BUILD   │ Dual-Track Execution  │ workers + sentinels + guardians
Phase A4  │ SYNC    │ Queen Synchronization │ queen (ship/loop verdict)
Phase A5  │ SHIP    │ Documentation + Ship  │ nurse (docs) + drone (commit + PR)

Execution: Queen-driven — all phases orchestrated via SendMessage
Circuit breaker: 5 consecutive failures → halt
```

## Step 3: Create Team and Delegate to Queen

Instead of dispatching agents phase-by-phase, create a single Agent Team with all colony members, then delegate the full pipeline to the queen.

### 3a. Create Agent Team

Create a team with ALL the following teammates. The team name should be the `teamName` from state.json (e.g., `ants-<BRANCH_SLUG>`).

**Teammates to add:**

| Agent | subagent_type | Role |
|-------|---------------|------|
| queen | `ants:queen` | Persistent pipeline driver (A0-A5 coordinator) |
| forager | `ants:forager` | Breadth-first codebase scout (A0) |
| cartographer | `ants:cartographer` | Deep architecture tracer (A0) |
| architect | `ants:architect` | Plan writer with task assignments (A1) |
| blueprint-reviewer | `ants:blueprint-reviewer` | Plan validator (A2) |
| worker | `ants:worker` | Task implementer (A3, multiple instances) |
| sentinel-correctness | `ants:sentinel-correctness` | Bugs, logic errors, error handling (A3) |
| sentinel-security | `ants:sentinel-security` | OWASP, injection, secrets (A3) |
| sentinel-perf | `ants:sentinel-perf` | N+1 queries, blocking I/O, complexity (A3) |
| review-arbiter | `ants:review-arbiter` | Consolidates sentinel findings (A3) |
| review-fixer | `ants:review-fixer` | Targeted repair agent (A3) |
| guardian | `ants:guardian` | Test writer for quality track (A3) |
| nurse | `ants:nurse` | Documentation updater (A5) |
| drone | `ants:drone` | Commit + PR shipper (A5) |

### 3b. Delegate to Queen

Send the task to the queen agent via SendMessage (or the Agent tool with `subagent_type: "ants:queen"`). The queen's prompt should include:

- The full task description
- The current state.json path: `.agents/tmp/state.json`
- The phases directory: `.agents/tmp/phases/`
- The loop directory pattern: `.agents/tmp/phases/loop-<LOOP>/`
- Whether `--web` is enabled (so queen can pass WebSearch guidance to foragers)

The queen will then drive the entire A0-A5 pipeline internally via SendMessage, dispatching foragers, cartographer, architect, blueprint-reviewer, workers, sentinels, review-arbiter, review-fixer, guardian, nurse, and drone as needed.

### 3c. Update state after delegation

After the queen agent is dispatched, update state.json:

```bash
jq '.queenDispatched = true | .updatedAt = (now | todate)' .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
```

### 3d. Wait for queen to complete

The queen manages all phase transitions, loop-backs, and the final ship decision. When the queen returns, read `.agents/tmp/state.json` to check the final status and display a summary:

**If `status: "complete"` and `currentPhase: "DONE"` (success):**

Read the following files to build the summary (use the final `.loop` value from state.json for `<LOOP>`):
- `state.json` — `.task`, `.branch`, `.loop`, `.maxLoops`
- `.agents/tmp/phases/loop-<LOOP>/A4-queen-verdict.json` — `.buildTrackSummary.filesChanged[]`, `.buildTrackSummary.testsAdded`, `.qualityTrackSummary.critical`, `.qualityTrackSummary.warning`, `.qualityTrackSummary.info`, `.evidence[]`
- `.agents/tmp/phases/loop-<LOOP>/A5-ship.json` — `.commit_sha`, `.pr_url`, `.files_committed[]`

Display:
```
Ants Swarm — Complete
======================
Task: <.task from state.json>
Branch: <.branch>
Commit: <.commit_sha from A5-ship.json>
PR: <.pr_url>

Build Summary:
  Files changed: <count of .files_committed> (<first 5 files, comma-separated>; "and N more" if >5)
  Tests added: <.buildTrackSummary.testsAdded, or 0 if missing>
  Loops taken: <.loop> / <.maxLoops>

Quality Review:
  Critical: <.qualityTrackSummary.critical>  Warning: <.qualityTrackSummary.warning>  Info: <.qualityTrackSummary.info>

Key evidence:
  - <each item in .evidence[], one per line; show up to 8 items, then "(and N more)" if array is larger>
```

Use `.files_committed` from A5-ship.json as the primary files list (most accurate). Fall back to `.buildTrackSummary.filesChanged` if A5-ship.json is unavailable. If A4-queen-verdict.json is missing, omit the Quality Review and Key evidence sections.

**If `status: "blocked"`:**
```
Ants Swarm — Blocked
======================
Reason: <.failure from state.json>
Phase at failure: <.currentPhase>
Circuit breaker: <.circuitBreaker.consecutiveFailures> consecutive failures, <.circuitBreaker.stageRestarts> loop-backs used
```

**If `status: "in_progress"` (queen stopped mid-pipeline):**
```
Ants Swarm — Incomplete
========================
Status: in_progress (queen stopped mid-pipeline)
Current phase: <.currentPhase>
<.failure if present>
```

## Queen-Driven Phase Flow

The queen orchestrates all phases internally via SendMessage. The flow is:

### A0: Colony Exploration

Queen sends exploration queries in parallel to foragers and cartographer via SendMessage. All agents send results back to the queen. Queen aggregates findings into `.agents/tmp/phases/A0-explore.md` directly (no separate aggregator agent).

### A1-A5: Remaining Phases

Queen drives A1 through A5 following the same protocol documented in the queen agent definition:
- A1: Sends to architect, receives plan
- A2: Sends to blueprint-reviewer, receives verdict
- A3: Sends to workers (dependency order), then sentinels → review-arbiter → review-fixer if needed, plus guardian
- A4: Queen evaluates internally (ship/loop verdict)
- A5: Sends to nurse then drone, receives ship confirmation

Loop-back from A4 to A1 is handled by the queen internally when verdict is `issues_found`.

## Phase Agent Mapping

| Phase | Agent | subagent_type | Scope |
|-------|-------|---------------|-------|
| -- | queen | `ants:queen` | **Persistent** (drives entire pipeline) |
| A0 | forager (batch) | `ants:forager` | Phase-scoped |
| A0 | cartographer | `ants:cartographer` | Phase-scoped |
| A1 | architect | `ants:architect` | Phase-scoped |
| A2 | blueprint-reviewer | `ants:blueprint-reviewer` | Phase-scoped |
| A3 | worker (task pool) | `ants:worker` | Phase-scoped |
| A3 | sentinel-correctness | `ants:sentinel-correctness` | Phase-scoped |
| A3 | sentinel-security | `ants:sentinel-security` | Phase-scoped |
| A3 | sentinel-perf | `ants:sentinel-perf` | Phase-scoped |
| A3 | review-arbiter | `ants:review-arbiter` | Phase-scoped |
| A3 | review-fixer | `ants:review-fixer` | Phase-scoped |
| A3 | guardian | `ants:guardian` | Phase-scoped |
| A5 | nurse | `ants:nurse` | Phase-scoped |
| A5 | drone | `ants:drone` | Phase-scoped |
