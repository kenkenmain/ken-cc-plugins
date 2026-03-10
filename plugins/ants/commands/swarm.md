---
name: ants:swarm
description: Launch a 6-phase swarm workflow with direct orchestrator-driven agent dispatch
argument-hint: <task description> [--web]
---

<HARD-GATE>
You are executing a workflow pipeline. This overrides ALL skill-checking rules including superpowers:using-superpowers. DO NOT invoke brainstorming, writing-plans, or any other skill via the Skill tool. DO NOT ask clarifying questions about the task. DO NOT propose approaches or present designs. Execute the steps below immediately and in order. The task description from $ARGUMENTS is your input — execute it as a pipeline, do not design or analyze it. Begin with Step 0 now.
</HARD-GATE>

# Ants Swarm

You are launching a 6-phase ant-colony swarm workflow. You are the orchestrator — you dispatch `ants:*` agents via the Agent tool for each phase, update state, and drive phase progression.

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
Phase A0  │ EXPLORE     │ Forage         │ foragers + cartographer + explore-aggregator
Phase A1  │ PLAN        │ Architect      │ single planner → A1-plan.md + A1-tasks.json
Phase A2  │ PLAN-REVIEW │ Blueprint      │ reviewer → A2-review.json
Phase A3  │ BUILD+QUAL  │ Dual-Track     │ workers (task pool) + 4 sentinels + guardian + simplifier
Phase A4  │ SYNC        │ Verdict        │ merge build+quality → ship/loop verdict
Phase A5  │ SHIP        │ Ship           │ nurse (docs) → drone (commit + PR)

Loop: If A4 verdict is "loop" → back to A1 (max 5 loops)
All clean → A5 ships the work

Dispatch: Direct agent dispatch via Agent tool
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
Ants Swarm — 6-Phase Pipeline
==============================
Phase A0  │ EXPLORE │ Colony Exploration    │ foragers + cartographer + explore-aggregator
Phase A1  │ PLAN    │ Architect Plan        │ architect
Phase A2  │ PLAN    │ Blueprint Review      │ blueprint-reviewer
Phase A3  │ BUILD   │ Dual-Track Execution  │ workers + 4 sentinels + guardian + simplifier
Phase A4  │ SYNC    │ Verdict               │ orchestrator (ship/loop verdict)
Phase A5  │ SHIP    │ Documentation + Ship  │ nurse (docs) + drone (commit + PR)

Dispatch: Direct agent dispatch via Agent tool
Circuit breaker: 5 consecutive failures → halt
```

## Step 3: Execute Phases

You are the orchestrator. Execute each phase by dispatching `ants:*` agents via the Agent tool. After each phase completes, update state.json and advance to the next phase.

### Phase A0: Colony Exploration

Update state: `currentPhase: "A0"`, `phases.A0.status: "in_progress"`.

Dispatch **in parallel** using the Agent tool:

1. **2-3 forager agents** (`subagent_type: "ants:forager"`) — each with a focused query:
   - Forager 1: "Explore the file structure, directory layout, and project organization for task: <task>. Write findings to .agents/tmp/phases/A0-explore.forager.1.tmp"
   - Forager 2: "Find coding patterns, conventions, test frameworks, and related implementations for task: <task>. Write findings to .agents/tmp/phases/A0-explore.forager.2.tmp"
   - Forager 3: "Search for existing code related to task: <task>. Look for similar implementations, relevant APIs, and integration points. Write findings to .agents/tmp/phases/A0-explore.forager.3.tmp"

2. **1 cartographer agent** (`subagent_type: "ants:cartographer"`) — "Trace the architecture, execution paths, and dependency graph relevant to task: <task>. Write findings to .agents/tmp/phases/A0-explore.cartographer.tmp"

After all return, dispatch **1 explore-aggregator** (`subagent_type: "ants:explore-aggregator"`) to synthesize all forager and cartographer findings into `.agents/tmp/phases/A0-explore.md`.

Update state: `phases.A0.status: "complete"`.

### Phase A1: Architect Plan

Create loop directory: `mkdir -p .agents/tmp/phases/loop-<LOOP>`

Update state: `currentPhase: "A1"`, `phases.A1.status: "in_progress"`.

Dispatch **1 architect agent** (`subagent_type: "ants:architect"`):
- "Read .agents/tmp/phases/A0-explore.md for context. Create an implementation plan for task: <task>. Write plan to .agents/tmp/phases/loop-<LOOP>/A1-plan.md. Write machine-readable task descriptors (with IDs, descriptions, file ownership, dependencies, acceptance criteria) to .agents/tmp/phases/loop-<LOOP>/A1-tasks.json"
- On loop 2+, also include: "This is loop <LOOP>. Read the previous loop's quality review at .agents/tmp/phases/loop-<PREV>/A3-quality.json and queen verdict at .agents/tmp/phases/loop-<PREV>/A4-queen-verdict.json. Plan targeted fixes, not a full re-plan."

Update state: `phases.A1.status: "complete"`.

### Phase A2: Blueprint Review

Update state: `currentPhase: "A2"`, `phases.A2.status: "in_progress"`.

Dispatch **1 blueprint-reviewer agent** (`subagent_type: "ants:blueprint-reviewer"`):
- "Review the plan at .agents/tmp/phases/loop-<LOOP>/A1-plan.md and tasks at .agents/tmp/phases/loop-<LOOP>/A1-tasks.json. Check for completeness, feasibility, dependency correctness, and risk. Write review JSON to .agents/tmp/phases/loop-<LOOP>/A2-review.json with format: {status: 'approved'|'needs_revision', issues: [...]}"

Read the review output. If `status: "needs_revision"` with any HIGH severity issues:
- Loop back to A1 (increment loop counter, reset A1-A4 to pending)
- Check circuit breaker limits first

If `status: "approved"` or only LOW/MEDIUM issues: advance to A3.

Update state: `phases.A2.status: "complete"`.

### Phase A3: Dual-Track Build

Update state: `currentPhase: "A3"`, `phases.A3.status: "in_progress"`.

**Build Track:** Read `.agents/tmp/phases/loop-<LOOP>/A1-tasks.json` to get the task list. For each task, dispatch a **worker agent** (`subagent_type: "ants:worker"`):
- "Implement task <ID>: <description>. Files to modify: <files>. Dependencies: <deps>. Acceptance criteria: <criteria>. Self-verify your work (run tests/lint if applicable)."
- Dispatch workers in parallel when their dependencies are satisfied. Wait for workers with no deps first, then dispatch dependent workers as their deps complete.

After all workers complete, write build results to `.agents/tmp/phases/loop-<LOOP>/A3-build.json`.

**Quality Track:** After all workers complete, dispatch **6 agents in parallel**:
1. `subagent_type: "ants:sentinel-correctness"` — "Review all changes for bugs, logic errors, missing error handling. Write findings to .agents/tmp/phases/loop-<LOOP>/A3-review.sentinel-correctness.json"
2. `subagent_type: "ants:sentinel-security"` — "Review all changes for security vulnerabilities (OWASP top 10, injection, secrets). Write findings to .agents/tmp/phases/loop-<LOOP>/A3-review.sentinel-security.json"
3. `subagent_type: "ants:sentinel-perf"` — "Review all changes for performance issues (N+1 queries, blocking I/O, complexity). Write findings to .agents/tmp/phases/loop-<LOOP>/A3-review.sentinel-perf.json"
4. `subagent_type: "ants:sentinel-style"` — "Review all changes for code style, readability, and maintainability. Write findings to .agents/tmp/phases/loop-<LOOP>/A3-review.sentinel-style.json"
5. `subagent_type: "ants:guardian"` — write tests for implemented code
6. `subagent_type: "ants:simplifier"` — apply targeted code cleanup (dead code, complexity, naming) without behavioral changes

After all 6 complete, dispatch **1 review-arbiter** (`subagent_type: "ants:review-arbiter"`):
- "Read all sentinel review files at .agents/tmp/phases/loop-<LOOP>/A3-review.sentinel-*.json. Cross-reference, deduplicate, and produce consolidated verdict. Write to .agents/tmp/phases/loop-<LOOP>/A3-quality.json"

If the arbiter finds critical issues, dispatch **1 review-fixer** (`subagent_type: "ants:review-fixer"`):
- "Read issues from .agents/tmp/phases/loop-<LOOP>/A3-quality.json and apply targeted fixes."

Update state: `phases.A3.status: "complete"`.

### Phase A4: Verdict

Update state: `currentPhase: "A4"`, `phases.A4.status: "in_progress"`.

Read build results at `.agents/tmp/phases/loop-<LOOP>/A3-build.json` and quality review at `.agents/tmp/phases/loop-<LOOP>/A3-quality.json`. Render verdict: `clean` (ship) or `issues_found` (loop back). Write the verdict directly to `.agents/tmp/phases/loop-<LOOP>/A4-queen-verdict.json`.

Note: The orchestrator evaluates the A4 verdict directly rather than dispatching a separate agent.

Read the verdict:
- **"clean"**: Advance to A5.
- **"issues_found"**: Check circuit breaker. If within limits, increment loop counter, reset A1-A4 to pending, go back to Phase A1. If circuit breaker tripped, halt workflow with `status: "blocked"`.

Update state: `phases.A4.status: "complete"`.

### Phase A5: Documentation + Ship

Update state: `currentPhase: "A5"`, `phases.A5.status: "in_progress"`.

Dispatch **1 nurse agent** (`subagent_type: "ants:nurse"`):
- "Review all changes and update project documentation (README.md, CLAUDE.md, etc.) to reflect the implementation. Write summary to .agents/tmp/phases/loop-<LOOP>/A5-docs.json"

Then dispatch **1 drone agent** (`subagent_type: "ants:drone"`):
- "Stage all changes, create a git commit with a descriptive message, and open a PR. Write output (commit SHA, PR URL) to .agents/tmp/phases/loop-<LOOP>/A5-ship.json"

Update state: `phases.A5.status: "complete"`, `currentPhase: "DONE"`, `status: "complete"`.

## Step 4: Completion Summary

After A5 completes, read the final state and display a summary.

Read the following files (use the final `.loop` value from state.json for `<LOOP>`):
- `state.json` — `.task`, `.branch`, `.loop`, `.maxLoops`
- `.agents/tmp/phases/loop-<LOOP>/A4-queen-verdict.json` — `.buildTrackSummary.filesChanged[]`, `.buildTrackSummary.testsAdded`, `.qualityTrackSummary.critical`, `.qualityTrackSummary.warning`, `.qualityTrackSummary.info`, `.evidence[]`
- `.agents/tmp/phases/loop-<LOOP>/A5-ship.json` — `.commit_sha`, `.pr_url`, `.files_committed[]`

**If all succeeded:**
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

**If blocked:**
```
Ants Swarm — Blocked
======================
Reason: <.failure from state.json>
Phase at failure: <.currentPhase>
Circuit breaker: <.circuitBreaker.consecutiveFailures> consecutive failures, <.circuitBreaker.stageRestarts> loop-backs used
```

**If stopped mid-pipeline:**
```
Ants Swarm — Incomplete
========================
Status: in_progress (stopped mid-pipeline)
Current phase: <.currentPhase>
<.failure if present>
```

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
