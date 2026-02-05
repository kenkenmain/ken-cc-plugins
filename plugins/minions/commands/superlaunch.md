---
name: minions:superlaunch
description: Superlaunch — Claude-only 15-phase thorough pipeline with subagents agents and minions hooks
argument-hint: <task description>
---

# Minions Superlaunch

You are launching a Claude-only 15-phase thorough development pipeline. This uses **subagents plugin agents** (battle-tested, 49 agents) driven by **minions plugin hooks** (Ralph-style loop driver).

Use the `superlaunch` skill for workflow reference documentation.

## Arguments

- `<task description>`: Required. The task to execute.

Parse from $ARGUMENTS to extract the task description.

## Pipeline

```
EXPLORE → PLAN → IMPLEMENT → TEST → FINAL → COMPLETE

Phase 0   │ EXPLORE   │ Explore                 │ dispatch
Phase 1.1 │ PLAN      │ Brainstorm              │ subagent
Phase 1.2 │ PLAN      │ Plan                    │ dispatch
Phase 1.3 │ PLAN      │ Plan Review             │ review
Phase 2.1 │ IMPLEMENT │ Task Execution          │ dispatch
Phase 2.2 │ IMPLEMENT │ Simplify                │ subagent
Phase 2.3 │ IMPLEMENT │ Implementation Review   │ review
Phase 3.1 │ TEST      │ Run Tests & Analyze     │ subagent
Phase 3.2 │ TEST      │ Analyze Failures        │ subagent
Phase 3.3 │ TEST      │ Develop Tests           │ subagent
Phase 3.4 │ TEST      │ Test Dev Review         │ review
Phase 3.5 │ TEST      │ Test Review             │ review
Phase 4.1 │ FINAL     │ Documentation           │ subagent
Phase 4.2 │ FINAL     │ Final Review            │ review
Phase 4.3 │ FINAL     │ Completion              │ subagent

Gates: EXPLORE→PLAN, PLAN→IMPLEMENT, IMPLEMENT→TEST, TEST→FINAL, FINAL→COMPLETE
```

## Step 1: Initialize State

Create directories and write state file inline. No init agent needed.

### 1a. Create directories

```bash
mkdir -p .agents/tmp/phases
rm -f .agents/tmp/phases/*.tmp
```

### 1b. Capture session PID and generate sessionId

```bash
echo $PPID
```

Store the output as `ownerPpid`.

```bash
head -c 8 /dev/urandom | xxd -p
```

Store the output as `sessionId`.

### 1c. Create feature branch

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

### 1d. Write state.json

Write `.agents/tmp/state.json` with the following structure. Use Bash with jq for atomic write (write to tmp file, then mv):

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "superlaunch",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "0",
  "currentStage": "EXPLORE",
  "codexAvailable": false,
  "reviewer": "subagents:claude-reviewer",
  "testDeveloper": "subagents:test-developer",
  "failureAnalyzer": "subagents:failure-analyzer",
  "docUpdater": "subagents:doc-updater",
  "ownerPpid": "<PPID value>",
  "sessionId": "<sessionId value>",
  "branch": "<BRANCH_NAME>",
  "schedule": [
    {"phase":"0","stage":"EXPLORE","name":"Explore","type":"dispatch"},
    {"phase":"1.1","stage":"PLAN","name":"Brainstorm","type":"subagent"},
    {"phase":"1.2","stage":"PLAN","name":"Plan","type":"dispatch"},
    {"phase":"1.3","stage":"PLAN","name":"Plan Review","type":"review"},
    {"phase":"2.1","stage":"IMPLEMENT","name":"Task Execution","type":"dispatch"},
    {"phase":"2.2","stage":"IMPLEMENT","name":"Simplify","type":"subagent"},
    {"phase":"2.3","stage":"IMPLEMENT","name":"Implementation Review","type":"review"},
    {"phase":"3.1","stage":"TEST","name":"Run Tests & Analyze","type":"subagent"},
    {"phase":"3.2","stage":"TEST","name":"Analyze Failures","type":"subagent"},
    {"phase":"3.3","stage":"TEST","name":"Develop Tests","type":"subagent"},
    {"phase":"3.4","stage":"TEST","name":"Test Dev Review","type":"review"},
    {"phase":"3.5","stage":"TEST","name":"Test Review","type":"review"},
    {"phase":"4.1","stage":"FINAL","name":"Documentation","type":"subagent"},
    {"phase":"4.2","stage":"FINAL","name":"Final Review","type":"review"},
    {"phase":"4.3","stage":"FINAL","name":"Completion","type":"subagent"}
  ],
  "gates": {
    "EXPLORE->PLAN": {"required":["0-explore.md"],"phase":"0"},
    "PLAN->IMPLEMENT": {"required":["1.1-brainstorm.md","1.2-plan.md","1.3-plan-review.json"],"phase":"1.3"},
    "IMPLEMENT->TEST": {"required":["2.1-tasks.json","2.3-impl-review.json"],"phase":"2.3"},
    "TEST->FINAL": {"required":["3.1-test-results.json","3.3-test-dev.json","3.5-test-review.json"],"phase":"3.5"},
    "FINAL->COMPLETE": {"required":["4.2-final-review.json"],"phase":"4.2"}
  },
  "stages": {
    "EXPLORE": {"status":"pending","phases":["0"]},
    "PLAN": {"status":"pending","phases":["1.1","1.2","1.3"]},
    "IMPLEMENT": {"status":"pending","phases":["2.1","2.2","2.3"]},
    "TEST": {"status":"pending","phases":["3.1","3.2","3.3","3.4","3.5"]},
    "FINAL": {"status":"pending","phases":["4.1","4.2","4.3"]}
  },
  "reviewPolicy": {"maxFixAttempts": 10, "maxStageRestarts": 3},
  "supplementaryPolicy": "on-issues",
  "webSearch": true,
  "coverageThreshold": 90,
  "files": [],
  "failure": null
}
```

## Step 2: Display Schedule

Show the user the planned execution:

```
Minions Superlaunch — 15-Phase Thorough Pipeline (Claude-only)
===============================================================
Phase 0   │ EXPLORE   │ Explore                 │ dispatch  → explorers + aggregator
Phase 1.1 │ PLAN      │ Brainstorm              │ subagent  → brainstormer
Phase 1.2 │ PLAN      │ Plan                    │ dispatch  → planners + aggregator
Phase 1.3 │ PLAN      │ Plan Review             │ review    → claude-reviewer
Phase 2.1 │ IMPLEMENT │ Task Execution          │ dispatch  → task agents (per complexity)
Phase 2.2 │ IMPLEMENT │ Simplify                │ subagent  → simplifier
Phase 2.3 │ IMPLEMENT │ Implementation Review   │ review    → claude-reviewer + supplementary
Phase 3.1 │ TEST      │ Run Tests & Analyze     │ subagent  → test-developer
Phase 3.2 │ TEST      │ Analyze Failures        │ subagent  → failure-analyzer
Phase 3.3 │ TEST      │ Develop Tests           │ subagent  → test-developer
Phase 3.4 │ TEST      │ Test Dev Review         │ review    → claude-reviewer
Phase 3.5 │ TEST      │ Test Review             │ review    → claude-reviewer
Phase 4.1 │ FINAL     │ Documentation           │ subagent  → doc-updater + claude-md-updater
Phase 4.2 │ FINAL     │ Final Review            │ review    → claude-reviewer + supplementary
Phase 4.3 │ FINAL     │ Completion              │ subagent  → completion-handler + retrospective

Gates:
  EXPLORE → PLAN:      requires 0-explore.md
  PLAN → IMPLEMENT:    requires 1.1-brainstorm.md, 1.2-plan.md, 1.3-plan-review.json
  IMPLEMENT → TEST:    requires 2.1-tasks.json, 2.3-impl-review.json
  TEST → FINAL:        requires 3.1-test-results.json, 3.3-test-dev.json, 3.5-test-review.json
  FINAL → COMPLETE:    requires 4.2-final-review.json
```

## Step 3: Initialize Task List

Create tasks for progress tracking:

1. **TaskCreate:** "Execute EXPLORE stage" (activeForm: "Exploring codebase")
2. **TaskCreate:** "Execute PLAN stage" (activeForm: "Planning implementation")
3. **TaskCreate:** "Execute IMPLEMENT stage" (activeForm: "Implementing tasks")
4. **TaskCreate:** "Execute TEST stage" (activeForm: "Testing implementation")
5. **TaskCreate:** "Execute FINAL stage" (activeForm: "Finalizing and shipping")

Set dependencies: PLAN blocked by EXPLORE, IMPLEMENT blocked by PLAN, TEST blocked by IMPLEMENT, FINAL blocked by TEST.

## Step 4: Dispatch Phase 0 (Explore)

Read the prompt template at `prompts/superlaunch/0-explore.md` for dispatch instructions.

Dispatch the explore phase using `subagents:explorer` agents (parallel batch) and `subagents:deep-explorer` (supplementary).

After all explorers complete, dispatch `subagents:explore-aggregator` to merge results into `.agents/tmp/phases/0-explore.md`.

After Phase 0 completes, the Stop hook (`on-stop.sh`) drives the orchestrator through all 15 phases automatically via schedule-driven prompt generation.

## Phase Agent Mapping

| Phase | Agent | subagent_type |
|-------|-------|---------------|
| 0 | explorer (batch) | `subagents:explorer` |
| 0 | deep-explorer (supplementary) | `subagents:deep-explorer` |
| 0 | explore-aggregator | `subagents:explore-aggregator` |
| 1.1 | brainstormer | `subagents:brainstormer` |
| 1.2 | planner (batch) | `subagents:planner` |
| 1.2 | architecture-analyst (supplementary) | `subagents:architecture-analyst` |
| 1.2 | plan-aggregator | `subagents:plan-aggregator` |
| 1.3 | claude-reviewer | `subagents:claude-reviewer` |
| 2.1 | sonnet-task-agent / opus-task-agent | `subagents:sonnet-task-agent` / `subagents:opus-task-agent` |
| 2.2 | simplifier | `subagents:simplifier` |
| 2.3 | claude-reviewer + supplementary | `subagents:claude-reviewer` |
| 3.1 | test-developer | `subagents:test-developer` |
| 3.2 | failure-analyzer | `subagents:failure-analyzer` |
| 3.3 | test-developer | `subagents:test-developer` |
| 3.4 | claude-reviewer | `subagents:claude-reviewer` |
| 3.5 | claude-reviewer | `subagents:claude-reviewer` |
| 4.1 | doc-updater + claude-md-updater | `subagents:doc-updater` |
| 4.2 | claude-reviewer + supplementary | `subagents:claude-reviewer` |
| 4.3 | completion-handler + retrospective | `subagents:completion-handler` |
