---
name: sswarm
description: Social swarm — orchestrator-driven 6-phase pipeline with competing agents, per-phase lead consolidators, and peer-to-peer SendMessage coordination
---

# Social Swarm Pipeline

Orchestrator-driven 6-phase development pipeline with **competing parallel agents** and **per-phase lead consolidators**. The orchestrator dispatches `ants:*` agents via the Agent tool. Phases A1 and A2 feature multiple competing agents whose outputs are consolidated by dedicated lead agents (plan-arbiter, review-lead) via SendMessage.

## Key Architecture

- `pipeline: "sswarm"` in state.json
- `plugin: "ants"` — so ants hooks fire
- All agents are `ants:*` prefixed — they exist in the ants plugin
- **Orchestrator dispatches agents directly** via the Agent tool for each phase
- A4 (sync/verdict) is evaluated by the orchestrator directly — no separate agent dispatch
- **Lead agents spawned FIRST** (background), then feeder agents in parallel (foreground)
- State schema v5 with additional `phaseLeads` map
- All existing hooks are compatible — no hook changes required

## Key Differences from Swarm

| Feature | swarm | sswarm |
|---------|-------|--------|
| A1 planning | 1 architect | 3 competing architects + plan-arbiter (lead) |
| A2 review | 1 blueprint-reviewer | 3 competing reviewers + review-lead (lead) |
| Lead agents | None | plan-arbiter (A1), review-lead (A2) |
| Agent count per run | ~15 agents | ~21 agents (6 more for competing + leads) |
| A0, A3, A4, A5 | Identical | Identical |
| State schema | v5 | v5 + `phaseLeads` map |
| Hooks | All 8 hooks | Same 8 hooks, unchanged |

## 6-Phase Pipeline

```
Phase A0  │ EXPLORE │ Colony Exploration    │ foragers + cartographer + explore-aggregator (lead)
Phase A1  │ PLAN    │ Competing Architects  │ 3 architects ──→ plan-arbiter (lead)
Phase A2  │ PLAN    │ Competing Reviews     │ 3 blueprint-reviewers ──→ review-lead (lead)
Phase A3  │ BUILD   │ Dual-Track Execution  │ workers (task pool) + 4 sentinels + guardian + simplifier + arbiter
Phase A4  │ SYNC    │ Verdict               │ orchestrator evaluates internally (circuit breaker aware)
Phase A5  │ SHIP    │ Documentation + Ship  │ nurse + drone
```

### Pipeline Diagram

```
         A0 Explore
         foragers + cartographer (parallel)
         explore-aggregator synthesizes -> A0-explore.md
             |
         A1 Competing Architects
         plan-arbiter (lead, background)
         architect ×3 (parallel) ──SendMessage──→ plan-arbiter
         plan-arbiter selects/merges -> A1-plan.md + A1-tasks.json
             |
         A2 Competing Reviews
         review-lead (lead, background)
         blueprint-reviewer ×3 (parallel) ──SendMessage──→ review-lead
         review-lead consolidates -> A2-review.json
             |
    +--------+--------+
    |    Phase A3      |
    |  (dual-track)    |
    |                  |
    | Build Track      | Quality Track (Adversarial)
    | (task pool)      |
    |  workers         | sentinel-correctness  \
    |  dispatched      | sentinel-security      \
    |  by dependency   | sentinel-perf           } parallel
    |  order           | sentinel-style         /
    |       |          | guardian              /
    |  build results   | simplifier           /
    |                  |       |
    |                  | review-arbiter consolidates
    +--------+--------+
             |
         A4 Verdict (orchestrator evaluates, circuit breaker aware)
          /       \
     ship          loop
      |              |
   A5 Ship      A1 (loop back with feedback)
```

## Phase Details

### Phase A0: Colony Exploration

Same as swarm — foragers + cartographer + explore-aggregator.

Output: `.agents/tmp/phases/A0-explore.md`

### Phase A1: Competing Architects

The orchestrator spawns a **plan-arbiter** (lead) in the background, then dispatches **3 architect agents** in parallel. Each architect independently explores the context and writes a plan. After completing their plan, each architect sends a summary to the plan-arbiter via SendMessage.

The plan-arbiter evaluates all 3 plans on five criteria (completeness, feasibility, task count, risk, dependency correctness), selects the best plan or synthesizes a merged plan, and writes the canonical output files.

**Spawn order (critical):**
1. `plan-arbiter` — spawned FIRST with `run_in_background: true`
2. `architect` ×3 — spawned in parallel (foreground), each sends to plan-arbiter
3. Wait for architects to complete, then wait for plan-arbiter

Output:
- `.agents/tmp/phases/loop-{LOOP}/A1-plan.md` (canonical, written by plan-arbiter)
- `.agents/tmp/phases/loop-{LOOP}/A1-tasks.json` (canonical, written by plan-arbiter)
- `.agents/tmp/phases/loop-{LOOP}/A1-plan.architect.{1,2,3}.tmp` (individual architect plans)

### Phase A2: Competing Reviews

The orchestrator spawns a **review-lead** (lead) in the background, then dispatches **3 blueprint-reviewer agents** in parallel. Each reviewer independently evaluates the plan. After completing their review, each reviewer sends findings to the review-lead via SendMessage.

The review-lead deduplicates issues, merges severity (highest wins), applies cross-reference elevation, and produces a consolidated verdict.

**Spawn order (critical):**
1. `review-lead` — spawned FIRST with `run_in_background: true`
2. `blueprint-reviewer` ×3 — spawned in parallel (foreground), each sends to review-lead
3. Wait for reviewers to complete, then wait for review-lead

Output: `.agents/tmp/phases/loop-{LOOP}/A2-review.json` with `.status: "approved"|"needs_revision"`

### Phase A3: Dual-Track Build

Same as swarm — self-organizing task pool + adversarial review team.

### Phase A4: Verdict

Same as swarm — orchestrator evaluates directly.

### Phase A5: Documentation + Ship

Same as swarm — nurse then drone.

## SendMessage Routing Contract

| Sender | Recipient | Payload | Phase |
|--------|-----------|---------|-------|
| forager | explore-aggregator | exploration findings | A0 |
| cartographer | explore-aggregator | architecture trace | A0 |
| architect | plan-arbiter | `{planPath, tasksPath, approach, tradeoffs}` | A1 |
| blueprint-reviewer | review-lead | `{status, issues[], severity, dependencySummary}` | A2 |
| worker | review-arbiter | `{taskId, status, filesModified}` | A3 |
| sentinel-* | review-arbiter | findings JSON | A3 |
| guardian | review-arbiter | `{testsWritten, testResults}` | A3 |
| simplifier | review-arbiter | `{filesSimplified, changesApplied}` | A3 |
| review-fixer | review-arbiter | `{issuesFixed, filesModified}` | A3 |
| nurse | drone | `{docsUpdated, summary}` | A5 |

## Phase-Agent Mapping

| Phase | Stage | Agent(s) | Lead? | Description |
|-------|-------|----------|-------|-------------|
| A0 | EXPLORE | forager ×2-3 | No | Breadth-first scouts |
| A0 | EXPLORE | cartographer ×1 | No | Deep architecture tracer |
| A0 | EXPLORE | explore-aggregator ×1 | Yes | Synthesizes A0 findings |
| A1 | PLAN | architect ×3 | No | Competing plan writers |
| A1 | PLAN | plan-arbiter ×1 | Yes | Evaluates + selects/merges plans |
| A2 | PLAN | blueprint-reviewer ×3 | No | Competing plan reviewers |
| A2 | PLAN | review-lead ×1 | Yes | Consolidates review verdicts |
| A3 | BUILD | worker ×N (task pool) | No | Task implementers |
| A3 | BUILD | sentinel-correctness ×1 | No | Bugs, logic errors |
| A3 | BUILD | sentinel-security ×1 | No | OWASP, injection |
| A3 | BUILD | sentinel-perf ×1 | No | Performance issues |
| A3 | BUILD | sentinel-style ×1 | No | Style, readability |
| A3 | BUILD | guardian ×1 | No | Test writer |
| A3 | BUILD | simplifier ×1 | No | Code cleanup |
| A3 | BUILD | review-arbiter ×1 | Yes | Consolidates sentinel findings |
| A3 | BUILD | review-fixer ×0-1 | No | Targeted repairs |
| A5 | SHIP | nurse ×1 | No | Documentation updates |
| A5 | SHIP | drone ×1 | Yes | Commit + PR |

## State Schema Additions

sswarm uses the standard v5 schema with these additions:

```json
{
  "pipeline": "sswarm",
  "teamName": "ants-sswarm-<slug>",
  "phaseLeads": {
    "A0": "explore-aggregator",
    "A1": "plan-arbiter",
    "A2": "review-lead",
    "A3": "review-arbiter",
    "A5": "drone"
  }
}
```

The `phaseLeads` map documents which agent serves as the consolidation lead for each phase. This is informational — hooks do not read it. The orchestrator uses it for dispatch ordering (lead first, then feeders).

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
| A3 | `loop-{L}/A3-build.json` | orchestrator | Build track results |
| A3 | `loop-{L}/A3-quality.json` | review-arbiter | Quality track verdict |
| A4 | `loop-{L}/A4-queen-verdict.json` | orchestrator | Ship/loop verdict |
| A5 | `loop-{L}/A5-docs.json` | nurse | Documentation summary |
| A5 | `loop-{L}/A5-ship.json` | drone | Commit/PR output |
