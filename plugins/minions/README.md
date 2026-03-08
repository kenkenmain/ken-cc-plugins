# minions

Personality-driven multi-pipeline workflow plugin for Claude Code. Four pipelines for different needs: a fast 4-phase loop (launch), a thorough 15-phase pipeline (superlaunch), a Cursor-inspired commit-per-task flow (cursor), and a review-fix iteration loop (review). All 38 agents are leaf agents driven by hook-based orchestration.

## Installation

```bash
# From local directory
claude --plugin-dir ./plugins/minions

# Or install to project scope
claude plugin install ./plugins/minions --scope project
```

## Quick Start

```bash
# Launch: 4-phase personality-driven workflow with loop-back
/minions:launch Add authentication middleware to the API

# Superlaunch: 15-phase thorough pipeline (Claude-only)
/minions:superlaunch Refactor the database layer with connection pooling

# Cursor: Cursor-inspired workflow with per-task commits and judge verdicts
/minions:cursor Build a REST API for user management

# Review: Review-fix iteration loop (up to 5 iterations)
/minions:review Fix all issues in the authentication module
```

`/minions:launch` runs a fast 4-phase loop: explore, scout+plan, build in parallel, then 6 reviewers in parallel. Loops back on issues (max 10 loops).

`/minions:superlaunch` runs a thorough 15-phase pipeline with dedicated stages for exploration, planning, implementation, testing, and finalization. Includes review-fix cycles and stage restarts.

`/minions:cursor` uses a Cursor-inspired flow with parallel sub-scouts, per-task commits, and a single judge that delivers approve/fix/replan verdicts. Fix cycles (max 5) and replan loops (max 3).

`/minions:review` dispatches 5 parallel reviewers, fixes all reported issues (critical, warning, info), and iterates until clean or max 5 iterations reached.

## Pipeline Overview

### Launch (F0-F4)

```
F0 Explore       4x parallel haiku explorers
     |
F1 Scout         explore + brainstorm + plan
     |
F2 Build         parallel builders (one per task)
     |
F3 Review        critic || pedant || witness || security-reviewer
     |            || silent-failure-hunter || judgement-agent
     |
  verdict?
   / \
clean  issues --> back to F1 (max 10 loops)
  |
F4 Ship          docs + commit + PR
```

| Phase | Stage | Agent(s) | Type |
|-------|-------|----------|------|
| F0 | EXPLORE | explorer-files, explorer-architecture, explorer-tests, explorer-patterns | dispatch (parallel) |
| F1 | PLAN | scout | subagent |
| F2 | BUILD | builder (x1 per task) | dispatch (parallel) |
| F3 | REVIEW | critic, pedant, witness, security-reviewer, silent-failure-hunter, judgement-agent | dispatch (parallel) |
| F4 | SHIP | shipper | subagent |

### Superlaunch (S0-S14)

```
EXPLORE --> PLAN --> IMPLEMENT --> TEST --> FINAL --> COMPLETE
  S0      S1-S3     S4-S6       S7-S11    S12-S14
```

| Phase | Stage | Name | Agent(s) | Type |
|-------|-------|------|----------|------|
| S0 | EXPLORE | Explore | explorer (batch), deep-explorer, explore-aggregator | dispatch |
| S1 | PLAN | Brainstorm | brainstormer | subagent |
| S2 | PLAN | Plan | planner (batch), architecture-analyst, plan-aggregator | dispatch |
| S3 | PLAN | Plan Review | plan-reviewer, judgement-agent | review |
| S4 | IMPLEMENT | Implement | task-agent (parallel batch) | dispatch |
| S5 | IMPLEMENT | Simplify | simplifier | subagent |
| S6 | IMPLEMENT | Impl Review | impl-reviewer + supplementary | review |
| S7 | TEST | Run Tests | test-developer | subagent |
| S8 | TEST | Analyze | failure-analyzer | subagent |
| S9 | TEST | Develop Tests | test-developer | subagent |
| S10 | TEST | Test Dev Review | test-dev-reviewer, judgement-agent | review |
| S11 | TEST | Test Review | test-reviewer, judgement-agent | review |
| S12 | FINAL | Documentation | doc-updater, claude-md-updater | subagent |
| S13 | FINAL | Final Review | final-reviewer + supplementary | review |
| S14 | FINAL | Completion | shipper, retrospective-analyst | subagent |

Stage gates enforce artifact requirements between stages:

| Gate | Required Artifacts |
|------|--------------------|
| EXPLORE -> PLAN | S0-explore.md |
| PLAN -> IMPLEMENT | S1-brainstorm.md, S2-plan.md, S3-plan-review.json |
| IMPLEMENT -> TEST | S4-tasks.json, S6-impl-review.json |
| TEST -> FINAL | S7-test-results.json, S9-test-dev.json, S11-test-review.json |
| FINAL -> COMPLETE | S13-final-review.json |

### Cursor (C1-C4)

```
C0 Explore      4x parallel haiku explorers
     |
C1 Plan         N sub-scouts (parallel, per-domain)
     |
C2 Build        N cursor-builders (per-task commits)
     |
C3 Judge        1 judge --> approve / fix / replan
    / | \
   /  |  \
approve fix  replan --> back to C1 (max 3 loops)
  |    |
  |   C2.5 Fix --> C3 re-judge (max 5 fix cycles)
  |
C4 Ship         squash-merge + PR
```

### Review (R1-R2)

```
R1 Review       5x parallel reviewers (critic, pedant, witness,
     |           security-reviewer, silent-failure-hunter)
     |
  verdict?
   / \
clean  issues --> R2 Fix (review-fixer) --> R1 (max 5 iterations)
  |
DONE
```

## Agent Roster

| Agent | Role | Model | Pipeline(s) |
|-------|------|-------|-------------|
| explorer | Breadth-first codebase scout (batch) | haiku | superlaunch |
| explorer-files | File structure mapper | haiku | launch, cursor |
| explorer-architecture | Architecture tracer | haiku | launch, cursor |
| explorer-tests | Test conventions surveyor | haiku | launch, cursor |
| explorer-patterns | Coding patterns finder | haiku | launch, cursor |
| deep-explorer | Deep architecture tracer | haiku | superlaunch |
| explore-aggregator | Merges explorer outputs | haiku | superlaunch |
| scout | Explore + brainstorm + plan | sonnet | launch |
| brainstormer | Strategy analysis | inherit | superlaunch |
| planner | Implementation plan (batch) | inherit | superlaunch |
| architecture-analyst | Architecture blueprint | inherit | superlaunch |
| plan-aggregator | Merges planner outputs | haiku | superlaunch |
| plan-reviewer | Plan validation | inherit | superlaunch |
| sub-scout | Domain-specific planner | sonnet | cursor |
| builder | Task implementer (no git) | inherit | launch |
| cursor-builder | Task implementer (per-task commits) | inherit | cursor |
| task-agent | Task executor | inherit | superlaunch |
| simplifier | Code simplification | inherit | superlaunch |
| critic | Correctness + bugs + security | inherit | launch, review |
| pedant | Quality + style + complexity | inherit | launch, review |
| witness | Runtime verification | inherit | launch, review |
| security-reviewer | Deep security review (OWASP) | inherit | launch, review |
| silent-failure-hunter | Silent failure analysis | inherit | launch, review |
| judgement-agent | Holistic judgment reviewer | inherit | launch, superlaunch |
| judge | Approve/fix/replan verdict | inherit | cursor |
| impl-reviewer | Implementation code review | inherit | superlaunch |
| test-developer | Test writer + CI config | inherit | superlaunch |
| test-dev-reviewer | Test code reviewer | inherit | superlaunch |
| test-reviewer | Test coverage reviewer | inherit | superlaunch |
| failure-analyzer | Test failure root cause | inherit | superlaunch |
| review-fixer | Targeted issue fixer | inherit | review |
| doc-updater | Documentation updater | sonnet | superlaunch |
| claude-md-updater | CLAUDE.md learnings updater | sonnet | superlaunch |
| claude-reviewer | Claude reasoning reviewer | inherit | superlaunch |
| type-reviewer | Type design quality reviewer | sonnet | superlaunch |
| retrospective-analyst | Workflow metrics analyst | inherit | superlaunch |
| shipper | Commit + PR | inherit | launch, cursor, superlaunch |

All 38 agents are leaf agents (`disallowedTools: [Task]`). Workflow orchestration is driven by shell hooks, not agent spawning.

## Comparison

| | minions:launch | minions:superlaunch | minions:cursor | minions:review | ants:swarm | subagents:dispatch |
|---|---|---|---|---|---|---|
| Phases | 5 (F0-F4) | 15 (S0-S14) | 5 (C0-C4) | 2 (R1-R2) | 6 (A0-A5) | 5-15 (profile-based) |
| Build model | Parallel builders | Parallel task-agents | Per-task commits | N/A (review only) | Task pool + adversarial review | Sequential with review |
| Review style | 6 parallel reviewers | Per-phase reviewers + judgement | Single judge verdict | 5 parallel reviewers | 3 specialist sentinels + arbiter | Configurable reviewer |
| Loop type | F3 issues -> F1 re-scout (max 10) | Review-fix cycles + stage restarts | Judge: approve/fix/replan | R1-R2 iteration (max 5) | Queen verdict -> re-plan (max 5) | Fix cycles per phase |
| Agents | 38 personality-themed | (subset of 38) | (subset of 38) | (subset of 38) | 16 colony-themed | 49 generic |
| Best for | Fast iteration with broad review | Thorough coverage with testing | Incremental commits with single judge | Targeted code review + fixes | Adversarial quality with task pools | Complex multi-phase pipelines |
| Orchestration | Hook-driven (Ralph Loop) | Hook-driven (schedule) | Hook-driven (verdict) | Hook-driven (iteration) | Agent Teams delegate mode | Hook-driven (auto-chaining) |

**Choose launch when:** You want fast iteration with a broad 6-reviewer panel and personality-driven agents.

**Choose superlaunch when:** You need thorough 15-phase coverage with dedicated test development, failure analysis, coverage loops, and documentation phases.

**Choose cursor when:** You want per-task commits, a single judge making approve/fix/replan decisions, and Cursor-style incremental development.

**Choose review when:** You have existing code that needs review and targeted fixes without a full build pipeline.

**Choose ants when:** You want adversarial quality review with specialist sentinels and self-organizing task pools.

**Choose subagents when:** You need a configurable multi-phase pipeline with Codex MCP integration.

## State and Output

Workflow state lives in `.agents/tmp/state.json`. Phase outputs are written to `.agents/tmp/phases/`. Loop-specific files are organized under `loop-{N}/` subdirectories.

All state and output files are gitignored. They are temporary artifacts of the workflow execution.

## Requirements

- Claude Code with plugin support
- `jq` installed (used by shell hooks for state management)

## License

MIT
