---
name: swarm
description: Ant-colony themed 6-phase swarm pipeline with self-organizing task pool and adversarial review teams
---

# Swarm Pipeline

Ant-colony themed 6-phase development pipeline with dual-track parallel execution, adversarial review teams, and self-organizing task dispatch. Uses **ants plugin agents** (self-contained) driven by **ants plugin hooks** (Agent Teams delegate mode). No Codex MCP dependency.

## Key Architecture

- `pipeline: "swarm"` in state.json
- `plugin: "ants"` -- so ants hooks fire
- Other plugins' hooks silently exit (they check `plugin` field in state.json)
- All agents are `ants:*` prefixed -- they exist in the ants plugin
- State schema v4 with `phases`, `circuitBreaker`, `taskPool`, `teamName`, `messages`, `planApproved`, `shutdown`, `webhookUrl`, `lintConfig`, `configSnapshot`, `compactMetadata`, and `worktreePath` fields

## 6-Phase Pipeline

```
Phase A0  | EXPLORE   | Colony Exploration     | teams → foragers + cartographer + aggregator
Phase A1  | PLAN      | Architect Plan         | teams → architect
Phase A2  | PLAN      | Blueprint Review       | teams → blueprint-reviewer
Phase A3  | BUILD     | Dual-Track Execution   | teams → workers (task pool) + adversarial sentinels + arbiter
Phase A4  | SYNC      | Queen Synchronization  | teams → queen (circuit breaker aware)
Phase A5  | SHIP      | Documentation + Ship   | teams → nurse + drone
```

### Pipeline Diagram

```
         A0 Explore
             |
         A1 Architect
             |
         A2 Blueprint Review
             |
    +--------+--------+
    |    Phase A3      |
    |  (dual-track)    |
    |                  |
    | Build Track      | Quality Track (Adversarial)
    | (task pool)      |
    |  workers claim   | sentinel-correctness  \
    |  tasks as deps   | sentinel-security      } parallel
    |  are satisfied   | sentinel-perf         /
    |                  |       |
    |                  | review-arbiter (consolidate)
    +--------+--------+
             |
         A4 Queen Sync (circuit breaker aware)
          /       \
     ship          loop
      |              |
   A5 Ship      A1 (loop back)
```

## Phase Details

### Phase A0: Colony Exploration

Dispatches **forager** and **cartographer** agents in parallel to gather codebase context before planning begins.

- **Foragers** (haiku, x2-4): Breadth-first scouts, each assigned a focused query (file structure, tests, patterns, related code)
- **Cartographer** (sonnet, x1): Depth-first architecture tracer -- maps execution paths, dependency graphs, layered structure
- **Explore-aggregator** (haiku, x1): Merges all temp files into a single consolidated report

Output: `.agents/tmp/phases/A0-explore.md`

This phase is **supplementary, not required**. If agents fail or time out, the workflow continues without that intelligence.

### Phase A1: Architect Plan

Single `ants:architect` agent (sonnet) explores the codebase (using A0 context if available) and writes a structured implementation plan with task assignments for the task pool.

On loop 2+, the architect reads the previous loop's review outputs and plans targeted fixes rather than re-planning from scratch.

Output:
- `.agents/tmp/phases/loop-{LOOP}/A1-plan.md` -- human-readable plan
- `.agents/tmp/phases/loop-{LOOP}/A1-tasks.json` -- machine-readable task descriptors for task pool

Must contain:
- Summary and chosen approach
- Task table with columns: ID, Description, Files, Dependencies, Complexity, Acceptance Criteria
- Task dependency graph (which tasks depend on which)

### Phase A2: Blueprint Review

Single `ants:blueprint-reviewer` agent (sonnet) validates the architect's plan for completeness, feasibility, dependency correctness, and risk.

Output: JSON with `status: "approved" | "needs_revision"`

If `needs_revision` with HIGH issues: loop back to A1 for the architect to revise. If `approved`: proceed to A3.

### Phase A3: Dual-Track Execution

The core differentiator. Two parallel tracks execute:

#### Build Track (Task Pool)

Workers are dispatched from a **self-organizing task pool** based on dependency satisfaction:

1. `pool_init()` reads `A1-tasks.json` and initializes the task pool in state.json
2. Tasks with no dependencies start as `ready`; others start as `pending`
3. Workers atomically claim ready tasks via `pool_claim_task()`
4. As workers complete, `pool_complete_task()` recomputes the ready set -- previously pending tasks whose dependencies are now all complete become ready
5. New workers are dispatched for newly ready tasks
6. Pool is complete when all tasks are `complete` or `failed`

Each worker:
- Implements exactly one task from the pool
- Can only edit files listed in the task's `files_owned` field (enforced by edit gate)
- Self-verifies (tests, lint, typecheck)
- Outputs structured JSON with status, files modified, tests written
- Has git blocked by hook (no commits)

**Fallback:** If no `taskPool` exists in state (v0.1 state files), A3 falls back to legacy wave-based dispatch with the generic sentinel.

#### Quality Track (Adversarial Review)

After all workers complete (pool drained), three specialist sentinels run **in parallel**:

- **sentinel-correctness** -- bugs, logic errors, missing error handling, incorrect API usage, race conditions
- **sentinel-security** -- OWASP top 10, injection attacks, authentication flaws, secrets exposure, access control
- **sentinel-perf** -- N+1 queries, unnecessary allocations, blocking I/O, missing caching, algorithmic complexity

Each sentinel writes its findings to a separate file:
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-correctness.json`
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-security.json`
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-perf.json`

After all three sentinels complete, the **review-arbiter** runs:
- Reads all three sentinel outputs
- Cross-references findings across dimensions
- Deduplicates overlapping issues
- Resolves conflicts (e.g., security vs performance trade-offs)
- Produces consolidated verdict: `.agents/tmp/phases/loop-{LOOP}/A3-quality.json`

The arbiter's output is backward compatible with the v0.1 sentinel quality format.

#### Guardian (Test Writing)

Guardian agents write tests for implemented code alongside the review track. One guardian per batch of completed tasks.

#### Task Pool Status Lifecycle

```
pending  ---> ready  ---> claimed  ---> complete
                                    \--> failed
```

- `pending`: Dependencies not yet satisfied
- `ready`: All dependencies complete, available for claiming
- `claimed`: Worker has taken ownership
- `complete`: Implementation finished successfully
- `failed`: Worker reported failure (blocks dependents)

Build track output: `.agents/tmp/phases/loop-{LOOP}/A3-build.json`
Quality track output: `.agents/tmp/phases/loop-{LOOP}/A3-quality.json`

### Phase A4: Queen Synchronization

Single `ants:queen` agent (sonnet, read-only) reads the arbiter's consolidated `A3-quality.json` and the build track's `A3-build.json`, cross-references, and renders a verdict.

The queen is **circuit breaker aware** -- she checks `circuitBreaker.stageRestarts` and `circuitBreaker.consecutiveFailures` before recommending a loop-back.

- **clean**: Quality track clean (or info-only issues) AND build track completed successfully
- **issues_found**: Any critical or warning issue unresolved, OR build track incomplete

Output: `.agents/tmp/phases/loop-{LOOP}/A4-queen-verdict.json`

### Phase A5: Documentation + Ship

Two sub-steps:

1. **Nurse** (sonnet): Updates project documentation to reflect implementation changes (README.md, CLAUDE.md, etc.)
2. **Drone**: Commits changes and opens a PR

Nurse output: `.agents/tmp/phases/loop-{LOOP}/A5-docs.json`
Drone output: `.agents/tmp/phases/loop-{LOOP}/A5-ship.json`

## Circuit Breaker

The circuit breaker prevents infinite failure loops. It tracks three tiers:

| Tier | Counter | Default Limit | Scope |
|------|---------|---------------|-------|
| Consecutive failures | `circuitBreaker.consecutiveFailures` | 5 | Cross-loop |
| Fix attempts | `circuitBreaker.fixAttempts[phase]` | 5 per phase | Per-loop (reset on loop-back) |
| Stage restarts | `circuitBreaker.stageRestarts` | 2 | Cross-loop |

When any limit is exceeded, the workflow halts with `status: "blocked"`. Success resets the consecutive failure counter. Fix attempts reset per-loop.

Library: `hooks/lib/circuit-breaker.sh`

## Loop-Back Logic

The queen's verdict drives progression:

```
A4 verdict == "clean"         -->  Advance to A5 (ship)
A4 verdict == "issues_found"  -->  Return to A1 (re-plan fixes)
                                   Circuit breaker checks:
                                   - stageRestarts < maxStageRestarts
                                   - consecutiveFailures < maxConsecutiveFailures
                                   If either exceeded: block workflow
```

### Loop Limits

- **Maximum loops:** 5 (configurable via `state.maxLoops`)
- **Loop counter:** `state.loop` (starts at 1)
- On each loop-back, `loop` increments and `reset_phases_for_loop()` resets A1-A4 to pending
- If `loop > maxLoops`: workflow blocks, requires user intervention

### Loop Context

On loop 2+:
- A1 architect reads previous loop's A3-quality.json and A4-queen-verdict.json
- Architect plans **targeted fixes**, not full re-plans
- Previous loop's files are preserved in `loop-{N}/` directories

## State Schema (v4)

```json
{
  "version": 4,
  "plugin": "ants",
  "pipeline": "swarm",
  "status": "in_progress|blocked|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID if available>",
  "currentPhase": "A0|A1|A2|A3|A4|A5|DONE|STOPPED",
  "loop": 1,
  "maxLoops": 5,
  "teamName": "ants-<branch-slug>",
  "startedAt": "ISO timestamp",
  "schedule": [
    {"phase": "A0", "stage": "EXPLORE", "label": "Colony Exploration", "type": "teams"},
    {"phase": "A1", "stage": "PLAN", "label": "Architect Plan", "type": "teams"},
    {"phase": "A2", "stage": "PLAN", "label": "Blueprint Review", "type": "teams"},
    {"phase": "A3", "stage": "BUILD", "label": "Dual-Track Execution", "type": "teams"},
    {"phase": "A4", "stage": "SYNC", "label": "Queen Synchronization", "type": "teams"},
    {"phase": "A5", "stage": "SHIP", "label": "Documentation + Ship", "type": "teams"}
  ],
  "phases": {
    "A0": {"status": "complete", "startedAt": "...", "completedAt": "..."},
    "A1": {"status": "in_progress", "startedAt": "..."},
    "A2": {"status": "pending"},
    "A3": {"status": "pending"},
    "A4": {"status": "pending"},
    "A5": {"status": "pending"}
  },
  "taskPool": [
    {
      "id": "T1",
      "description": "Implement auth module",
      "dependencies": [],
      "files_owned": ["src/auth.ts"],
      "status": "ready",
      "claimed_by": null
    }
  ],
  "circuitBreaker": {
    "consecutiveFailures": 0,
    "maxConsecutiveFailures": 5,
    "maxFixAttempts": 5,
    "maxStageRestarts": 2,
    "fixAttempts": {},
    "stageRestarts": 0
  },
  "failure": null,
  "worktreePath": null,
  "messages": [],
  "planApproved": false,
  "shutdown": false,
  "webhookUrl": null,
  "lintConfig": null,
  "configSnapshot": null,
  "compactMetadata": null
}
```

## Phase Output Files

All outputs live under `.agents/tmp/phases/`:

| Phase | File | Format | Description |
|-------|------|--------|-------------|
| A0 | `A0-explore.forager.{N}.tmp` | Markdown | Individual forager results |
| A0 | `A0-explore.cartographer.tmp` | Markdown | Cartographer architecture map |
| A0 | `A0-explore.md` | Markdown | Aggregated exploration report |
| A1 | `loop-{L}/A1-plan.md` | Markdown | Architect's implementation plan |
| A1 | `loop-{L}/A1-tasks.json` | JSON | Task descriptors for task pool |
| A2 | `loop-{L}/A2-review.json` | JSON | Blueprint review verdict |
| A3 | `loop-{L}/A3-build.json` | JSON | Build track worker results |
| A3 | `loop-{L}/A3-review.sentinel-correctness.json` | JSON | Correctness sentinel findings |
| A3 | `loop-{L}/A3-review.sentinel-security.json` | JSON | Security sentinel findings |
| A3 | `loop-{L}/A3-review.sentinel-perf.json` | JSON | Performance sentinel findings |
| A3 | `loop-{L}/A3-quality.json` | JSON | Arbiter consolidated verdict |
| A4 | `loop-{L}/A4-queen-verdict.json` | JSON | Queen synchronization verdict |
| A5 | `loop-{L}/A5-docs.json` | JSON | Nurse documentation update summary |
| A5 | `loop-{L}/A5-ship.json` | JSON | Drone commit/PR output |

## Stage Gates

| Gate | Required | Transition |
|------|----------|------------|
| EXPLORE -> PLAN | `A0-explore.md` (soft -- continues if missing) | After Phase A0 |
| PLAN -> BUILD | `loop-{L}/A1-plan.md` + `loop-{L}/A1-tasks.json` + A2 review approved | After Phase A2 |
| BUILD -> SYNC | `loop-{L}/A3-build.json` + `loop-{L}/A3-quality.json` | After Phase A3 |
| SYNC -> SHIP | `loop-{L}/A4-queen-verdict.json` with verdict `clean` | After Phase A4 |

## Verdict Field Naming

Different phases use different JSON field names for their decision outputs. The hook reads both for compatibility:

| Phase | File | Decision Field | Values |
|-------|------|---------------|--------|
| A2 | A2-review.json | `.status` or `.verdict` | `approved`, `needs_revision` |
| A3 | A3-quality.json | `.verdict` | `clean`, `issues_found` |
| A4 | A4-queen-verdict.json | `.verdict` | `clean`, `issues_found` |

The A2 hook accepts either `.status` or `.verdict` (`jq '.status // .verdict'`). A3 and A4 use `.verdict` consistently.

## Difference from Minions

| Aspect | ants:swarm | minions:superlaunch |
|--------|-----------|---------------------|
| Phases | 6 (A0-A5) | 15 (S0-S14) |
| Theme | Ant colony (forager, architect, worker, queen) | Generic minions |
| Key innovation | Task pool + adversarial review teams (3 sentinels + arbiter) | Sequential phases with review-fix cycles |
| Loop mechanism | A4 queen verdict -> A1 re-plan (max 5, circuit breaker) | Review phases with fix attempts + stage restarts |
| Agents | 16 specialized colony roles | 26+ agents |
| Failure handling | Circuit breaker with 3 tiers | Fix budget per review phase |
| Complexity | Streamlined for medium tasks | Thorough for complex tasks |

## pswarm Pipeline

The `pswarm` (persistent swarm) command extends the swarm pipeline into a continuously-running loop. After each full A0→A5 cycle ships a commit, pswarm automatically resets all phases and starts a fresh run — re-exploring the changed codebase, re-planning remaining work, and shipping again.

### Command Syntax

```
/ants:pswarm <task description> [--max-loops N] [--worktree]
```

- `<task description>`: Required. The task to solve.
- `--max-loops N`: Maximum number of full runs (default: 50). Each run is a complete A0→A5 cycle.
- `--worktree`: Create a git worktree for isolated development.

### How It Differs from Swarm

| Aspect | swarm | pswarm |
|--------|-------|--------|
| Runs | Single A0→A5 cycle | Multiple A0→A5 cycles |
| After A5 ships | Workflow completes | Resets to A0, starts next run |
| Inner loops (A4→A1) | Up to 5 re-plan cycles per run | Same — up to 5 per run |
| Max iterations | 1 run × 5 inner loops | N runs × 5 inner loops each |
| State field | `pipeline: "swarm"` | `pipeline: "pswarm"` |

### pswarm-Specific State Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `pswarmRun` | number | 1 | Current full run number (increments after each A5 ship) |
| `maxRuns` | number | 50 | Maximum full runs allowed (from `--max-loops N`) |

### Run Lifecycle

```
Run 1: A0 → A1 → A2 → A3 → A4 → A5 (ship commit)
        ↓ reset all phases + circuit breaker
Run 2: A0 → A1 → A2 → A3 → A4 → A5 (ship commit)
        ↓ reset all phases + circuit breaker
Run N: A0 → A1 → A2 → A3 → A4 → A5 (ship commit)
        ↓ maxRuns reached → workflow complete
```

Each run boundary resets:
- All phases (A0-A5) to pending
- Inner loop counter to 1
- Circuit breaker counters (stageRestarts, fixAttempts, consecutiveFailures)
- planApproved to false
- taskPool to empty

### Termination Conditions

pswarm stops when:
1. `pswarmRun >= maxRuns` — maximum runs exhausted
2. `shutdown = true` in state.json — user requested graceful shutdown
3. Circuit breaker tripped within a run — workflow blocks (user intervention needed)

### Implementation Details

The pswarm pipeline reuses all existing swarm infrastructure:
- Same agents (forager, architect, worker, queen, etc.)
- Same hooks (on-task-completed.sh branches on `pipeline` field)
- Same circuit breaker and task pool
- Two new library functions: `reset_phases_for_pswarm()` (dag.sh) and `cb_reset_for_run()` (circuit-breaker.sh)
