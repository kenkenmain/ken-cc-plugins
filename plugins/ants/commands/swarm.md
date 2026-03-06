---
name: ants:swarm
description: Launch a 6-phase swarm workflow with dual-track parallel build and quality execution
argument-hint: <task description>
---

# Ants Swarm

You are launching a 6-phase ant-colony swarm workflow with dual-track parallel build and quality execution.

Use the `swarm` skill for workflow reference documentation.

## Arguments

- `<task description>`: Required. The task to execute.

Parse from $ARGUMENTS to extract the task description.

## Pipeline

```
Phase A0  │ EXPLORE     │ Forage         │ 3-5 parallel foragers + cartographer → aggregator
Phase A1  │ PLAN        │ Architect      │ single planner → A1-plan.md
Phase A2  │ PLAN-REVIEW │ Blueprint      │ reviewer → A2-review.json
Phase A3  │ BUILD+QUAL  │ Dual-Track     │ workers (parallel waves) + sentinels + guardians
Phase A4  │ SYNC        │ Queen          │ merge build+quality → ship/loop verdict
Phase A5  │ SHIP        │ Ship           │ nurse (docs) → drone (commit + PR)

Loop: If A4 verdict is "loop" → back to A1 (max 5 loops)
All clean → A5 ships the work
```

## Step 1: Initialize State

Create directories and write state file inline.

### 1a. Create directories

```bash
mkdir -p .agents/tmp/phases
rm -rf .agents/tmp/phases
mkdir -p .agents/tmp/phases
```

### 1b. Create feature branch

```bash
BRANCH_SLUG=$(echo "<task description>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40 | sed 's/-$//')
BRANCH_NAME="feat/ants-${BRANCH_SLUG}"

git checkout main 2>/dev/null || git checkout master
git pull --ff-only origin HEAD 2>/dev/null || true
git checkout -b "$BRANCH_NAME"
```

Store `BRANCH_NAME` for state.json.

### 1c. Write state.json

Write `.agents/tmp/state.json` with the following structure. Use Bash with jq for atomic write:

```json
{
  "version": 1,
  "plugin": "ants",
  "pipeline": "swarm",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "A0",
  "currentStage": "EXPLORE",
  "ownerPpid": "<PPID>",
  "sessionId": "<random hex>",
  "branch": "<BRANCH_NAME>",
  "maxLoops": 5,
  "loop": 1,
  "schedule": [
    {"phase":"A0","stage":"EXPLORE","name":"Forage","type":"dispatch"},
    {"phase":"A1","stage":"PLAN","name":"Architect","type":"subagent"},
    {"phase":"A2","stage":"PLAN-REVIEW","name":"Blueprint Review","type":"review"},
    {"phase":"A3","stage":"BUILD+QUAL","name":"Dual-Track Build","type":"dispatch"},
    {"phase":"A4","stage":"SYNC","name":"Synchronize","type":"subagent"},
    {"phase":"A5","stage":"SHIP","name":"Ship","type":"subagent"}
  ],
  "buildTrack": {
    "waves": [],
    "currentWave": 0,
    "totalWaves": 0
  },
  "qualityTrack": {
    "reviews": [],
    "criticalIssues": 0
  },
  "files": [],
  "failure": null
}
```

## Step 2: Display Schedule

```
Ants Swarm — 6-Phase Dual-Track Pipeline
=========================================
Phase A0  │ EXPLORE     │ Forage         │ dispatch  → foragers + cartographer + aggregator
Phase A1  │ PLAN        │ Architect      │ subagent  → architect
Phase A2  │ PLAN-REVIEW │ Blueprint      │ review    → blueprint-reviewer
Phase A3  │ BUILD+QUAL  │ Dual-Track     │ dispatch  → workers + sentinels + guardians (waves)
Phase A4  │ SYNC        │ Queen          │ subagent  → queen (ship/loop verdict)
Phase A5  │ SHIP        │ Ship           │ subagent  → nurse (docs) + drone (commit + PR)
```

## Step 3: Dispatch Phase A0 (Forage)

Read the prompt template at `prompts/A0-explore.md` for dispatch instructions.

Dispatch 3-5 `ants:forager` agents in parallel + 1 `ants:cartographer`, then `ants:explore-aggregator`.

After Phase A0 completes, the Stop hook (`on-stop.sh`) drives the orchestrator through all phases automatically.

## Phase Agent Mapping

| Phase | Agent | subagent_type |
|-------|-------|---------------|
| A0 | forager (batch) | `ants:forager` |
| A0 | cartographer | `ants:cartographer` |
| A0 | explore-aggregator | `ants:explore-aggregator` |
| A1 | architect | `ants:architect` |
| A2 | blueprint-reviewer | `ants:blueprint-reviewer` |
| A3 | worker (batch per wave) | `ants:worker` |
| A3 | sentinel (per wave) | `ants:sentinel` |
| A3 | guardian (per wave) | `ants:guardian` |
| A4 | queen | `ants:queen` |
| A5 | nurse | `ants:nurse` |
| A5 | drone | `ants:drone` |
