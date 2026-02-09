---
name: minions:superlaunch
description: Superlaunch — Claude-only 15-phase thorough pipeline with minions agents and minions hooks
argument-hint: <task description>
---

# Minions Superlaunch

You are launching a Claude-only 15-phase thorough development pipeline. This uses **minions plugin agents** (self-contained, 26 superlaunch agents) driven by **minions plugin hooks** (Ralph-style loop driver).

Use the `superlaunch` skill for workflow reference documentation.

## Arguments

- `<task description>`: Required. The task to execute.

Parse from $ARGUMENTS to extract the task description.

## Pipeline

```
EXPLORE → PLAN → IMPLEMENT → TEST → FINAL → COMPLETE

Phase S0  │ EXPLORE   │ Explore                 │ dispatch
Phase S1  │ PLAN      │ Brainstorm              │ subagent
Phase S2  │ PLAN      │ Plan                    │ dispatch
Phase S3  │ PLAN      │ Plan Review             │ review
Phase S4  │ IMPLEMENT │ Implement               │ dispatch
Phase S5  │ IMPLEMENT │ Simplify                │ subagent
Phase S6  │ IMPLEMENT │ Impl Review             │ review
Phase S7  │ TEST      │ Run Tests               │ subagent
Phase S8  │ TEST      │ Analyze                 │ subagent
Phase S9  │ TEST      │ Develop Tests           │ subagent
Phase S10 │ TEST      │ Test Dev Review         │ review
Phase S11 │ TEST      │ Test Review             │ review
Phase S12 │ FINAL     │ Documentation           │ subagent
Phase S13 │ FINAL     │ Final Review            │ review
Phase S14 │ FINAL     │ Completion              │ subagent

Gates: EXPLORE→PLAN, PLAN→IMPLEMENT, IMPLEMENT→TEST, TEST→FINAL, FINAL→COMPLETE
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
  "pipeline": "superlaunch",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "S0",
  "currentStage": "EXPLORE",
  "codexAvailable": false,
  "testDeveloper": "minions:test-developer",
  "failureAnalyzer": "minions:failure-analyzer",
  "docUpdater": "minions:doc-updater",
  "ownerPpid": "<PPID value>",
  "sessionId": "<sessionId value>",
  "branch": "<BRANCH_NAME>",
  "schedule": [
    {"phase":"S0","stage":"EXPLORE","name":"Explore","type":"dispatch"},
    {"phase":"S1","stage":"PLAN","name":"Brainstorm","type":"subagent"},
    {"phase":"S2","stage":"PLAN","name":"Plan","type":"dispatch"},
    {"phase":"S3","stage":"PLAN","name":"Plan Review","type":"review"},
    {"phase":"S4","stage":"IMPLEMENT","name":"Implement","type":"dispatch"},
    {"phase":"S5","stage":"IMPLEMENT","name":"Simplify","type":"subagent"},
    {"phase":"S6","stage":"IMPLEMENT","name":"Impl Review","type":"review"},
    {"phase":"S7","stage":"TEST","name":"Run Tests","type":"subagent"},
    {"phase":"S8","stage":"TEST","name":"Analyze","type":"subagent"},
    {"phase":"S9","stage":"TEST","name":"Develop Tests","type":"subagent"},
    {"phase":"S10","stage":"TEST","name":"Test Dev Review","type":"review"},
    {"phase":"S11","stage":"TEST","name":"Test Review","type":"review"},
    {"phase":"S12","stage":"FINAL","name":"Documentation","type":"subagent"},
    {"phase":"S13","stage":"FINAL","name":"Final Review","type":"review"},
    {"phase":"S14","stage":"FINAL","name":"Completion","type":"subagent"}
  ],
  "gates": {
    "EXPLORE->PLAN": {"required":["S0-explore.md"],"phase":"S0"},
    "PLAN->IMPLEMENT": {"required":["S1-brainstorm.md","S2-plan.md","S3-plan-review.json"],"phase":"S3"},
    "IMPLEMENT->TEST": {"required":["S4-tasks.json","S6-impl-review.json"],"phase":"S6"},
    "TEST->FINAL": {"required":["S7-test-results.json","S9-test-dev.json","S11-test-review.json"],"phase":"S11"},
    "FINAL->COMPLETE": {"required":["S13-final-review.json"],"phase":"S13"}
  },
  "stages": {
    "EXPLORE": {"status":"pending","phases":["S0"],"restartCount":0},
    "PLAN": {"status":"pending","phases":["S1","S2","S3"],"restartCount":0},
    "IMPLEMENT": {"status":"pending","phases":["S4","S5","S6"],"restartCount":0},
    "TEST": {"status":"pending","phases":["S7","S8","S9","S10","S11"],"restartCount":0},
    "FINAL": {"status":"pending","phases":["S12","S13","S14"],"restartCount":0}
  },
  "reviewPolicy": {"maxFixAttempts": 10, "maxStageRestarts": 3},
  "supplementaryPolicy": "on-issues",
  "webSearch": true,
  "coverageThreshold": 90,
  "files": [],
  "failure": null,
  "fixAttempts": {},
  "coverageLoop": {"iteration": 0},
  "reviewFix": null,
  "supplementaryRun": {}
}
```

## Step 2: Display Schedule

Show the user the planned execution:

```
Minions Superlaunch — 15-Phase Thorough Pipeline (Claude-only)
===============================================================
Phase S0  │ EXPLORE   │ Explore                 │ dispatch  → explorers + aggregator
Phase S1  │ PLAN      │ Brainstorm              │ subagent  → brainstormer
Phase S2  │ PLAN      │ Plan                    │ dispatch  → planners + aggregator
Phase S3  │ PLAN      │ Plan Review             │ review    → plan-reviewer + judgement-agent
Phase S4  │ IMPLEMENT │ Implement               │ dispatch  → task-agent (parallel batch)
Phase S5  │ IMPLEMENT │ Simplify                │ subagent  → simplifier
Phase S6  │ IMPLEMENT │ Impl Review             │ review    → impl-reviewer + supplementary
Phase S7  │ TEST      │ Run Tests               │ subagent  → test-developer
Phase S8  │ TEST      │ Analyze                 │ subagent  → failure-analyzer
Phase S9  │ TEST      │ Develop Tests           │ subagent  → test-developer
Phase S10 │ TEST      │ Test Dev Review         │ review    → test-dev-reviewer + judgement-agent
Phase S11 │ TEST      │ Test Review             │ review    → test-reviewer + judgement-agent
Phase S12 │ FINAL     │ Documentation           │ subagent  → doc-updater + claude-md-updater
Phase S13 │ FINAL     │ Final Review            │ review    → final-reviewer + supplementary
Phase S14 │ FINAL     │ Completion              │ subagent  → shipper + retrospective

Gates:
  EXPLORE → PLAN:      requires S0-explore.md
  PLAN → IMPLEMENT:    requires S1-brainstorm.md, S2-plan.md, S3-plan-review.json
  IMPLEMENT → TEST:    requires S4-tasks.json, S6-impl-review.json
  TEST → FINAL:        requires S7-test-results.json, S9-test-dev.json, S11-test-review.json
  FINAL → COMPLETE:    requires S13-final-review.json
```

## Step 3: Initialize Task List

Create tasks for progress tracking. Each task tracks one pipeline stage:

1. **TaskCreate:** subject: "Execute EXPLORE stage", description: "Phase S0 — Explore codebase", activeForm: "Exploring codebase"
2. **TaskCreate:** subject: "Execute PLAN stage", description: "Phases S1-S3 — Brainstorm, Plan, Plan Review. Review may trigger fix cycles (up to maxFixAttempts) or stage restarts (up to maxStageRestarts).", activeForm: "Planning implementation"
3. **TaskCreate:** subject: "Execute IMPLEMENT stage", description: "Phases S4-S6 — Implement, Simplify, Impl Review. Review may trigger fix cycles or stage restarts.", activeForm: "Implementing tasks"
4. **TaskCreate:** subject: "Execute TEST stage", description: "Phases S7-S11 — Run Tests, Analyze, Develop Tests, Reviews. Includes coverage loop (S9-S11 repeats until threshold met) and review-fix cycles.", activeForm: "Testing implementation"
5. **TaskCreate:** subject: "Execute FINAL stage", description: "Phases S12-S14 — Documentation, Final Review, Completion. Review may trigger fix cycles or stage restarts.", activeForm: "Finalizing and shipping"

Set dependencies: PLAN blocked by EXPLORE, IMPLEMENT blocked by PLAN, TEST blocked by IMPLEMENT, FINAL blocked by TEST.

Then mark "Execute EXPLORE stage" as **in_progress** since Step 4 dispatches S0 next.

## Step 4: Dispatch Phase S0 (Explore)

Read the prompt template at `prompts/superlaunch/S0-explore.md` for dispatch instructions.

Dispatch the explore phase using `minions:explorer` agents (parallel batch) and `minions:deep-explorer` (supplementary).

After all explorers complete, dispatch `minions:explore-aggregator` to merge results into `.agents/tmp/phases/S0-explore.md`.

After Phase S0 completes, the Stop hook (`on-stop.sh`) drives the orchestrator through all 15 phases automatically via schedule-driven prompt generation.

## Phase Agent Mapping

| Phase | Agent | subagent_type |
|-------|-------|---------------|
| S0 | explorer (batch) | `minions:explorer` |
| S0 | deep-explorer (supplementary) | `minions:deep-explorer` |
| S0 | explore-aggregator | `minions:explore-aggregator` |
| S1 | brainstormer | `minions:brainstormer` |
| S2 | planner (batch) | `minions:planner` |
| S2 | architecture-analyst (supplementary) | `minions:architecture-analyst` |
| S2 | plan-aggregator | `minions:plan-aggregator` |
| S3 | plan-reviewer + judgement-agent | `minions:plan-reviewer` |
| S4 | task-agent (batch) | `minions:task-agent` |
| S5 | simplifier | `minions:simplifier` |
| S6 | impl-reviewer + supplementary | `minions:impl-reviewer` |
| S7 | test-developer | `minions:test-developer` |
| S8 | failure-analyzer | `minions:failure-analyzer` |
| S9 | test-developer | `minions:test-developer` |
| S10 | test-dev-reviewer + judgement-agent | `minions:test-dev-reviewer` |
| S11 | test-reviewer + judgement-agent | `minions:test-reviewer` |
| S12 | doc-updater + claude-md-updater | `minions:doc-updater` |
| S13 | final-reviewer + supplementary | `minions:final-reviewer` |
| S14 | shipper + retrospective | `minions:shipper` |
