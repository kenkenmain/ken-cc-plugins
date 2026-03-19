# ants Plugin -- Agent Instructions

Ant-colony themed swarm workflow with Agent Teams delegate mode (Command-as-Active-Lead), dual-track parallel build, adversarial quality review, and self-improvement pipeline. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Plugin Structure

```
plugins/ants/
├── .claude-plugin/plugin.json    # Plugin manifest (name, version)
├── agents/                        # Agent definitions (24 agents)
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
│   ├── queen.md                   # A4 verdict evaluator / team lead initializer
│   ├── review-arbiter.md          # Consolidates adversarial sentinel findings
│   ├── review-fixer.md            # Targeted repair agent for review-fix cycles
│   ├── sentinel.md                # (deprecated) Generic sentinel reviewer -- use specialist sentinels
│   ├── sentinel-correctness.md    # Specialist: bugs, logic errors, error handling
│   ├── sentinel-perf.md           # Specialist: N+1 queries, blocking I/O, complexity
│   ├── sentinel-security.md       # Specialist: OWASP, injection, secrets, access control
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
│   ├── on-teammate-idle.sh        # TeammateIdle: full task router (assigns next ready phase/task)
│   ├── on-task-completed.sh       # TaskCompleted: quality gate + state advancement (validates output, advances state, sets signal flags)
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

## Environment Requirement

The swarm, sswarm, and pswarm pipelines require the Agent Teams experimental flag:

```
CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

Commands check this env var as Step 0 and abort with a clear error message if it is not set. The debug and improve pipelines do NOT require this flag (they are stateless, direct-dispatch pipelines).

## Agent Roster

| # | Agent | Role | Model | Tools | Leaf? |
|---|-------|------|-------|-------|-------|
| 1 | architect | Plans implementation with task assignments | sonnet | Read, Glob, Grep, WebSearch, Write | Yes |
| 2 | blueprint-reviewer | Validates plan completeness and task correctness | sonnet | Read, Glob, Grep, Write | Yes |
| 3 | bug-scout | Parallel bug investigator (debug D0) | haiku | Read, Glob, Grep, Write, Bash | Yes |
| 4 | cartographer | Deep architecture tracer | sonnet | Read, Glob, Grep, Write | Yes |
| 5 | drone | Commits changes and opens PR | inherit | Read, Glob, Grep, Bash, Write | Yes |
| 6 | explore-aggregator | Synthesizes A0 forager+cartographer results into A0-explore.md | sonnet | Read, Write | Yes |
| 7 | fix-worker | Implements debug fix with tests (debug D3) | inherit | Read, Grep, Glob, Edit, Write, Bash | Yes |
| 8 | forager | Breadth-first codebase scout | haiku | Read, Glob, Grep, Write, WebSearch | Yes |
| 9 | guardian | Test writer and runner for quality track | sonnet | Read, Write, Edit, Bash, Glob, Grep, WebSearch | Yes |
| 10 | nurse | Updates documentation after implementation | sonnet | Read, Write, Edit, Glob, Grep | Yes |
| 11 | plan-arbiter | A1 lead: evaluates competing architect plans, selects/merges best (sswarm) | sonnet | Read, Write, Glob, Grep | Yes |
| 12 | queen | A4 verdict evaluator / team lead initializer | sonnet | Read, Glob, Grep, Write | Yes |
| 13 | review-arbiter | Consolidates adversarial sentinel findings | sonnet | Read, Glob, Grep, Write | Yes |
| 14 | review-fixer | Targeted repair for review-fix cycles | inherit | Read, Edit, Write, Glob, Grep | Yes |
| 15 | review-lead | A2 lead: consolidates competing blueprint review verdicts (sswarm) | sonnet | Read, Write, Glob, Grep | Yes |
| 16 | sentinel | (deprecated) Generic sentinel reviewer | sonnet | Read, Glob, Grep, Bash | Yes |
| 17 | sentinel-correctness | Specialist: bugs, logic errors, error handling | sonnet | Read, Glob, Grep, Bash, Write | Yes |
| 18 | sentinel-perf | Specialist: N+1 queries, blocking I/O, complexity | sonnet | Read, Glob, Grep, Bash, Write | Yes |
| 19 | sentinel-security | Specialist: OWASP, injection, secrets, access control | sonnet | Read, Glob, Grep, Bash, Write | Yes |
| 20 | sentinel-style | Specialist: code style, readability, maintainability | sonnet | Read, Glob, Grep, Bash, Write | Yes |
| 21 | simplifier | Post-build code cleanup (dead code, complexity, naming) | sonnet | Read, Edit, Glob, Grep, Bash | Yes |
| 22 | solution-aggregator | Ranks and selects best fix (debug D2) | sonnet | Read, Write, Glob | Yes |
| 23 | solution-proposer | Proposes one specific fix approach (debug D1) | sonnet | Read, Glob, Grep, Write | Yes |
| 24 | worker | Implements a single task from the plan | inherit | Read, Grep, Glob, Edit, Write, Bash | Yes |
| 25 | (orchestrator) | Agent Teams delegate mode with Command-as-Active-Lead (hooks, not an agent file) | -- | -- | -- |

All agents have `disallowedTools: [Task]` -- no agent can spawn subagents. Commands create Agent Teams and enter a monitoring loop (Command-as-Active-Lead). TeammateIdle hook routes tasks to idle teammates. TaskCompleted hook validates output and advances state. Hooks set signal flags in state.json; the command's monitoring loop reads these flags and calls TaskCreate for dynamic tasks (hooks are shell scripts and cannot call Claude tools). SendMessage is retained for optional peer communication only, NOT for dispatch coordination.

**Sentinel tool design:** Specialist sentinels (rows 17-20) have `Write` to create new output JSON files but exclude `Edit` via `disallowedTools` — sentinels must never modify existing project source files during adversarial review. This is intentional, not a bug.

**Simplifier tool design:** The simplifier (row 21) has `Edit` to apply code cleanup but excludes `Write` via `disallowedTools` — it makes surgical edits to existing files, never full rewrites.

### Deprecated Agents

- **sentinel** -- Replaced by specialist sentinels (sentinel-correctness, sentinel-security, sentinel-perf, sentinel-style) in v0.2/v0.5.4. The generic sentinel is retained for backward compatibility with v0.1 state files but should not be dispatched in new workflows.

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
                  TaskCompleted hook evaluates
                  A4 verdict inline (when arbiter completes)
                       |
                   verdict?
                  /        \
               ship       loop ──> back to A1
```

Commands create Agent Teams with task dependency chains (blockedBy) and enter a monitoring loop (Command-as-Active-Lead). TeammateIdle hook routes ready tasks to idle teammates. TaskCompleted hook validates output and advances state. A4 (sync/verdict) is evaluated inline by the TaskCompleted hook when the A3 arbiter completes -- it is not a separate agent dispatch.

Three pipeline variants are supported, selected by the `pipeline` field in state.json:

- **`swarm`** -- Single A0→A5 run; workflow completes after A5 ships (command: `/ants:swarm`)
- **`sswarm`** -- Social swarm with competing agents; A1 creates 3 architect tasks + plan-arbiter (blockedBy all 3), A2 creates 3 reviewer tasks + review-lead (blockedBy all 3); otherwise same as swarm (command: `/ants:sswarm`)
- **`pswarm`** -- Persistent multi-run loop; after A5 ships, the command's monitoring loop creates a fresh A0→A5 task graph and the pipeline restarts from A0 until `pswarmRun >= maxRuns` or `shutdown == true` (command: `/ants:pswarm`)

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| A0 | EXPLORE | forager x2-4, cartographer x1, explore-aggregator x1 | Parallel codebase exploration (explore-aggregator synthesizes results) |
| A1 | PLAN | architect x1 | Structured plan with task assignments |
| A2 | PLAN | blueprint-reviewer x1 | Plan validation |
| A3 | BUILD | worker xN (task pool), sentinel-correctness + sentinel-security + sentinel-perf + sentinel-style (adversarial review), simplifier x1, review-arbiter x1, guardian x1 | Self-organizing task pool with adversarial review and cleanup tracks |
| A4 | SYNC | TaskCompleted hook (inline) | Evaluated inline by TaskCompleted hook when A3 arbiter completes; reads A3-quality.json, renders ship/loop verdict (circuit breaker aware), sets signal flags |
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

The sswarm (social swarm) pipeline extends swarm with **competing parallel agents** and **per-phase lead consolidators**. Phases A1 and A2 create multiple competing task entries whose outputs are consolidated by dedicated lead tasks via task dependency chains (blockedBy):

| Phase | swarm | sswarm |
|-------|-------|--------|
| A0 | foragers + cartographer + aggregator | Same |
| A1 | 1 architect | 3 competing architects + plan-arbiter (blockedBy all 3) |
| A2 | 1 blueprint-reviewer | 3 competing reviewers + review-lead (blockedBy all 3) |
| A3 | workers + sentinels + guardian + simplifier | Same |
| A4 | TaskCompleted hook (inline verdict) | Same |
| A5 | nurse + drone | Same |

**Task dependency dispatch:** Competing agents at A1 and A2 are created as independent tasks (no deps on each other) all blockedBy the previous phase. The consolidator task (plan-arbiter / review-lead) is blockedBy all competing tasks. No spawn order constraints needed -- task dependencies replace SendMessage coordination.

**Lead agents:** plan-arbiter (row 11) and review-lead (row 15) read competing output files at known paths (set by dispatch prompt). Both follow the review-arbiter consolidation pattern with cross-reference elevation and deduplication.

**State additions:** `pipeline: "sswarm"`, `phaseLeads` map, `teamName: "ants-sswarm-<slug>"`.

**Hook compatibility:** All 8 hooks work unchanged with sswarm. Hooks check `plugin: "ants"` and `currentPhase` (A0-A5) but not `pipeline` for routing (except on-stop.sh which only special-cases pswarm).

## Dual-Track Build + Quality Design

Phase A3 is the core innovation. Two tracks run in coordinated execution:

**Build Track:** Workers claim tasks from a self-organizing task pool. Tasks with no dependencies start as "ready"; as tasks complete, dependent tasks become ready automatically. This replaces the rigid wave-based dispatch from v0.1.

**Quality Track (Adversarial Review + Cleanup):** After all workers complete (pool drained), six agents run in parallel:
- **sentinel-correctness** -- bugs, logic errors, missing error handling, race conditions
- **sentinel-security** -- OWASP top 10, injection, authentication, secrets exposure
- **sentinel-perf** -- N+1 queries, blocking I/O, unnecessary allocations, algorithmic complexity
- **sentinel-style** -- code style, readability, maintainability (excessive nesting, magic numbers, dead code)
- **guardian** -- writes and runs tests for the implemented code
- **simplifier** -- applies targeted code cleanup without behavioral changes (dead code removal, complexity reduction)

After all six complete, the **review-arbiter** cross-references sentinel findings, deduplicates overlapping issues, resolves conflicts, and produces a single consolidated verdict (A3-quality.json). If the review-arbiter identifies critical issues, a **review-fixer** is dispatched to apply targeted repairs before the quality verdict is finalized.

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

The `hooks/lib/teams.sh` library provides task graph generation, teammate prompt building, and dispatch helpers for the Agent Teams delegate mode pipeline:

- `teams_create_phase_tasks()` -- Creates TaskCreate entries for full A0→A5 linear dependency chain
- `teams_create_sswarm_tasks()` -- Creates sswarm-specific task graph with competing agents at A1/A2 (3 architects + plan-arbiter, 3 reviewers + review-lead)
- `teams_add_a3_subtasks()` -- Dynamically adds worker/sentinel/simplifier/arbiter tasks after A1 (sentinel_names array includes sentinel-style; arbiter blockedBy includes all 4 sentinels + guardian + simplifier)
- `teams_create_verdict_tasks()` -- Generates A5 tasks (nurse + drone) after clean A4 verdict
- `teams_create_pswarm_run_tasks()` -- Wrapper that generates fresh task graph for pswarm run boundary
- `teams_get_next_ready_task()` -- Reads state.json, returns next dispatchable phase/task
- `teams_get_a3_task_prompt()` -- Generates task-specific prompt for A3 worker task assignment
- `teams_build_teammate_prompt()` -- Generates phase-specific execution prompts for teammates
- `teams_assign_idle_teammate()` -- Builds exit-2 output for TeammateIdle hook
- `teams_reject_completion()` -- Builds exit-2 output for TaskCompleted rejection

Commands use TaskCreate, TaskGet, TaskList, TaskUpdate, and TaskStop tools to manage the team. Hooks set signal flags in state.json; the command's monitoring loop reads these flags and calls TaskCreate for dynamic tasks.

## Hook Architecture

Eight hooks drive the Agent Teams delegate mode workflow. TeammateIdle is the full task router (assigns next ready phase/task to idle teammates). TaskCompleted validates output, advances state, evaluates A4 verdict inline, and sets signal flags for the command's monitoring loop. Additional hooks provide edit control, lint-on-save, config snapshots, and compaction support:

### on-teammate-idle.sh (TeammateIdle event) -- Full Task Router

- Checks preconditions: shutdown flag, terminal status, circuit breaker
- Routes by currentPhase via case statement (A0-A5, sswarm variants, pswarm run boundary)
- A3 dispatch: dual-track routing (worker tasks from pool, then quality agents, then arbiter)
- sswarm A1/A2: dispatches competing slots (architect-1/2/3, reviewer-1/2/3) + consolidator
- Generates task-specific prompts via `teams_build_teammate_prompt()` and `teams_get_a3_task_prompt()`
- Returns exit 2 with prompt to assign work to idle teammate
- Returns exit 0 if no tasks ready (workflow complete/blocked/waiting/shutdown)

### on-task-completed.sh (TaskCompleted event) -- Quality Gate + State Advancement

- Validates output file exists and is valid JSON
- Phase-specific quality gates with state advancement:
  - A0: A0-explore.md exists → advance currentPhase to A1
  - A1: A1-plan.md exists → init task pool, advance to A2, set `needsA3Tasks` signal flag
  - A2: Review verdict — needs_revision with HIGH → loop to A1 (circuit breaker); else → A3. `.status` is the sole canonical verdict field in A2-review.json.
  - A3 Worker: Updates task pool, checks build track completion
  - A3 Sentinel/Guardian/Simplifier: Marks agent complete, checks all quality agents done
  - A3 Arbiter: Consolidates quality verdict, evaluates **A4 verdict inline** -- reads A3-quality.json, determines clean/issues_found. Clean → sets `needsA5Tasks` flag, advances to A5. Issues found → sets `needsLoopReset` flag, resets to A1.
  - A4: Legacy compatibility shim (verdict now evaluated inline by A3 arbiter handler)
  - A5: A5-ship.json with commit_sha → workflow DONE (swarm/sswarm) or sets `needsPswarmReset` flag (pswarm)
- Updates circuit breaker on success/failure
- Sets signal flags for command's monitoring loop (hooks cannot call TaskCreate directly)
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
- `check_ants_workflow()` -- plugin guard, session scoping, status check, auto-migration v1->v6
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
- `teams_create_phase_tasks()` -- creates TaskCreate entries for full A0→A5 linear dependency chain
- `teams_create_sswarm_tasks()` -- creates sswarm-specific task graph with competing agents at A1/A2
- `teams_add_a3_subtasks()` -- dynamically adds worker/sentinel/arbiter tasks after A1
- `teams_create_verdict_tasks()` -- generates A5 tasks (nurse + drone) after clean verdict
- `teams_create_pswarm_run_tasks()` -- wrapper for fresh task graph at pswarm run boundary
- `teams_get_next_ready_task()` -- finds next dispatchable phase/task from state
- `teams_get_a3_task_prompt()` -- generates task-specific prompt for A3 worker task assignment
- `teams_build_teammate_prompt()` -- generates phase-specific execution prompts for teammates
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
├── state.json                           # Workflow state (v6)
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
│   │   ├── A4-queen-verdict.json     # Verdict (written by TaskCompleted hook inline A4 evaluation)
│   │   ├── A5-docs.json              # Nurse documentation summary
│   │   └── A5-ship.json              # Drone commit/PR output
│   ├── loop-2/                        # If looped back
│   │   └── ...
```

## State Schema (v6)

```json
{
  "version": 6,
  "plugin": "ants",
  "pipeline": "swarm|sswarm|pswarm",
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

### New v0.6 State Fields (Agent Teams)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `teamCreated` | boolean | false | Replaces `queenDispatched`. Set true after team creation + teammate spawn. |
| `teammateCount` | number | 0 | Number of teammates spawned (3 for swarm/pswarm, 5 for sswarm). |
| `taskGraphVersion` | number | 1 | Incremented on loop-back (`reset_phases_for_loop`) and pswarm run boundary (`reset_phases_for_pswarm`). Commands use this to detect when fresh TaskCreate calls are needed. |
| `needsA3Tasks` | boolean | false | Signal flag: set by `on-task-completed.sh` when A1 completes. Command creates A3 worker/sentinel/arbiter tasks. |
| `needsA5Tasks` | boolean | false | Signal flag: set by `on-task-completed.sh` when A4 verdict is clean. Command creates A5 nurse/drone tasks. |
| `needsLoopReset` | boolean | false | Signal flag: set by `on-task-completed.sh` when A4 verdict is `issues_found`. Command creates fresh A1-A4 tasks. |
| `needsPswarmReset` | boolean | false | Signal flag: set by `on-task-completed.sh` when A5 completes in pswarm and `pswarmRun < maxRuns`. Command creates fresh A0-A5 task graph. |

### v0.4 State Fields (preserved)

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

Cross-phase communication via the `messages` array in state.json. Agents can send messages to other agents using `add_message "from" "to" "content"` and retrieve them with `get_messages_for "recipient"`. Messages are tagged with the current loop number and timestamp. This enables feedback loops without re-planning (e.g., passing targeted notes to the architect for the next loop). Note: this uses the state.json messages array, not SendMessage.

## Communication

Agents communicate results via output files written to `.agents/tmp/phases/`. The naming contract for output files is documented in the Phase Output Files section of the swarm SKILL.md and in `docs/shared-teams-init.md` (section 9).

### File-Based Communication (v0.6)

All inter-agent communication uses file-based output. Each agent writes its results to a known file path:

- **Linear phases (A0, A1, A2, A5)**: task dependencies via blockedBy chains ensure agents read predecessor output files
- **Competing agents (sswarm A1/A2)**: 3 independent tasks write to competitor-specific temp files; the consolidator task (blockedBy all 3) reads all files
- **A3 quality track**: sentinels write individual review JSONs; arbiter reads all sentinel + guardian + simplifier output files

### SendMessage

SendMessage is retained for **optional peer communication only**, NOT for dispatch coordination. All dispatch and phase transitions are handled by task dependencies (blockedBy chains), TeammateIdle hook routing, and TaskCompleted hook state advancement. No agent requires SendMessage for core workflow functionality.

### teamCreated State Field

The `teamCreated` field (v6, replaces `queenDispatched` from v5) tracks whether the Agent Team has been created and teammates have been spawned. It is set to `true` after team creation and prevents duplicate team initialization.

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

- Skip A4 verdict evaluation -- always evaluate A4 verdict (inline in TaskCompleted hook) before shipping
- Ship when critical or warning issues remain unresolved
- Allow agents to spawn subagents (all are leaf agents)
- Commit secrets or credentials
- Modify files during EXPLORE, PLAN, or SYNC stages (enforced by edit gate)
- Proceed past maxLoops without user approval
- Ignore circuit breaker trips -- always halt and surface to user
