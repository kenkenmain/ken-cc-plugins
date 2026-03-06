---
name: swarm
description: Ant-colony themed 6-phase swarm pipeline with dual-track parallel build and quality execution
---

# Swarm Pipeline

Ant-colony themed 6-phase development pipeline with dual-track parallel execution. Uses **ants plugin agents** (self-contained) driven by **ants plugin hooks** (Ralph-style loop driver). No Codex MCP dependency.

## Key Architecture

- `pipeline: "swarm"` in state.json
- `plugin: "ants"` -- so ants hooks fire
- Other plugins' hooks silently exit (they check `plugin` field in state.json)
- All agents are `ants:*` prefixed -- they exist in the ants plugin

## 6-Phase Pipeline

```
Phase A0  | EXPLORE   | Colony Exploration     | dispatch  -> foragers + cartographer + aggregator
Phase A1  | PLAN      | Architect Plan         | subagent  -> architect
Phase A2  | PLAN      | Blueprint Review       | subagent  -> blueprint-reviewer
Phase A3  | BUILD     | Dual-Track Execution   | dispatch  -> workers (build) + sentinels (quality)
Phase A4  | SYNC      | Queen Synchronization  | subagent  -> queen
Phase A5  | SHIP      | Documentation + Ship   | subagent  -> nurse + drone
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
    | Build Track      | Quality Track
    | (workers)        | (sentinels)
    |  Wave 1 ------> |  sentinel reviews
    |  Wave 2 ------> |  per-wave quality
    +--------+--------+
             |
         A4 Queen Sync
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

Single `ants:architect` agent (sonnet) explores the codebase (using A0 context if available) and writes a structured implementation plan with wave assignments for dual-track execution.

On loop 2+, the architect reads the previous loop's review outputs and plans targeted fixes rather than re-planning from scratch.

Output: `.agents/tmp/phases/loop-{LOOP}/A1-plan.md`

Must contain:
- Summary and chosen approach
- Task table with columns: ID, Description, Files, Wave, Complexity, Dependencies, Acceptance Criteria
- Wave summary (Wave 1 foundation tasks, Wave 2 dependent tasks)

### Phase A2: Blueprint Review

Single `ants:blueprint-reviewer` agent (sonnet) validates the architect's plan for completeness, feasibility, wave correctness, and risk.

Output: JSON with `status: "approved" | "needs_revision"`

If `needs_revision` with HIGH issues: loop back to A1 for the architect to revise. If `approved`: proceed to A3.

### Phase A3: Dual-Track Execution

The core differentiator. Two parallel tracks execute simultaneously:

#### Build Track (workers)

Workers are dispatched in **waves** according to the architect's plan:

1. **Wave 1** -- Foundation tasks with no cross-task dependencies. Multiple workers dispatch in parallel, one per task.
2. **Wave 1 completion barrier** -- All Wave 1 workers must complete before Wave 2 starts.
3. **Wave 2** -- Dependent tasks that build on Wave 1 outputs. Multiple workers dispatch in parallel.

Each worker:
- Implements exactly one task from the plan
- Self-verifies (tests, lint, typecheck)
- Outputs structured JSON with status, files modified, tests written
- Has git blocked by hook (no commits)
- Has a Stop gate (prompt-based hard validation)

#### Quality Track (sentinels)

Sentinel review agents run **per wave**, reviewing the output of each wave as it completes:

- After Wave 1 completes: sentinels review Wave 1 implementation
- After Wave 2 completes: sentinels review Wave 2 implementation

Sentinels check:
- Code correctness and adherence to acceptance criteria
- Integration risks between tasks
- Test coverage gaps
- Issue severity classification (critical, warning, info)

#### Wave Synchronization

```
Build Track              Quality Track
-----------              -------------
Wave 1 workers (parallel)
    |
    +-- barrier ----------> Sentinels review Wave 1
    |                           |
Wave 2 workers (parallel)       |
    |                           |
    +-- barrier ----------> Sentinels review Wave 2
    |                           |
    +-- both tracks --------+---+
             |
          Phase A4
```

Build track output: `.agents/tmp/phases/loop-{LOOP}/A3-build.json`
Quality track output: `.agents/tmp/phases/loop-{LOOP}/A3-quality.json`

### Phase A4: Queen Synchronization

Single `ants:queen` agent (sonnet, read-only) merges results from both tracks and renders a verdict:

- **clean**: Quality track clean (or info-only issues) AND build track completed successfully
- **issues_found**: Any critical or warning issue unresolved, OR build track incomplete

The queen cross-references quality issues against the build implementation to determine which issues are actually still valid.

Output: `.agents/tmp/phases/loop-{LOOP}/A4-queen-verdict.json`

### Phase A5: Documentation + Ship

Two sub-steps:

1. **Nurse** (sonnet): Updates project documentation to reflect implementation changes (README.md, CLAUDE.md, etc.)
2. **Drone**: Commits changes and opens a PR

Nurse output: `.agents/tmp/phases/loop-{LOOP}/A5-docs.json`
Drone output: `.agents/tmp/phases/loop-{LOOP}/A5-ship.json`

## Loop-Back Logic

The queen's verdict drives progression:

```
A4 verdict == "clean"         -->  Advance to A5 (ship)
A4 verdict == "issues_found"  -->  Return to A1 (re-plan fixes)
```

### Loop Limits

- **Maximum loops:** 5 (configurable via `state.maxLoops`)
- **Loop counter:** `state.loop` (starts at 1)
- On each loop-back, `loop` increments
- If `loop > maxLoops`: workflow blocks, requires user intervention

### Loop Context

On loop 2+:
- A1 architect reads previous loop's A3-quality.json and A4-queen-verdict.json
- Architect plans **targeted fixes**, not full re-plans
- Previous loop's files are preserved in `loop-{N}/` directories

## State Schema

```json
{
  "version": 1,
  "plugin": "ants",
  "pipeline": "swarm",
  "status": "in_progress|blocked|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID if available>",
  "currentPhase": "A0|A1|A2|A3|A4|A5|DONE|STOPPED",
  "loop": 1,
  "maxLoops": 5,
  "webSearch": true,
  "startedAt": "ISO timestamp",
  "schedule": [
    {"phase": "A0", "stage": "EXPLORE", "label": "Colony Exploration", "type": "dispatch"},
    {"phase": "A1", "stage": "PLAN", "label": "Architect Plan", "type": "subagent"},
    {"phase": "A2", "stage": "PLAN", "label": "Blueprint Review", "type": "subagent"},
    {"phase": "A3", "stage": "BUILD", "label": "Dual-Track Execution", "type": "dispatch"},
    {"phase": "A4", "stage": "SYNC", "label": "Queen Synchronization", "type": "subagent"},
    {"phase": "A5", "stage": "SHIP", "label": "Documentation + Ship", "type": "subagent"}
  ],
  "stages": {
    "EXPLORE": {"status": "pending", "phases": ["A0"]},
    "PLAN": {"status": "pending", "phases": ["A1", "A2"]},
    "BUILD": {"status": "pending", "phases": ["A3"]},
    "SYNC": {"status": "pending", "phases": ["A4"]},
    "SHIP": {"status": "pending", "phases": ["A5"]}
  },
  "gates": {
    "EXPLORE->PLAN": ["A0-explore.md"],
    "PLAN->BUILD": ["loop-{LOOP}/A1-plan.md", "A2-review approved"],
    "BUILD->SYNC": ["loop-{LOOP}/A3-build.json", "loop-{LOOP}/A3-quality.json"],
    "SYNC->SHIP": ["loop-{LOOP}/A4-queen-verdict.json with verdict=clean"]
  },
  "waves": {
    "current": 0,
    "total": 0,
    "wave1Complete": false,
    "wave2Complete": false
  },
  "failure": null
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
| A2 | `loop-{L}/A2-review.json` | JSON | Blueprint review verdict |
| A3 | `loop-{L}/A3-build.json` | JSON | Build track worker results |
| A3 | `loop-{L}/A3-quality.json` | JSON | Quality track sentinel results |
| A4 | `loop-{L}/A4-queen-verdict.json` | JSON | Queen synchronization verdict |
| A5 | `loop-{L}/A5-docs.json` | JSON | Nurse documentation update summary |
| A5 | `loop-{L}/A5-ship.json` | JSON | Drone commit/PR output |

## Stage Gates

| Gate | Required | Transition |
|------|----------|------------|
| EXPLORE -> PLAN | `A0-explore.md` (soft -- continues if missing) | After Phase A0 |
| PLAN -> BUILD | `loop-{L}/A1-plan.md` + A2 review approved | After Phase A2 |
| BUILD -> SYNC | `loop-{L}/A3-build.json` + `loop-{L}/A3-quality.json` | After Phase A3 |
| SYNC -> SHIP | `loop-{L}/A4-queen-verdict.json` with verdict `clean` | After Phase A4 |

## Difference from Minions

| Aspect | ants:swarm | minions:superlaunch |
|--------|-----------|---------------------|
| Phases | 6 (A0-A5) | 15 (S0-S14) |
| Theme | Ant colony (forager, architect, worker, queen) | Generic minions |
| Key innovation | Dual-track Phase A3 (build + quality in parallel) | Sequential phases with review-fix cycles |
| Loop mechanism | A4 queen verdict -> A1 re-plan (max 5) | Review phases with fix attempts + stage restarts |
| Agents | 11 specialized colony roles | 26+ agents |
| Complexity | Streamlined for medium tasks | Thorough for complex tasks |
