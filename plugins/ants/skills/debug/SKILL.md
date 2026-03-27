---
name: debug
description: Colony diagnostic pipeline -- 6-phase targeted bug repair with parallel investigation, competitive solution ranking, and adversarial review
---

# Debug Pipeline

Targeted bug repair pipeline for the ant colony. Six phases (D0-D5) dispatch specialized agents to investigate, diagnose, fix, and ship a bug fix. Uses **stateless direct dispatch** -- no state.json, no hooks, no Agent Teams orchestration. The orchestrator (debug command) spawns agents directly via Task tool calls.

## Key Architecture

- **Stateless:** No `.agents/tmp/state.json` is created or read during debug
- **Direct dispatch:** The debug command spawns agents via Task, reads their output files, and proceeds
- **No hooks:** Because no ants state.json exists, `check_ants_workflow()` in every hook returns false (exits 0 immediately), so all hooks pass through without interfering
- **Self-contained:** All output files live under `.agents/tmp/debug/`

## 6-Phase Pipeline

```
Phase D0  | EXPLORE     | Bug Investigation      | 3x parallel bug-scout
Phase D1  | PROPOSE     | Solution Proposals      | 3x parallel solution-proposer
Phase D2  | AGGREGATE   | Solution Ranking         | 1x solution-aggregator + user confirmation
Phase D3  | IMPLEMENT   | Fix Implementation       | 1x fix-worker
Phase D4  | REVIEW      | Adversarial Review       | 6x parallel sentinels + review-arbiter
Phase D5  | SHIP        | Documentation + Commit   | 1x nurse + 1x drone
```

### Pipeline Diagram

```
        D0 Explore (3x parallel bug-scout)
            |
        D1 Propose (3x parallel solution-proposer)
            |
        D2 Aggregate (solution-aggregator ranks proposals)
            |
        [user confirms selected fix]
            |
        D3 Implement (fix-worker applies the fix)
            |
        D4 Review (adversarial)
       / / | \ \ \
  correct. secur. perf style testing docs  (6x parallel sentinels)
       \ \ | / / /
        review-arbiter (consolidate)
            |
        D5 Ship
          /    \
      nurse    drone
   (docs)    (commit)
```

## Phase Details

### Phase D0: Bug Investigation (EXPLORE)

Three `ants:bug-scout` agents (haiku) are dispatched in parallel, each assigned a focused investigation query derived from the bug report. Each scout investigates from three angles: error manifestation, execution path, and test/change context.

After all scouts complete, their temp files are aggregated into a consolidated exploration report.

- **Agents:** 3x `ants:bug-scout` (haiku, parallel)
- **Input:** Bug description from user
- **Temp output:** `.agents/tmp/debug/explore.bug-scout.{N}.tmp` (one per scout)
- **Final output:** `.agents/tmp/debug/D0-explore.md` (aggregated report)

### Phase D1: Solution Proposals (PROPOSE)

Three `ants:solution-proposer` agents (sonnet) are dispatched in parallel. Each reads the D0 exploration report and independently proposes exactly one targeted fix. Proposals include root cause analysis, concrete code changes, trade-offs, confidence assessment, and testing strategy.

- **Agents:** 3x `ants:solution-proposer` (sonnet, parallel)
- **Input:** D0-explore.md
- **Temp output:** `.agents/tmp/debug/propose.solution-proposer.{N}.tmp` (one per proposer)

### Phase D2: Solution Ranking (AGGREGATE)

A single `ants:solution-aggregator` agent (sonnet) reads all proposal temp files, scores each on 5 dimensions (correctness, scope, risk, confidence, testability), ranks them by weighted total, and recommends the best fix.

After the aggregator writes its output, the orchestrator presents the recommendation to the user for confirmation before proceeding to implementation.

- **Agent:** 1x `ants:solution-aggregator` (sonnet)
- **Input:** All `propose.solution-proposer.{N}.tmp` files
- **Output:** `.agents/tmp/debug/D2-solutions.md`
- **Gate:** User confirmation required before advancing to D3

### Phase D3: Fix Implementation (IMPLEMENT)

A single `ants:fix-worker` agent (inherit) reads the selected solution from D2-solutions.md, implements the fix, writes regression tests, and self-verifies (tests, lint, typecheck).

- **Agent:** 1x `ants:fix-worker` (inherit)
- **Input:** D2-solutions.md
- **Output:** `.agents/tmp/debug/D3-implementation.json`

**Edit gate interaction:** The fix-worker can freely edit project files because no ants state.json exists during the debug pipeline. The `on-edit-gate.sh` hook calls `check_ants_workflow()` at the top of every invocation. Since there is no `.agents/tmp/state.json`, this function returns false and the hook exits 0 (allow). This means the edit gate imposes no stage-based restrictions during debug -- the fix-worker operates with full edit access.

### Phase D4: Adversarial Review (REVIEW)

Six specialist sentinel agents run in parallel, each reviewing the fix from a different dimension:

- **`ants:sentinel-correctness`** (sonnet) -- bugs, logic errors, missing error handling, race conditions
- **`ants:sentinel-security`** (sonnet) -- OWASP top 10, injection, authentication, secrets exposure
- **`ants:sentinel-perf`** (sonnet) -- N+1 queries, blocking I/O, unnecessary allocations, algorithmic complexity
- **`ants:sentinel-style`** (sonnet) -- code style, readability, maintainability, dead code
- **`ants:sentinel-testing`** (sonnet) -- test quality, coverage gaps, missing edge cases, flaky tests
- **`ants:sentinel-docs`** (sonnet) -- documentation accuracy, stale comments, missing docstrings

After all six sentinels complete, the `ants:review-arbiter` (sonnet) cross-references findings, deduplicates overlapping issues, resolves conflicts, and produces a consolidated quality verdict.

- **Agents:** 6x parallel sentinels + 1x `ants:review-arbiter` (sequential after sentinels)
- **Input:** D3-implementation.json + modified source files
- **Sentinel output:** `.agents/tmp/debug/D4-review.sentinel-correctness.json`, `.agents/tmp/debug/D4-review.sentinel-security.json`, `.agents/tmp/debug/D4-review.sentinel-perf.json`, `.agents/tmp/debug/D4-review.sentinel-style.json`, `.agents/tmp/debug/D4-review.sentinel-testing.json`, `.agents/tmp/debug/D4-review.sentinel-docs.json`
- **Arbiter output:** `.agents/tmp/debug/D4-quality.json`

### Phase D5: Documentation + Ship (SHIP)

Two agents run sequentially:

1. **`ants:nurse`** (sonnet) -- updates project documentation (README, CLAUDE.md, etc.) to reflect the bug fix
2. **`ants:drone`** (inherit) -- commits changes and optionally opens a PR

- **Agents:** 1x `ants:nurse` (sonnet), then 1x `ants:drone` (inherit)
- **Nurse output:** `.agents/tmp/debug/D5-docs.json`
- **Drone output:** `.agents/tmp/debug/D5-ship.json`

## Phase-Agent Mapping

| Phase | Agent | Model | New/Reused | Count | Execution |
|-------|-------|-------|------------|-------|-----------|
| D0 | `ants:bug-scout` | haiku | New | 3 | Parallel |
| D1 | `ants:solution-proposer` | sonnet | New | 3 | Parallel |
| D2 | `ants:solution-aggregator` | sonnet | New | 1 | Single |
| D3 | `ants:fix-worker` | inherit | New | 1 | Single |
| D4 | `ants:sentinel-correctness` | sonnet | Reused | 1 | Parallel |
| D4 | `ants:sentinel-security` | sonnet | Reused | 1 | Parallel |
| D4 | `ants:sentinel-perf` | sonnet | Reused | 1 | Parallel |
| D4 | `ants:sentinel-style` | sonnet | Reused | 1 | Parallel |
| D4 | `ants:sentinel-testing` | sonnet | Reused | 1 | Parallel |
| D4 | `ants:sentinel-docs` | sonnet | Reused | 1 | Parallel |
| D4 | `ants:review-arbiter` | sonnet | Reused | 1 | Sequential (after sentinels) |
| D5 | `ants:nurse` | sonnet | Reused | 1 | Sequential |
| D5 | `ants:drone` | inherit | Reused | 1 | Sequential (after nurse) |

**Total:** 13 agents (4 new debug-specific + 9 reused from swarm pipeline)

## Output File Layout

All output files live under `.agents/tmp/debug/`:

| Phase | File | Format | Description |
|-------|------|--------|-------------|
| D0 temp | `.agents/tmp/debug/explore.bug-scout.{N}.tmp` | Markdown | Individual bug scout investigation results (N = 1, 2, 3) |
| D0 final | `.agents/tmp/debug/D0-explore.md` | Markdown | Aggregated exploration report from all scouts |
| D1 temp | `.agents/tmp/debug/propose.solution-proposer.{N}.tmp` | Markdown | Individual solution proposals (N = 1, 2, 3) |
| D2 final | `.agents/tmp/debug/D2-solutions.md` | Markdown | Ranked solution analysis with recommendation |
| D3 output | `.agents/tmp/debug/D3-implementation.json` | JSON | Fix implementation report (files, tests, verification) |
| D4 sentinels | `.agents/tmp/debug/D4-review.sentinel-correctness.json` | JSON | Correctness sentinel findings |
| D4 sentinels | `.agents/tmp/debug/D4-review.sentinel-security.json` | JSON | Security sentinel findings |
| D4 sentinels | `.agents/tmp/debug/D4-review.sentinel-perf.json` | JSON | Performance sentinel findings |
| D4 sentinels | `.agents/tmp/debug/D4-review.sentinel-style.json` | JSON | Style sentinel findings |
| D4 sentinels | `.agents/tmp/debug/D4-review.sentinel-testing.json` | JSON | Testing sentinel findings |
| D4 sentinels | `.agents/tmp/debug/D4-review.sentinel-docs.json` | JSON | Documentation sentinel findings |
| D4 arbiter | `.agents/tmp/debug/D4-quality.json` | JSON | Consolidated quality verdict |
| D5 docs | `.agents/tmp/debug/D5-docs.json` | JSON | Nurse documentation update summary |
| D5 ship | `.agents/tmp/debug/D5-ship.json` | JSON | Drone commit/PR output |

## Orchestration Model

The debug pipeline uses **stateless direct dispatch** -- fundamentally different from the swarm pipeline's hook-driven Agent Teams orchestration.

### No state.json

The debug pipeline does not create or maintain `.agents/tmp/state.json`. The orchestrator (debug command) tracks progress internally via its prompt logic, not via external state files. This means:

- No `pipeline` field to set
- No `currentPhase` to track
- No `circuitBreaker` to manage
- No session scoping via `ownerPpid`/`sessionId`

### No hooks

Because no `.agents/tmp/state.json` exists, every ants hook that calls `check_ants_workflow()` at the top of its execution will find no state file and immediately exit 0 (allow/no-op). This applies to:

- `on-edit-gate.sh` -- exits 0, so fix-worker edits are unrestricted
- `on-teammate-idle.sh` -- exits 0, no task assignment
- `on-task-completed.sh` -- exits 0, no quality gates
- `on-stop.sh` -- exits 0, no shutdown handling
- `on-post-edit-lint.sh` -- exits 0, no lint-on-save
- `on-subagent-start.sh` -- exits 0, no context injection
- `on-config-change.sh` -- exits 0, no config snapshots
- `on-pre-compact.sh` -- exits 0, no metadata preservation

### Direct dispatch flow

The debug command orchestrates phases sequentially by:

1. Spawning agents via Task tool calls
2. Waiting for each agent (or batch of parallel agents) to complete
3. Reading the output files they produce
4. Deciding whether to proceed based on output content
5. Spawning the next phase's agents

This is simpler than the swarm pipeline but does not support automatic loop-back, circuit breaking, or concurrent multi-session workflows.

## Difference from Swarm

| Aspect | debug | swarm |
|--------|-------|-------|
| Phases | 6 (D0-D5) | 6 (A0-A5) |
| Purpose | Fix a single known bug | Build a feature from scratch |
| Orchestration | Stateless direct dispatch | Hook-driven Agent Teams |
| State file | None | `.agents/tmp/state.json` |
| Loop-back | None | A4 queen verdict -> A1 re-plan |
| Circuit breaker | None | 3-tier (failures, fix attempts, restarts) |
| Task pool | None | Self-organizing dependency-driven pool |
| Edit gate | Passes through (no state file) | Stage-based enforcement |
| Parallel exploration | 3x bug-scout (bug-focused) | 2-4x forager + 1x cartographer (codebase-wide) |
| User gate | D2 (confirm fix before implementing) | A1 (plan approval before building) |
