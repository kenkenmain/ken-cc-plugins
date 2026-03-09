---
name: swarm
description: Ant-colony themed 6-phase swarm pipeline with self-organizing task pool and adversarial review teams
---

# Swarm Pipeline

Ant-colony themed 6-phase development pipeline with dual-track parallel execution, adversarial review teams, and self-organizing task dispatch. The **queen** is the persistent central coordinator, driving every phase transition via **SendMessage**. All agents report results back through SendMessage, creating a hub-and-spoke communication model. Uses **ants plugin agents** (self-contained) driven by **ants plugin hooks** (Agent Teams delegate mode). No Codex MCP dependency.

## Key Architecture

- `pipeline: "swarm"` in state.json
- `plugin: "ants"` -- so ants hooks fire
- Other plugins' hooks silently exit (they check `plugin` field in state.json)
- All agents are `ants:*` prefixed -- they exist in the ants plugin
- **Queen is persistent** -- spawned once at pipeline start, drives all phases A0-A5 via SendMessage
- A4 (sync/verdict) is internal to the queen -- no separate agent dispatch
- State schema v5 with `phases`, `circuitBreaker`, `taskPool`, `teamName`, `messages`, `planApproved`, `shutdown`, `webhookUrl`, `lintConfig`, `configSnapshot`, `compactMetadata`, `worktreePath`, `webSearch`, and `queenDispatched` fields

## 6-Phase Pipeline

```
Phase A0  | EXPLORE   | Colony Exploration     | queen dispatches foragers + cartographer, aggregates results
Phase A1  | PLAN      | Architect Plan         | queen dispatches architect
Phase A2  | PLAN      | Blueprint Review       | queen dispatches blueprint-reviewer
Phase A3  | BUILD     | Dual-Track Execution   | queen dispatches workers (task pool) + sentinels + guardian + arbiter
Phase A4  | SYNC      | Queen Verdict          | queen evaluates internally (circuit breaker aware)
Phase A5  | SHIP      | Documentation + Ship   | queen dispatches nurse + drone
```

### Pipeline Diagram

```
         A0 Explore
         queen dispatches foragers + cartographer
         queen aggregates findings -> A0-explore.md
             |
         A1 Architect
         queen dispatches architect via SendMessage
             |
         A2 Blueprint Review
         queen dispatches blueprint-reviewer via SendMessage
             |
    +--------+--------+
    |    Phase A3      |
    |  (dual-track)    |
    |                  |
    | Build Track      | Quality Track (Adversarial)
    | (task pool)      |
    |  queen sends     | sentinel-correctness  \
    |  tasks to        | sentinel-security      } parallel, report
    |  workers via     | sentinel-perf         /  to review-arbiter
    |  SendMessage     | guardian (tests) --> queen
    |       |          |       |
    |  workers report  | review-arbiter --> queen
    |  back to queen   |
    +--------+--------+
             |
         A4 Queen Verdict (internal, circuit breaker aware)
          /       \
     ship          loop
      |              |
   A5 Ship      A1 (loop back, queen sends feedback to architect)
```

## Communication Flow

All coordination flows through SendMessage. The queen is the central hub.

```
                 +-------------------+
                 |      queen        |
                 | (persistent hub)  |
                 +-------------------+
                /  |  |  |  |  |  |  \
  SendMessage  /   |  |  |  |  |  |   \  SendMessage
  (dispatch)  v    v  v  v  v  v  v    v  (dispatch)
         forager  cartographer  architect  blueprint-reviewer
         worker   nurse   drone   guardian
                    |
                    |  All report results back to queen via SendMessage
                    |
                 Exception: sentinels report to review-arbiter
                    |
         sentinel-correctness  --->  review-arbiter  --->  queen
         sentinel-security     --->  review-arbiter
         sentinel-perf         --->  review-arbiter
```

### SendMessage Sender-Recipient Pairs

| Sender | Recipient | Phase | Purpose |
|--------|-----------|-------|---------|
| queen | forager (x2-4) | A0 | Dispatch exploration queries |
| queen | cartographer | A0 | Dispatch architecture tracing |
| forager | queen | A0 | Return exploration findings |
| cartographer | queen | A0 | Return architecture map |
| queen | architect | A1 | Dispatch plan creation (includes A0 context, loop feedback) |
| architect | queen | A1 | Return plan confirmation (paths to A1-plan.md, A1-tasks.json) |
| queen | blueprint-reviewer | A2 | Dispatch plan validation |
| blueprint-reviewer | queen | A2 | Return review verdict (approved/needs_revision) |
| queen | worker (xN) | A3 | Dispatch task assignments from pool |
| worker | queen | A3 | Return task completion report |
| queen | sentinel-correctness | A3 | Dispatch correctness review |
| queen | sentinel-security | A3 | Dispatch security review |
| queen | sentinel-perf | A3 | Dispatch performance review |
| queen | guardian | A3 | Dispatch test writing |
| sentinel-correctness | review-arbiter | A3 | Send correctness findings |
| sentinel-security | review-arbiter | A3 | Send security findings |
| sentinel-perf | review-arbiter | A3 | Send performance findings |
| guardian | queen | A3 | Return test completion report |
| queen | review-arbiter | A3 | Dispatch consolidation (after sentinels complete) |
| review-arbiter | queen | A3 | Return consolidated quality verdict |
| queen | review-fixer | A3 | Dispatch targeted repairs (if critical issues found) |
| review-fixer | queen | A3 | Return fix completion report |
| queen | nurse | A5 | Dispatch documentation update |
| nurse | queen | A5 | Return documentation confirmation |
| queen | drone | A5 | Dispatch commit/PR |
| drone | queen | A5 | Return {commit_sha, pr_url} |

**Key rules:**
- All agents send results back to `"queen"` -- the queen is the central hub
- Exception: specialist sentinels send findings to `"review-arbiter"` for consolidation before the arbiter reports to queen
- Queen dispatches to agents by their exact agent name (e.g., `"forager"`, `"architect"`, `"worker"`)
- A4 (sync/verdict) is internal to queen -- no separate agent is dispatched

## Phase Details

### Phase A0: Colony Exploration

Queen dispatches **forager** and **cartographer** agents in parallel via SendMessage, then aggregates their findings directly into a unified exploration report.

- **Foragers** (haiku, x2-4): Breadth-first scouts, each assigned a focused query (file structure, tests, patterns, related code). Each forager sends results back to queen via SendMessage.
- **Cartographer** (sonnet, x1): Depth-first architecture tracer -- maps execution paths, dependency graphs, layered structure. Sends results back to queen via SendMessage.
- **Queen** aggregates all forager and cartographer results into a single consolidated report.

Output: `.agents/tmp/phases/A0-explore.md` (written by queen)

This phase is **supplementary, not required**. If agents fail or time out, the workflow continues without that intelligence.

### Phase A1: Architect Plan

Queen dispatches `ants:architect` (sonnet) via SendMessage with aggregated A0 context. Architect writes a structured implementation plan with task assignments for the task pool and sends confirmation back to queen.

On loop 2+, queen includes targeted feedback from the previous A4 verdict, directing the architect to plan fixes rather than re-planning from scratch.

Output:
- `.agents/tmp/phases/loop-{LOOP}/A1-plan.md` -- human-readable plan
- `.agents/tmp/phases/loop-{LOOP}/A1-tasks.json` -- machine-readable task descriptors for task pool

Must contain:
- Summary and chosen approach
- Task table with columns: ID, Description, Files, Dependencies, Complexity, Acceptance Criteria
- Task dependency graph (which tasks depend on which)

### Phase A2: Blueprint Review

Queen dispatches `ants:blueprint-reviewer` (sonnet) via SendMessage with paths to A1-plan.md and A1-tasks.json. Blueprint-reviewer validates the plan for completeness, feasibility, dependency correctness, and risk, then sends verdict back to queen.

Output: `.agents/tmp/phases/loop-{LOOP}/A2-review.json` with `status: "approved" | "needs_revision"`

If `needs_revision` with HIGH issues: queen loops back to A1 with feedback for the architect. If `approved`: queen advances to A3.

### Phase A3: Dual-Track Execution

The core differentiator. Queen coordinates two parallel tracks:

#### Build Track (Task Pool)

Queen dispatches workers from a **self-organizing task pool** based on dependency satisfaction:

1. `pool_init()` reads `A1-tasks.json` and initializes the task pool in state.json
2. Tasks with no dependencies start as `ready`; others start as `pending`
3. Queen sends task assignments to workers via SendMessage; workers atomically claim ready tasks via `pool_claim_task()`
4. As workers complete and report back to queen, `pool_complete_task()` recomputes the ready set -- previously pending tasks whose dependencies are now all complete become ready
5. Queen dispatches new workers for newly ready tasks
6. Pool is complete when all tasks are `complete` or `failed`

Each worker:
- Implements exactly one task from the pool
- Can only edit files listed in the task's `files_owned` field (enforced by edit gate)
- Self-verifies (tests, lint, typecheck)
- Sends structured JSON report back to queen via SendMessage (status, files modified, tests written)
- Has git blocked by hook (no commits)

**Fallback:** If no `taskPool` exists in state (v0.1 state files), A3 falls back to legacy wave-based dispatch with the generic sentinel.

#### Quality Track (Adversarial Review)

After all workers complete (pool drained), queen dispatches the quality track via SendMessage:

- **sentinel-correctness** -- bugs, logic errors, missing error handling, incorrect API usage, race conditions
- **sentinel-security** -- OWASP top 10, injection attacks, authentication flaws, secrets exposure, access control
- **sentinel-perf** -- N+1 queries, unnecessary allocations, blocking I/O, missing caching, algorithmic complexity
- **guardian** -- writes tests for implemented code, reports coverage back to queen via SendMessage

Sentinels send findings to **review-arbiter** (not to queen):
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-correctness.json`
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-security.json`
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-perf.json`

Guardian sends test completion report directly to queen: `{status, testsWritten, summary}`

After all three sentinels complete, queen dispatches the **review-arbiter**:
- Reads all three sentinel outputs
- Cross-references findings across dimensions
- Deduplicates overlapping issues
- Resolves conflicts (e.g., security vs performance trade-offs)
- Sends consolidated verdict back to queen
- Produces: `.agents/tmp/phases/loop-{LOOP}/A3-quality.json`

The arbiter's output is backward compatible with the v0.1 sentinel quality format.

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

### Phase A4: Queen Verdict (Internal)

The queen evaluates all A3 evidence internally -- no separate agent is dispatched for this phase. She reads the arbiter's consolidated `A3-quality.json`, the build track's `A3-build.json`, and guardian results, then cross-references and renders a verdict.

The queen is **circuit breaker aware** -- she checks `circuitBreaker.stageRestarts` and `circuitBreaker.consecutiveFailures` before recommending a loop-back.

- **clean**: Quality track clean (or info-only issues) AND build track completed successfully AND guardian tests passing
- **issues_found**: Any critical or warning issue unresolved, OR build track incomplete

Output: `.agents/tmp/phases/loop-{LOOP}/A4-queen-verdict.json`

### Phase A5: Documentation + Ship

Queen dispatches two agents sequentially via SendMessage:

1. **Nurse** (sonnet): Updates project documentation to reflect implementation changes (README.md, CLAUDE.md, etc.). Sends confirmation back to queen.
2. **Drone** (after nurse completes): Commits changes and opens a PR. Sends `{commit_sha, pr_url}` back to queen.

Nurse output: `.agents/tmp/phases/loop-{LOOP}/A5-docs.json`
Drone output: `.agents/tmp/phases/loop-{LOOP}/A5-ship.json`

## Phase-Agent Mapping

| Phase | Stage | Agent(s) | Communication | Description |
|-------|-------|----------|---------------|-------------|
| A0 | EXPLORE | forager x2-4, cartographer x1 | All report to queen via SendMessage | Parallel codebase exploration (queen aggregates results directly) |
| A1 | PLAN | architect x1 | Reports to queen via SendMessage | Structured plan with task assignments |
| A2 | PLAN | blueprint-reviewer x1 | Reports to queen via SendMessage | Plan validation |
| A3 | BUILD | worker xN (task pool), sentinel-correctness + sentinel-security + sentinel-perf, guardian xN, review-arbiter x1 | Workers/guardian/arbiter report to queen; sentinels report to review-arbiter | Self-organizing task pool with adversarial review teams |
| A4 | SYNC | queen (internal) | No dispatch -- queen evaluates internally | Queen evaluates all A3 evidence, renders ship/loop verdict (circuit breaker aware) |
| A5 | SHIP | nurse x1, drone x1 | Both report to queen via SendMessage | Documentation update + commit/PR |

Note: The queen is **persistent** across all phases -- she is spawned once at pipeline start and drives every phase transition. She is not dispatched at A4 only.

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
                                   Queen sends targeted feedback to architect via SendMessage
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
- Queen sends previous loop's A3-quality.json and A4-queen-verdict.json as feedback to the architect
- Architect plans **targeted fixes**, not full re-plans
- Previous loop's files are preserved in `loop-{N}/` directories

## State Schema (v5)

```json
{
  "version": 5,
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
    {"phase": "A4", "stage": "SYNC", "label": "Queen Verdict", "type": "teams"},
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
  "compactMetadata": null,
  "webSearch": false,
  "queenDispatched": false
}
```

## Phase Output Files

All outputs live under `.agents/tmp/phases/`:

| Phase | File | Format | Written By | Description |
|-------|------|--------|------------|-------------|
| A0 | `A0-explore.md` | Markdown | Queen (aggregated) | Unified exploration report |
| A1 | `loop-{L}/A1-plan.md` | Markdown | Architect | Implementation plan |
| A1 | `loop-{L}/A1-tasks.json` | JSON | Architect | Task descriptors for task pool |
| A2 | `loop-{L}/A2-review.json` | JSON | Blueprint-reviewer | Blueprint review verdict |
| A3 | `loop-{L}/A3-build.json` | JSON | Queen (aggregated from workers) | Build track worker results |
| A3 | `loop-{L}/A3-review.sentinel-correctness.json` | JSON | Sentinel-correctness | Correctness findings |
| A3 | `loop-{L}/A3-review.sentinel-security.json` | JSON | Sentinel-security | Security findings |
| A3 | `loop-{L}/A3-review.sentinel-perf.json` | JSON | Sentinel-perf | Performance findings |
| A3 | `loop-{L}/A3-quality.json` | JSON | Review-arbiter | Consolidated quality verdict |
| A4 | `loop-{L}/A4-queen-verdict.json` | JSON | Queen | Ship/loop verdict with evidence |
| A5 | `loop-{L}/A5-docs.json` | JSON | Nurse | Documentation update summary |
| A5 | `loop-{L}/A5-ship.json` | JSON | Drone | Commit/PR output |

## Stage Gates

| Gate | Required | Transition |
|------|----------|------------|
| EXPLORE -> PLAN | `A0-explore.md` (soft -- continues if missing) | After Phase A0 |
| PLAN -> BUILD | `loop-{L}/A1-plan.md` + `loop-{L}/A1-tasks.json` + `loop-{L}/A2-review.json` approved | After Phase A2 |
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
| Coordination | Queen as persistent hub via SendMessage | Sequential phases with hook-driven transitions |
| Key innovation | Task pool + adversarial review teams (3 sentinels + arbiter) | Sequential phases with review-fix cycles |
| Loop mechanism | Queen verdict (A4 internal) -> A1 re-plan (max 5, circuit breaker) | Review phases with fix attempts + stage restarts |
| Agents | 19 specialized colony roles | 26+ agents |
| Failure handling | Circuit breaker with 3 tiers | Fix budget per review phase |
| Complexity | Streamlined for medium tasks | Thorough for complex tasks |

## pswarm Pipeline

The `pswarm` (persistent swarm) command extends the swarm pipeline into a continuously-running loop. After each full A0-A5 cycle ships a commit, pswarm automatically resets all phases and starts a fresh run -- re-exploring the changed codebase, re-planning remaining work, and shipping again.

### Command Syntax

```
/ants:pswarm <task description> [--max-loops N] [--worktree] [--web]
```

- `<task description>`: Required. The task to solve.
- `--max-loops N`: Maximum number of full runs (default: 50). Each run is a complete A0-A5 cycle.
- `--worktree`: Create a git worktree for isolated development.
- `--web`: Enable WebSearch for forager agents during exploration (A0) and planning (A1) phases. Opt-in, default: disabled.

### How It Differs from Swarm

| Aspect | swarm | pswarm |
|--------|-------|--------|
| Runs | Single A0-A5 cycle | Multiple A0-A5 cycles |
| After A5 ships | Workflow completes | Resets to A0, starts next run |
| Inner loops (A4->A1) | Up to 5 re-plan cycles per run | Same -- up to 5 per run |
| Max iterations | 1 run x 5 inner loops | N runs x 5 inner loops each |
| State field | `pipeline: "swarm"` | `pipeline: "pswarm"` |

### pswarm-Specific State Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `pswarmRun` | number | 1 | Current full run number (increments after each A5 ship) |
| `maxRuns` | number | 50 | Maximum full runs allowed (from `--max-loops N`) |
| `webSearch` | boolean | false | When true, forager agents can use WebSearch to research external libraries and APIs |

Note: `webSearch` persists across pswarm runs (not reset between runs).

### Run Lifecycle

```
Run 1: A0 -> A1 -> A2 -> A3 -> A4 -> A5 (ship commit)
        | reset all phases + circuit breaker
Run 2: A0 -> A1 -> A2 -> A3 -> A4 -> A5 (ship commit)
        | reset all phases + circuit breaker
Run N: A0 -> A1 -> A2 -> A3 -> A4 -> A5 (ship commit)
        | maxRuns reached -> workflow complete
```

Each run boundary resets:
- All phases (A0-A5) to pending
- Inner loop counter to 1
- Circuit breaker counters (stageRestarts, fixAttempts, consecutiveFailures)
- planApproved to false
- taskPool to empty

### Termination Conditions

pswarm stops when:
1. `pswarmRun >= maxRuns` -- maximum runs exhausted
2. `shutdown = true` in state.json -- user requested graceful shutdown
3. Circuit breaker tripped within a run -- workflow blocks (user intervention needed)

### Implementation Details

The pswarm pipeline reuses all existing swarm infrastructure:
- Same agents (forager, architect, worker, queen, etc.)
- Same hooks (on-task-completed.sh branches on `pipeline` field)
- Same circuit breaker and task pool
- Two new library functions: `reset_phases_for_pswarm()` (dag.sh) and `cb_reset_for_run()` (circuit-breaker.sh)
