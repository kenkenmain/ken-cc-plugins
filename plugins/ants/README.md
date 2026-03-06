# ants

Ant-colony themed swarm workflow for Claude Code. Builds software using parallel agent waves with dual-track execution: workers build while sentinels review, synchronized by a queen.

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

This launches a 6-phase pipeline that explores the codebase, plans the implementation, builds in parallel waves with concurrent quality review, and ships the result.

## Pipeline Overview

```
  A0 Explore         foragers + cartographer scout the codebase
       |
  A1 Architect        plans implementation with wave assignments
       |
  A2 Blueprint Review validates the plan before building
       |
  A3 Dual-Track       workers build in waves, sentinels review each wave
       |
  A4 Queen Sync       merges tracks, decides: ship or loop back
      / \
  ship   loop ------> back to A1 (max 5 loops)
   |
  A5 Ship             update docs, commit, open PR
```

### What Makes It Different

The key innovation is **Phase A3: Dual-Track Execution**. Instead of building everything then reviewing everything (sequential), ants runs two parallel tracks:

- **Build track:** Workers implement tasks in waves (Wave 1 foundation, then Wave 2 dependent work)
- **Quality track:** Soldiers review each wave as it completes

This catches issues per-wave rather than at the end, and the queen synthesizes both tracks before deciding to ship or loop.

## Agent Roster

| Agent | Role | Model | Phase |
|-------|------|-------|-------|
| forager | Breadth-first codebase scout (x2-4) | haiku | A0 |
| cartographer | Deep architecture tracer | sonnet | A0 |
| explore-aggregator | Merges exploration results | haiku | A0 |
| architect | Plans implementation with wave assignments | sonnet | A1 |
| blueprint-reviewer | Validates plan completeness and wave logic | sonnet | A2 |
| worker | Implements a single task (x1 per task per wave) | inherit | A3 build |
| sentinel | Sentinel code reviewer (per wave) | sonnet | A3 quality |
| queen | Merges tracks, renders ship/loop verdict | sonnet | A4 |
| nurse | Updates documentation | sonnet | A5 |
| drone | Commits and opens PR | inherit | A5 |

All 10 agent definitions are leaf agents (cannot spawn subagents). The orchestrator loop is driven entirely by hooks.

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
Build Track              Quality Track
-----------              -------------
Wave 1 workers           (wait)
    |
    barrier -----------> Soldiers review Wave 1
    |
Wave 2 workers           (wait)
    |
    barrier -----------> Soldiers review Wave 2
    |
    both complete -----> Phase A4
```

Workers in the same wave run in parallel. Each worker implements exactly one task, self-verifies (tests, lint, typecheck), and reports results. Workers cannot use git (blocked by hook).

Soldiers run sentinel reviews after each wave, checking correctness, coverage, and integration risks.

### Loop-Back

If the queen finds unresolved critical or warning issues, the workflow loops back to A1. The architect reads the previous loop's feedback and plans targeted fixes (not a full re-plan). Maximum 5 loops before blocking.

## Comparison with Minions

| | ants:swarm | minions:superlaunch |
|---|-----------|---------------------|
| Phases | 6 (A0-A5) | 15 (S0-S14) |
| Build model | Dual-track (build + quality in parallel) | Sequential with review-fix cycles |
| Loop type | Queen verdict -> re-plan (max 5) | Per-review fix attempts + stage restarts |
| Agents | 11 colony-themed | 26+ generic |
| Best for | Medium complexity tasks | Complex tasks needing thorough coverage |
| Theme | Ant colony | Minions |

**Choose ants when:** You want faster iteration with parallel quality checks and a streamlined 6-phase pipeline.

**Choose minions when:** You need thorough 15-phase coverage with dedicated test development, failure analysis, and documentation phases.

## State and Output

Workflow state lives in `.agents/tmp/state.json`. Phase outputs are written to `.agents/tmp/phases/`. Loop-specific files are organized under `loop-{N}/` subdirectories.

All state and output files are gitignored. They are temporary artifacts of the workflow execution.

## Requirements

- Claude Code with plugin support
- `jq` installed (used by shell hooks for state management)
- `flock` available (used for atomic state updates; note: not stock macOS -- install via `brew install util-linux` or use the fallback path)

## License

MIT
