# ants Plugin -- Agent Instructions

Ant-colony themed swarm workflow with Agent Teams delegate mode, dual-track parallel build, and adversarial quality review.

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
│   ├── swarm/SKILL.md             # Swarm pipeline reference
│   └── workflow/SKILL.md          # Agent Teams delegate mode
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
| 17 | (orchestrator) | Agent Teams delegate mode (hooks, not an agent file) | -- | -- | -- |

All agents have `disallowedTools: [Task]` -- no agent can spawn subagents. The orchestrator (hooks) manages task assignment and quality gates via TeammateIdle/TaskCompleted hooks.

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

## Agent Teams (v0.3)

Ants v0.3 uses Agent Teams delegate mode exclusively. The `hooks/lib/teams.sh` library provides:

- `teams_create_phase_tasks()` -- Creates TaskCreate entries for A0→A5 with dependency chains
- `teams_add_a3_subtasks()` -- Dynamically adds worker/sentinel/arbiter tasks after A1
- `teams_get_next_ready_task()` -- Reads state.json, returns next dispatchable phase
- `teams_build_teammate_prompt()` -- Generates direct execution prompts for teammates
- `teams_assign_idle_teammate()` -- Builds exit-2 output for TeammateIdle hook
- `teams_reject_completion()` -- Builds exit-2 output for TaskCompleted rejection

The swarm command auto-enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` before creating the team.

## Hook Architecture

Eight hooks drive the workflow via Agent Teams delegate mode:

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
  - A2: Review verdict — needs_revision with HIGH → loop to A1; else → A3
  - A3: Workers update task pool, sentinels write markers, arbiter consolidates
  - A4: Parse queen verdict — clean → A5, issues_found → loop to A1
  - A5: A5-ship.json with commit_sha → workflow DONE
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
- `check_ants_workflow()` -- plugin guard, session scoping, status check, auto-migration v1->v4
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
├── state.json                           # Workflow state (v4)
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
  "compactMetadata": null
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

## Graceful Shutdown (v0.4)

Set `.shutdown = true` in state.json to request a graceful shutdown. The `shutdown_check()` function (called by hooks) detects this flag and emits `{"continue": false, "stopReason": "..."}` to halt the workflow cleanly. This allows in-progress phases to complete before stopping, unlike a hard kill.

## Plan Approval (v0.4)

When `.planApproved` is `false` (default), the TaskCompleted hook holds the workflow at A1 after the architect writes the plan. The plan must be reviewed and `.planApproved` set to `true` before the workflow advances to A2 (blueprint review). This prevents premature implementation of poorly-scoped plans.

## Teammate Messaging (v0.4)

Cross-phase communication via the `messages` array in state.json. Agents can send messages to other agents using `add_message "from" "to" "content"` and retrieve them with `get_messages_for "recipient"`. Messages are tagged with the current loop number and timestamp. This enables feedback loops without re-planning (e.g., queen sending targeted notes to the architect for the next loop).

## Worktree Isolation (v0.4)

When `.worktreePath` is set, the workflow operates in a git worktree at the specified path. This isolates the workflow's file changes from the main branch, enabling multiple workflows to run concurrently on the same repository.

## Lint-on-Save (v0.4)

The PostToolUse hook (`on-post-edit-lint.sh`) runs language-aware linting after every successful Edit/Write during BUILD (A3) and SHIP (A5) phases. Lint results are advisory only (non-blocking). Supported linters: `bash -n` for shell scripts, `jq empty` for JSON, `python3 -m py_compile` for Python. Disable via `.lintConfig.enabled = false` in state.json.

## HTTP Webhooks (v0.4)

Set `.webhookUrl` in state.json to receive fire-and-forget HTTP POST notifications for phase and workflow lifecycle events. The `webhook.sh` library sends all notifications in the background with a 5-second timeout. Events: `phase.started`, `phase.completed`, `phase.failed`, `workflow.completed`, `workflow.blocked`, `workflow.stopped`. If no URL is configured, all webhook calls are silent no-ops.

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
