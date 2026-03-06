# ants Plugin -- Agent Instructions

Ant-colony themed swarm workflow with dual-track parallel build and adversarial quality review.

## Plugin Structure

```
plugins/ants/
├── .claude-plugin/plugin.json    # Plugin manifest (name, version)
├── agents/                        # Agent definitions (16 agents)
│   ├── architect.md               # Plan writer with task assignments
│   ├── blueprint-reviewer.md      # Plan validator
│   ├── cartographer.md            # Deep architecture tracer
│   ├── drone.md                   # Commit + PR shipper
│   ├── explore-aggregator.md      # Merges forager/cartographer outputs
│   ├── forager.md                 # Breadth-first codebase scout
│   ├── guardian.md                # Test writer for quality track
│   ├── nurse.md                   # Documentation updater
│   ├── queen.md                   # Track sync + ship/loop verdict
│   ├── review-arbiter.md          # Consolidates adversarial sentinel findings
│   ├── review-fixer.md            # Targeted repair agent for review-fix cycles
│   ├── sentinel.md                # (deprecated) Generic sentinel reviewer -- use specialist sentinels
│   ├── sentinel-correctness.md    # Specialist: bugs, logic errors, error handling
│   ├── sentinel-perf.md           # Specialist: N+1 queries, blocking I/O, complexity
│   ├── sentinel-security.md       # Specialist: OWASP, injection, secrets, access control
│   └── worker.md                  # Task implementer (one per task)
├── commands/                      # Slash commands
│   └── swarm.md                   # /ants:swarm <task>
├── docs/                          # Architecture documentation
│   └── teams-migration.md         # Agent Teams API migration guide
├── hooks/                         # Shell hooks (Ralph Loop driver)
│   ├── hooks.json                 # Hook event configuration
│   ├── on-stop.sh                 # Stop: prompt re-injection
│   ├── on-subagent-stop.sh        # SubagentStop: validate + advance
│   ├── on-task-gate.sh            # PreToolUse (Task): dispatch validation
│   ├── on-edit-gate.sh            # PreToolUse (Edit/Write): edit control
│   ├── on-teams-stub.sh           # TeammateIdle/TaskCompleted: no-op until Teams API stable
│   └── lib/
│       ├── state.sh               # Shared bash state helpers
│       ├── swarm.sh               # Pipeline-specific phase routing
│       ├── dag.sh                 # Phase-level DAG status tracker
│       ├── circuit-breaker.sh     # Fix-budget and consecutive failure tracking
│       ├── task-pool.sh           # Self-organizing task pool for A3
│       └── teams.sh               # Agent Teams API readiness layer
├── prompts/                       # Phase prompt templates
│   ├── A0-explore.md              # Colony exploration dispatch
│   ├── A1-plan.md                 # Architect plan dispatch
│   ├── A2-review.md               # Blueprint review dispatch
│   ├── A3-build.md                # Dual-track build dispatch
│   ├── A4-sync.md                 # Queen synchronization dispatch
│   └── A5-ship.md                 # Documentation + ship dispatch
├── skills/                        # Workflow documentation
│   ├── swarm/SKILL.md             # Swarm pipeline reference
│   └── workflow/SKILL.md          # Ralph Loop mechanics
├── CLAUDE.md                      # This file -- architecture docs
└── README.md                      # User-facing documentation
```

## Agent Roster

| # | Agent | Role | Model | Tools | Leaf? |
|---|-------|------|-------|-------|-------|
| 1 | forager | Breadth-first codebase scout | haiku | Read, Glob, Grep, Write | Yes |
| 2 | cartographer | Deep architecture tracer | sonnet | Read, Glob, Grep, Write | Yes |
| 3 | explore-aggregator | Merges explorer outputs into report | haiku | Read, Write, Glob | Yes |
| 4 | architect | Plans implementation with task assignments | sonnet | Read, Glob, Grep, WebSearch | Yes |
| 5 | blueprint-reviewer | Validates plan completeness and task correctness | sonnet | Read, Glob, Grep | Yes |
| 6 | worker | Implements a single task from the plan | inherit | Read, Grep, Glob, Edit, Write, Bash | Yes |
| 7 | sentinel | (deprecated) Generic sentinel reviewer | sonnet | Read, Glob, Grep, Bash | Yes |
| 8 | sentinel-correctness | Specialist: bugs, logic errors, error handling | sonnet | Read, Glob, Grep, Bash, Write | Yes |
| 9 | sentinel-security | Specialist: OWASP, injection, secrets, access control | sonnet | Read, Glob, Grep, Bash, Write | Yes |
| 10 | sentinel-perf | Specialist: N+1 queries, blocking I/O, complexity | sonnet | Read, Glob, Grep, Bash, Write | Yes |
| 11 | review-arbiter | Consolidates adversarial sentinel findings | sonnet | Read, Glob, Grep | Yes |
| 12 | review-fixer | Targeted repair for review-fix cycles | inherit | Read, Edit, Write, Glob, Grep | Yes |
| 13 | guardian | Test writer for quality track | sonnet | Read, Glob, Grep, Edit, Write, Bash | Yes |
| 14 | queen | Merges track results and renders ship/loop verdict | sonnet | Read, Glob, Grep | Yes |
| 15 | nurse | Updates documentation after implementation | sonnet | Read, Write, Edit, Glob, Grep | Yes |
| 16 | drone | Commits changes and opens PR | inherit | Read, Glob, Grep, Bash, Write | Yes |
| 17 | (orchestrator) | Ralph Loop driver (hooks, not an agent file) | -- | -- | -- |

All agents have `disallowedTools: [Task]` -- no agent can spawn subagents. The orchestrator (hooks) is the only entity that dispatches agents.

### Deprecated Agents

- **sentinel** -- Replaced by specialist sentinels (sentinel-correctness, sentinel-security, sentinel-perf) in v0.2. The generic sentinel is retained for backward compatibility with v0.1 state files but should not be dispatched in new workflows.

## Pipeline Phases (A0-A5)

```
EXPLORE ──> PLAN ──> BUILD ──> SYNC ──> SHIP
  A0        A1,A2     A3       A4       A5
                               |
                          verdict?
                         /        \
                      ship       loop ──> back to A1
```

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| A0 | EXPLORE | forager x2-4, cartographer x1, explore-aggregator x1 | Parallel codebase exploration |
| A1 | PLAN | architect x1 | Structured plan with task assignments |
| A2 | PLAN | blueprint-reviewer x1 | Plan validation |
| A3 | BUILD | worker xN (task pool), sentinel-correctness + sentinel-security + sentinel-perf (adversarial review), review-arbiter x1, guardian xN | Self-organizing task pool with adversarial review teams |
| A4 | SYNC | queen x1 | Merge tracks, ship/loop verdict (circuit breaker aware) |
| A5 | SHIP | nurse x1, drone x1 | Documentation update + commit/PR |

## Dual-Track Build + Quality Design

Phase A3 is the core innovation. Two tracks run in coordinated execution:

**Build Track:** Workers claim tasks from a self-organizing task pool. Tasks with no dependencies start as "ready"; as tasks complete, dependent tasks become ready automatically. This replaces the rigid wave-based dispatch from v0.1.

**Quality Track (Adversarial Review):** After each batch of workers completes, three specialist sentinels run in parallel:
- **sentinel-correctness** -- bugs, logic errors, missing error handling, race conditions
- **sentinel-security** -- OWASP top 10, injection, authentication, secrets exposure
- **sentinel-perf** -- N+1 queries, blocking I/O, unnecessary allocations, algorithmic complexity

After all three sentinels complete, the **review-arbiter** cross-references findings, deduplicates overlapping issues, resolves conflicts, and produces a single consolidated verdict (A3-quality.json).

**Task Pool Synchronization:** Workers in the pool run in parallel when their dependencies are satisfied. After all workers complete (pool drained), the adversarial review team runs. This replaces the wave barrier model with dependency-driven dispatch.

**Fallback:** If no `taskPool` exists in state (v0.1 state files), A3 falls back to legacy wave-based dispatch with the generic sentinel.

## Circuit Breaker

The circuit breaker prevents infinite failure loops by tracking:

- **Consecutive failures** -- Trips after 5 consecutive failures (configurable via `circuitBreaker.maxConsecutiveFailures`)
- **Fix attempts** -- Per-phase budget of 5 attempts (configurable via `circuitBreaker.maxFixAttempts`)
- **Stage restarts** -- Maximum 2 loop-backs from A4 to A1 (configurable via `circuitBreaker.maxStageRestarts`)

When the circuit breaker trips, the workflow halts with status `blocked` and requires user intervention. Success resets the consecutive failure counter.

Library: `hooks/lib/circuit-breaker.sh`

## Agent Teams Readiness

The v0.2 dispatch layer is designed for a future migration to the Claude Code Agent Teams API. The `hooks/lib/teams.sh` library provides:

- `teams_detect()` -- Checks `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var
- `teams_get_dispatch_mode()` -- Returns `"subagent"` (current) or `"teams"` (future)
- `teams_build_task_descriptor()` -- Builds dispatch-mode-agnostic task descriptors

All dispatch flows through this library so the Teams migration is a single-file change. See `docs/teams-migration.md` for the step-by-step guide.

Current hooks.json includes `TeammateIdle` and `TaskCompleted` stubs (`on-teams-stub.sh`) that exit 0 until the Teams API stabilizes.

## Hook Architecture

Six hooks drive the workflow via the Ralph Loop pattern:

### on-stop.sh (Stop event)

- Reads `state.json` to determine current phase
- Generates phase-specific orchestrator prompt (~30-60 lines)
- Returns `{"decision":"block","reason":"<prompt>"}` to keep Claude working
- Allows exit only when status is `complete` or `blocked`

### on-subagent-stop.sh (SubagentStop event)

- Validates subagent output file exists and is valid
- Checks stage gates at boundaries
- Handles A4 queen verdict (ship -> A5, loop -> A1 with incremented counter)
- Handles A3 task pool completion (all tasks done -> sentinel review -> arbiter)
- Advances `currentPhase` in state
- Updates circuit breaker on success/failure
- Exits silently (no stdout) -- Stop hook handles prompt injection

### on-task-gate.sh (PreToolUse: Task)

- Validates that the dispatched `ants:*` agent matches the current phase
- Blocks dispatch of wrong agent types
- Prevents out-of-order phase execution

### on-edit-gate.sh (PreToolUse: Edit/Write)

- Allows file edits only in BUILD (A3) and SHIP (A5) stages
- Blocks edits during EXPLORE, PLAN, and SYNC stages
- Allows writes to `.agents/` path at all times (state and output files)
- Validates file ownership via task pool (workers can only edit their assigned files)

### on-teams-stub.sh (TeammateIdle / TaskCompleted)

- No-op stub that exits 0 while the Agent Teams API is experimental
- Will be activated when Teams API becomes stable (see `docs/teams-migration.md`)

### hooks.json Configuration

```json
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "on-stop.sh"}]}],
    "SubagentStop": [{"hooks": [{"type": "command", "command": "on-subagent-stop.sh"}]}],
    "PreToolUse": [
      {"matcher": "Task", "hooks": [{"type": "command", "command": "on-task-gate.sh"}]},
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "on-edit-gate.sh"}]}
    ],
    "TeammateIdle": [{"hooks": [{"type": "command", "command": "on-teams-stub.sh"}]}],
    "TaskCompleted": [{"hooks": [{"type": "command", "command": "on-teams-stub.sh"}]}]
  }
}
```

## State Management

State tracked in `.agents/tmp/state.json`. Shared libraries in `hooks/lib/`:

### state.sh (core)
- `check_ants_workflow()` -- plugin guard, session scoping, status check
- `read_state_field()` / `state_get()` -- read fields with optional required validation
- `update_state()` -- atomic state update with file locking (flock)
- `validate_json_file()` -- check file exists and contains valid JSON
- `require_int()` -- validate integer fields

### dag.sh (phase tracking)
- `get_phase_status()` / `is_phase_complete()` -- read phase status
- `mark_phase_in_progress()` / `mark_phase_complete()` -- update phase status
- `reset_phases_for_loop()` -- reset A1-A4 to pending for loop-back

### circuit-breaker.sh (failure tracking)
- `cb_init()` -- initialize circuit breaker fields
- `cb_record_failure()` / `cb_record_success()` -- track consecutive outcomes
- `cb_is_tripped()` -- check if breaker is tripped
- `cb_increment_fix_attempts()` -- per-phase fix budget
- `cb_increment_stage_restarts()` -- loop-back budget

### task-pool.sh (A3 task dispatch)
- `pool_init()` -- initialize pool from architect's A1-tasks.json
- `pool_claim_task()` -- atomically claim next available task (mkdir lock)
- `pool_complete_task()` / `pool_fail_task()` -- update task status
- `pool_recompute_ready()` -- promote pending tasks whose deps are complete
- `pool_get_file_owner()` -- file ownership enforcement for edit gate

### teams.sh (dispatch abstraction)
- `teams_detect()` -- check Agent Teams API availability
- `teams_get_dispatch_mode()` -- returns "subagent" or "teams"
- `teams_build_task_descriptor()` -- dispatch-mode-agnostic task descriptors

Session scoping via `ownerPpid` + `sessionId` ensures hooks only fire for the session that owns the workflow.

### Output File Layout

```
.agents/tmp/
├── state.json                           # Workflow state (v2)
├── phases/
│   ├── A0-explore.forager.1.tmp         # Forager results
│   ├── A0-explore.forager.2.tmp
│   ├── A0-explore.cartographer.tmp      # Cartographer results
│   ├── A0-explore.md                    # Aggregated exploration
│   ├── loop-1/
│   │   ├── A1-plan.md                   # Architect's plan
│   │   ├── A1-tasks.json                # Task descriptors for task pool
│   │   ├── A2-review.json              # Blueprint review
│   │   ├── A3-build.json              # Worker results
│   │   ├── A3-review.sentinel-correctness.json  # Correctness review
│   │   ├── A3-review.sentinel-security.json     # Security review
│   │   ├── A3-review.sentinel-perf.json         # Performance review
│   │   ├── A3-quality.json            # Arbiter consolidated verdict
│   │   ├── A4-queen-verdict.json     # Queen verdict
│   │   ├── A5-docs.json              # Nurse documentation summary
│   │   └── A5-ship.json              # Drone commit/PR output
│   ├── loop-2/                        # If looped back
│   │   └── ...
```

## State Schema (v2)

```json
{
  "version": 2,
  "plugin": "ants",
  "pipeline": "swarm",
  "status": "in_progress|blocked|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID if available>",
  "currentPhase": "A0|A1|A2|A3|A4|A5|DONE|STOPPED",
  "loop": 1,
  "maxLoops": 5,
  "dispatchMode": "subagent",
  "startedAt": "ISO timestamp",
  "schedule": [
    {"phase": "A0", "stage": "EXPLORE", "label": "Colony Exploration", "type": "dispatch"},
    {"phase": "A1", "stage": "PLAN", "label": "Architect Plan", "type": "subagent"},
    {"phase": "A2", "stage": "PLAN", "label": "Blueprint Review", "type": "subagent"},
    {"phase": "A3", "stage": "BUILD", "label": "Dual-Track Execution", "type": "dispatch"},
    {"phase": "A4", "stage": "SYNC", "label": "Queen Synchronization", "type": "subagent"},
    {"phase": "A5", "stage": "SHIP", "label": "Documentation + Ship", "type": "subagent"}
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
  "failure": null
}
```

## Code Style

- **Markdown:** YAML frontmatter, follow existing agent structure
- **Naming:** kebab-case for files (e.g., `blueprint-reviewer.md`, `explore-aggregator.md`)
- **Agent theme:** Ant colony roles (forager, cartographer, architect, worker, sentinel, queen, nurse, drone)
- **Shell hooks:** `set -euo pipefail`, use `local var; var="$(cmd)"` (not `local var="$(cmd)"`), source libs from `$SCRIPT_DIR/lib/`
- **Shell validation:** Run `bash -n <script>` after modifying hook shell scripts
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
