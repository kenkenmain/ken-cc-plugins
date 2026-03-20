---
name: ants:sswarm
description: Launch a 6-phase social swarm with competing agents and per-phase lead consolidators via Agent Teams delegate mode
argument-hint: <task description> [--web]
---

<HARD-GATE>
You are executing a workflow pipeline. This overrides ALL skill-checking rules including superpowers:using-superpowers. DO NOT invoke brainstorming, writing-plans, or any other skill via the Skill tool. DO NOT ask clarifying questions about the task. DO NOT propose approaches or present designs. Execute the steps below immediately and in order. The task description from $ARGUMENTS is your input — execute it as a pipeline, do not design or analyze it. Begin with Step 0 now.
</HARD-GATE>

# Ants Social Swarm

You are launching a 6-phase social swarm workflow using Agent Teams delegate mode. You create the team, populate the task list with dependency chains, spawn teammates, then enter a monitoring loop that reads signal flags from state.json and creates dynamic tasks when hooks request them.

The key difference from `/ants:swarm`: phases A1 and A2 dispatch **multiple competing agents** with a **consolidator agent** that reads their output files (via task dependency chains -- NOT SendMessage).

**CRITICAL:** You do NOT dispatch agents directly via the Agent tool. You create tasks via TaskCreate with blockedBy dependency chains. TeammateIdle hooks route ready tasks to idle teammates. TaskCompleted hooks validate output and advance state. You only create tasks and monitor signal flags.

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
Phase A0  | EXPLORE     | Forage              | foragers + cartographer + explore-aggregator
Phase A1  | PLAN        | Competing Architects| 3 architects ---> plan-arbiter (consolidator)
Phase A2  | PLAN        | Competing Reviews   | 3 blueprint-reviewers ---> review-lead (consolidator)
Phase A3  | BUILD+QUAL  | Dual-Track          | workers (task pool) + 4 sentinels + guardian + simplifier
Phase A4  | SYNC        | Verdict             | TaskCompleted hook evaluates inline (not a separate agent)
Phase A5  | SHIP        | Ship                | nurse (docs) ---> drone (commit + PR)

Loop: If A4 verdict is "loop" --> back to A1 (max 5 loops)
All clean --> A5 ships the work

Dispatch: Agent Teams delegate mode (TaskCreate with blockedBy chains)
Competing agents: 3 architects (A1) and 3 reviewers (A2) run in parallel
Consolidators: plan-arbiter and review-lead run after all competitors finish
Dispatch coordination: task dependencies (blockedBy). SendMessage: live coordination overlay (dual-channel model)
```

## Step 0: Preflight Checks

### 0a. Verify Agent Teams environment

```bash
if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" != "1" ]]; then
  echo "ERROR: Agent Teams requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
  echo "Set this environment variable before running the sswarm command."
  exit 1
fi
```

### 0b. Load deferred tools

```
ToolSearch("select:TeamCreate,TeamDelete,TaskCreate,TaskGet,TaskList,TaskUpdate,TaskStop,SendMessage")
```

These tools are required for creating and managing the Agent Teams team and task graph. `TeamCreate` creates the team. `TaskCreate` populates the task list. `SendMessage` enables graceful shutdown of teammates.

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
  "version": 6,
  "plugin": "ants",
  "pipeline": "sswarm",
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
  "teamName": "ants-sswarm-<BRANCH_SLUG>",
  "maxLoops": 5,
  "loop": 1,
  "teamCreated": false,
  "teammateCount": 0,
  "taskGraphVersion": 1,
  "needsA3Tasks": false,
  "needsA5Tasks": false,
  "needsLoopReset": false,
  "needsPswarmReset": false,
  "phaseLeads": {
    "A0": "explore-aggregator",
    "A1": "plan-arbiter",
    "A2": "review-lead",
    "A3": "review-arbiter",
    "A5": "drone"
  },
  "schedule": [
    {"phase":"A0","stage":"EXPLORE","label":"Colony Exploration","type":"agents"},
    {"phase":"A1","stage":"PLAN","label":"Competing Architects","type":"agents"},
    {"phase":"A2","stage":"PLAN","label":"Competing Reviews","type":"agents"},
    {"phase":"A3","stage":"BUILD","label":"Dual-Track Execution","type":"agents"},
    {"phase":"A4","stage":"SYNC","label":"Verdict","type":"agents"},
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
Ants Social Swarm -- 6-Phase Pipeline (Agent Teams Delegate Mode)
==================================================================
Phase A0  | EXPLORE | Colony Exploration    | foragers + cartographer + explore-aggregator
Phase A1  | PLAN    | Competing Architects  | 3 architects ---> plan-arbiter (consolidator)
Phase A2  | PLAN    | Competing Reviews     | 3 reviewers ---> review-lead (consolidator)
Phase A3  | BUILD   | Dual-Track Execution  | workers + 4 sentinels + guardian + simplifier
Phase A4  | SYNC    | Verdict               | TaskCompleted hook (inline, no agent)
Phase A5  | SHIP    | Documentation + Ship  | nurse (docs) + drone (commit + PR)

Dispatch: Agent Teams delegate mode (TaskCreate with blockedBy chains)
Competing agents: 3 architects (A1), 3 reviewers (A2) -- task dependencies + SendMessage coordination overlay
Teammates: 5 (higher concurrency for competing agents)
Circuit breaker: 5 consecutive failures --> halt
```

## Step 3: Create Team + Task Graph + Monitoring Loop

You are the command lead. You create the team, populate the initial task graph, spawn 5 teammates, then enter a monitoring loop. You do NOT dispatch agents directly.

### 3a. Create the sswarm task graph

Create the initial sswarm task graph with competing agents at A1 and A2. The task graph has these tasks with dependency chains:

**A0 tasks** (same as swarm):
- `A0-forager-1`: subject "A0 Forager: Colony exploration 1", blockedBy []
- `A0-forager-2`: subject "A0 Forager: Colony exploration 2", blockedBy []
- `A0-cartographer`: subject "A0 Cartographer: Deep architecture trace", blockedBy []
- `A0-explore-aggregator`: subject "A0 Explore Aggregator: Synthesize findings", blockedBy [A0-forager-1, A0-forager-2, A0-cartographer]

**A1 tasks** (3 competing architects + plan-arbiter consolidator):
- `A1-architect-1`: subject "A1 Architect 1: Competing plan", blockedBy [A0-explore-aggregator]
  - Description: "Create a detailed implementation plan for: <task>. Write plan output to: .agents/tmp/phases/loop-1/A1-plan.architect.1.tmp. Write task descriptors to: .agents/tmp/phases/loop-1/A1-tasks.architect.1.tmp"
- `A1-architect-2`: subject "A1 Architect 2: Competing plan", blockedBy [A0-explore-aggregator]
  - Description: Same but with `.architect.2.tmp` file paths
- `A1-architect-3`: subject "A1 Architect 3: Competing plan", blockedBy [A0-explore-aggregator]
  - Description: Same but with `.architect.3.tmp` file paths
- `A1-plan-arbiter`: subject "A1 Plan Arbiter: Consolidate plans", blockedBy [A1-architect-1, A1-architect-2, A1-architect-3]
  - Description: "Read the 3 competing plans and select/merge the best approach. Input files: .agents/tmp/phases/loop-1/A1-plan.architect.{1,2,3}.tmp. Output: .agents/tmp/phases/loop-1/A1-plan.md and .agents/tmp/phases/loop-1/A1-tasks.json"

**A2 tasks** (3 competing reviewers + review-lead consolidator):
- `A2-reviewer-1`: subject "A2 Blueprint Reviewer 1: Competing review", blockedBy [A1-plan-arbiter]
  - Description: "Review the consolidated plan for completeness and feasibility. Input: .agents/tmp/phases/loop-1/A1-plan.md. Write review to: .agents/tmp/phases/loop-1/A2-review.reviewer.1.tmp"
- `A2-reviewer-2`: subject "A2 Blueprint Reviewer 2: Competing review", blockedBy [A1-plan-arbiter]
  - Description: Same but with `.reviewer.2.tmp` file path
- `A2-reviewer-3`: subject "A2 Blueprint Reviewer 3: Competing review", blockedBy [A1-plan-arbiter]
  - Description: Same but with `.reviewer.3.tmp` file path
- `A2-review-lead`: subject "A2 Review Lead: Consolidate reviews", blockedBy [A2-reviewer-1, A2-reviewer-2, A2-reviewer-3]
  - Description: "Read the 3 competing reviews and produce a unified review verdict. Input files: .agents/tmp/phases/loop-1/A2-review.reviewer.{1,2,3}.tmp. Output: .agents/tmp/phases/loop-1/A2-review.json"

**A3-A5 placeholder tasks** (created dynamically later via signal flags):
- These are NOT created now. A3 worker/sentinel/arbiter tasks are created when `needsA3Tasks` flag is set (after A1 completes). A5 nurse/drone tasks are created when `needsA5Tasks` flag is set (after clean verdict).

### 3b. Call TaskCreate for each task

For each task in the graph above, call **TaskCreate** with:
- `subject`: The task subject (must start with "A{N} " for routing)
- `description`: Task-specific instructions including file paths and context
- `blockedBy`: Array of task IDs that must complete first

Store the returned task IDs in state.json (update state with task graph metadata).

Create the loop directory first:

```bash
mkdir -p .agents/tmp/phases/loop-1
```

### 3c. Create team and spawn 5 teammates

**Step 1 — Create the team:**

```
TeamCreate(
  team_name: "<teamName from state.json>",
  description: "Ants sswarm workflow for: <task description>"
)
```

**Step 2 — Spawn 5 teammates:**

Spawn 5 teammates using the `Agent` tool. Each MUST have `team_name` set. sswarm needs 5 for higher concurrency (A1 has 3 competing architects, A2 has 3 competing reviewers).

```
Agent(
  prompt: "You are a teammate in the ants sswarm workflow. Check TaskList for available tasks, claim unassigned tasks via TaskUpdate(owner), and work on them. When done, mark tasks as completed via TaskUpdate(status: completed). Check TaskList again for more work.",
  team_name: "<teamName from state.json>",
  name: "teammate-1",
  run_in_background: true,
  description: "Ants teammate 1"
)
```

Repeat for `teammate-2` through `teammate-5`. All run in background.

**IMPORTANT:** All `Agent` calls must include `team_name` matching the TeamCreate team_name. Without this, teammates won't join the team and TeammateIdle hooks won't fire.

### 3d. Update state

```bash
jq '.teamCreated = true | .teammateCount = 5 | .updatedAt = (now | todate)' .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
```

### 3e. Enter monitoring loop

Enter a monitoring loop that reads state.json on each cycle and creates dynamic tasks when hooks set signal flags. The loop runs until the workflow reaches a terminal state.

**CRITICAL: You are the only entity that can call TaskCreate.** Hooks are shell scripts and cannot call Claude tools. Hooks set signal flags in state.json; you detect them and perform the TaskCreate calls.

**Monitoring loop pseudocode:**

```
while true:
  Read state.json

  # Check terminal conditions
  if status == "complete" or status == "blocked" or status == "stopped":
    break
  if currentPhase == "DONE" or currentPhase == "STOPPED" or currentPhase == "BLOCKED":
    break
  if shutdown == true:
    break

  # Check signal flags (set by on-task-completed.sh hook)

  if needsA3Tasks == true:
    # A1 completed -- create A3 worker/sentinel/guardian/simplifier/arbiter tasks
    # Read .agents/tmp/phases/loop-<LOOP>/A1-tasks.json for worker task descriptors
    # Generate A3 subtask graph (workers blockedBy A2, sentinels+guardian+simplifier
    # blockedBy all workers, arbiter blockedBy all quality agents)
    # Call TaskCreate for each A3 subtask
    # Clear flag: update state needsA3Tasks = false

  if needsA5Tasks == true:
    # A4 verdict was "clean" -- create A5 nurse + drone tasks
    # A5-nurse blockedBy [A3-arbiter], A5-drone blockedBy [A5-nurse]
    # Call TaskCreate for nurse and drone
    # Clear flag: update state needsA5Tasks = false

  if needsLoopReset == true:
    # A4 verdict was "issues_found" -- create fresh A1-A4 tasks for next loop
    # Re-create sswarm task graph for A1 and A2 (3 architects + arbiter,
    # 3 reviewers + lead) with updated loop number in file paths
    # Call TaskCreate for each new task
    # Clear flag: update state needsLoopReset = false

  # Wait before next cycle (avoid busy-spinning)
  sleep/wait
```

**Signal flag details:**

| Flag | Set By | When | Your Action |
|------|--------|------|-------------|
| `needsA3Tasks` | `on-task-completed.sh` handle_a1() | A1 plan + A1-tasks.json validated | Read A1-tasks.json, generate A3 subtasks via `teams_add_a3_subtasks()` pattern, call TaskCreate for each |
| `needsA5Tasks` | `on-task-completed.sh` handle_a3_arbiter() | A4 verdict is "clean" (evaluated inline) | Create A5-nurse (blockedBy [A3-arbiter]) and A5-drone (blockedBy [A5-nurse]) |
| `needsLoopReset` | `on-task-completed.sh` handle_a3_arbiter() | A4 verdict is "issues_found", budget not exhausted | Create fresh A1-A2 sswarm tasks (3 architects + arbiter + 3 reviewers + lead) with incremented loop paths |

**When creating A3 tasks (needsA3Tasks handler):**

Read `.agents/tmp/phases/loop-<LOOP>/A1-tasks.json` for worker task descriptors. For each worker task:
- TaskCreate with subject "A3 Worker: <task_name>", blockedBy depends on task dependencies
- All workers blockedBy at minimum [A2-review-lead] (sswarm-specific: review-lead is the A2 consolidator)

After all worker TaskCreates, create quality track tasks:
- 4 sentinel tasks: blockedBy all worker task IDs
- 1 guardian task: blockedBy all worker task IDs
- 1 simplifier task: blockedBy all worker task IDs
- 1 arbiter task: blockedBy all sentinel + guardian + simplifier task IDs
- 1 review-fixer task (optional): blockedBy arbiter

**When creating loop-reset tasks (needsLoopReset handler):**

The current loop number has already been incremented by the hook. Read the new loop from state.json. Create fresh sswarm tasks with the new loop directory in file paths:
- 3 architects: blockedBy [A0-explore-aggregator] (A0 results persist across loops)
- 1 plan-arbiter: blockedBy all 3 architects
- 3 reviewers: blockedBy [plan-arbiter]
- 1 review-lead: blockedBy all 3 reviewers

Include loop context in architect descriptions: "This is loop <LOOP>. Read the previous loop's quality review at .agents/tmp/phases/loop-<PREV>/A3-quality.json and verdict at .agents/tmp/phases/loop-<PREV>/A4-queen-verdict.json. Plan targeted fixes, not a full re-plan."

## Step 4: Completion Summary

After the monitoring loop exits, read the final state and display a summary.

Read the following files (use the final `.loop` value from state.json for `<LOOP>`):
- `state.json` -- `.task`, `.branch`, `.loop`, `.maxLoops`, `.teammateCount`
- `.agents/tmp/phases/loop-<LOOP>/A4-queen-verdict.json` -- `.buildTrackSummary.filesChanged[]`, `.buildTrackSummary.testsAdded`, `.qualityTrackSummary.critical`, `.qualityTrackSummary.warning`, `.qualityTrackSummary.info`, `.evidence[]`
- `.agents/tmp/phases/loop-<LOOP>/A5-ship.json` -- `.commit_sha`, `.pr_url`, `.files_committed[]`

**If all succeeded:**
```
Ants Social Swarm -- Complete
==============================
Task: <.task from state.json>
Branch: <.branch>
Commit: <.commit_sha from A5-ship.json>
PR: <.pr_url>

Build Summary:
  Files changed: <count of .files_committed> (<first 5 files, comma-separated>; "and N more" if >5)
  Tests added: <.buildTrackSummary.testsAdded, or 0 if missing>
  Loops taken: <.loop> / <.maxLoops>
  Teammates: <.teammateCount>

Quality Review:
  Critical: <.qualityTrackSummary.critical>  Warning: <.qualityTrackSummary.warning>  Info: <.qualityTrackSummary.info>

Lead Agents:
  A1 plan-arbiter: selected/merged from 3 competing architects
  A2 review-lead: consolidated 3 competing reviewer verdicts

Key evidence:
  - <each item in .evidence[], one per line; show up to 8 items, then "(and N more)" if array is larger>
```

Use `.files_committed` from A5-ship.json as the primary files list (most accurate). Fall back to `.buildTrackSummary.filesChanged` if A5-ship.json is unavailable. If A4-queen-verdict.json is missing, omit the Quality Review and Key evidence sections.

**If blocked:**
```
Ants Social Swarm -- Blocked
==============================
Reason: <.failure from state.json>
Phase at failure: <.currentPhase>
Circuit breaker: <.circuitBreaker.consecutiveFailures> consecutive failures, <.circuitBreaker.stageRestarts> loop-backs used
```

**If stopped mid-pipeline:**
```
Ants Social Swarm -- Incomplete
================================
Status: in_progress (stopped mid-pipeline)
Current phase: <.currentPhase>
<.failure if present>
```

## Phase Agent Mapping

| Phase | Agent | subagent_type | Role |
|-------|-------|---------------|------|
| A0 | forager (batch) | `ants:forager` | Feeder |
| A0 | cartographer | `ants:cartographer` | Feeder |
| A0 | explore-aggregator | `ants:explore-aggregator` | Consolidator |
| A1 | architect (x3) | `ants:architect` | Competing |
| A1 | plan-arbiter | `ants:plan-arbiter` | Consolidator |
| A2 | blueprint-reviewer (x3) | `ants:blueprint-reviewer` | Competing |
| A2 | review-lead | `ants:review-lead` | Consolidator |
| A3 | worker (task pool) | `ants:worker` | Builder |
| A3 | sentinel-correctness | `ants:sentinel-correctness` | Quality |
| A3 | sentinel-security | `ants:sentinel-security` | Quality |
| A3 | sentinel-perf | `ants:sentinel-perf` | Quality |
| A3 | sentinel-style | `ants:sentinel-style` | Quality |
| A3 | simplifier | `ants:simplifier` | Quality |
| A3 | review-arbiter | `ants:review-arbiter` | Consolidator |
| A3 | review-fixer | `ants:review-fixer` | Fixer |
| A3 | guardian | `ants:guardian` | Quality |
| A4 | (none -- inline hook) | -- | Verdict |
| A5 | nurse | `ants:nurse` | Docs |
| A5 | drone | `ants:drone` | Ship |

## Task Dependency Graph (sswarm)

```
A0-forager-1 ----------------+
A0-forager-2 ----------------+
A0-cartographer -------------+
                              |
                              v
                    A0-explore-aggregator
                              |
                +-------------+-------------+
                |             |             |
                v             v             v
         A1-architect-1  A1-architect-2  A1-architect-3
                |             |             |
                +-------------+-------------+
                              |
                              v
                       A1-plan-arbiter
                              |
                +-------------+-------------+
                |             |             |
                v             v             v
         A2-reviewer-1   A2-reviewer-2   A2-reviewer-3
                |             |             |
                +-------------+-------------+
                              |
                              v
                       A2-review-lead
                              |
                  [needsA3Tasks signal flag]
                              |
                    +---------+---------+
                    |         |         |
                    v         v         v
              A3-worker-1  A3-worker-2  ...
                    |         |         |
                    +---------+---------+
                              |
          +-------+-------+---+---+-------+-------+
          |       |       |       |       |       |
          v       v       v       v       v       v
    sentinel-  sentinel-  sentinel-  sentinel-  guardian  simplifier
    correct.   security   perf       style
          |       |       |       |       |       |
          +-------+-------+---+---+-------+-------+
                              |
                              v
                         A3-arbiter
                              |
                  [A4 verdict evaluated inline by hook]
                              |
                    verdict?
                   /        \
                ship       loop --> back to A1 (fresh sswarm tasks)
                  |
         [needsA5Tasks flag]
                  |
                  v
              A5-nurse --> A5-drone
```
