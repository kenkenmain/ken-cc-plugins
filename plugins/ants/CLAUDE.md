# ants Plugin -- Agent Instructions

Ant-colony themed swarm workflow with Agent Teams delegate mode, dual-track parallel build, adversarial quality review, and self-improvement pipeline.

## Plugin Structure

```
plugins/ants/
├── .claude-plugin/plugin.json    # Plugin manifest (name, version)
├── agents/                        # Agent definitions (41 agents)
│   ├── architect.md               # Plan writer with task assignments
│   ├── blueprint-reviewer.md      # Plan validator
│   ├── bug-scout.md               # Parallel bug investigator (debug D0)
│   ├── cartographer.md            # Deep architecture tracer
│   ├── drone.md                   # Commit + PR shipper
│   ├── fix-worker.md              # Implements debug fix with tests (debug D3)
│   ├── forager.md                 # Breadth-first codebase scout
│   ├── guardian.md                # Test writer for quality track
│   ├── nurse.md                   # Documentation updater
│   ├── plan-arbiter.md            # A1 lead: evaluates competing architect plans (sswarm)
│   ├── review-lead.md             # A2 lead: consolidates competing blueprint reviews (sswarm)
│   ├── queen.md                   # Persistent central dispatcher, phase driver, A0→A5 orchestrator
│   ├── review-arbiter.md          # Consolidates adversarial sentinel findings
│   ├── review-fixer.md            # Targeted repair agent for review-fix cycles
│   ├── sentinel.md                # (deprecated) Generic sentinel reviewer -- use specialist sentinels
│   ├── sentinel-correctness.md    # Specialist: bugs, logic errors, error handling
│   ├── sentinel-perf.md           # Specialist: N+1 queries, blocking I/O, complexity
│   ├── sentinel-security.md       # Specialist: OWASP, injection, secrets, access control
│   ├── sentinel-accessibility.md  # Specialist: ARIA, keyboard nav, contrast, screen reader compat
│   ├── sentinel-observability.md  # Specialist: logging, metrics, tracing, alerting gaps
│   ├── sentinel-api-contracts.md  # Specialist: API surface, backward compat, versioning
│   ├── sentinel-data-integrity.md # Specialist: data consistency, validation, persistence correctness
│   ├── brainstormer-pragmatist.md    # Personality brainstormer: ship-fast, reuse existing code
│   ├── brainstormer-perfectionist.md # Personality brainstormer: thorough design, extensibility
│   ├── brainstormer-adversarial.md   # Personality brainstormer: stress-tests assumptions, failure modes
│   ├── brainstorm-lead.md            # A0 sswarm lead: consolidates competing brainstormer proposals
│   ├── architect-conservative.md     # Personality architect: minimal-change, proven patterns
│   ├── architect-bold.md             # Personality architect: ambitious design, greenfield solutions
│   ├── architect-security-first.md   # Personality architect: security-driven design
│   ├── blueprint-reviewer-skeptic.md    # Adversarial reviewer: disputes assumptions, demands evidence
│   ├── blueprint-reviewer-advocate.md   # Adversarial reviewer: constructive, finds what works
│   ├── blueprint-reviewer-pragmatist.md # Adversarial reviewer: implementation-focused, tradeoff-aware
│   ├── worker-defensive.md    # Personality worker: guard clauses, input validation, edge case coverage
│   ├── worker-minimal.md      # Personality worker: minimal changes, smallest possible diff
│   ├── worker-test-first.md   # Personality worker: TDD, tests written before implementation
│   ├── solution-aggregator.md     # Ranks and selects best fix (debug D2)
│   ├── solution-proposer.md       # Proposes one specific fix approach (debug D1)
│   └── worker.md                  # Task implementer (one per task)
├── commands/                      # Slash commands (5 commands: swarm, sswarm, pswarm, debug, improve)
│   ├── debug.md                   # /ants:debug <bug description>
│   ├── improve.md                 # /ants:improve <description>
│   ├── sswarm.md                  # /ants:sswarm <task> (social swarm with competing agents)
│   ├── swarm.md                   # /ants:swarm <task>
│   └── pswarm.md                  # /ants:pswarm <task> [--max-loops N] [--worktree]
├── docs/                          # Architecture documentation
│   └── teams-migration.md         # Agent Teams API migration guide
├── hooks/                         # Shell hooks (Agent Teams delegate mode)
│   ├── hooks.json                 # Hook event configuration (8 hooks)
│   ├── on-teammate-idle.sh        # TeammateIdle: task router (assigns next ready phase)
│   ├── on-task-completed.sh       # TaskCompleted: quality gate (validates output, advances state)
│   ├── on-stop.sh                 # Stop: allows lead to stop (teammates continue)
│   ├── on-subagent-stop.sh        # SubagentStop: no-op (exit 0)
│   ├── on-edit-gate.sh            # PreToolUse (Edit/Write): edit control
│   ├── on-post-edit-lint.sh       # PostToolUse (Edit/Write): lint-on-save advisory
│   ├── on-subagent-start.sh       # SubagentStart: injects workflow context
│   ├── on-config-change.sh        # ConfigChange: snapshots config changes
│   ├── on-pre-compact.sh          # PreCompact: saves metadata before compaction
│   └── lib/
│       ├── state.sh               # Shared bash state helpers
│       ├── swarm.sh               # Pipeline-specific phase routing
│       ├── dag.sh                 # Phase-level DAG status tracker
│       ├── circuit-breaker.sh     # Fix-budget and consecutive failure tracking
│       ├── task-pool.sh           # Self-organizing task pool for A3
│       ├── teams.sh               # Agent Teams dispatch layer (task creation, prompts)
│       ├── webhook.sh             # Fire-and-forget HTTP webhook notifications
│       └── lint.sh                # Language-aware lint runner abstraction
├── prompts/                       # Phase prompt templates
│   ├── A0-explore.md              # Colony exploration dispatch
│   ├── A1-plan.md                 # Architect plan dispatch
│   ├── A2-review.md               # Blueprint review dispatch
│   ├── A3-build.md                # Dual-track build dispatch
│   ├── A4-sync.md                 # Queen synchronization dispatch
│   └── A5-ship.md                 # Documentation + ship dispatch
├── skills/                        # Workflow documentation
│   ├── debug/SKILL.md             # Debug pipeline reference
│   ├── improve/SKILL.md           # Improve pipeline reference
│   ├── sswarm/SKILL.md            # Social swarm pipeline reference
│   ├── swarm/SKILL.md             # Swarm pipeline reference
│   └── workflow/SKILL.md          # Agent Teams delegate mode
├── CLAUDE.md                      # This file -- architecture docs
└── README.md                      # User-facing documentation
```

## Agent Roster

| # | Agent | Role | Model | Tools | Leaf? |
|---|-------|------|-------|-------|-------|
| 1 | architect | Plans implementation with task assignments | sonnet | Read, Glob, Grep, WebSearch, Write, SendMessage | Yes |
| 2 | blueprint-reviewer | Validates plan completeness and task correctness | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 3 | bug-scout | Parallel bug investigator (debug D0) | haiku | Read, Glob, Grep, Write, Bash | Yes |
| 4 | cartographer | Deep architecture tracer | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 5 | drone | Commits changes and opens PR | inherit | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 6 | explore-aggregator | Synthesizes A0 forager+cartographer results into A0-explore.md | sonnet | Read, Write, SendMessage | Yes |
| 7 | fix-worker | Implements debug fix with tests (debug D3) | inherit | Read, Grep, Glob, Edit, Write, Bash | Yes |
| 8 | forager | Breadth-first codebase scout | haiku | Read, Glob, Grep, Write, WebSearch, SendMessage | Yes |
| 9 | guardian | Test writer and runner for quality track | sonnet | Read, Write, Edit, Bash, Glob, Grep, WebSearch, SendMessage | Yes |
| 10 | nurse | Updates documentation after implementation | sonnet | Read, Write, Edit, Glob, Grep, SendMessage | Yes |
| 11 | plan-arbiter | A1 lead: evaluates competing architect plans, selects/merges best (sswarm) | sonnet | Read, Write, Glob, Grep, SendMessage | Yes |
| 12 | queen | Persistent central dispatcher, phase driver, A0→A5 orchestrator | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 13 | review-arbiter | Consolidates adversarial sentinel findings | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 14 | review-fixer | Targeted repair for review-fix cycles | inherit | Read, Edit, Write, Glob, Grep, SendMessage | Yes |
| 15 | review-lead | A2 lead: consolidates competing blueprint review verdicts (sswarm) | sonnet | Read, Write, Glob, Grep, SendMessage | Yes |
| 16 | sentinel | (deprecated) Generic sentinel reviewer | sonnet | Read, Glob, Grep, Bash | Yes |
| 17 | sentinel-correctness | Specialist: bugs, logic errors, error handling | sonnet | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 18 | sentinel-perf | Specialist: N+1 queries, blocking I/O, complexity | sonnet | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 19 | sentinel-security | Specialist: OWASP, injection, secrets, access control | sonnet | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 20 | sentinel-style | Specialist: code style, readability, maintainability | sonnet | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 21 | sentinel-accessibility | Specialist: ARIA, keyboard nav, contrast, screen reader compat | sonnet | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 22 | sentinel-observability | Specialist: logging, metrics, tracing, alerting gaps | sonnet | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 23 | sentinel-api-contracts | Specialist: API surface, backward compat, versioning | sonnet | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 24 | sentinel-data-integrity | Specialist: data consistency, validation, persistence correctness | sonnet | Read, Glob, Grep, Bash, Write, SendMessage | Yes |
| 25 | simplifier | Post-build code cleanup (dead code, complexity, naming) | sonnet | Read, Edit, Glob, Grep, Bash, SendMessage | Yes |
| 26 | solution-aggregator | Ranks and selects best fix (debug D2) | sonnet | Read, Write, Glob | Yes |
| 27 | solution-proposer | Proposes one specific fix approach (debug D1) | sonnet | Read, Glob, Grep, Write | Yes |
| 28 | worker | Implements a single task from the plan | inherit | Read, Grep, Glob, Edit, Write, Bash, SendMessage | Yes |
| 29 | brainstormer-pragmatist | A0 sswarm: ship-fast brainstormer, favors reuse and minimal scope | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 30 | brainstormer-perfectionist | A0 sswarm: thoroughness brainstormer, favors complete design and extensibility | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 31 | brainstormer-adversarial | A0 sswarm: stress-test brainstormer, finds failure modes and proposes defensive alternatives | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 32 | brainstorm-lead | A0 sswarm lead: consolidates competing brainstormer proposals, evaluates on 4 criteria | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 33 | architect-conservative | A1 sswarm: minimal-change architect, proven patterns, incremental evolution | sonnet | Read, Glob, Grep, WebSearch, Write, SendMessage | Yes |
| 34 | architect-bold | A1 sswarm: ambitious architect, greenfield solutions, bold design | sonnet | Read, Glob, Grep, WebSearch, Write, SendMessage | Yes |
| 35 | architect-security-first | A1 sswarm: security-driven architect, threat modeling, defense-in-depth | sonnet | Read, Glob, Grep, WebSearch, Write, SendMessage | Yes |
| 36 | blueprint-reviewer-skeptic | A2 sswarm: disputes assumptions, demands evidence, stress-tests feasibility | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 37 | blueprint-reviewer-advocate | A2 sswarm: constructive reviewer, finds what works and amplifies strengths | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 38 | blueprint-reviewer-pragmatist | A2 sswarm: implementation-focused reviewer, tradeoff-aware, practical gaps | sonnet | Read, Glob, Grep, Write, SendMessage | Yes |
| 39 | worker-defensive | A3 personality worker: guard clauses, input validation, edge case coverage | sonnet | Read, Grep, Glob, Edit, Write, Bash, SendMessage | Yes |
| 40 | worker-minimal | A3 personality worker: smallest possible diff, conservative changes | sonnet | Read, Grep, Glob, Edit, Write, Bash, SendMessage | Yes |
| 41 | worker-test-first | A3 personality worker: TDD, tests written before implementation | sonnet | Read, Grep, Glob, Edit, Write, Bash, SendMessage | Yes |
| 42 | (orchestrator) | Agent Teams delegate mode (hooks, not an agent file) | -- | -- | -- |

All agents have `disallowedTools: [Task]` -- no agent can spawn subagents. The orchestrator (command executor) dispatches agents directly via the Agent tool for each phase and drives all phase transitions. Hooks provide supplementary gates (edit control, lint-on-save, config snapshots, compaction) and lifecycle support.

**Sentinel tool design:** Specialist sentinels (rows 17-24) have `Write` to create new output JSON files but exclude `Edit` via `disallowedTools` — sentinels must never modify existing project source files during adversarial review. This is intentional, not a bug.

**Simplifier tool design:** The simplifier (row 21) has `Edit` to apply code cleanup but excludes `Write` via `disallowedTools` — it makes surgical edits to existing files, never full rewrites.

### Deprecated Agents

- **sentinel** -- Replaced by specialist sentinels (sentinel-correctness, sentinel-security, sentinel-perf, sentinel-style, sentinel-accessibility, sentinel-observability, sentinel-api-contracts, sentinel-data-integrity) in v0.2/v0.5.4/v0.5.7. The generic sentinel is retained for backward compatibility with v0.1 state files but should not be dispatched in new workflows.

### WebSearch Strategy

| Agent | Has WebSearch | Activation |
|-------|--------------|------------|
| forager | Yes | Controlled by `webSearch` state flag and dispatch prompt |
| architect | Yes | Controlled by dispatch prompt (`--web` flag) |
| guardian | Yes | Controlled by dispatch prompt |
| All others | No | -- |

WebSearch is opt-in. The `--web` CLI flag sets `webSearch: true` in state.json, which the dispatch prompts use to include or omit WebSearch guidance for eligible agents.

## Pipeline Phases (A0-A5)

```
EXPLORE ──> PLAN ──> BUILD ──────────────> SHIP
  A0        A1,A2     A3                    A5
                       |
                  orchestrator evaluates
                  (A4 internal)
                       |
                   verdict?
                  /        \
               ship       loop ──> back to A1
```

The orchestrator dispatches agents directly via the Agent tool for each phase. A4 (sync/verdict) is not a separate agent dispatch -- it is evaluated directly by the orchestrator after receiving all A3 results.

Three pipeline variants are supported, selected by the `pipeline` field in state.json:

- **`swarm`** -- Single A0→A5 run; workflow completes after A5 ships (command: `/ants:swarm`)
- **`sswarm`** -- Social swarm with competing agents; A1 dispatches 3 architects + plan-arbiter lead, A2 dispatches 3 reviewers + review-lead lead; otherwise same as swarm (command: `/ants:sswarm`)
- **`pswarm`** -- Persistent multi-run loop; after A5 ships, all phases reset to pending and the pipeline restarts from A0 until `pswarmRun >= maxRuns` or `shutdown == true` (command: `/ants:pswarm`)

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| A0 | EXPLORE | forager x2-4, cartographer x1, explore-aggregator x1 | Parallel codebase exploration (explore-aggregator synthesizes results) |
| A1 | PLAN | architect x1 | Structured plan with task assignments |
| A2 | PLAN | blueprint-reviewer x1 | Plan validation |
| A3 | BUILD | worker xN (task pool), sentinel-correctness + sentinel-security + sentinel-perf + sentinel-style + sentinel-accessibility + sentinel-observability + sentinel-api-contracts + sentinel-data-integrity (adversarial review), simplifier x1, review-arbiter x1, guardian x1 | Self-organizing task pool with 8-domain adversarial review and cleanup tracks |
| A4 | SYNC | orchestrator (internal) | Orchestrator evaluates all A3 evidence, renders ship/loop verdict (circuit breaker aware) |
| A5 | SHIP | nurse x1, drone x1 | Documentation update + commit/PR |

## Debug Pipeline (D0-D5)

Stateless 6-phase debugging pipeline dispatched directly by `/ants:debug`. No state.json, no hooks, no Agent Teams -- the command orchestrates all agents synchronously.

```
D0 EXPLORE   — 3× bug-scout (parallel)
D1 PROPOSE   — 3× solution-proposer (parallel)
D2 AGGREGATE — solution-aggregator + user confirmation
D3 IMPLEMENT — fix-worker (implements fix + tests)
D4 REVIEW    — 3× sentinels + review-arbiter
D5 SHIP      — nurse + drone
```

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| D0 | EXPLORE | bug-scout ×3 | Parallel bug investigation (error, execution path, tests) |
| D1 | PROPOSE | solution-proposer ×3 | Parallel fix proposals (minimal, comprehensive, defensive) |
| D2 | AGGREGATE | solution-aggregator ×1 | Rank proposals + user selects |
| D3 | IMPLEMENT | fix-worker ×1 | Implement fix, write tests, self-verify |
| D4 | REVIEW | sentinel-correctness + sentinel-security + sentinel-perf + review-arbiter | Adversarial review of fix |
| D5 | SHIP | nurse ×1, drone ×1 | Documentation + commit/PR |

Output files: `.agents/tmp/debug/` (see `skills/debug/SKILL.md` for complete layout).

## Improve Pipeline (I0-I2)

Stateless iterative review-fix pipeline dispatched directly by `/ants:improve`. No state.json, no hooks, no Agent Teams -- the command orchestrates all agents synchronously, like the debug pipeline.

```
I0 REVIEW    -- 3x sentinels (parallel) + review-arbiter
I1 FIX       -- review-fixer applies targeted fixes
[loop back to I0 if issues remain, up to 5 iterations]
I2 REPORT    -- summary of all iterations
```

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| I0 | REVIEW | sentinel-correctness + sentinel-security + sentinel-perf + review-arbiter | Parallel adversarial review, arbiter consolidates |
| I1 | FIX | review-fixer x1 | Applies targeted fixes for all issues (info severity and above) |
| I2 | REPORT | (orchestrator) | Displays iteration-by-iteration summary |

**Key differences from swarm pipeline:**
- Fixes ALL severities (info, warning, critical) -- not just critical/warning
- No exploration, planning, building, or shipping phases -- purely review and fix
- Stateless with iteration limit (max 5) instead of circuit breaker
- No state.json -- iteration progress tracked in command conversation context

**Key differences from debug pipeline:**
- Iterative loop (review-fix-review) vs single-pass (investigate-fix-ship)
- No exploration or proposal phases -- goes straight to review
- Does not ship (no commit, no PR) -- user decides what to do after

Output files: `.agents/tmp/improve/` with per-iteration subdirectories (`iter-1/`, `iter-2/`, etc.). Each iteration produces `I0-quality.json` (arbiter verdict) and `I1-fix.json` (fixer output, if issues found). The arbiter captures all severities by default -- no threshold override needed. See `skills/improve/SKILL.md` for complete layout.

## Social Swarm Pipeline (sswarm)

The sswarm (social swarm) pipeline extends swarm with **competing parallel agents** and **per-phase lead consolidators**. Phases A0, A1, and A2 dispatch multiple personality agents whose outputs are consolidated by dedicated leads via SendMessage:

| Phase | swarm | sswarm |
|-------|-------|--------|
| A0 | foragers + cartographer + aggregator | Same + 3 competing brainstormers + brainstorm-lead |
| A1 | 1 architect | 3 personality architects (conservative, bold, security-first) + plan-arbiter (lead) |
| A2 | 1 blueprint-reviewer | 3 adversarial reviewers (skeptic, advocate, pragmatist) + review-lead (lead) |
| A3 | workers + sentinels + guardian + simplifier | Same |
| A4 | orchestrator verdict | Same |
| A5 | nurse + drone | Same |

**Lead spawn order (critical):** Lead agents must be spawned FIRST with `run_in_background: true`, then feeder agents in parallel (foreground). This ensures leads are alive to receive SendMessage from feeders.

**Personality architects (A1):** Each architect has a distinct planning philosophy — conservative (minimal change, proven patterns), bold (ambitious design, greenfield solutions), security-first (threat modeling, defense-in-depth). The plan-arbiter evaluates all three plans and selects or synthesizes the best.

**Adversarial blueprint reviewers (A2):** Each reviewer approaches validation from a different angle — skeptic (disputes assumptions, demands evidence), advocate (constructive, amplifies strengths), pragmatist (implementation-focused, tradeoff-aware). The review-lead consolidates their findings into a single A2-review.json verdict.

**Brainstorm personalities (A0 sswarm):** Three brainstormers — pragmatist (ship-fast, reuse), perfectionist (thorough design, extensibility), adversarial (stress-tests assumptions, failure modes) — propose competing approaches. The brainstorm-lead evaluates on 4 criteria (feasibility, scope, codebase alignment, risk) and writes the canonical A0-brainstorm.md.

**State additions:** `pipeline: "sswarm"`, `phaseLeads` map, `teamName: "ants-sswarm-<slug>"`.

**Hook compatibility:** All 8 hooks work unchanged with sswarm. Hooks check `plugin: "ants"` and `currentPhase` (A0-A5) but not `pipeline` for routing (except on-stop.sh which only special-cases pswarm).

## Dual-Track Build + Quality Design

Phase A3 is the core innovation. Two tracks run in coordinated execution:

**Build Track:** Workers claim tasks from a self-organizing task pool. Tasks with no dependencies start as "ready"; as tasks complete, dependent tasks become ready automatically. This replaces the rigid wave-based dispatch from v0.1.

**Quality Track (Adversarial Review + Cleanup):** After all workers complete (pool drained), ten agents run in parallel:
- **sentinel-correctness** -- bugs, logic errors, missing error handling, race conditions
- **sentinel-security** -- OWASP top 10, injection, authentication, secrets exposure
- **sentinel-perf** -- N+1 queries, blocking I/O, unnecessary allocations, algorithmic complexity
- **sentinel-style** -- code style, readability, maintainability (excessive nesting, magic numbers, dead code)
- **sentinel-accessibility** -- ARIA attributes, keyboard navigation, color contrast, screen reader compatibility
- **sentinel-observability** -- logging gaps, missing metrics, trace coverage, alerting blindspots
- **sentinel-api-contracts** -- API surface changes, backward compatibility, versioning violations
- **sentinel-data-integrity** -- data consistency, validation gaps, persistence correctness
- **guardian** -- writes and runs tests for the implemented code
- **simplifier** -- applies targeted code cleanup without behavioral changes (dead code removal, complexity reduction)

After all ten complete, the **review-arbiter** cross-references sentinel findings from all 8 domains, deduplicates overlapping issues, resolves conflicts, and produces a single consolidated verdict (A3-quality.json). If the review-arbiter identifies critical issues, a **review-fixer** is dispatched to apply targeted repairs before the quality verdict is finalized.

**Task Pool Synchronization:** Workers in the pool run in parallel when their dependencies are satisfied. After all workers complete (pool drained), the adversarial review team runs. This replaces the wave barrier model with dependency-driven dispatch.

**Fallback:** If no `taskPool` exists in state (v0.1 state files), A3 falls back to legacy wave-based dispatch with the generic sentinel.

## Circuit Breaker

The circuit breaker prevents infinite failure loops by tracking:

- **Consecutive failures** -- Trips after 5 consecutive failures (configurable via `circuitBreaker.maxConsecutiveFailures`)
- **Fix attempts** -- Per-phase budget of 5 attempts (configurable via `circuitBreaker.maxFixAttempts`)
- **Stage restarts** -- Maximum 2 loop-backs from A4 to A1 (configurable via `circuitBreaker.maxStageRestarts`)

When the circuit breaker trips, the workflow halts with status `blocked` and requires user intervention. Success resets the consecutive failure counter.

Library: `hooks/lib/circuit-breaker.sh`

## Agent Teams Helpers

In v0.5.x the orchestrator drives all phase transitions directly via the Agent tool. The `hooks/lib/teams.sh` library provides hooks and helpers for this orchestrator-driven pipeline (the original Agent Teams delegate mode functions are retained as legacy stubs):

- `teams_create_phase_tasks()` -- Creates TaskCreate entries for A0→A5 with dependency chains
- `teams_add_a3_subtasks()` -- Dynamically adds worker/sentinel/simplifier/arbiter tasks after A1 (sentinel_names array includes all 8 sentinels; arbiter blockedBy includes all 8 sentinels + guardian + simplifier)
- `teams_get_next_ready_task()` -- Reads state.json, returns next dispatchable phase
- `teams_build_teammate_prompt()` -- Generates direct execution prompts for teammates
- `teams_assign_idle_teammate()` -- Builds exit-2 output for TeammateIdle hook
- `teams_reject_completion()` -- Builds exit-2 output for TaskCompleted rejection

The swarm command uses ToolSearch to load Agent Teams tools (TaskCreate, TaskGet, TaskList, TaskUpdate, TaskStop) before creating the team.

## Hook Architecture

Eight hooks support the workflow. The orchestrator drives all phase transitions by dispatching agents via the Agent tool. Hooks provide supplementary gates (edit control, lint-on-save, config snapshots, compaction) and lifecycle support:

### on-teammate-idle.sh (TeammateIdle event)

- Checks circuit breaker (if tripped → allows idle, workflow blocks)
- Reads `state.json` to find next ready phase via `teams_get_next_ready_task()`
- Generates phase-specific teammate execution prompt via `teams_build_teammate_prompt()`
- Returns exit 2 with prompt to keep teammate working
- Returns exit 0 if no tasks ready (workflow complete/blocked/waiting)

### on-task-completed.sh (TaskCompleted event)

- Validates output file exists and is valid JSON
- Phase-specific quality gates:
  - A0: A0-explore.md exists → advance to A1
  - A1: A1-plan.md exists → advance to A2 (checks A1-tasks.json for A3 sub-tasks)
  - A2: Review verdict — needs_revision with HIGH → loop to A1; else → A3. `.status` is the sole canonical verdict field in A2-review.json.
  - A3: Workers update task pool, 8 sentinels write domain-specific markers, arbiter consolidates
  - A4: Parse queen verdict — clean → A5, issues_found → loop to A1
  - A5: A5-ship.json with commit_sha → workflow DONE (swarm) or reset to A0 (pswarm)
- Updates circuit breaker on success/failure
- Exit 0 = accept | Exit 2 = reject with feedback

### on-stop.sh (Stop event)

- Allows lead to stop freely (teammates continue independently)
- No prompt re-injection — Agent Teams handles coordination

### on-edit-gate.sh (PreToolUse: Edit/Write)

- Allows file edits only in BUILD (A3) and SHIP (A5) stages
- Blocks edits during EXPLORE, PLAN, and SYNC stages
- Allows writes to `.agents/` path at all times (state and output files)
- Logs file ownership advisory via task pool (ownership enforced at worker prompt level, not hook level)

### on-subagent-stop.sh (SubagentStop event -- not wired in hooks.json)

- No-op (exit 0) -- retained as safety fallback if SubagentStop fires for internal subagents
- Not configured in hooks.json -- TaskCompleted handles all validation and state advancement

### on-post-edit-lint.sh (PostToolUse: Edit/Write -- v0.4)

- Runs language-aware lint on files after successful edits during A3 (BUILD) and A5 (SHIP) phases
- Non-blocking: provides lint results as informational context only (exit 0 always)
- Skips `.agents/` files and respects `lintConfig.enabled` state flag
- Uses `lint.sh` library for shell (`bash -n`), JSON (`jq empty`), and Python (`py_compile`) linting

### on-subagent-start.sh (SubagentStart event -- v0.4)

- Injects workflow context (phase, loop, status, stage) into subagents via `additionalContext`
- Non-blocking (exit 0 always)
- Ensures teammates are aware of the current workflow state when spawned

### on-config-change.sh (ConfigChange event -- v0.4)

- Detects configuration changes during active workflows
- Updates `configSnapshot` in state.json with timestamp and source
- Defensive: gracefully handles empty or invalid stdin (exit 0 always)

### on-pre-compact.sh (PreCompact event -- v0.4)

- Saves critical workflow metadata before context compaction
- Preserves current phase, loop, status, and task pool summary in `compactMetadata`
- Ensures workflow can resume after compaction by reading preserved metadata
- Non-blocking (exit 0 always)

### hooks.json Configuration

```json
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "on-stop.sh"}]}],
    "TeammateIdle": [{"hooks": [{"type": "command", "command": "on-teammate-idle.sh"}]}],
    "TaskCompleted": [{"hooks": [{"type": "command", "command": "on-task-completed.sh"}]}],
    "PreToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "on-edit-gate.sh"}]}
    ],
    "PostToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "on-post-edit-lint.sh"}]}
    ],
    "SubagentStart": [{"hooks": [{"type": "command", "command": "on-subagent-start.sh"}]}],
    "ConfigChange": [{"hooks": [{"type": "command", "command": "on-config-change.sh"}]}],
    "PreCompact": [{"hooks": [{"type": "command", "command": "on-pre-compact.sh"}]}]
  }
}
```

## State Management

State tracked in `.agents/tmp/state.json`. Shared libraries in `hooks/lib/`:

### state.sh (core)
- `check_ants_workflow()` -- plugin guard, session scoping, status check, auto-migration v1->v5
- `state_get()` -- read fields with optional required validation
- `update_state()` -- atomic state update with file locking (flock with mkdir fallback on macOS)
- `validate_json_file()` -- check file exists and contains valid JSON
- `require_int()` -- validate integer fields
- `continue_false_exit()` -- emit `{"continue": false, "stopReason": ...}` JSON and exit 0
- `shutdown_check()` -- check shutdown flag and halt gracefully if set
- `add_message()` -- add cross-phase message to state.json messages array
- `get_messages_for()` -- retrieve messages targeted at a specific recipient

### dag.sh (phase tracking)
- `reset_phases_for_loop()` -- reset A1-A4 to pending for loop-back
- `reset_phases_for_pswarm()` -- reset A0-A5 to pending for pswarm run boundary

### circuit-breaker.sh (failure tracking)
- `cb_init()` -- initialize circuit breaker fields
- `cb_record_failure()` / `cb_record_success()` -- track consecutive outcomes
- `cb_is_tripped()` -- check if breaker is tripped
- `cb_increment_fix_attempts()` -- per-phase fix budget
- `cb_increment_stage_restarts()` -- loop-back budget
- `cb_reset_for_run()` -- reset all circuit breaker counters at pswarm run boundary

### task-pool.sh (A3 task dispatch)
- `pool_init()` -- initialize pool from architect's A1-tasks.json
- `pool_claim_task()` -- atomically claim next available task (mkdir lock)
- `pool_complete_task()` / `pool_fail_task()` -- update task status
- `pool_recompute_ready()` -- promote pending tasks whose deps are complete
- `pool_get_file_owner()` -- file ownership enforcement for edit gate

### teams.sh (Agent Teams dispatch)
- `teams_create_phase_tasks()` -- creates TaskCreate entries for A0→A5 dependency chain
- `teams_add_a3_subtasks()` -- dynamically adds worker/sentinel/arbiter tasks after A1
- `teams_get_next_ready_task()` -- finds next dispatchable phase from state
- `teams_build_teammate_prompt()` -- generates execution prompts for teammates
- `teams_assign_idle_teammate()` / `teams_reject_completion()` -- exit-2 handlers

### webhook.sh (HTTP notifications -- v0.4)
- `webhook_fire()` -- fire-and-forget HTTP POST to configured webhook URL (background curl)
- `webhook_phase_event()` -- send phase lifecycle events (started/completed/failed)
- `webhook_workflow_event()` -- send workflow lifecycle events (completed/blocked/stopped)

### lint.sh (lint runner -- v0.4)
- `lint_file()` -- run language-appropriate linter on a single file (shell, JSON, Python)
- `lint_check_enabled()` -- check if linting is enabled in workflow state
- `lint_format_advisory()` -- format lint result JSON as human-readable string

Session scoping via `ownerPpid` + `sessionId` ensures hooks only fire for the session that owns the workflow.

### Output File Layout

```
.agents/tmp/
├── state.json                           # Workflow state (v5)
├── phases/
│   ├── A0-explore.forager.1.tmp         # Forager results
│   ├── A0-explore.forager.2.tmp
│   ├── A0-explore.cartographer.tmp      # Cartographer results
│   ├── A0-explore.md                    # Aggregated exploration
│   ├── loop-1/
│   │   ├── A1-plan.architect.{1,2,3}.tmp        # Individual architect plans (sswarm only)
│   │   ├── A1-tasks.architect.{1,2,3}.tmp        # Individual task descriptors (sswarm only)
│   │   ├── A1-plan.md                   # Canonical architect plan (plan-arbiter in sswarm, architect in swarm)
│   │   ├── A1-tasks.json                # Task descriptors for task pool
│   │   ├── A2-review.json              # Blueprint review (review-lead in sswarm, blueprint-reviewer in swarm)
│   │   ├── A3-build.json              # Worker results
│   │   ├── A3-review.sentinel-correctness.json  # Correctness review
│   │   ├── A3-review.sentinel-security.json     # Security review
│   │   ├── A3-review.sentinel-perf.json         # Performance review
│   │   ├── A3-review.sentinel-style.json        # Style review
│   │   ├── A3-quality.json            # Arbiter consolidated verdict
│   │   ├── A4-queen-verdict.json     # Queen verdict
│   │   ├── A5-docs.json              # Nurse documentation summary
│   │   └── A5-ship.json              # Drone commit/PR output
│   ├── loop-2/                        # If looped back
│   │   └── ...
```

## State Schema (v5)

```json
{
  "version": 5,
  "plugin": "ants",
  "pipeline": "swarm|sswarm|pswarm",
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
  "webSearch": false,
  "queenDispatched": false
}
```

### New v0.4 State Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `worktreePath` | string/null | null | Absolute path to git worktree if workflow uses worktree isolation |
| `messages` | array | [] | Cross-phase messages for teammate communication (`add_message()` / `get_messages_for()`) |
| `planApproved` | boolean | false | Whether the architect's plan has been approved (A1 gate) |
| `shutdown` | boolean | false | Graceful shutdown flag -- when true, `shutdown_check()` stops the workflow |
| `webhookUrl` | string/null | null | HTTP endpoint for fire-and-forget webhook notifications |
| `lintConfig` | object/null | null | Lint configuration (`{"enabled": true/false}`) for PostToolUse lint-on-save |
| `configSnapshot` | object/null | null | Last config change metadata (`{"lastChangeAt": ..., "source": ...}`) |
| `compactMetadata` | object/null | null | Workflow state snapshot saved before context compaction |
| `queenDispatched` | boolean | false | Whether the queen has been spawned for the current workflow run (prevents duplicate dispatches) |

### New v0.4.3 State Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `webSearch` | boolean | false | When true, forager agents receive guidance to use WebSearch for external library/API research during A0 exploration and A1 planning |

### New v0.4.2 State Fields (pswarm)

These fields are present only when `pipeline == "pswarm"`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `pswarmRun` | number | 1 | Current full run number; increments after each A5 ship before the next A0 starts |
| `maxRuns` | number | 50 | Maximum full A0→A5 runs allowed (set from `--max-loops N` argument) |

## Graceful Shutdown (v0.4)

Set `.shutdown = true` in state.json to request a graceful shutdown. The `shutdown_check()` function (called by hooks) detects this flag and emits `{"continue": false, "stopReason": "..."}` to halt the workflow cleanly. This allows in-progress phases to complete before stopping, unlike a hard kill.

## Plan Approval (v0.4)

When `.planApproved` is `false` (default), the TaskCompleted hook holds the workflow at A1 after the architect writes the plan. The plan must be reviewed and `.planApproved` set to `true` before the workflow advances to A2 (blueprint review). This prevents premature implementation of poorly-scoped plans.

## Teammate Messaging (v0.4)

Cross-phase communication via the `messages` array in state.json. Agents can send messages to other agents using `add_message "from" "to" "content"` and retrieve them with `get_messages_for "recipient"`. Messages are tagged with the current loop number and timestamp. This enables feedback loops without re-planning (e.g., queen sending targeted notes to the architect for the next loop).

## Communication

The orchestrator dispatches agents directly via the Agent tool for each phase. Agents communicate results via their output files (written to `.agents/tmp/phases/`). The naming contract for output files is documented in the Phase Output Files section of the swarm SKILL.md.

### SendMessage

SendMessage-based communication is used in two pipeline variants:

- **sswarm** — Lead agents (plan-arbiter, review-lead) receive competing outputs from feeder agents (architects, blueprint-reviewers) via SendMessage during A1 and A2. The orchestrator spawns leads first (background), then feeders send results to leads.
- **pswarm** — The `queen` agent drives the pipeline and receives agent results via SendMessage.

In **swarm** mode, the orchestrator drives all phases directly and SendMessage is not required (though agents that support it may use it).

### queenDispatched State Field

The `queenDispatched` field in state.json tracks whether the pipeline has started execution. It is set to `true` when the first phase begins and prevents duplicate pipeline starts.

## Worktree Isolation (v0.4)

When `.worktreePath` is set, the workflow operates in a git worktree at the specified path. This isolates the workflow's file changes from the main branch, enabling multiple workflows to run concurrently on the same repository. Hooks always execute from the main project root directory, not from the worktree. The `worktreePath` field in state.json directs worker agents to read/write files in the isolated worktree directory.

## Lint-on-Save (v0.4)

The PostToolUse hook (`on-post-edit-lint.sh`) runs language-aware linting after every successful Edit/Write during BUILD (A3) and SHIP (A5) phases. Lint results are advisory only (non-blocking). Supported linters: `bash -n` for shell scripts, `jq empty` for JSON, `python3 -m py_compile` for Python. Disable via `.lintConfig.enabled = false` in state.json.

## HTTP Webhooks (v0.4)

Set `.webhookUrl` in state.json to receive fire-and-forget HTTP POST notifications for phase and workflow lifecycle events. The `webhook.sh` library sends all notifications in the background with a 5-second timeout. Events: `phase.started`, `phase.completed`, `phase.failed`, `workflow.completed`, `workflow.blocked`, `workflow.stopped`. If no URL is configured, all webhook calls are silent no-ops.

## Code Style

- **Markdown:** YAML frontmatter, follow existing agent structure
- **Naming:** kebab-case for files (e.g., `blueprint-reviewer.md`, `sentinel-correctness.md`)
- **Agent theme:** Ant colony roles (forager, cartographer, architect, worker, sentinel, queen, nurse, drone)
- **Shell hooks:** `set -euo pipefail`, use `local var; var="$(cmd)"` (not `local var="$(cmd)"`), source libs from `$SCRIPT_DIR/lib/`
- **Shell validation:** Run `bash -n <script>` after modifying hook shell scripts
- **Prompt gates:** Use XML-tag gates in command templates for mechanical enforcement. Two gate types: `<HARD-GATE>` blocks skill/brainstorm invocation and forces immediate pipeline execution; `<COMPLETION-GATE>` blocks premature termination and forces termination-condition checks. Do not invent new gate names without documenting them here.
- **Git commits:** Prefix with `feat|fix|docs|chore|ci`, include co-author line
- **Git excludes:** Never commit `.agents/**`, `*.tmp`, `*.log`

## Boundaries

### Always

- Update state.json after each phase completes
- Follow phase progression (A0 -> A1 -> A2 -> A3 -> A4 -> A5)
- Respect stage gates before advancing
- Validate output files before marking phases complete
- Use `disallowedTools: [Task]` on all leaf agents
- Block git commands in worker agents
- Bump plugin.json version on changes
- Check circuit breaker before retrying or looping back

### Ask First

- Skipping phases (A0 can be skipped, others require confirmation)
- Changing maxLoops mid-workflow
- Modifying state.json schema
- Adding new agents to the roster
- Changing task pool dispatch strategy

### Never

- Skip A4 queen verdict -- always sync before shipping
- Ship when critical or warning issues remain unresolved
- Allow agents to spawn subagents (all are leaf agents)
- Commit secrets or credentials
- Modify files during EXPLORE, PLAN, or SYNC stages (enforced by edit gate)
- Proceed past maxLoops without user approval
- Ignore circuit breaker trips -- always halt and surface to user
