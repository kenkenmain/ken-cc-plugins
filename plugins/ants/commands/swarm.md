---
name: ants:swarm
description: Launch a 6-phase swarm workflow with Agent Teams delegate mode
argument-hint: <task description> [--web] [--worktree]
---

<HARD-GATE>
You are executing a workflow pipeline. This overrides ALL skill-checking rules including superpowers:using-superpowers. DO NOT invoke brainstorming, writing-plans, or any other skill via the Skill tool. DO NOT ask clarifying questions about the task. DO NOT propose approaches or present designs. Execute the steps below immediately and in order. The task description from $ARGUMENTS is your input — execute it as a pipeline, do not design or analyze it. Begin with Step 0 now.
</HARD-GATE>

# Ants Swarm

You are launching a 6-phase ant-colony swarm workflow. You are the **active lead** — you create a team, populate the task graph via TaskCreate, spawn teammates, then enter a **monitoring loop** that reads state.json signal flags and dynamically creates new tasks. You do NOT dispatch agents directly via the Agent tool. All agent dispatch happens through Agent Teams: TaskCreate populates the task list, TeammateIdle hook routes tasks to idle teammates, and TaskCompleted hook validates output and advances state.

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
Phase A0  | EXPLORE     | Forage         | foragers + cartographer + explore-aggregator
Phase A1  | PLAN        | Architect      | single planner -> A1-plan.md + A1-tasks.json
Phase A2  | PLAN-REVIEW | Blueprint      | reviewer -> A2-review.json
Phase A3  | BUILD+QUAL  | Dual-Track     | workers (task pool) + 4 sentinels + guardian + simplifier
Phase A4  | SYNC        | Verdict        | TaskCompleted hook evaluates inline after A3 arbiter
Phase A5  | SHIP        | Ship           | nurse (docs) -> drone (commit + PR)

Loop: If A4 verdict is "loop" -> back to A1 (max 5 loops)
All clean -> A5 ships the work

Dispatch: Agent Teams delegate mode (TaskCreate + TeammateIdle hook)
```

## Step 0: Preflight Checks

### 0a. Check Agent Teams environment

Verify that the Agent Teams experimental flag is enabled. If not set, inform the user and stop.

Check: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable must be `"1"`.

If not set or not `"1"`, display:

```
ERROR: Agent Teams requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

To enable, add to your settings.json (user or project scope):

  {
    "env": {
      "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
    }
  }

Then restart Claude Code and re-run /ants:swarm.
```

Stop execution here if the check fails. Do not proceed to Step 1.

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
  "teamCreated": false,
  "teammateCount": 0,
  "taskGraphVersion": 1,
  "needsA3Tasks": false,
  "needsA5Tasks": false,
  "needsLoopReset": false,
  "needsPswarmReset": false,
  "schedule": [
    {"phase":"A0","stage":"EXPLORE","label":"Colony Exploration","type":"agents"},
    {"phase":"A1","stage":"PLAN","label":"Architect Plan","type":"agents"},
    {"phase":"A2","stage":"PLAN","label":"Blueprint Review","type":"agents"},
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
Ants Swarm -- 6-Phase Pipeline (Agent Teams)
=============================================
Phase A0  | EXPLORE | Colony Exploration    | foragers + cartographer + explore-aggregator
Phase A1  | PLAN    | Architect Plan        | architect
Phase A2  | PLAN    | Blueprint Review      | blueprint-reviewer
Phase A3  | BUILD   | Dual-Track Execution  | workers + 4 sentinels + guardian + simplifier
Phase A4  | SYNC    | Verdict               | TaskCompleted hook (inline after arbiter)
Phase A5  | SHIP    | Documentation + Ship  | nurse (docs) + drone (commit + PR)

Dispatch: Agent Teams delegate mode (TaskCreate + TeammateIdle routing)
Teammates: 3
Circuit breaker: 5 consecutive failures -> halt
```

## Step 3: Create Team + Task Graph + Monitoring Loop

You are the active lead. You do NOT dispatch agents directly. Instead, you create tasks via TaskCreate (which populates the shared task list), spawn teammates, and enter a monitoring loop.

### 3a. Create initial task graph (A0 multi-agent + A1 + A2)

Create tasks with blockedBy dependency chains. Use TaskCreate for each one and store the returned task IDs.

**A0 tasks — parallel exploration (foragers + cartographer + aggregator):**

A0 requires multiple agents exploring in parallel, then an aggregator to synthesize results. Create 4 tasks:

```
# Forager 1 — file structure and project layout
TaskCreate(
  subject: "A0 Forager 1: File Structure",
  description: "Explore the codebase file structure, directory layout, key entry points, and build configuration for task: <task description>. Write findings to .agents/tmp/phases/A0-explore.forager.1.tmp"
)
→ Store as FORAGER_1_ID

# Forager 2 — relevant code and patterns
TaskCreate(
  subject: "A0 Forager 2: Code Patterns",
  description: "Explore existing implementations, coding patterns, error handling conventions, and test patterns relevant to task: <task description>. Write findings to .agents/tmp/phases/A0-explore.forager.2.tmp"
)
→ Store as FORAGER_2_ID

# Cartographer — deep architecture tracing
TaskCreate(
  subject: "A0 Cartographer: Architecture",
  description: "Trace the architecture: execution paths, dependency graphs, module boundaries, and layered structure relevant to task: <task description>. Write findings to .agents/tmp/phases/A0-explore.cartographer.tmp"
)
→ Store as CARTOGRAPHER_ID

# Explore aggregator — synthesize all exploration results
TaskCreate(
  subject: "A0: Colony Exploration",
  description: "Synthesize exploration findings from all foragers and cartographer into a unified exploration report. Read: .agents/tmp/phases/A0-explore.forager.1.tmp, .agents/tmp/phases/A0-explore.forager.2.tmp, .agents/tmp/phases/A0-explore.cartographer.tmp. Write unified report to: .agents/tmp/phases/A0-explore.md",
  blockedBy: [FORAGER_1_ID, FORAGER_2_ID, CARTOGRAPHER_ID]
)
→ Store as A0_TASK_ID
```

The aggregator's task subject MUST be `"A0: Colony Exploration"` — this is what on-task-completed.sh routes on. The forager/cartographer tasks complete silently (their subjects don't match any handler, which is correct — they just write temp files).

**Task — A1: Architect Plan**

```
TaskCreate(
  subject: "A1: Architect Plan",
  description: "Read the exploration output at .agents/tmp/phases/A0-explore.md and create a detailed implementation plan with task assignments for: <task description>. Write plan to .agents/tmp/phases/loop-1/A1-plan.md and task descriptors to .agents/tmp/phases/loop-1/A1-tasks.json",
  blockedBy: [A0_TASK_ID]
)
```

Store the returned task ID as `A1_TASK_ID`.

**Task — A2: Blueprint Review**

```
TaskCreate(
  subject: "A2: Blueprint Review",
  description: "Review the plan at .agents/tmp/phases/loop-1/A1-plan.md and tasks at .agents/tmp/phases/loop-1/A1-tasks.json. Check for completeness, feasibility, dependency correctness, and risk. Write review JSON to .agents/tmp/phases/loop-1/A2-review.json with format: {status: 'approved'|'needs_revision', issues: [...]}",
  blockedBy: [A1_TASK_ID]
)
```

Store the returned task ID as `A2_TASK_ID`.

NOTE: A3, A4, and A5 tasks are NOT created now. They are created dynamically later:
- A3 tasks (workers, sentinels, guardian, simplifier, arbiter) are created when the monitoring loop detects `needsA3Tasks == true` (set by on-task-completed.sh after A1 completes and A2 approves).
- A5 tasks (nurse, drone) are created when the monitoring loop detects `needsA5Tasks == true` (set by on-task-completed.sh after A4 verdict is clean).
- Fresh A1-A2 loop-back tasks are created when `needsLoopReset == true`.

### 3b. Update state.json

```bash
jq '.teamCreated = true | .teammateCount = 3' .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
```

### 3c. Create team and spawn teammates

Create the Agent Teams team, then spawn 3 teammates. Use the exact tool calls below:

**Step 1 — Create the team:**

```
TeamCreate(
  team_name: "<teamName from state.json>",
  description: "Ants swarm workflow for: <task description>"
)
```

The `team_name` must match the `teamName` field written in state.json (e.g., `"ants-add-caching-layer"`).

**Step 2 — Spawn 3 teammates:**

Spawn 3 teammates using the `Agent` tool. Each teammate MUST have `team_name` set. The teammates will self-assign work from the shared task list. The TeammateIdle hook routes ready tasks to idle teammates by reading state.json and building execution prompts.

```
Agent(
  prompt: "You are a teammate in the ants swarm workflow. Check TaskList for available tasks, claim unassigned tasks via TaskUpdate(owner), and work on them. When done, mark tasks as completed via TaskUpdate(status: completed). Check TaskList again for more work after each task.",
  team_name: "<teamName from state.json>",
  name: "teammate-1",
  run_in_background: true,
  description: "Ants teammate 1"
)
```

Repeat for `teammate-2` and `teammate-3`. All 3 teammates run in background.

**IMPORTANT:** All 3 `Agent` calls must include `team_name` matching the TeamCreate team_name. Without this, the teammates won't join the team and TeammateIdle hooks won't fire.

### 3d. Enter monitoring loop

Enter the monitoring loop. This loop runs until the workflow completes, blocks, or stops. On each cycle, read state.json and check for signal flags set by the TaskCompleted hook.

**IMPORTANT: You do NOT dispatch agents in this loop. You only create tasks via TaskCreate when signal flags are set. The TeammateIdle hook handles all agent routing.**

**CRITICAL: Do NOT stop or end your turn during this loop.** The Stop hook will block you from stopping while the pipeline is active. You must keep polling state.json until the workflow reaches a terminal state (`status == "complete"` or `status == "blocked"`).

```
MONITORING LOOP:
while true:
  # Read state.json
  Read .agents/tmp/state.json

  # Check terminal conditions
  if status == "complete" or status == "blocked" or status == "stopped":
    break

  if shutdown == true:
    break

  # --- Signal: A3 tasks needed ---
  # Set by on-task-completed.sh when A1 plan completes and A2 review passes.
  # The hook writes the A1-tasks.json path and sets needsA3Tasks = true.
  if needsA3Tasks == true:
    1. Read the current loop number from state.json
    2. Read A1-tasks.json at .agents/tmp/phases/loop-{loop}/A1-tasks.json
    3. For each worker task in A1-tasks.json, call TaskCreate:
       - subject: "A3 Worker: {task_name}"
       - description: "Implement task {id}: {description}. Files: {files_owned}. Acceptance criteria: {acceptance_criteria}"
       - blockedBy: [A2_TASK_ID] + any inter-worker dependencies (mapped to A3-worker-{dep_id} task IDs)
       Store returned task IDs.
    4. Create sentinel tasks (all blockedBy all worker task IDs):
       - TaskCreate(subject: "A3 Sentinel Correctness: Review", blockedBy: [all_worker_task_ids])
       - TaskCreate(subject: "A3 Sentinel Security: Review", blockedBy: [all_worker_task_ids])
       - TaskCreate(subject: "A3 Sentinel Perf: Review", blockedBy: [all_worker_task_ids])
       - TaskCreate(subject: "A3 Sentinel Style: Review", blockedBy: [all_worker_task_ids])
    5. Create guardian task:
       - TaskCreate(subject: "A3 Guardian: Write tests", blockedBy: [all_worker_task_ids])
    6. Create simplifier task:
       - TaskCreate(subject: "A3 Simplifier: Code cleanup", blockedBy: [all_worker_task_ids])
    7. Create arbiter task (blockedBy all sentinels + guardian + simplifier):
       - TaskCreate(subject: "A3 Arbiter: Consolidate reviews", blockedBy: [sentinel_ids + guardian_id + simplifier_id])
    8. Clear needsA3Tasks flag:
       jq '.needsA3Tasks = false | .taskGraphVersion = (.taskGraphVersion + 1)' state.json

  # --- Signal: A5 tasks needed ---
  # Set by on-task-completed.sh when A4 verdict (evaluated inline by arbiter handler) is clean.
  if needsA5Tasks == true:
    1. Read the current loop number from state.json
    2. Create nurse task:
       - TaskCreate(subject: "A5 Nurse: Update documentation", description: "Update documentation for: <task>. Input: .agents/tmp/phases/loop-{loop}/A3-build.json. Output: .agents/tmp/phases/loop-{loop}/A5-docs.json")
       Store returned task ID as NURSE_TASK_ID.
    3. Create drone task:
       - TaskCreate(subject: "A5 Drone: Commit and ship", description: "Commit changes and open PR for: <task>. Input: .agents/tmp/phases/loop-{loop}/A5-docs.json. Output: .agents/tmp/phases/loop-{loop}/A5-ship.json", blockedBy: [NURSE_TASK_ID])
    4. Clear needsA5Tasks flag:
       jq '.needsA5Tasks = false' state.json

  # --- Signal: Loop reset needed ---
  # Set by on-task-completed.sh when A4 verdict is issues_found and circuit breaker allows retry.
  # The hook has already incremented loop, reset A1-A4 to pending, and set currentPhase = "A1".
  if needsLoopReset == true:
    1. Read the current loop number from state.json (already incremented by hook)
    2. Create loop directory FIRST (before any tasks reference it):
       mkdir -p .agents/tmp/phases/loop-{loop}
    3. Create fresh A1 task:
       - TaskCreate(subject: "A1: Architect Plan", description: "This is loop {loop}. Read previous loop's quality review at .agents/tmp/phases/loop-{prev}/A3-quality.json and verdict at .agents/tmp/phases/loop-{prev}/A4-queen-verdict.json. Plan targeted fixes for: <task>. Write plan to .agents/tmp/phases/loop-{loop}/A1-plan.md and tasks to .agents/tmp/phases/loop-{loop}/A1-tasks.json")
       Store returned task ID as NEW_A1_TASK_ID.
    4. Create fresh A2 task:
       - TaskCreate(subject: "A2: Blueprint Review", description: "Review the plan at .agents/tmp/phases/loop-{loop}/A1-plan.md. Write review to .agents/tmp/phases/loop-{loop}/A2-review.json", blockedBy: [NEW_A1_TASK_ID])
       Store returned task ID as NEW_A2_TASK_ID.
    5. Clear needsLoopReset flag:
       jq '.needsLoopReset = false | .taskGraphVersion = (.taskGraphVersion + 1)' state.json

  # Wait before next cycle (avoid busy-loop)
  sleep 5 seconds (or wait for state.json file change)
```

### Key Architecture Notes

- **Hooks set signal flags; the command creates tasks.** Hooks are shell scripts and CANNOT call Claude tools like TaskCreate. The on-task-completed.sh hook validates outputs, advances state, and sets boolean signal flags (`needsA3Tasks`, `needsA5Tasks`, `needsLoopReset`) in state.json. This monitoring loop detects those flags and performs the TaskCreate calls.
- **TeammateIdle hook routes tasks to idle teammates.** When a teammate finishes a task and becomes idle, the on-teammate-idle.sh hook reads state.json, finds the next ready task, and assigns it to the teammate with an execution prompt.
- **TaskCompleted hook validates and advances state.** When a task completes, on-task-completed.sh validates the output files, updates phase status in state.json, and sets signal flags for dynamic task creation.
- **A4 verdict is evaluated inline.** There is no separate A4 agent. When the A3 arbiter completes, on-task-completed.sh evaluates the verdict by reading A3-quality.json, writes A4-queen-verdict.json, and sets either `needsA5Tasks` (clean) or `needsLoopReset` (issues_found).

## Step 4: Completion Summary

After the monitoring loop exits, read the final state and display a summary.

Read the following files (use the final `.loop` value from state.json for `<LOOP>`):
- `state.json` -- `.task`, `.branch`, `.loop`, `.maxLoops`
- `.agents/tmp/phases/loop-<LOOP>/A4-queen-verdict.json` -- `.buildTrackSummary.filesChanged[]`, `.buildTrackSummary.testsAdded`, `.qualityTrackSummary.critical`, `.qualityTrackSummary.warning`, `.qualityTrackSummary.info`, `.evidence[]`
- `.agents/tmp/phases/loop-<LOOP>/A5-ship.json` -- `.commit_sha`, `.pr_url`, `.files_committed[]`

**If all succeeded:**
```
Ants Swarm -- Complete
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

**If blocked:**
```
Ants Swarm -- Blocked
======================
Reason: <.failure from state.json>
Phase at failure: <.currentPhase>
Circuit breaker: <.circuitBreaker.consecutiveFailures> consecutive failures, <.circuitBreaker.stageRestarts> loop-backs used
```

**If stopped mid-pipeline:**
```
Ants Swarm -- Incomplete
========================
Status: in_progress (stopped mid-pipeline)
Current phase: <.currentPhase>
<.failure if present>
```

Clean up the team after displaying the summary.

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
| A3 | sentinel-style | `ants:sentinel-style` |
| A3 | simplifier | `ants:simplifier` |
| A3 | review-arbiter | `ants:review-arbiter` |
| A3 | review-fixer | `ants:review-fixer` |
| A3 | guardian | `ants:guardian` |
| A5 | nurse | `ants:nurse` |
| A5 | drone | `ants:drone` |
