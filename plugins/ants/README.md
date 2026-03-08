# ants

Ant-colony themed swarm workflow for Claude Code. Builds software using parallel agents with adversarial review teams: workers build while specialist sentinels review from three angles, an arbiter consolidates findings, and a queen decides to ship or loop.

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

/ants:pswarm Continuously improve test coverage --max-loops 10
/ants:pswarm Fix all lint warnings --worktree
```

The `--worktree` flag creates a git worktree for isolated development, enabling multiple workflows to run concurrently on the same repository.

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
| explore-aggregator | Merges exploration results | haiku | A0 |
| architect | Plans implementation with task assignments | sonnet | A1 |
| blueprint-reviewer | Validates plan completeness and task logic | sonnet | A2 |
| worker | Implements a single task (x1 per task) | inherit | A3 build |
| sentinel-correctness | Bugs, logic errors, error handling | sonnet | A3 quality |
| sentinel-security | OWASP, injection, secrets, access control | sonnet | A3 quality |
| sentinel-perf | N+1 queries, blocking I/O, complexity | sonnet | A3 quality |
| review-arbiter | Consolidates adversarial sentinel findings | sonnet | A3 quality |
| review-fixer | Targeted repair for review-fix cycles | inherit | A3 quality |
| guardian | Test writer for quality track | sonnet | A3 quality |
| queen | Merges tracks, renders ship/loop verdict | sonnet | A4 |
| nurse | Updates documentation | sonnet | A5 |
| drone | Commits and opens PR | inherit | A5 |
| sentinel | (deprecated) Generic reviewer from v0.1 | sonnet | -- |

All 16 agent definitions are leaf agents (cannot spawn subagents). The workflow is driven by Agent Teams hooks (TeammateIdle/TaskCompleted).

## How It Works

### Agent Teams Delegate Mode

The workflow is driven by Agent Teams, not conversation memory:

1. The `/ants:swarm` command auto-enables Agent Teams, creates a team, and populates the task list
2. Lead spawns 3-5 teammates and enters delegate mode (coordination-only)
3. When a teammate goes idle, the **TeammateIdle hook** assigns the next ready phase
4. When a teammate completes a task, the **TaskCompleted hook** validates output and advances state
5. This repeats until the workflow completes or blocks

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
| Agents | 16 colony-themed | 26+ generic |
| Failure handling | Circuit breaker with 3 tiers | Fix budget per review phase |
| Best for | Medium complexity tasks | Complex tasks needing thorough coverage |
| Theme | Ant colony | Minions |

**Choose ants when:** You want faster iteration with adversarial quality checks, self-organizing task dispatch, and a streamlined 6-phase pipeline.

**Choose minions when:** You need thorough 15-phase coverage with dedicated test development, failure analysis, and documentation phases.

## State and Output

Workflow state lives in `.agents/tmp/state.json` (v4 schema). Phase outputs are written to `.agents/tmp/phases/`. Loop-specific files are organized under `loop-{N}/` subdirectories.

All state and output files are gitignored. They are temporary artifacts of the workflow execution.

## Requirements

- Claude Code with plugin support
- `jq` installed (used by shell hooks for state management)
- `flock` available (used for atomic state updates; note: not stock macOS -- install via `brew install util-linux` or use the fallback path)

## License

MIT
