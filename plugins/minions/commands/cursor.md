---
name: minions:cursor
description: Launch a Cursor-inspired development workflow with parallel sub-scouts, per-task commits, and a single judge
argument-hint: <task description>
---

# Minions Cursor

You are launching a Cursor-inspired development workflow with parallel sub-planning, incremental commits, and a single judge verdict system.

## Arguments

- `<task description>`: Required. The task to execute.

Parse from $ARGUMENTS to extract the task description.

## Pipeline

```
Explorers (4x haiku, parallel) → C1 (sub-scouts) → C2 (cursor-builders) → C3 (judge)
                                      ↑                                       │
                                      │              ┌── approve ─────────── C4 (shipper)
                                      │              │
                                      └── replan ────┤
                                                     │
                                           fix ──── C2.5 (fix-builders) → C3 (re-judge)
                                                     ↑                       │
                                                     └─── fix (max 5) ──────┘

Replan: max 3 loops
Fix cycle: max 5 per loop
```

## Step 1: Initialize State

Create directories and write state file inline. No init agent needed.

### 1a. Create directories

```bash
mkdir -p .agents/tmp/phases
rm -rf .agents/tmp/phases
mkdir -p .agents/tmp/phases
```

### 1b. Create feature branch

Create a feature branch from main for this workflow. Generate a slug from the task description:

```bash
# Generate branch name from task (first 40 chars, slugified)
BRANCH_SLUG=$(echo "<task description>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40 | sed 's/-$//')
BRANCH_NAME="feat/cursor-${BRANCH_SLUG}"

# Ensure we're on main and create branch
git checkout main 2>/dev/null || git checkout master
git pull --ff-only origin HEAD 2>/dev/null || true
git checkout -b "$BRANCH_NAME"
```

Store `BRANCH_NAME` for state.json.

### 1c. Write state.json

Write `.agents/tmp/state.json` with the following structure. Use Bash with jq for atomic write (write to tmp file, then mv). Generate `ownerPpid` from `$PPID` and `sessionId` from `head -c 8 /dev/urandom | xxd -p` inline in the jq command:

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "cursor",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "C1",
  "loop": 1,
  "maxLoops": 3,
  "fixCycle": 0,
  "maxFixCycles": 5,
  "ownerPpid": "<PPID value>",
  "sessionId": "<sessionId value>",
  "branch": "<BRANCH_NAME>",
  "schedule": [
    { "phase": "C1", "name": "Plan", "type": "dispatch" },
    { "phase": "C2", "name": "Build", "type": "dispatch" },
    { "phase": "C3", "name": "Judge", "type": "subagent" },
    { "phase": "C4", "name": "Ship", "type": "subagent" }
  ],
  "loops": [
    {
      "loop": 1,
      "startedAt": "<ISO timestamp>",
      "c1": { "status": "pending" },
      "c2": { "status": "pending" },
      "c3": { "status": "pending" }
    }
  ],
  "files": [],
  "failure": null
}
```

## Step 2: Display Schedule

Show the user the planned execution:

```
Minions Cursor — Cursor-Inspired Workflow
============================================
Pre-C1    │ Explore  │ 4x parallel haiku explorers          │ dispatch
Phase C1  │ Plan     │ N sub-scouts (parallel, per-domain)  │ dispatch
Phase C2  │ Build    │ N cursor-builders (per-task commits)  │ dispatch
Phase C3  │ Judge    │ 1 judge (approve/fix/replan)          │ subagent
Phase C2.5│ Fix      │ N fix-builders (targeted fixes)       │ dispatch
Phase C4  │ Ship     │ 1 shipper (squash-merge + PR)         │ subagent

Verdict flow:
  approve  → C4 (ship)
  fix      → C2.5 → C3 (max 5 fix cycles per loop)
  replan   → C1 (max 3 loops)

Gates:
  C1 → C2:   requires c1-plan.md
  C2 → C3:   requires c2-tasks.json
  C3 → C4:   requires c3-judge.json with verdict: approve
  C3 → C2.5: requires c3-judge.json with verdict: fix
  C3 → C1:   requires c3-judge.json with verdict: replan
```

## Step 3: Initialize Task List

Create tasks for progress tracking:

1. **TaskCreate:** "Execute C1: Plan" (activeForm: "Planning with sub-scouts")
2. **TaskCreate:** "Execute C2: Build" (activeForm: "Building with per-task commits")
3. **TaskCreate:** "Execute C3: Judge" (activeForm: "Judging implementation")
4. **TaskCreate:** "Execute C4: Ship" (activeForm: "Shipping implementation")

Set dependencies: C2 blocked by C1, C3 blocked by C2, C4 blocked by C3.

## Step 3.5: Pre-C1 Exploration

Dispatch 4 parallel explorer agents (haiku model) to gather codebase context before sub-scouts plan.

```bash
mkdir -p .agents/tmp/phases
```

Dispatch these 4 agents IN PARALLEL using the Task tool with `model: haiku`:

1. **explorer-files** (subagent_type: `minions:explorer-files`) — Map file structure, directories, naming conventions
2. **explorer-architecture** (subagent_type: `minions:explorer-architecture`) — Trace architecture, dependencies, module boundaries
3. **explorer-tests** (subagent_type: `minions:explorer-tests`) — Survey test frameworks, patterns, coverage
4. **explorer-patterns** (subagent_type: `minions:explorer-patterns`) — Find coding conventions, error handling, related implementations

Each explorer receives:
- The task description
- Its output file path: `.agents/tmp/phases/f0-explorer.{name}.tmp`

Each explorer writes its findings directly to its output file using the Write tool.

After ALL 4 complete, consolidate their output files into a single file:

`.agents/tmp/phases/f0-explorer-context.md`

Structure:
```markdown
# Explorer Context

## File Structure
{content from .agents/tmp/phases/f0-explorer.files.tmp}

## Architecture
{content from .agents/tmp/phases/f0-explorer.architecture.tmp}

## Tests
{content from .agents/tmp/phases/f0-explorer.tests.tmp}

## Patterns
{content from .agents/tmp/phases/f0-explorer.patterns.tmp}
```

**Fallback:** During consolidation, check if each `.tmp` file exists before reading it. If an explorer failed, timed out, or did not write its output file, skip that section. The explorer step is supplementary — it does not block C1 dispatch.

## Step 4: Dispatch C1 (Plan)

Create the loop directory and dispatch sub-scouts:

```bash
mkdir -p .agents/tmp/phases/loop-1
```

Analyze the task and split it into 2-3 domains (e.g., backend/frontend/tests, core/api/config, data/logic/ui).

For each domain, dispatch a **sub-scout** agent (subagent_type: `minions:sub-scout`) in parallel. Each sub-scout receives:
- The full task description
- The assigned domain name and prefix (e.g., "backend" with prefix "B")

Each sub-scout writes its partial plan to `.agents/tmp/phases/loop-1/c1-sub-scout.{domain-slug}.md`.

After ALL sub-scouts complete, read all partial plans, merge their task tables into a unified plan, renumber tasks sequentially (1, 2, 3, ...), resolve cross-domain dependencies, and write the final plan to:

`.agents/tmp/phases/loop-1/c1-plan.md`

After plan aggregation completes, the Stop hook (`on-stop.sh`) drives the orchestrator to dispatch C2, then C3, and handles fix cycles and replan loops automatically.

## Loop Behavior

- After C3, the judge delivers one of three verdicts:
  - **approve**: Advance to C4 (ship)
  - **fix**: Dispatch fix-builders (C2.5) for targeted patches, then re-judge (C3)
  - **replan**: Loop back to C1 with the judge's replan_reason as guidance
- Fix cycles (C2.5→C3) repeat up to 5 times per loop
- If fix cycles exhaust, it forces a replan
- Replan loops (C1→C2→C3) repeat up to 3 times total
- At max replans with issues: workflow stops, reports remaining issues to user

## Phase Agent Mapping

| Phase | Agent | subagent_type |
|-------|-------|---------------|
| Pre-C1 | explorer-files | `minions:explorer-files` |
| Pre-C1 | explorer-architecture | `minions:explorer-architecture` |
| Pre-C1 | explorer-tests | `minions:explorer-tests` |
| Pre-C1 | explorer-patterns | `minions:explorer-patterns` |
| C1 | sub-scout (per domain) | `minions:sub-scout` |
| C2 | cursor-builder (per task) | `minions:cursor-builder` |
| C3 | judge | `minions:judge` |
| C2.5 | cursor-builder (per fix) | `minions:cursor-builder` |
| C4 | shipper | `minions:shipper` |
