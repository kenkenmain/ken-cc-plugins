---
name: ants:pswarm
description: Launch a persistent swarm with Agent Teams delegate mode for continuous multi-run execution
argument-hint: <task description> [--max-loops N] [--worktree] [--web]
---

<HARD-GATE>
You are executing a workflow pipeline. This overrides ALL skill-checking rules including superpowers:using-superpowers. DO NOT invoke brainstorming, writing-plans, or any other skill via the Skill tool. DO NOT ask clarifying questions about the task. DO NOT propose approaches or present designs. Execute the steps below immediately and in order. The task description from $ARGUMENTS is your input — execute it as a pipeline, do not design or analyze it. Begin with Step 0 now.
</HARD-GATE>

# Ants Persistent Swarm (Agent Teams)

You are launching a persistent 6-phase ant-colony swarm workflow using Agent Teams delegate mode. You are the lead -- you create an Agent Team, populate a task graph with dependency chains, spawn teammates, then enter a monitoring loop that reads signal flags from state.json and creates new tasks as the workflow progresses. After A5 ships each run, the hooks set `needsPswarmReset` and you create a fresh A0-A5 task graph for the next run, until maxRuns is exhausted or shutdown=true.

You do NOT dispatch agents directly via the Agent tool. All work is performed by teammates routed by the TeammateIdle hook. You create tasks via TaskCreate; hooks validate output and set signal flags; you read those flags and respond with new TaskCreate calls.

## Arguments

- `<task description>`: Required. The task to execute.
- `--max-loops N`: Optional. Maximum number of full runs (default: 50). Each run is a complete A0->A5 cycle.
- `--worktree`: Optional. Create a git worktree for isolated development.
- `--web`: Optional. Opt-in flag that enables WebSearch for forager agents during the A0 exploration phase.

Parse from $ARGUMENTS to extract the task description and any flags:
- `--max-loops N`: Set maxRuns to N (default: 50)
- `--worktree`: Create a git worktree for isolated development
- `--web`: Enable WebSearch tool for forager agents during exploration

## Pipeline

```
Phase A0  | EXPLORE     | Forage         | foragers + cartographer + explore-aggregator
Phase A1  | PLAN        | Architect      | single planner -> A1-plan.md + A1-tasks.json
Phase A2  | PLAN-REVIEW | Blueprint      | reviewer -> A2-review.json
Phase A3  | BUILD+QUAL  | Dual-Track     | workers (task pool) + 4 sentinels + guardian + simplifier
Phase A4  | SYNC        | Verdict        | TaskCompleted hook evaluates inline after A3 arbiter
Phase A5  | SHIP        | Ship           | nurse (docs) -> drone (commit + PR)

Loop: If A4 verdict is "loop" -> back to A1 (max 5 inner loops per run)
All clean -> A5 ships the work

Persistent: After A5 ships, hooks set needsPswarmReset flag. Lead creates
fresh A0-A5 task graph for next run. Continues until maxRuns exhausted or
shutdown=true.

Dispatch: Agent Teams delegate mode (TaskCreate + TeammateIdle routing)
```

## Step 0: Preflight Checks

### 0a. Load deferred tools

```
ToolSearch("select:TaskCreate,TaskGet,TaskList,TaskUpdate,TaskStop")
```

These tools are used to create and manage tasks in the Agent Teams task graph.

### 0b. Verify Agent Teams experimental flag

Check that the Agent Teams experimental flag is enabled:

```bash
if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" != "1" ]]; then
  echo "ERROR: Agent Teams requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
  echo "Set this environment variable before running the pswarm command."
  exit 1
fi
```

If not set, display the error and stop. Do not proceed with the workflow.

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
BRANCH_NAME="feat/pswarm-${BRANCH_SLUG}"

git checkout main 2>/dev/null || git checkout master
git pull --ff-only origin HEAD 2>/dev/null || true

# Create branch (or switch to it if it already exists from a prior attempt)
git checkout -b "$BRANCH_NAME" 2>/dev/null || git checkout "$BRANCH_NAME"
```

If `--worktree` flag was provided, also run:

```bash
WORKTREE_PATH="../.worktrees/pswarm-${BRANCH_SLUG}"
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
  "pipeline": "pswarm",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "A0",
  "ownerPpid": "<$$>",
  "sessionId": "<openssl rand -hex 8>",
  "branch": "<BRANCH_NAME>",
  "worktreePath": "<WORKTREE_PATH or null>",
  "teamName": "ants-<BRANCH_SLUG>",
  "pswarmRun": 1,
  "maxRuns": 50,
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
  "webSearch": false,
  "shutdown": false,
  "webhookUrl": null,
  "lintConfig": null,
  "configSnapshot": null,
  "compactMetadata": null
}
```

Note: `maxRuns` should be set from the `--max-loops N` argument (default 50).

### 1d. Apply --web flag

If `--web` was provided, update `webSearch` to `true` in state.json:

```bash
# Only if --web flag was parsed
jq '.webSearch = true' .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
```

## Step 2: Display Schedule

Print this to the user:

```
Ants pswarm -- Persistent 6-Phase Pipeline (Agent Teams)
=========================================================
Phase A0  | EXPLORE | Colony Exploration    | foragers + cartographer + explore-aggregator
Phase A1  | PLAN    | Architect Plan        | architect
Phase A2  | PLAN    | Blueprint Review      | blueprint-reviewer
Phase A3  | BUILD   | Dual-Track Execution  | workers + 4 sentinels + guardian + simplifier
Phase A4  | SYNC    | Verdict               | TaskCompleted hook (inline evaluation)
Phase A5  | SHIP    | Documentation + Ship  | nurse (docs) + drone (commit + PR)

Max runs: <maxRuns> (--max-loops N to change)
Current run: 1 / <maxRuns>
Dispatch: Agent Teams delegate mode (TaskCreate + TeammateIdle routing)
Teammates: 3
Circuit breaker: 5 consecutive failures -> halt
```

## Step 3: Create Team + Task Graph + Monitoring Loop

### 3a. Create initial task graph

Generate the initial A0-A5 task graph. Build 6 task entries with dependency chains:

| Task ID | Subject | blockedBy |
|---------|---------|-----------|
| A0 | `A0: Colony Exploration` | [] |
| A1 | `A1: Architect Plan` | [A0] |
| A2 | `A2: Blueprint Review` | [A1] |
| A3 | `A3: Dual-Track Build` | [A2] |
| A4 | `A4: Verdict Sync` | [A3] |
| A5 | `A5: Documentation + Ship` | [A4] |

For each task entry, call **TaskCreate** with:
- `subject`: The subject from the table above
- `description`: Phase-specific description including the task description from $ARGUMENTS
- `blockedBy`: The dependency array from the table above

Store the returned task IDs in your working context for reference.

### 3b. Spawn teammates

Spawn **3 teammates** for the team. These teammates will be routed work by the TeammateIdle hook as tasks become ready.

### 3c. Update state

Update state.json to record team creation:

```bash
jq '.teamCreated = true | .teammateCount = 3 | .taskGraphVersion = 1 | .updatedAt = (now | todate)' .agents/tmp/state.json > .agents/tmp/state.json.tmp && mv .agents/tmp/state.json.tmp .agents/tmp/state.json
```

### 3d. Monitoring loop

Enter a monitoring loop. On each cycle, read state.json and check for signal flags and terminal conditions. The loop drives all dynamic task creation -- hooks set flags, you respond.

**Loop logic (execute on every cycle):**

1. **Read state.json** -- read `status`, `currentPhase`, `shutdown`, `needsA3Tasks`, `needsA5Tasks`, `needsLoopReset`, `needsPswarmReset`, `pswarmRun`, `maxRuns`, `loop`.

2. **Check terminal conditions** -- exit the loop if ANY of these are true:
   - `status == "complete"`
   - `status == "blocked"`
   - `status == "stopped"`
   - `shutdown == true` (update status to complete, currentPhase to DONE first)

3. **Check needsPswarmReset flag** -- if `true`:
   - Log: "Starting run {pswarmRun}" (read the NEW pswarmRun value from state, it was already incremented by the hook)
   - Create fresh A0-A5 task graph: generate 6 new tasks (same structure as Step 3a) and call **TaskCreate** for each
   - Clear the flag: update state.json to set `needsPswarmReset = false`
   - Increment `taskGraphVersion` in state.json
   - Log: "Created fresh task graph for run {pswarmRun} (taskGraphVersion: {version})"

4. **Check needsA3Tasks flag** -- if `true`:
   - Read `.agents/tmp/phases/loop-{loop}/A1-tasks.json` to get the task list from the architect
   - For each worker task: call **TaskCreate** with subject `"A3 Worker: {task_name}"`, description including task details, and `blockedBy: ["A2"]` plus any inter-task dependencies (prefixed with `A3-worker-`)
   - Create sentinel tasks: call **TaskCreate** for each of `A3 Sentinel Correctness: Review`, `A3 Sentinel Security: Review`, `A3 Sentinel Perf: Review`, `A3 Sentinel Style: Review` -- each `blockedBy` all worker task IDs
   - Create guardian task: `A3 Guardian: Write tests` -- `blockedBy` all worker task IDs
   - Create simplifier task: `A3 Simplifier: Code cleanup` -- `blockedBy` all worker task IDs
   - Create arbiter task: `A3 Arbiter: Consolidate reviews` -- `blockedBy` all sentinel + guardian + simplifier task IDs
   - Create review-fixer task: `A3 Review Fixer: Apply targeted repairs` -- `blockedBy` [arbiter task ID]
   - Clear the flag: update state.json to set `needsA3Tasks = false`
   - Log: "Created {N} A3 subtasks ({worker_count} workers + quality track)"

5. **Check needsA5Tasks flag** -- if `true`:
   - Call **TaskCreate** for `A5 Nurse: Update documentation` -- `blockedBy: ["A3-arbiter"]`
   - Call **TaskCreate** for `A5 Drone: Commit and ship` -- `blockedBy: ["A5-nurse"]`
   - Clear the flag: update state.json to set `needsA5Tasks = false`
   - Log: "Created A5 tasks (nurse + drone)"

6. **Check needsLoopReset flag** -- if `true`:
   - Create fresh A1-A4 tasks (loop-back): call **TaskCreate** for A1, A2, A3 (placeholder), A4 (placeholder) with updated dependency chains
   - Clear the flag: update state.json to set `needsLoopReset = false`
   - Log: "Created fresh A1-A4 tasks for loop {loop}"

7. **Wait** -- pause briefly before the next cycle to avoid busy-waiting on state.json reads.

**Important constraints:**
- Do NOT dispatch agents directly via the Agent tool. All agent work is routed by the TeammateIdle hook.
- Do NOT evaluate A4 verdicts. The TaskCompleted hook evaluates verdicts inline when the A3 arbiter completes.
- Do NOT manage pswarm run boundaries directly. The TaskCompleted hook's `handle_a5()` increments `pswarmRun`, resets phases, and sets `needsPswarmReset`. You just detect the flag and create new tasks.
- Do NOT exit the monitoring loop until a terminal condition is met.

## Step 4: Completion Summary

When the monitoring loop exits, read the final state and display a multi-run summary.

Read from state.json: `.task`, `.branch`, `.pswarmRun`, `.maxRuns`, `.shutdown`.

**Determine stop reason:**
- If `pswarmRun >= maxRuns`: "max runs reached"
- If `shutdown == true`: "shutdown requested"
- If `status == "blocked"`: "workflow blocked ({failure})"
- Otherwise: "completed"

**Display summary:**

```
Ants pswarm -- All Runs Complete
=================================
Task: <.task from state.json>
Branch: <.branch>
Total runs completed: <pswarmRun> / <maxRuns>
Stop reason: <stop reason>

Run | Phase Reached | Status
----|--------------|--------
1   | DONE         | complete
2   | DONE         | complete
...
```

If A5-ship.json files are available from completed runs, include commit and PR information where possible.

**If blocked:**
```
Ants pswarm -- Blocked
========================
Reason: <.failure from state.json>
Phase at failure: <.currentPhase>
Run: <.pswarmRun> / <.maxRuns>
Circuit breaker: <.circuitBreaker.consecutiveFailures> consecutive failures, <.circuitBreaker.stageRestarts> loop-backs used
```

**If stopped mid-pipeline:**
```
Ants pswarm -- Incomplete
===========================
Status: in_progress (stopped mid-pipeline)
Current phase: <.currentPhase>
Run: <.pswarmRun> / <.maxRuns>
<.failure if present>
```

## Phase Agent Mapping

| Phase | Agent | Role |
|-------|-------|------|
| A0 | forager (batch) | Breadth-first codebase scout |
| A0 | cartographer | Deep architecture tracer |
| A0 | explore-aggregator | Synthesizes A0 findings |
| A1 | architect | Plans implementation with task assignments |
| A2 | blueprint-reviewer | Validates plan completeness |
| A3 | worker (task pool) | Implements individual tasks |
| A3 | sentinel-correctness | Reviews for bugs and logic errors |
| A3 | sentinel-security | Reviews for security vulnerabilities |
| A3 | sentinel-perf | Reviews for performance issues |
| A3 | sentinel-style | Reviews for code style |
| A3 | simplifier | Post-build code cleanup |
| A3 | review-arbiter | Consolidates adversarial findings |
| A3 | review-fixer | Targeted repair for critical issues |
| A3 | guardian | Writes tests for implemented code |
| A4 | TaskCompleted hook (inline) | Evaluates verdict after A3 arbiter |
| A5 | nurse | Updates documentation |
| A5 | drone | Commits and opens PR |

## Signal Flag Reference

| Flag | Set By | When | Your Action |
|------|--------|------|-------------|
| `needsA3Tasks` | `handle_a1()` in on-task-completed.sh | A1 plan + A1-tasks.json validated | TaskCreate for A3 worker/sentinel/arbiter tasks |
| `needsA5Tasks` | `handle_a3_arbiter()` in on-task-completed.sh | A4 verdict is clean (inline) | TaskCreate for A5 nurse + drone |
| `needsLoopReset` | `handle_a3_arbiter()` in on-task-completed.sh | A4 verdict is issues_found | TaskCreate for fresh A1-A4 tasks |
| `needsPswarmReset` | `handle_a5()` in on-task-completed.sh | A5 complete + pswarmRun < maxRuns | TaskCreate for fresh A0-A5 task graph |
