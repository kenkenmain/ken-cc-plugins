---
name: superlaunch
description: Claude-only 15-phase thorough pipeline — dispatches subagents agents through minions hooks
---

# Superlaunch Workflow

Claude-only 15-phase thorough pipeline matching `/subagents:dispatch --profile thorough`. Uses **subagents plugin agents** (battle-tested, no duplication) driven by **minions plugin hooks** (Ralph-style loop driver). No Codex MCP dependency.

## Key Architecture

- `pipeline: "superlaunch"` in state.json
- `plugin: "minions"` — so minions hooks fire
- Subagents hooks silently exit (they check `plugin == "subagents"`)
- All agents are `subagents:*` prefixed — they exist in the subagents plugin

## Execution Flow (Ralph-Style)

The orchestrator uses the Ralph Loop pattern: the Stop hook generates a **schedule-driven orchestrator prompt** every time Claude tries to stop. Claude reads state from disk and dispatches the current phase.

```
superlaunch.md initializes state (pipeline: "superlaunch", 15-phase schedule)
  → dispatches Phase 0 (Explore)
  → on-subagent-stop.sh validates output, checks gates, advances state
  → on-stop.sh reads schedule, generates phase prompt, blocks stop
  → Claude dispatches next subagents agent
  → cycle repeats through all 15 phases
```

## 15-Phase Thorough Schedule

```
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
```

## Stage Gates

| Gate | Required Files | Transition |
|------|---------------|------------|
| EXPLORE→PLAN | `0-explore.md` | After Phase 0 |
| PLAN→IMPLEMENT | `1.1-brainstorm.md`, `1.2-plan.md`, `1.3-plan-review.json` | After Phase 1.3 |
| IMPLEMENT→TEST | `2.1-tasks.json`, `2.3-impl-review.json` | After Phase 2.3 |
| TEST→FINAL | `3.1-test-results.json`, `3.3-test-dev.json`, `3.5-test-review.json` | After Phase 3.5 |
| FINAL→COMPLETE | `4.2-final-review.json` | After Phase 4.2 |

## Review-Fix Cycles

Review phases (1.3, 2.3, 3.4, 3.5, 4.2) support two-tier retry:

```
Tier 1: 10 fix attempts per review phase (within one run of the stage)
Tier 2: 3 stage restarts (each restart resets fix counters to 0)
Total:  up to 3 x 10 = 30 fix attempts per review phase before blocking
```

## Coverage Loop

Phases 3.3 → 3.4 → 3.5 repeat until `coverage >= coverageThreshold` (default 90%) or 20 iterations reached.

## Supplementary Agents

Dispatched in parallel with primary agents (controlled by `supplementaryPolicy`):

| Phase | Supplementary Agents |
|-------|---------------------|
| 0 | `subagents:deep-explorer` |
| 1.2 | `subagents:architecture-analyst` |
| 2.3 | `subagents:code-quality-reviewer`, `subagents:error-handling-reviewer`, `subagents:type-reviewer` |
| 4.1 | `subagents:claude-md-updater` |
| 4.2 | `subagents:code-quality-reviewer`, `subagents:test-coverage-reviewer`, `subagents:comment-reviewer` |
| 4.3 | `subagents:retrospective-analyst` |

## State Schema (superlaunch)

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "superlaunch",
  "status": "in_progress|blocked|complete",
  "currentPhase": "0|1.1|1.2|...|4.3|DONE|STOPPED",
  "currentStage": "EXPLORE|PLAN|IMPLEMENT|TEST|FINAL",
  "codexAvailable": false,
  "reviewer": "subagents:claude-reviewer",
  "testDeveloper": "subagents:test-developer",
  "failureAnalyzer": "subagents:failure-analyzer",
  "docUpdater": "subagents:doc-updater",
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
| on-task-gate.sh | PreToolUse (Task) | Validates `subagents:*` agent matches current phase via `is_sl_agent_allowed()` |
| on-edit-gate.sh | PreToolUse (Edit/Write) | Allows edits in IMPLEMENT and FINAL stages only |
| on-launch-init.sh | UserPromptSubmit | Shows pipeline and stage info for stale state detection |

## Difference from /minions:launch

| Aspect | launch | superlaunch |
|--------|--------|-------------|
| Phases | 4 (F1-F4) | 15 (0 through 4.3) |
| Agents | `minions:*` (12 agents) | `subagents:*` (49 agents) |
| Hooks | Same hooks, `launch` branch | Same hooks, `superlaunch` branch |
| Codex | No | No |
| Review | 5 parallel personality reviewers | Structured review-fix cycles |
| State | `loop`/`maxLoops` counters | `currentStage`/`currentPhase` schedule |
