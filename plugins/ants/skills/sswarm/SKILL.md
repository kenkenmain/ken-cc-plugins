---
name: sswarm
description: Social swarm -- Agent Teams delegate mode 6-phase pipeline with competing agents coordinated via task dependency chains (dispatch ordering) and SendMessage (live coordination overlay), with per-phase lead consolidators
---

# Social Swarm Pipeline

Agent Teams delegate mode 6-phase development pipeline with **competing parallel agents** and **per-phase lead consolidators**. The command creates a team with dependency-chain task graphs, spawns 5 teammates, then enters a monitoring loop. Phases A1 and A2 feature multiple competing agents whose outputs are consolidated by dedicated lead agents (plan-arbiter, review-lead) via **blockedBy task dependency chains** for dispatch ordering, with **SendMessage as a live coordination overlay** for status broadcasts and handoff signals. Competing agents write to independent temp files (source of truth for hooks); consolidator tasks are blockedBy all competitors and read their output files directly.

## Key Architecture

- `pipeline: "sswarm"` in state.json
- `plugin: "ants"` -- so ants hooks fire
- All agents are `ants:*` prefixed -- they exist in the ants plugin
- **Agent Teams delegate mode** with Command-as-Active-Lead monitoring loop
- Command creates initial tasks via TaskCreate with **blockedBy dependency chains**
- Competing agents (3 architects, 3 reviewers) have **no dependencies on each other** -- they run in parallel
- Consolidator tasks (plan-arbiter, review-lead) are **blockedBy all competitors** -- they run after all competitors complete
- A4 verdict is evaluated **inline** by `handle_a3_arbiter()` in the TaskCompleted hook -- no separate agent dispatch
- State schema v6 with additional `phaseLeads` map
- All existing hooks are compatible -- TeammateIdle routes by currentPhase, TaskCompleted validates and advances

## Key Differences from Swarm

| Feature | swarm | sswarm |
|---------|-------|--------|
| A1 planning | 1 architect | 3 competing architects + plan-arbiter (lead) via blockedBy dependency chain |
| A2 review | 1 blueprint-reviewer | 3 competing reviewers + review-lead (lead) via blockedBy dependency chain |
| Lead agents | None | plan-arbiter (A1), review-lead (A2) -- read competitor output files directly |
| Competitor coordination | N/A | blockedBy task dependencies + SendMessage live overlay |
| Teammate count | 3 | 5 (more parallelism for competing agents) |
| Agent count per run | ~15 agents | ~21 agents (6 more for competing + leads) |
| A0, A3, A4, A5 | Identical | Identical |
| State schema | v6 | v6 + `phaseLeads` map |
| Hooks | All hooks | Same hooks, unchanged |

## 6-Phase Pipeline

```
Phase A0  | EXPLORE | Colony Exploration    | foragers + cartographer + explore-aggregator (lead)
Phase A1  | PLAN    | Competing Architects  | 3 architects (parallel, no deps on each other) → plan-arbiter (blockedBy all 3)
Phase A2  | PLAN    | Competing Reviews     | 3 blueprint-reviewers (parallel) → review-lead (blockedBy all 3)
Phase A3  | BUILD   | Dual-Track Execution  | workers (task pool) + 4 sentinels + guardian + simplifier + arbiter
Phase A4  | SYNC    | Verdict               | TaskCompleted hook evaluates inline (handle_a3_arbiter)
Phase A5  | SHIP    | Documentation + Ship  | nurse + drone
```

### Pipeline Diagram

```
Command creates team + initial sswarm task graph (12 tasks):

  A0-forager-1 ────────┐
  A0-forager-2 ────────┤
  A0-cartographer ─────┤
                        └─► A0-explore-aggregator
                                     |
                        ┌────────────┼────────────┐
                        ▼            ▼            ▼
                 A1-architect-1  A1-architect-2  A1-architect-3   (parallel, no deps on each other)
                        |            |            |
                        └────────────┼────────────┘
                                     ▼
                              A1-plan-arbiter              (blockedBy all 3 architects)
                              reads competitor files, selects/merges -> A1-plan.md + A1-tasks.json
                                     |
                        ┌────────────┼────────────┐
                        ▼            ▼            ▼
                  A2-reviewer-1  A2-reviewer-2  A2-reviewer-3    (parallel, no deps on each other)
                        |            |            |
                        └────────────┼────────────┘
                                     ▼
                              A2-review-lead               (blockedBy all 3 reviewers)
                              consolidates -> A2-review.json
                                     |
                    +────────────────+────────────────+
                    |    Phase A3                      |
                    |  (dual-track)                    |
                    |                                  |
                    | Build Track      | Quality Track (Adversarial)
                    | (task pool)      |
                    |  workers         | sentinel-correctness  \
                    |  claimed from    | sentinel-security      \
                    |  pool by         | sentinel-perf           } parallel
                    |  TeammateIdle    | sentinel-style         /
                    |       |          | guardian              /
                    |  build results   | simplifier           /
                    |                  |       |
                    |                  | review-arbiter consolidates
                    +────────────────+────────────────+
                                     |
                    A4 Verdict (evaluated INLINE by handle_a3_arbiter)
                      /       \
                 ship          loop
                  |              |
               A5 Ship      A1 (needsLoopReset → command creates fresh competing task graph)

Command spawns 5 teammates, enters monitoring loop
```

### sswarm Task Graph Structure

The sswarm task graph uses **blockedBy dependency chains** for dispatch ordering, with **SendMessage as a live coordination overlay** for status broadcasts and handoff signals (dual-channel model):

- **Competing agents** (architects at A1, reviewers at A2): 3 independent tasks with no dependencies on each other -- they run in parallel when their phase prerequisites complete
- **Consolidator tasks** (plan-arbiter, review-lead): blockedBy all 3 competitors -- they run only after all competing outputs exist
- **File-based input (primary)**: Consolidator agents read competitor output files at known paths (specified in dispatch prompt). Files are the source of truth validated by hooks.
- **SendMessage (overlay)**: Agents send coordination messages (status updates, completion signals) alongside their file output. SendMessage accelerates coordination but is never required for phase gates.
- **No spawn order constraint**: All tasks are created upfront with dependency declarations; the Agent Teams runtime schedules them automatically

## Phase Details

### Phase A0: Colony Exploration

Same as swarm — foragers + cartographer + explore-aggregator.

Output: `.agents/tmp/phases/A0-explore.md`

### Phase A1: Competing Architects

The command creates **3 architect tasks** (A1-architect-1, A1-architect-2, A1-architect-3) all blockedBy the A0 explore-aggregator task -- they run in parallel with no dependencies on each other. Each architect independently explores the context and writes a plan to a unique temp file.

The command also creates an **A1-plan-arbiter** task blockedBy all 3 architect tasks. The plan-arbiter reads all 3 competitor output files (specified in its dispatch prompt), evaluates on five criteria (completeness, feasibility, task count, risk, dependency correctness), selects the best plan or synthesizes a merged plan, and writes the canonical output files.

**Dependency chain (replaces spawn order):**
- `A1-architect-1`, `A1-architect-2`, `A1-architect-3` -- all blockedBy `[A0-explore-aggregator]` (parallel)
- `A1-plan-arbiter` -- blockedBy `[A1-architect-1, A1-architect-2, A1-architect-3]` (runs after all 3 complete)

Output:
- `.agents/tmp/phases/loop-{LOOP}/A1-plan.md` (canonical, written by plan-arbiter)
- `.agents/tmp/phases/loop-{LOOP}/A1-tasks.json` (canonical, written by plan-arbiter)
- `.agents/tmp/phases/loop-{LOOP}/A1-plan.architect.{1,2,3}.tmp` (individual architect plans)
- `.agents/tmp/phases/loop-{LOOP}/A1-tasks.architect.{1,2,3}.tmp` (individual task descriptors)

### Phase A2: Competing Reviews

The command creates **3 blueprint-reviewer tasks** (A2-reviewer-1, A2-reviewer-2, A2-reviewer-3) all blockedBy the A1-plan-arbiter task -- they run in parallel with no dependencies on each other. Each reviewer independently evaluates the plan and writes findings to a unique temp file.

The command also creates an **A2-review-lead** task blockedBy all 3 reviewer tasks. The review-lead reads all 3 competitor output files (specified in its dispatch prompt), deduplicates issues, merges severity (highest wins), applies cross-reference elevation, and produces a consolidated verdict.

**Dependency chain (replaces spawn order):**
- `A2-reviewer-1`, `A2-reviewer-2`, `A2-reviewer-3` -- all blockedBy `[A1-plan-arbiter]` (parallel)
- `A2-review-lead` -- blockedBy `[A2-reviewer-1, A2-reviewer-2, A2-reviewer-3]` (runs after all 3 complete)

Output: `.agents/tmp/phases/loop-{LOOP}/A2-review.json` with `.status: "approved"|"needs_revision"`

### Phase A3: Dual-Track Build

Same as swarm — self-organizing task pool + adversarial review team.

### Phase A4: Verdict

Same as swarm -- evaluated inline by `handle_a3_arbiter()` in the TaskCompleted hook when the review-arbiter task completes. No separate agent dispatch.

### Phase A5: Documentation + Ship

Same as swarm -- nurse then drone, created via `needsA5Tasks` signal flag.

## Task Dependency Contract

All dispatch coordination uses **blockedBy task dependency chains** and **file-based output** (validated by hooks). SendMessage provides a **live coordination overlay** alongside these chains -- agents write files first (source of truth), then send coordination messages for status broadcasts and handoff signals:

| Producer | Consumer | Output File | Dependency Mechanism | Phase |
|----------|----------|-------------|---------------------|-------|
| forager | explore-aggregator | `A0-explore.forager.{N}.tmp` | blockedBy task dependency | A0 |
| cartographer | explore-aggregator | `A0-explore.cartographer.tmp` | blockedBy task dependency | A0 |
| architect {N} | plan-arbiter | `A1-plan.architect.{N}.tmp` | blockedBy task dependency | A1 |
| blueprint-reviewer {N} | review-lead | `A2-review.reviewer.{N}.tmp` | blockedBy task dependency | A2 |
| worker | review-arbiter | worker output files | blockedBy (quality track after build complete) | A3 |
| sentinel-* | review-arbiter | `A3-review.sentinel-*.json` | blockedBy task dependency | A3 |
| guardian | review-arbiter | guardian output | blockedBy task dependency | A3 |
| simplifier | review-arbiter | simplifier output | blockedBy task dependency | A3 |
| nurse | drone | `A5-docs.json` | blockedBy task dependency (A5-drone blockedBy A5-nurse) | A5 |

## Phase-Agent Mapping

| Phase | Stage | Agent(s) | Consolidator? | Description |
|-------|-------|----------|---------------|-------------|
| A0 | EXPLORE | forager x2-3 | No | Breadth-first scouts |
| A0 | EXPLORE | cartographer x1 | No | Deep architecture tracer |
| A0 | EXPLORE | explore-aggregator x1 | Yes | Synthesizes A0 findings (blockedBy foragers + cartographer) |
| A1 | PLAN | architect x3 | No | Competing plan writers (parallel, no deps on each other) |
| A1 | PLAN | plan-arbiter x1 | Yes | Reads competitor files, selects/merges plans (blockedBy all 3 architects) |
| A2 | PLAN | blueprint-reviewer x3 | No | Competing plan reviewers (parallel, no deps on each other) |
| A2 | PLAN | review-lead x1 | Yes | Reads competitor files, consolidates verdicts (blockedBy all 3 reviewers) |
| A3 | BUILD | worker xN (task pool) | No | Task implementers (assigned by TeammateIdle hook) |
| A3 | BUILD | sentinel-correctness x1 | No | Bugs, logic errors |
| A3 | BUILD | sentinel-security x1 | No | OWASP, injection |
| A3 | BUILD | sentinel-perf x1 | No | Performance issues |
| A3 | BUILD | sentinel-style x1 | No | Style, readability |
| A3 | BUILD | guardian x1 | No | Test writer |
| A3 | BUILD | simplifier x1 | No | Code cleanup |
| A3 | BUILD | review-arbiter x1 | Yes | Consolidates sentinel findings (blockedBy all quality agents) |
| A3 | BUILD | review-fixer x0-1 | No | Targeted repairs |
| A4 | SYNC | TaskCompleted hook (inline) | -- | Evaluated inline by handle_a3_arbiter(); no separate agent |
| A5 | SHIP | nurse x1 | No | Documentation updates |
| A5 | SHIP | drone x1 | Yes | Commit + PR (blockedBy nurse) |

## State Schema Additions

sswarm uses the standard v6 schema with these additions:

```json
{
  "pipeline": "sswarm",
  "teamName": "ants-sswarm-<slug>",
  "teammateCount": 5,
  "phaseLeads": {
    "A0": "explore-aggregator",
    "A1": "plan-arbiter",
    "A2": "review-lead",
    "A3": "review-arbiter",
    "A5": "drone"
  }
}
```

The `phaseLeads` map documents which agent serves as the consolidation lead for each phase. This is informational -- hooks do not read it. The task dependency graph (blockedBy chains) ensures consolidators run after all competitors complete. The `teammateCount` is 5 for sswarm (vs 3 for swarm/pswarm) to provide sufficient parallelism for the competing agents.

## Circuit Breaker

Same as swarm — 3-tier circuit breaker with consecutive failures, fix attempts, and stage restarts.

## Phase Output Files

All outputs live under `.agents/tmp/phases/`. Same paths as swarm, with additional architect temp files:

| Phase | File | Written By | Description |
|-------|------|------------|-------------|
| A0 | `A0-explore.md` | explore-aggregator | Unified exploration |
| A1 | `loop-{L}/A1-plan.architect.{1,2,3}.tmp` | architect ×3 | Individual competing plans |
| A1 | `loop-{L}/A1-tasks.architect.{1,2,3}.tmp` | architect ×3 | Individual task descriptors |
| A1 | `loop-{L}/A1-plan.md` | plan-arbiter | Canonical selected/merged plan |
| A1 | `loop-{L}/A1-tasks.json` | plan-arbiter | Canonical task descriptors |
| A2 | `loop-{L}/A2-review.json` | review-lead | Consolidated review verdict |
| A3 | `loop-{L}/A3-build.json` | TaskCompleted hook (aggregated) | Build track results |
| A3 | `loop-{L}/A3-quality.json` | review-arbiter | Quality track verdict |
| A4 | `loop-{L}/A4-queen-verdict.json` | TaskCompleted hook (handle_a3_arbiter) | Ship/loop verdict |
| A5 | `loop-{L}/A5-docs.json` | nurse | Documentation summary |
| A5 | `loop-{L}/A5-ship.json` | drone | Commit/PR output |
