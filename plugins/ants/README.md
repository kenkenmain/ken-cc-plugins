# ants

Ant-colony themed swarm workflow for Claude Code. Builds software using parallel agents with adversarial review teams: workers build while specialist sentinels review from three angles, an arbiter consolidates findings, and a queen decides to ship or loop. Also includes a self-improvement pipeline that iteratively reviews and fixes code issues.

## Installation

```bash
# From local directory
claude --plugin-dir ./plugins/ants

# Or install to project scope
claude plugin install ./plugins/ants --scope project
```

## Quick Start

```bash
/ants:swarm Add a caching layer to the API endpoints
/ants:swarm --worktree Add a caching layer to the API endpoints
/ants:swarm --web Integrate a third-party payment SDK

/ants:pswarm Continuously improve test coverage --max-loops 10
/ants:pswarm Fix all lint warnings --worktree
/ants:pswarm Research and implement OAuth2 --web --max-loops 5

# Debug: 6-phase bug investigation and fix pipeline
/ants:debug Fix the authentication middleware returning 500 on expired tokens

# Improve: iterative review-fix pipeline (fixes all issues, info severity and up)
/ants:improve Review and fix all issues in the authentication module
/ants:improve Clean up error handling across the API layer
```

The `--worktree` flag creates a git worktree for isolated development, enabling multiple workflows to run concurrently on the same repository.

The `--web` flag enables WebSearch for forager agents (A0 exploration) and the architect (A1 planning). Use this when the task requires researching external libraries, API documentation, or best practices that are not in the codebase. Off by default.

`/ants:swarm` launches a single 6-phase pipeline that explores the codebase, plans the implementation, builds with a self-organizing task pool, runs adversarial review, and ships the result.

`/ants:pswarm` (persistent swarm) runs the same pipeline in a continuous loop — after each A5 ship it resets all phases and starts the next run from A0, re-exploring the evolved codebase. Use this for tasks that require multiple incremental passes (e.g., progressively improving coverage, fixing lint warnings across many files).

## Pipeline Overview

```
  A0 Explore         foragers + cartographer scout the codebase
       |
  A1 Architect        plans implementation with task assignments
       |
  A2 Blueprint Review validates the plan before building
       |
  A3 Dual-Track       workers build from task pool,
       |               adversarial sentinels review:
       |                 sentinel-correctness (bugs, logic)
       |                 sentinel-security (OWASP, injection)
       |                 sentinel-perf (N+1, blocking I/O)
       |               review-arbiter consolidates findings
       |
  A4 Queen Sync       reads arbiter verdict, decides: ship or loop
      / \                (circuit breaker aware)
  ship   loop ------> back to A1 (max 5 loops)
   |
  A5 Ship             update docs, commit, open PR
```

## Debug Pipeline

Use `/ants:debug` when you have a specific bug to investigate, want parallel investigation from multiple angles, and want user confirmation before applying the fix.

```
  D0 Explore         3 bug-scouts investigate in parallel
       |               (error analysis, execution path, test gaps)
  D1 Propose         3 solution-proposers generate fix approaches
       |               (minimal, comprehensive, defensive)
  D2 Aggregate       solution-aggregator ranks proposals
       |               → user selects preferred approach
  D3 Implement       fix-worker implements fix + writes tests
       |
  D4 Review          adversarial sentinel review of the fix
       |               (correctness, security, performance)
  D5 Ship            update docs, commit, open PR
```

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| D0 | EXPLORE | bug-scout ×3 | Parallel bug investigation (error, execution path, tests) |
| D1 | PROPOSE | solution-proposer ×3 | Parallel fix proposals (minimal, comprehensive, defensive) |
| D2 | AGGREGATE | solution-aggregator ×1 | Rank proposals + user selects |
| D3 | IMPLEMENT | fix-worker ×1 | Implement fix, write tests, self-verify |
| D4 | REVIEW | sentinel-correctness + sentinel-security + sentinel-perf + review-arbiter | Adversarial review of fix |
| D5 | SHIP | nurse ×1, drone ×1 | Documentation + commit/PR |

The debug pipeline is **stateless** -- no state.json, no hooks, no Agent Teams. The `/ants:debug` command orchestrates all agents synchronously. Output files are written to `.agents/tmp/debug/`.

**Choose debug when:** You have a specific bug to investigate, want parallel investigation from multiple angles, and want user confirmation before applying the fix.

## Improve Pipeline

Use `/ants:improve` when you want to iteratively review existing code and fix all issues -- from info severity upwards -- until the code is clean or the iteration limit is reached.

```
  I0 Review          3 specialist sentinels review in parallel
       |                (correctness, security, performance)
       |              review-arbiter consolidates findings
       |
  I1 Fix             review-fixer applies targeted fixes
       |                (processes all severities: critical > warning > info)
       |
  [loop]             re-review after fixes, up to 5 iterations
       |
  I2 Report          summary of all iterations and remaining issues
```

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| I0 | REVIEW | sentinel-correctness + sentinel-security + sentinel-perf + review-arbiter | Parallel adversarial review + consolidation |
| I1 | FIX | review-fixer x1 | Apply targeted minimal fixes for all issues |
| I2 | REPORT | (orchestrator) | Display iteration-by-iteration summary |

The improve pipeline is **stateless** -- no state.json, no hooks, no Agent Teams. The `/ants:improve` command orchestrates all agents synchronously. Output files are written to `.agents/tmp/improve/`.

**Choose improve when:** You have existing code that works but want to systematically clean up all issues across correctness, security, and performance. Unlike swarm (which builds new features) or debug (which investigates specific bugs), improve focuses purely on iterating review-fix cycles until the code is clean.

**Severity policy:** The improve pipeline fixes ALL issue severities (info, warning, critical). This is intentionally more thorough than the swarm pipeline's queen, which only blocks on critical and warning issues.

### What's New in v0.5.2

- **Pipeline completion summaries** — All four pipelines now print a human-readable summary after execution completes:
  - `/ants:swarm` — displays "Ants Swarm — Complete" block with commit SHA, PR URL, files changed, tests added, loops taken, quality counts (critical/warning/info), and key evidence from the A4 verdict. Blocked and incomplete states also show structured diagnostic info.
  - `/ants:pswarm` — displays a per-run summary after each A5 ship, and a final "Ants pswarm — All Runs Complete" table with one row per run (commit, PR URL, files changed) and a total row when the pipeline stops.
  - `/ants:debug` — Step 8 now reads D4-quality.json for issue counts and D3-implementation.json for a files changed list, showing quality review results alongside the fix summary.
  - `/ants:improve` — I2 REPORT now specifies exact JSON field paths for reliable data reading, adds a Total row to the iteration table, and shows a clear stop reason (clean vs max iterations reached).

### What's New in v0.5.1

- **Queen as persistent central dispatcher** -- The queen agent is now the sole orchestrator of the A0→A5 pipeline. It dispatches each phase via SendMessage, receives results from agents, and evaluates the A4 verdict internally. This replaces the previous model where TeammateIdle/TaskCompleted hooks drove phase transitions.
- **explore-aggregator removed** -- The queen aggregates A0 exploration results directly, eliminating the explore-aggregator agent. All phase outputs are routed through the queen.
- **teams.sh SendMessage helpers** -- New helper functions for constructing and routing SendMessage payloads. Single-task model replaces multi-task dispatch. Control character stripping and `.from` allowlist validation added for message security.
- **Hook simplification** -- on-teammate-idle.sh, on-task-completed.sh, and on-stop.sh simplified. Hooks now handle supplementary gates only; all phase coordination is queen-driven.
- **Security and performance fixes** -- Unsanitized task_id input validated via `^[A-Za-z0-9_-]+$` regex gate; hot-path sequential `state_get` calls consolidated to single batched `jq` calls in on-teammate-idle.sh, circuit-breaker.sh, and teams.sh.

### What's New in v0.5.0

- **Self-improvement pipeline (`/ants:improve`)** -- New stateless pipeline that iteratively reviews code using adversarial sentinels and fixes all issues from info severity upwards. Reuses existing sentinel, arbiter, and review-fixer agents in a focused review-fix loop (up to 5 iterations). No state.json, no hooks -- follows the same stateless direct-dispatch model as `/ants:debug`.

### What's New in v0.4.4

- **Architect tool fix** -- `architect` agent now includes `Write` in its tools list, fixing a bug where the architect could not write its own plan file.
- **Guardian WebSearch guard** -- `guardian` agent prompt now includes an explicit activation guard consistent with the established opt-in `--web` pattern for WebSearch-capable agents.
- **Documentation corrections** -- `CLAUDE.md` architect roster row, hook behavior notes for `on-task-completed.sh` A2 gate, and the `A2-review.md` canonical `.status` field annotation updated to match actual implementation.

### What's New in v0.4.3

- **Opt-in WebSearch (`--web`)** -- New flag for both `/ants:swarm` and `/ants:pswarm`. When set, forager agents during A0 exploration and the architect during A1 planning can use WebSearch to research external library documentation, API references, and best practices. Stored as `webSearch: true` in state.json (v5). Off by default to avoid unnecessary web requests.
- **Message content sanitization** -- Agent prompt messages injected via teams.sh are now truncated to 500 characters per message, preventing runaway context inflation from large cross-phase messages.
- **State schema v5** -- Adds `webSearch` field; auto-migration from v4 (and earlier) is handled by state.sh.

### What's New in v0.4.2

- **Persistent swarm (`/ants:pswarm`)** -- New command that runs the full A0→A5 pipeline in a continuous loop. After each ship, all phases reset and the colony starts a fresh run. Stops when `--max-loops N` is exhausted, `shutdown = true` is set in state.json, or the circuit breaker trips. Each run gets a fresh codebase exploration so the architect re-plans incrementally on the evolved state.
- **`reset_phases_for_pswarm()`** (dag.sh) -- resets all phases A0-A5 to pending at each pswarm run boundary
- **`cb_reset_for_run()`** (circuit-breaker.sh) -- resets all circuit breaker counters at the run boundary so each run starts with a clean slate
- **State fields** -- `pswarmRun` (current run number) and `maxRuns` (from `--max-loops`) added for pswarm pipelines

### What's New in v0.4

- **Graceful shutdown** -- Set `.shutdown = true` in state.json to stop the workflow cleanly after in-progress phases complete
- **Plan approval gate** -- Architect plans require explicit approval (`.planApproved = true`) before advancing to blueprint review
- **Teammate messaging** -- Cross-phase communication via `add_message()` / `get_messages_for()` enables feedback loops without re-planning
- **Worktree isolation** -- Run workflows in git worktrees for concurrent execution on the same repository
- **Lint-on-save** -- PostToolUse hook runs language-aware linting (shell, JSON, Python) after edits during build/ship phases
- **HTTP webhooks** -- Fire-and-forget notifications for phase and workflow lifecycle events via configurable webhook URL
- **SubagentStart context injection** -- Teammates receive workflow state context (phase, loop, status) when spawned
- **PreCompact metadata** -- Critical workflow state is saved before context compaction for safe resumption
- **ConfigChange tracking** -- Configuration changes are snapshotted in state.json with timestamps
- **State schema v4** -- Adds 8 new fields: `worktreePath`, `messages`, `planApproved`, `shutdown`, `webhookUrl`, `lintConfig`, `configSnapshot`, `compactMetadata`

### What Was New in v0.3

- **Agent Teams delegate mode** -- Lead creates team, populates shared task list, enters delegate mode. Teammates self-claim work. No Ralph Loop
- **Auto-enable** -- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is auto-set by the swarm command. No user config needed
- **TeammateIdle/TaskCompleted hooks** -- Replace Stop/SubagentStop as workflow drivers. TeammateIdle assigns tasks, TaskCompleted validates output
- **State schema v3** -- Adds `teamName`, removes `dispatchMode` and `agentTeamsAvailable` fields

### What Was New in v0.2

- **Adversarial review teams** -- Three specialist sentinels (correctness, security, performance) replace the single generic sentinel, with a review-arbiter consolidating findings
- **Self-organizing task pool** -- Dependency-driven task dispatch replaces rigid wave barriers; tasks become ready as their dependencies complete
- **Circuit breaker** -- Consecutive failure tracking, per-phase fix budgets, and stage restart limits prevent infinite failure loops
- **5 new agents** -- sentinel-correctness, sentinel-security, sentinel-perf, review-arbiter, review-fixer (total: 16 agents)

### What Makes It Different

The key innovation is **Phase A3: Dual-Track Execution with Adversarial Review**. Instead of building everything then reviewing everything (sequential), ants runs two parallel tracks:

- **Build track:** Workers claim tasks from a self-organizing pool -- tasks with satisfied dependencies are dispatched in parallel automatically
- **Quality track (adversarial):** Three specialist sentinels review from different angles (correctness, security, performance), then an arbiter cross-references and deduplicates findings into a single verdict

This catches issues from multiple perspectives rather than relying on a single reviewer, and the queen synthesizes the arbiter's consolidated verdict before deciding to ship or loop.

## Agent Roster

| Agent | Role | Model | Phase |
|-------|------|-------|-------|
| forager | Breadth-first codebase scout (x2-4) | haiku | A0 |
| cartographer | Deep architecture tracer | sonnet | A0 |
| architect | Plans implementation with task assignments | sonnet | A1 |
| blueprint-reviewer | Validates plan completeness and task logic | sonnet | A2 |
| worker | Implements a single task (x1 per task) | inherit | A3 build |
| sentinel-correctness | Bugs, logic errors, error handling | sonnet | A3 quality, I0 |
| sentinel-security | OWASP, injection, secrets, access control | sonnet | A3 quality, I0 |
| sentinel-perf | N+1 queries, blocking I/O, complexity | sonnet | A3 quality, I0 |
| review-arbiter | Consolidates adversarial sentinel findings | sonnet | A3 quality, I0 |
| review-fixer | Targeted repair for review-fix cycles | inherit | A3 quality, I1 |
| guardian | Test writer for quality track | sonnet | A3 quality |
| queen | Persistent central dispatcher — drives A0→A5 via SendMessage, evaluates A4 verdict internally | sonnet | A0-A5 |
| nurse | Updates documentation | sonnet | A5 |
| drone | Commits and opens PR | inherit | A5 |
| bug-scout | Parallel bug investigator (×3) | haiku | D0 |
| solution-proposer | Proposes one specific fix approach (×3) | sonnet | D1 |
| solution-aggregator | Ranks and selects best fix | sonnet | D2 |
| fix-worker | Implements debug fix with tests | inherit | D3 |
| sentinel | (deprecated) Generic reviewer from v0.1 | sonnet | -- |

All 19 agent definitions are leaf agents (cannot spawn subagents). The swarm/pswarm workflow is driven by the queen agent via SendMessage — the queen dispatches each phase, receives results, and decides to advance or loop. Hooks provide supplementary gates (edit control, lint-on-save, config snapshots). The debug pipeline is orchestrated synchronously by the `/ants:debug` command.

## How It Works

### Queen-Driven Orchestration

The workflow is driven by the **queen agent** via SendMessage — not by TeammateIdle/TaskCompleted hooks:

1. The `/ants:swarm` command creates a team and spawns the queen as the persistent coordinator
2. The queen dispatches each phase by sending messages to specialist agents (forager, cartographer, architect, etc.)
3. Each agent reports results back to the queen via SendMessage
4. The queen evaluates A4 (verdict) internally — no separate agent is dispatched for sync
5. On a clean verdict the queen dispatches A5 (ship); on issues found it loops back to A1
6. Hooks provide supplementary gates: edit control (on-edit-gate.sh), lint-on-save, config snapshots, and compaction metadata

### Dual-Track Phase A3

```
Build Track                    Quality Track (Adversarial)
-----------                    ---------------------------
Task pool workers (parallel)
    |
    pool drained ----------->  sentinel-correctness  \
                                sentinel-security     } parallel
                                sentinel-perf        /
                                    |
                                review-arbiter (consolidate)
                                    |
                               A3-quality.json
    |                               |
    both complete --------------+---+
             |
          Phase A4
```

Workers claim tasks from the pool as dependencies are satisfied. Each worker implements exactly one task, self-verifies (tests, lint, typecheck), and reports results. Workers cannot use git (blocked by hook).

After all workers complete, three specialist sentinels review the output in parallel, each focusing on a different dimension. The review-arbiter then consolidates their findings into a single A3-quality.json.

### Circuit Breaker

The circuit breaker prevents runaway failure loops:

| Limit | Default | Description |
|-------|---------|-------------|
| Consecutive failures | 5 | Trips breaker, halts workflow |
| Fix attempts per phase | 5 | Budget for review-fix cycles |
| Stage restarts | 2 | Max A4-to-A1 loop-backs |

When any limit is exceeded, the workflow blocks with a diagnostic message. Success resets the consecutive failure counter.

### Loop-Back

If the queen finds unresolved critical or warning issues, the workflow loops back to A1. The architect reads the previous loop's feedback and plans targeted fixes (not a full re-plan). Maximum 5 loops before blocking.

## Comparison with Minions

| | ants:swarm | minions:superlaunch |
|---|-----------|---------------------|
| Phases | 6 (A0-A5) | 15 (S0-S14) |
| Build model | Task pool + adversarial review teams | Sequential with review-fix cycles |
| Review style | 3 specialist sentinels + arbiter | Single reviewer per phase |
| Loop type | Queen verdict -> re-plan (max 5, circuit breaker) | Per-review fix attempts + stage restarts |
| Agents | 20 colony-themed | 26+ generic |
| Failure handling | Circuit breaker with 3 tiers | Fix budget per review phase |
| Best for | Medium complexity tasks | Complex tasks needing thorough coverage |
| Theme | Ant colony | Minions |

**Choose ants when:** You want faster iteration with adversarial quality checks, self-organizing task dispatch, and a streamlined 6-phase pipeline.

**Choose minions when:** You need thorough 15-phase coverage with dedicated test development, failure analysis, and documentation phases.

## State and Output

Workflow state lives in `.agents/tmp/state.json` (v5 schema). Phase outputs are written to `.agents/tmp/phases/`. Loop-specific files are organized under `loop-{N}/` subdirectories.

All state and output files are gitignored. They are temporary artifacts of the workflow execution.

## Requirements

- Claude Code with plugin support
- `jq` installed (used by shell hooks for state management)
- `flock` available (used for atomic state updates; note: not stock macOS -- install via `brew install util-linux` or use the fallback path)

## License

MIT
