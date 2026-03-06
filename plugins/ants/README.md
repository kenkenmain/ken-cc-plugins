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
```

This launches a 6-phase pipeline that explores the codebase, plans the implementation, builds with a self-organizing task pool, runs adversarial review, and ships the result.

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

### What's New in v0.2

- **Adversarial review teams** -- Three specialist sentinels (correctness, security, performance) replace the single generic sentinel, with a review-arbiter consolidating findings
- **Self-organizing task pool** -- Dependency-driven task dispatch replaces rigid wave barriers; tasks become ready as their dependencies complete
- **Circuit breaker** -- Consecutive failure tracking, per-phase fix budgets, and stage restart limits prevent infinite failure loops
- **Agent Teams readiness** -- Dispatch abstraction layer prepared for Claude Code Agent Teams API migration
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

All 16 agent definitions are leaf agents (cannot spawn subagents). The orchestrator loop is driven entirely by hooks.

## How It Works

### Ralph Loop Pattern

The workflow is driven by shell hooks, not conversation memory:

1. The `/ants:swarm` command initializes state and dispatches Phase A0
2. When the subagent completes, the **SubagentStop hook** validates output and advances state
3. When Claude tries to stop, the **Stop hook** generates a phase-specific prompt and blocks the stop
4. Claude receives the prompt, reads state from disk, and dispatches the next phase
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

Workflow state lives in `.agents/tmp/state.json` (v2 schema). Phase outputs are written to `.agents/tmp/phases/`. Loop-specific files are organized under `loop-{N}/` subdirectories.

All state and output files are gitignored. They are temporary artifacts of the workflow execution.

## Agent Teams Readiness

The dispatch layer is prepared for migration to the Claude Code Agent Teams API (currently experimental). When the API stabilizes:

1. Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
2. Update dispatch mode in `lib/teams.sh`
3. Enable `TeammateIdle` and `TaskCompleted` hooks

See `docs/teams-migration.md` for the complete migration guide. Rollback is immediate by unsetting the env var.

## Requirements

- Claude Code with plugin support
- `jq` installed (used by shell hooks for state management)
- `flock` available (used for atomic state updates; note: not stock macOS -- install via `brew install util-linux` or use the fallback path)

## License

MIT
