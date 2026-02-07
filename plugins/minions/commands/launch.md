---
name: minions:launch
description: Launch a 4-phase development workflow with personality-driven agents and loop-back issue resolution
argument-hint: <task description>
---

# Minions Launch

You are launching a 4-phase development workflow with personality-driven agents.

## Arguments

- `<task description>`: Required. The task to execute.

Parse from $ARGUMENTS to extract the task description.

## Pipeline

```
Explorers (4x haiku, parallel) → F1 (scout) → F2 (builder) → F3 (critic ∥ pedant ∥ witness ∥ security-reviewer ∥ silent-failure-hunter)
                                      ↑                              │
                                      └──────── if any issues ───────┘
                                                (max 10 loops)

All clean → F4 (shipper)
Loop 10 hit → stop and report
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
BRANCH_NAME="feat/minions-${BRANCH_SLUG}"

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
  "pipeline": "launch",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "F1",
  "loop": 1,
  "maxLoops": 10,
  "ownerPpid": "<PPID value>",
  "sessionId": "<sessionId value>",
  "branch": "<BRANCH_NAME>",
  "schedule": [
    { "phase": "F1", "name": "Scout", "type": "subagent" },
    { "phase": "F2", "name": "Build", "type": "dispatch" },
    { "phase": "F3", "name": "Review", "type": "dispatch" },
    { "phase": "F4", "name": "Ship", "type": "subagent" }
  ],
  "loops": [
    {
      "loop": 1,
      "startedAt": "<ISO timestamp>",
      "f1": { "status": "pending" },
      "f2": { "status": "pending" },
      "f3": { "status": "pending" }
    }
  ],
  "files": [],
  "failure": null
}
```

## Step 2: Display Schedule

Show the user the planned execution:

```
Minions Launch — 4-Phase Workflow
====================================
Pre-F1    │ Explore  │ 4x parallel haiku explorers         │ dispatch
Phase F1  │ Scout    │ Explore + brainstorm + plan       │ subagent
Phase F2  │ Build    │ Implement tasks (parallel)         │ dispatch
Phase F3  │ Review   │ critic ∥ pedant ∥ witness ∥ sec ∥ silent │ dispatch
Phase F4  │ Ship     │ Docs + commit + PR                 │ subagent

Loop: F1 → F2 → F3 (if issues, back to F1, max 10 loops)

Gates:
  F1 → F2:  requires f1-plan.md
  F2 → F3:  requires f2-tasks.json
  F3 → F4:  requires f3-verdict.json with verdict: clean
```

## Step 3: Initialize Task List

Create tasks for progress tracking:

1. **TaskCreate:** "Execute F1: Scout" (activeForm: "Scouting codebase")
2. **TaskCreate:** "Execute F2: Build" (activeForm: "Building implementation")
3. **TaskCreate:** "Execute F3: Review" (activeForm: "Reviewing implementation")
4. **TaskCreate:** "Execute F4: Ship" (activeForm: "Shipping implementation")

Set dependencies: F2 blocked by F1, F3 blocked by F2, F4 blocked by F3.

## Step 3.5: Pre-Scout Exploration

Dispatch 4 parallel explorer agents (haiku model) to gather codebase context before scout plans.

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

**Fallback:** During consolidation, check if each `.tmp` file exists before reading it. If an explorer failed, timed out, or did not write its output file, skip that section. The explorer step is supplementary — it does not block F1 dispatch. If no `.tmp` files exist, skip consolidation entirely and proceed to F1 without explorer context.

## Step 4: Dispatch F1 (Scout)

Create the loop directory and dispatch scout:

```bash
mkdir -p .agents/tmp/phases/loop-1
```

Dispatch the **scout** agent (subagent_type: `minions:scout`) with the task description.

Scout must write its plan to `.agents/tmp/phases/loop-1/f1-plan.md`.

After scout completes, the Stop hook (`on-stop.sh`) drives the orchestrator to dispatch F2, then F3, and handles loop-back automatically.

## Loop Behavior

- After F3, if any reviewer reports `issues_found`, the workflow loops back to F1
- Scout re-plans based on the previous loop's F3 outputs (targeted fixes, not full re-plan)
- Builders implement the fix plan
- Reviewers verify again
- This continues until F3 is clean or loop 10 is reached
- At loop 10 with issues: workflow stops, reports remaining issues to user

## Phase Agent Mapping

| Phase | Agent | subagent_type |
|-------|-------|---------------|
| Pre-F1 | explorer-files | `minions:explorer-files` |
| Pre-F1 | explorer-architecture | `minions:explorer-architecture` |
| Pre-F1 | explorer-tests | `minions:explorer-tests` |
| Pre-F1 | explorer-patterns | `minions:explorer-patterns` |
| F1 | scout | `minions:scout` |
| F2 | builder (per task) | `minions:builder` |
| F3 | critic | `minions:critic` |
| F3 | pedant | `minions:pedant` |
| F3 | witness | `minions:witness` |
| F3 | security-reviewer | `minions:security-reviewer` |
| F3 | silent-failure-hunter | `minions:silent-failure-hunter` |
| F4 | shipper | `minions:shipper` |
