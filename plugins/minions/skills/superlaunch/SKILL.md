---
name: superlaunch
description: Claude-only 15-phase thorough pipeline — dispatches minions agents through minions hooks
---

# Superlaunch Workflow

Claude-only 15-phase thorough pipeline for complex development tasks. Uses **minions plugin agents** (self-contained) driven by **minions plugin hooks** (Ralph-style loop driver). No Codex MCP dependency.

## Key Architecture

- `pipeline: "superlaunch"` in state.json
- `plugin: "minions"` — so minions hooks fire
- Other plugins' hooks silently exit (they check `plugin` field in state.json)
- All agents are `minions:*` prefixed — they exist in the minions plugin

## Execution Flow (Ralph-Style)

The orchestrator uses the Ralph Loop pattern: the Stop hook generates a **schedule-driven orchestrator prompt** every time Claude tries to stop. Claude reads state from disk and dispatches the current phase.

```
superlaunch.md initializes state (pipeline: "superlaunch", 15-phase schedule)
  → dispatches Phase S0 (Explore)
  → on-subagent-stop.sh validates output, checks gates, advances state
  → on-stop.sh reads schedule, generates phase prompt, blocks stop
  → Claude dispatches next minions agent
  → cycle repeats through all 15 phases
```

## 15-Phase Thorough Schedule

```
Phase S0  │ EXPLORE   │ Explore                 │ dispatch  → explorers + aggregator
Phase S1  │ PLAN      │ Brainstorm              │ subagent  → brainstormer
Phase S2  │ PLAN      │ Plan                    │ dispatch  → planners + aggregator
Phase S3  │ PLAN      │ Plan Review             │ review    → plan-reviewer
Phase S4  │ IMPLEMENT │ Implement               │ dispatch  → task-agent (parallel batch)
Phase S5  │ IMPLEMENT │ Simplify                │ subagent  → simplifier
Phase S6  │ IMPLEMENT │ Impl Review             │ review    → impl-reviewer + supplementary
Phase S7  │ TEST      │ Run Tests               │ subagent  → test-developer
Phase S8  │ TEST      │ Analyze                 │ subagent  → failure-analyzer
Phase S9  │ TEST      │ Develop Tests           │ subagent  → test-developer
Phase S10 │ TEST      │ Test Dev Review         │ review    → test-dev-reviewer
Phase S11 │ TEST      │ Test Review             │ review    → test-reviewer
Phase S12 │ FINAL     │ Documentation           │ subagent  → doc-updater + claude-md-updater
Phase S13 │ FINAL     │ Final Review            │ review    → final-reviewer + supplementary
Phase S14 │ FINAL     │ Completion              │ subagent  → shipper + retrospective
```

## Stage Gates

| Gate | Required Files | Transition |
|------|---------------|------------|
| EXPLORE→PLAN | `S0-explore.md` | After Phase S0 |
| PLAN→IMPLEMENT | `S1-brainstorm.md`, `S2-plan.md`, `S3-plan-review.json` | After Phase S3 |
| IMPLEMENT→TEST | `S4-tasks.json`, `S6-impl-review.json` | After Phase S6 |
| TEST→FINAL | `S7-test-results.json`, `S9-test-dev.json`, `S11-test-review.json` | After Phase S11 |
| FINAL→COMPLETE | `S13-final-review.json` | After Phase S13 |

## Review-Fix Cycles

Review phases (S3, S6, S10, S11, S13) support two-tier retry:

```
Tier 1: 10 fix attempts per review phase (within one run of the stage)
Tier 2: 3 stage restarts (each restart resets fix counters to 0)
Total:  up to 3 x 10 = 30 fix attempts per review phase before blocking
```

## Coverage Loop

Phases S9 → S10 → S11 repeat until `coverage >= coverageThreshold` (default 90%) or 20 iterations reached.

## Supplementary Agents

Dispatched in parallel with primary agents (controlled by `supplementaryPolicy`):

| Phase | Supplementary Agents |
|-------|---------------------|
| S0 | `minions:deep-explorer` |
| S2 | `minions:architecture-analyst` |
| S6 | `minions:critic`, `minions:silent-failure-hunter`, `minions:type-reviewer` |
| S12 | `minions:claude-md-updater` |
| S13 | `minions:pedant`, `minions:security-reviewer`, `minions:silent-failure-hunter` |
| S14 | `minions:retrospective-analyst` |

## State Schema (superlaunch)

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "superlaunch",
  "status": "in_progress|blocked|complete",
  "currentPhase": "S0|S1|S2|...|S14|DONE|STOPPED",
  "currentStage": "EXPLORE|PLAN|IMPLEMENT|TEST|FINAL",
  "codexAvailable": false,
  "testDeveloper": "minions:test-developer",
  "failureAnalyzer": "minions:failure-analyzer",
  "docUpdater": "minions:doc-updater",
  "schedule": [/* 15 phases */],
  "gates": {/* 5 stage gates */},
  "stages": {/* per-stage status tracking */},
  "reviewPolicy": {"maxFixAttempts": 10, "maxStageRestarts": 3},
  "supplementaryPolicy": "on-issues",
  "coverageThreshold": 90,
  "webSearch": true
}
```

## Hook Responsibilities

| Hook | Event | Superlaunch Behavior |
|------|-------|---------------------|
| on-stop.sh | Stop | Calls `generate_sl_prompt()` from `lib/superlaunch.sh` — schedule-driven prompt |
| on-subagent-stop.sh | SubagentStop | Validates output, checks gates, handles review-fix cycles, advances phase |
| on-task-gate.sh | PreToolUse (Task) | Validates `minions:*` agent matches current phase via `is_sl_agent_allowed()` |
| on-edit-gate.sh | PreToolUse (Edit/Write) | Allows edits in IMPLEMENT, TEST, and FINAL stages |
| on-launch-init.sh | UserPromptSubmit | Shows pipeline and stage info for stale state detection |

## Difference from /minions:launch

| Aspect | launch | superlaunch |
|--------|--------|-------------|
| Phases | 4 (F1-F4) | 15 (S0 through S14) |
| Agents | `minions:*` (12 agents) | `minions:*` (25 superlaunch agents) |
| Hooks | Same hooks, `launch` branch | Same hooks, `superlaunch` branch |
| Codex | No | No |
| Review | 5 parallel personality reviewers | Structured review-fix cycles |
| State | `loop`/`maxLoops` counters | `currentStage`/`currentPhase` schedule |
