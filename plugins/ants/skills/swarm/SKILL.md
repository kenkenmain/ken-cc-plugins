---
name: swarm
description: Ant-colony themed 6-phase swarm pipeline with Agent Teams delegate mode, dual-channel communication (files + SendMessage), Command-as-Active-Lead monitoring loop, self-organizing task pool, and adversarial review teams
---

# Swarm Pipeline

Ant-colony themed 6-phase development pipeline with Agent Teams delegate mode, dual-channel communication (file artifacts + SendMessage live coordination), dual-track parallel execution, adversarial review teams, and self-organizing task dispatch. The **command** (lead) creates a team with dependency-chain task graphs, spawns 3 teammates, then enters a **monitoring loop** that reads signal flags from state.json and performs dynamic TaskCreate calls. The **TeammateIdle hook** is the full task router for all phases. The **TaskCompleted hook** validates output, advances state, and evaluates the A4 verdict inline. Uses **ants plugin agents** (self-contained) driven by **ants plugin hooks**. No Codex MCP dependency.

## Key Architecture

- `pipeline: "swarm"` in state.json
- `plugin: "ants"` -- so ants hooks fire
- Other plugins' hooks silently exit (they check `plugin` field in state.json)
- All agents are `ants:*` prefixed -- they exist in the ants plugin
- **Agent Teams delegate mode** with Command-as-Active-Lead monitoring loop
- **Dual-channel communication**: files for persistent artifacts (hooks validate these), SendMessage for live coordination overlay
- Command creates team first (TeamCreate), then populates task graph (TaskCreate with blockedBy dependency chains)
- TeammateIdle hook routes idle teammates to next ready phase/task (hook-driven routing, not self-assignment from TaskList)
- TaskCompleted hook validates output, advances state, and sets signal flags
- Command monitoring loop reads signal flags and creates dynamic tasks (A3 workers, A5, loop-back). The command MUST NOT stop or exit during the monitoring loop -- a `<COMPLETION-GATE>` enforces polling until a terminal condition is met
- A4 verdict is evaluated **inline** by `handle_a3_arbiter()` in the TaskCompleted hook -- no separate agent dispatch
- State schema v6 with `phases`, `circuitBreaker`, `taskPool`, `teamName`, `teamCreated`, `teammateCount`, `taskGraphVersion`, signal flags (`needsA3Tasks`, `needsA5Tasks`, `needsLoopReset`, `needsPswarmReset`), `messages`, `planApproved`, `shutdown`, `webhookUrl`, `lintConfig`, `configSnapshot`, `compactMetadata`, `worktreePath`, and `webSearch` fields

## Dual-Channel Communication Model

The swarm pipeline uses two complementary communication channels. Both channels serve distinct purposes and work together -- neither replaces the other.

### File Channel (Persistent Artifacts)

Files are the **source of truth** for all phase outputs. Hooks validate that expected files exist and contain valid data before advancing state. Every phase gate checks files, not messages. File artifacts persist across compaction, loop-backs, and pswarm run boundaries.

### SendMessage Channel (Live Coordination Overlay)

SendMessage provides **real-time peer coordination** between teammates within a single Agent Teams session. It enables agents to share status updates, partial results, warnings, and coordination signals without writing intermediate files. SendMessage is ephemeral -- messages exist only within the current session context and are not persisted to disk or validated by hooks.

### Golden Rule

**Write the file FIRST, then SendMessage.** An agent must always write its output artifact to disk before sending any coordination message about it. This ensures that:
1. Hooks can validate the artifact immediately when TaskCompleted fires
2. If SendMessage delivery is delayed or lost, the file still exists for downstream consumers
3. The file channel remains the authoritative source of truth

### Channel Comparison

| Aspect | File Channel | SendMessage Channel |
|--------|-------------|---------------------|
| **Purpose** | Persistent phase artifacts, hook validation gates | Live coordination, status updates, partial result sharing |
| **Persistence** | Disk -- survives compaction, loop-backs, restarts | Ephemeral -- session context only |
| **Validation** | Hooks validate existence, format, content | No hook validation -- advisory only |
| **Latency** | Write + read from disk | Immediate in-session delivery |
| **Required for phase gates** | Yes -- hooks check files to advance state | No -- phase transitions never depend on messages |
| **Used by** | All 24 agents (every agent writes output files) | 16 agents (coordination overlay, see table below) |
| **Examples** | `A0-explore.md`, `A1-plan.md`, `A3-quality.json` | "Build track complete, starting quality review", "Worker 3 found API conflict in auth module" |

## Who Messages Whom (SendMessage)

Sixteen agents use SendMessage as a live coordination overlay alongside their file output. Messages are informational -- they accelerate coordination but are never required for phase gates.

| Phase | Sender | Recipient(s) | Message Content |
|-------|--------|-------------- |-----------------|
| A0 | explore-aggregator | team | Synthesis complete, summary of key findings |
| A1 | architect | team | Plan ready, task count, complexity estimate |
| A2 | blueprint-reviewer | team | Review verdict (approved/needs_revision), issue summary |
| A3 | worker (each) | team | Task completion notice, files changed, self-verification status |
| A3 | sentinel-correctness | review-arbiter | Review complete, critical/warning/info issue counts |
| A3 | sentinel-security | review-arbiter | Review complete, critical/warning/info issue counts |
| A3 | sentinel-perf | review-arbiter | Review complete, critical/warning/info issue counts |
| A3 | sentinel-style | review-arbiter | Review complete, critical/warning/info issue counts |
| A3 | guardian | team | Tests written, pass/fail counts |
| A3 | simplifier | team | Cleanup complete, changes applied summary |
| A3 | review-arbiter | team | Consolidated quality verdict, critical issue count |
| A3 | review-fixer | team | Fixes applied, files modified |
| A5 | nurse | drone | Documentation updated, files modified list |
| A5 | drone | team | Commit SHA, PR URL, ship status |
| A1 (sswarm) | plan-arbiter | team | Selected plan, merge strategy used |
| A2 (sswarm) | review-lead | team | Consolidated review verdict |

### Message Format Contract

Agents send plain-text summary messages via SendMessage. Messages are brief, human-readable coordination signals -- not structured JSON payloads. Each agent's Communication Protocol section defines its specific message format. Examples:

- Worker: `"Task T3 complete. Files modified: src/auth.ts. Self-verification: tests pass."`
- Sentinel: `"Sentinel correctness review complete. Found 0 critical, 2 warning, 5 info issues. Review at .agents/tmp/phases/loop-1/A3-review.sentinel-correctness.json"`
- Drone: `"Shipped. Commit: abc123. PR: https://... Files: 3 committed."`
- Architect: `"A1 plan complete. 5 tasks planned. Plan at .agents/tmp/phases/loop-1/A1-plan.md"`

### Agents WITHOUT SendMessage

Eight agents do not use SendMessage. Their communication is entirely file-based, with task dependency chains (blockedBy) ensuring consumers only run after producers complete:

| Agent | Rationale |
|-------|-----------|
| forager | Lightweight haiku scout -- writes temp file only, aggregator reads via blockedBy |
| cartographer | Writes temp file only, aggregator reads via blockedBy |
| queen | Legacy/edge-case agent -- not dispatched in standard pipeline flow |
| sentinel (deprecated) | Replaced by specialist sentinels; retained for v0.1 backward compatibility only |
| bug-scout | Debug pipeline only (D0) -- stateless, no Agent Teams context |
| solution-proposer | Debug pipeline only (D1) -- stateless, no Agent Teams context |
| solution-aggregator | Debug pipeline only (D2) -- stateless, no Agent Teams context |
| fix-worker | Debug pipeline only (D3) -- stateless, no Agent Teams context |

Note: forager and cartographer are excluded because they are high-volume, low-latency haiku/sonnet scouts whose only job is to write a temp file. The explore-aggregator reads their files via blockedBy dependency -- no live coordination adds value here.

## 6-Phase Pipeline

```
Phase A0  | EXPLORE   | Colony Exploration     | foragers + cartographer + explore-aggregator
Phase A1  | PLAN      | Architect Plan         | architect
Phase A2  | PLAN      | Blueprint Review       | blueprint-reviewer
Phase A3  | BUILD     | Dual-Track Execution   | workers (task pool) + 4 sentinels + guardian + simplifier + arbiter
Phase A4  | SYNC      | Verdict                | TaskCompleted hook evaluates inline (handle_a3_arbiter)
Phase A5  | SHIP      | Documentation + Ship   | nurse + drone
```

### Pipeline Diagram

```
Command creates team (TeamCreate first), then initial tasks (TaskCreate with blockedBy chains):
  A0-forager-1, A0-forager-2, A0-cartographer -> A0-explore-aggregator -> A1-architect -> A2-blueprint-reviewer
Command spawns 3 teammates (hook-driven routing via TeammateIdle), enters monitoring loop

         A0 Explore
         foragers + cartographer (parallel, routed by TeammateIdle hook)
         explore-aggregator synthesizes -> A0-explore.md
         explore-aggregator SendMessage -> lead: "synthesis complete"
         TaskCompleted hook advances state to A1
             |
         A1 Architect
         architect writes plan + task descriptors (assigned by TeammateIdle hook)
         architect SendMessage -> lead: "plan ready, N tasks"
         TaskCompleted hook advances state to A2, sets needsA3Tasks flag
         Command monitoring loop creates A3 worker/sentinel/arbiter tasks
             |
         A2 Blueprint Review
         blueprint-reviewer validates plan (assigned by TeammateIdle hook)
         blueprint-reviewer SendMessage -> lead: "approved" or "needs_revision"
         TaskCompleted hook advances state to A3
             |
    +--------+--------+
    |    Phase A3      |
    |  (dual-track)    |
    |                  |
    | Build Track      | Quality Track (Adversarial)
    | (task pool)      |
    |  workers         | sentinel-correctness  \
    |  claimed from    | sentinel-security      } parallel
    |  pool by         | sentinel-perf         /
    |  TeammateIdle    | sentinel-style       /
    |       |          | guardian (tests)
    |  workers SM ->   | simplifier (cleanup)
    |   arbiter        |       |
    |  build results   | sentinels+guardian+simplifier SM -> arbiter
    |                  | review-arbiter consolidates
    +--------+--------+
             |
         A4 Verdict (evaluated INLINE by handle_a3_arbiter in TaskCompleted hook)
          /       \
     ship          loop
      |              |
   A5 Ship      A1 (needsLoopReset flag -> command creates fresh A1-A4 tasks)
   nurse SM -> drone
   drone SM -> lead: "shipped"
   (needsA5Tasks flag -> command creates A5 nurse/drone tasks)
```

(SM = SendMessage)

## Phase Details

### Phase A0: Colony Exploration

TeammateIdle hook assigns **forager**, **cartographer**, and **explore-aggregator** agents to idle teammates:

- **Foragers** (haiku, x2-3): Breadth-first scouts, each assigned a focused query (file structure, tests, patterns, related code). Write findings to `.agents/tmp/phases/A0-explore.forager.N.tmp`.
- **Cartographer** (sonnet, x1): Depth-first architecture tracer -- maps execution paths, dependency graphs, layered structure. Writes findings to `.agents/tmp/phases/A0-explore.cartographer.tmp`.
- **Explore-aggregator** (sonnet, x1): Synthesizes all forager and cartographer findings into a unified report. blockedBy all foragers + cartographer via task dependency chain. After writing the report, sends a SendMessage to the lead with a summary of key findings.

Output: `.agents/tmp/phases/A0-explore.md` (written by explore-aggregator)

TaskCompleted hook validates output and advances state to A1.

This phase is **supplementary, not required**. If agents fail or time out, the workflow continues without that intelligence.

### Phase A1: Architect Plan

TeammateIdle hook assigns `ants:architect` (sonnet) with aggregated A0 context. Architect writes a structured implementation plan with task assignments for the task pool. After writing the plan, sends a SendMessage to the lead with task count and complexity estimate.

On loop 2+, the dispatch prompt includes targeted feedback from the previous A4 verdict, directing the architect to plan fixes rather than re-planning from scratch.

Output:
- `.agents/tmp/phases/loop-{LOOP}/A1-plan.md` -- human-readable plan
- `.agents/tmp/phases/loop-{LOOP}/A1-tasks.json` -- machine-readable task descriptors for task pool

Must contain:
- Summary and chosen approach
- Task table with columns: ID, Description, Files, Dependencies, Complexity, Acceptance Criteria
- Task dependency graph (which tasks depend on which)

TaskCompleted hook validates output, initializes task pool, sets `needsA3Tasks` signal flag, and advances state to A2. Command monitoring loop detects the flag and calls TaskCreate for all A3 worker/sentinel/arbiter tasks.

### Phase A2: Blueprint Review

TeammateIdle hook assigns `ants:blueprint-reviewer` (sonnet) with paths to A1-plan.md and A1-tasks.json. Blueprint-reviewer validates the plan for completeness, feasibility, dependency correctness, and risk. After writing the review, sends a SendMessage to the lead with the verdict and issue summary.

Output: `.agents/tmp/phases/loop-{LOOP}/A2-review.json` with `status: "approved" | "needs_revision"`

If `needs_revision` with HIGH issues: TaskCompleted hook loops back to A1 with feedback. If `approved`: TaskCompleted hook advances state to A3.

### Phase A3: Dual-Track Execution

The core differentiator. TeammateIdle hook coordinates two parallel tracks by routing idle teammates to available work:

#### Build Track (Task Pool)

TeammateIdle hook dispatches workers from a **self-organizing task pool** based on dependency satisfaction:

1. `pool_init()` reads `A1-tasks.json` and initializes the task pool in state.json
2. Tasks with no dependencies start as `ready`; others start as `pending`
3. TeammateIdle hook assigns workers to ready tasks; workers atomically claim tasks via `pool_claim_task()`
4. As workers complete, TaskCompleted hook calls `pool_complete_task()` which recomputes the ready set -- previously pending tasks whose dependencies are now all complete become ready
5. TeammateIdle hook assigns new workers for newly ready tasks
6. Pool is complete when all tasks are `complete` or `failed`

Each worker:
- Implements exactly one task from the pool
- Can only edit files listed in the task's `files_owned` field (enforced by edit gate)
- Self-verifies (tests, lint, typecheck)
- Has git blocked by hook (no commits)
- After completing, sends a SendMessage to the team with task completion notice, files changed, and self-verification status

**Fallback:** If no `taskPool` exists in state (v0.1 state files), A3 falls back to legacy wave-based dispatch with the generic sentinel.

#### Quality Track (Adversarial Review + Cleanup)

After all workers complete (build track complete), TeammateIdle hook assigns **6 agents** to idle teammates:

- **sentinel-correctness** -- bugs, logic errors, missing error handling, incorrect API usage, race conditions
- **sentinel-security** -- OWASP top 10, injection attacks, authentication flaws, secrets exposure, access control
- **sentinel-perf** -- N+1 queries, unnecessary allocations, blocking I/O, missing caching, algorithmic complexity
- **sentinel-style** -- code style, readability, maintainability (excessive nesting, magic numbers, dead code)
- **guardian** -- writes tests for implemented code
- **simplifier** -- applies targeted code cleanup without behavioral changes (dead code removal, complexity reduction)

Each quality track agent writes its output file, then sends a SendMessage to the review-arbiter with issue counts and completion status.

Sentinel output files:
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-correctness.json`
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-security.json`
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-perf.json`
- `.agents/tmp/phases/loop-{LOOP}/A3-review.sentinel-style.json`

After all 6 complete, TeammateIdle hook assigns the **review-arbiter**:
- Reads all four sentinel outputs
- Cross-references findings across dimensions
- Deduplicates overlapping issues
- Resolves conflicts (e.g., security vs performance trade-offs)
- Produces: `.agents/tmp/phases/loop-{LOOP}/A3-quality.json`
- Sends a SendMessage to the lead with the consolidated quality verdict and critical issue count

If the arbiter finds critical issues, a **review-fixer** task is created to apply targeted repairs. The review-fixer sends a SendMessage to the arbiter after applying fixes.

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

### Phase A4: Verdict (Evaluated Inline by TaskCompleted Hook)

The A4 verdict is evaluated **inline** by `handle_a3_arbiter()` in the TaskCompleted hook when the review-arbiter task completes -- no separate agent is dispatched. The hook reads the arbiter's consolidated `A3-quality.json`, counts critical and warning issues, and renders a verdict.

The hook is **circuit breaker aware** -- it checks `circuitBreaker.stageRestarts` and `circuitBreaker.consecutiveFailures` before triggering a loop-back.

- **clean**: Quality track clean (or info-only issues) AND build track completed successfully AND guardian tests passing. Hook sets `needsA5Tasks` signal flag; command creates A5 tasks.
- **issues_found**: Any critical or warning issue unresolved, OR build track incomplete. Hook sets `needsLoopReset` signal flag; command creates fresh A1-A4 tasks.

Output: `.agents/tmp/phases/loop-{LOOP}/A4-queen-verdict.json` (written by handle_a3_arbiter in the hook)

### Phase A5: Documentation + Ship

TeammateIdle hook assigns two agents via task dependency chain:

1. **Nurse** (sonnet): Updates project documentation to reflect implementation changes (README.md, CLAUDE.md, etc.). Created by command when `needsA5Tasks` flag detected. After writing docs, sends a SendMessage to the drone with the list of modified documentation files.
2. **Drone** (after nurse completes, blockedBy A5-nurse): Commits changes and opens a PR. After shipping, sends a SendMessage to the lead with the commit SHA and PR URL.

Nurse output: `.agents/tmp/phases/loop-{LOOP}/A5-docs.json`
Drone output: `.agents/tmp/phases/loop-{LOOP}/A5-ship.json`

## Phase-Agent Mapping

| Phase | Stage | Agent(s) | SendMessage | Description |
|-------|-------|----------|-------------|-------------|
| A0 | EXPLORE | forager x2-3, cartographer x1 | No | Breadth-first + depth-first exploration (file output only) |
| A0 | EXPLORE | explore-aggregator x1 | Yes -> team | Synthesizes findings, notifies team (assigned by TeammateIdle hook) |
| A1 | PLAN | architect x1 | Yes -> team | Structured plan with task assignments (assigned by TeammateIdle hook) |
| A2 | PLAN | blueprint-reviewer x1 | Yes -> team | Plan validation (assigned by TeammateIdle hook) |
| A3 | BUILD | worker xN (task pool) | Yes -> team | Self-organizing task pool, workers notify team on completion |
| A3 | BUILD | sentinel-correctness, sentinel-security, sentinel-perf, sentinel-style | Yes -> review-arbiter | Adversarial review, sentinels notify review-arbiter with issue counts |
| A3 | BUILD | guardian x1 | Yes -> team | Test writer, notifies team with test results |
| A3 | BUILD | simplifier x1 | Yes -> team | Code cleanup, notifies team with changes summary |
| A3 | BUILD | review-arbiter x1 | Yes -> team | Consolidates findings, notifies team with verdict |
| A3 | BUILD | review-fixer x0-1 | Yes -> team | Targeted repairs, notifies team after fixes |
| A4 | SYNC | TaskCompleted hook (inline) | -- | Evaluated inline by handle_a3_arbiter(); no separate agent dispatch |
| A5 | SHIP | nurse x1 | Yes -> drone | Documentation update, notifies drone with file list |
| A5 | SHIP | drone x1 | Yes -> team | Commit/PR, notifies team with SHA and PR URL |

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

The TaskCompleted hook's inline verdict evaluation drives progression:

```
A4 verdict == "clean"         -->  Advance to A5 (ship)
                                   Hook sets needsA5Tasks flag
                                   Command creates A5 nurse/drone tasks
A4 verdict == "issues_found"  -->  Return to A1 (re-plan fixes)
                                   Hook sets needsLoopReset flag
                                   Command creates fresh A1-A4 tasks
                                   Circuit breaker checks:
                                   - stageRestarts < maxStageRestarts
                                   - consecutiveFailures < maxConsecutiveFailures
                                   If either exceeded: block workflow
```

### Loop Limits

- **Maximum loops:** 5 (configurable via `state.maxLoops`)
- **Loop counter:** `state.loop` (starts at 1)
- On each loop-back, `loop` increments, `reset_phases_for_loop()` resets A1-A4 to pending, and `taskGraphVersion` increments
- If `loop > maxLoops`: workflow blocks, requires user intervention

### Loop Context

On loop 2+:
- Dispatch prompt includes previous loop's A3-quality.json and A4-queen-verdict.json as feedback to the architect
- Architect plans **targeted fixes**, not full re-plans
- Previous loop's files are preserved in `loop-{N}/` directories

## State Schema (v6)

```json
{
  "version": 6,
  "plugin": "ants",
  "pipeline": "swarm",
  "status": "in_progress|blocked|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID if available>",
  "currentPhase": "A0|A1|A2|A3|A4|A5|DONE|STOPPED|BLOCKED",
  "loop": 1,
  "maxLoops": 5,
  "teamName": "ants-<branch-slug>",
  "startedAt": "ISO timestamp",
  "teamCreated": false,
  "teammateCount": 0,
  "taskGraphVersion": 1,
  "needsA3Tasks": false,
  "needsA5Tasks": false,
  "needsLoopReset": false,
  "needsPswarmReset": false,
  "schedule": [
    {"phase": "A0", "stage": "EXPLORE", "label": "Colony Exploration", "type": "agents"},
    {"phase": "A1", "stage": "PLAN", "label": "Architect Plan", "type": "agents"},
    {"phase": "A2", "stage": "PLAN", "label": "Blueprint Review", "type": "agents"},
    {"phase": "A3", "stage": "BUILD", "label": "Dual-Track Execution", "type": "agents"},
    {"phase": "A4", "stage": "SYNC", "label": "Verdict", "type": "agents"},
    {"phase": "A5", "stage": "SHIP", "label": "Documentation + Ship", "type": "agents"}
  ],
  "phases": {
    "A0": {"status": "complete", "startedAt": "...", "completedAt": "..."},
    "A1": {"status": "in_progress", "startedAt": "..."},
    "A2": {"status": "pending"},
    "A3": {"status": "pending"},
    "A4": {"status": "pending"},
    "A5": {"status": "pending"}
  },
  "taskPool": [],
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
  "webSearch": false
}
```

## Phase Output Files

All outputs live under `.agents/tmp/phases/`:

| Phase | File | Format | Written By | Description |
|-------|------|--------|------------|-------------|
| A0 | `A0-explore.md` | Markdown | Explore-aggregator | Unified exploration report |
| A1 | `loop-{L}/A1-plan.md` | Markdown | Architect | Implementation plan |
| A1 | `loop-{L}/A1-tasks.json` | JSON | Architect | Task descriptors for task pool |
| A2 | `loop-{L}/A2-review.json` | JSON | Blueprint-reviewer | Blueprint review verdict |
| A3 | `loop-{L}/A3-build.json` | JSON | TaskCompleted hook (aggregated from workers) | Build track worker results |
| A3 | `loop-{L}/A3-review.sentinel-correctness.json` | JSON | Sentinel-correctness | Correctness findings |
| A3 | `loop-{L}/A3-review.sentinel-security.json` | JSON | Sentinel-security | Security findings |
| A3 | `loop-{L}/A3-review.sentinel-perf.json` | JSON | Sentinel-perf | Performance findings |
| A3 | `loop-{L}/A3-review.sentinel-style.json` | JSON | Sentinel-style | Style findings |
| A3 | `loop-{L}/A3-quality.json` | JSON | Review-arbiter | Consolidated quality verdict |
| A4 | `loop-{L}/A4-queen-verdict.json` | JSON | TaskCompleted hook (handle_a3_arbiter) | Ship/loop verdict with evidence |
| A5 | `loop-{L}/A5-docs.json` | JSON | Nurse | Documentation update summary |
| A5 | `loop-{L}/A5-ship.json` | JSON | Drone | Commit/PR output |

## Stage Gates

| Gate | Required | Transition |
|------|----------|------------|
| EXPLORE -> PLAN | `A0-explore.md` (soft -- continues if missing) | After Phase A0 |
| PLAN -> BUILD | `loop-{L}/A1-plan.md` + `loop-{L}/A1-tasks.json` + `loop-{L}/A2-review.json` approved | After Phase A2 |
| BUILD -> SYNC | `loop-{L}/A3-build.json` + `loop-{L}/A3-quality.json` | After Phase A3 |
| SYNC -> SHIP | `loop-{L}/A4-queen-verdict.json` with verdict `clean` | After Phase A4 |

Note: Stage gates are validated via the **file channel only**. SendMessage notifications are advisory and do not affect gate progression.

## Verdict Field Naming

Different phases use different JSON field names for their decision outputs. The hook reads both for compatibility:

| Phase | File | Decision Field | Values |
|-------|------|---------------|--------|
| A2 | A2-review.json | `.status` | `approved`, `needs_revision` |
| A3 | A3-quality.json | `.verdict` | `clean`, `issues_found` |
| A4 | A4-queen-verdict.json | `.verdict` | `clean`, `issues_found` |

The A2 hook reads `.status` only (the `.verdict` fallback was removed in v0.5.5). A3 and A4 use `.verdict` consistently.

## Difference from Minions

| Aspect | ants:swarm | minions:superlaunch |
|--------|-----------|---------------------|
| Phases | 6 (A0-A5) | 15 (S0-S14) |
| Theme | Ant colony (forager, architect, worker, sentinel) | Generic minions |
| Coordination | Agent Teams delegate mode with Command-as-Active-Lead monitoring loop | Sequential phases with hook-driven transitions |
| Communication | Dual-channel: files (persistent) + SendMessage (live coordination) | File-based only |
| Key innovation | Task pool + adversarial review teams (4 sentinels + arbiter) | Sequential phases with review-fix cycles |
| Loop mechanism | Orchestrator verdict (A4) -> A1 re-plan (max 5, circuit breaker) | Review phases with fix attempts + stage restarts |
| Agents | 24 specialized colony roles | 38 agents |
| Failure handling | Circuit breaker with 3 tiers | Fix budget per review phase |
| Complexity | Streamlined for medium tasks | Thorough for complex tasks |

## pswarm Pipeline

The `pswarm` (persistent swarm) command extends the swarm pipeline into a continuously-running loop. After each full A0-A5 cycle ships a commit, the TaskCompleted hook sets the `needsPswarmReset` signal flag. The command's monitoring loop detects this flag, creates a fresh A0-A5 task graph via `teams_create_pswarm_run_tasks()`, and calls TaskCreate for all new tasks -- re-exploring the changed codebase, re-planning remaining work, and shipping again.

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
- Same agents (forager, architect, worker, sentinel, etc.)
- Same hooks (on-task-completed.sh branches on `pipeline` field)
- Same circuit breaker and task pool
- Library functions: `reset_phases_for_pswarm()` (dag.sh) and `cb_reset_for_run()` (circuit-breaker.sh)
- `teams_create_pswarm_run_tasks()` (teams.sh) generates fresh task graph for each run boundary
- `needsPswarmReset` signal flag enables hook-to-command handoff for new TaskCreate calls
- `taskGraphVersion` increments on each run boundary to track task graph updates
