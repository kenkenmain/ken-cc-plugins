# Subagents Plugin

2-level agent architecture with parallel subagents and file-based state transfer for Claude Code.

## Overview

Orchestrates complex tasks through a main conversation that dispatches parallel subagents for exploration, planning, and task execution.

```
┌───────────────────────────────────────────────────────────┐
│ Pre-Workflow                                              │
│   └─ init-claude (state init, worktree, agent defaults)   │
└───────────────────────────────────────────────────────────┘
         │
         ▼
┌───────────────────────────────────────────────────────────┐
│ Main Conversation (Orchestrator)                          │
│   ├─ EXPLORE stage (parallel Explore agents)              │
│   ├─ PLAN stage (parallel Plan agents)                    │
│   ├─ IMPLEMENT stage (complexity-routed Task agents)      │
│   ├─ TEST stage                                           │
│   └─ FINAL stage                                          │
└───────────────────────────────────────────────────────────┘
         │
         ▼ Dispatches via Task tool
┌───────────────────────────────────────────────────────────┐
│ Parallel Subagents (minimal context)                      │
│   ├─ Explore agents (1-10, codebase exploration)          │
│   ├─ Plan agents (1-10, detailed planning)                │
│   └─ Task agents (wave-based, complexity-routed):         │
│       ├─ Easy  → sonnet-task-agent (direct, sonnet)       │
│       ├─ Medium → opus-task-agent (direct, opus)          │
│       └─ Hard  → codex-task-agent or opus-task-agent      │
└───────────────────────────────────────────────────────────┘
```

## Installation

```bash
claude plugin install ./plugins/subagents
```

## Commands

### `/subagents:init <task>`

Main entry point. Creates a git worktree for isolated development, then starts a subagent workflow. The worktree persists across Claude restarts.

```
/subagents:init Add OAuth support
/subagents:init --claude Add OAuth support
/subagents:init --no-worktree Quick config fix
/subagents:init --claude --no-test Refactor module
```

Use `--claude` for Claude-only mode (no Codex MCP). All other flags pass through to dispatch.

### `/subagents:teardown`

Commit, push to GitHub, create PR, and remove worktree.

```
/subagents:teardown
/subagents:teardown --no-pr
/subagents:teardown --force
```

### `/subagents:preflight`

Run pre-flight checks and environment setup. Verifies git, superpowers plugin, build tools, and Codex MCP availability.

```
/subagents:preflight
/subagents:preflight --fix
```

### `/subagents:dispatch <task>`

Start a new workflow with Codex MCP defaults (Codex reviewers configured by default, runtime fallback if unavailable).

**Options:**

- `--no-test` - Skip TEST stage
- `--no-worktree` - Skip git worktree creation (work directly in project directory)
- `--no-web-search` - Disable web search for libraries
- `--profile minimal|standard|thorough` - Override pipeline profile selection
- `--stage <name>` - Start from specific stage (EXPLORE, PLAN, IMPLEMENT, TEST, FINAL)
- `--plan <path>` - Use external plan file (for starting at IMPLEMENT)

```
/subagents:dispatch Add user authentication with OAuth support
/subagents:dispatch --no-test Refactor the payment module
/subagents:dispatch --no-worktree Quick config fix
/subagents:dispatch --no-web-search --profile minimal Fix typo in README
/subagents:dispatch --stage IMPLEMENT --plan docs/plans/my-plan.md Continue from plan
```

### `/subagents:dispatch-claude <task>`

Start a new workflow using Claude agents only (no Codex MCP dependency). Same stages, schedule, and gates as `dispatch` — only the agent defaults differ.

**Options:** Same as `dispatch`.

```
/subagents:dispatch-claude Add user authentication with OAuth support
/subagents:dispatch-claude --no-test Refactor the payment module
```

### `/subagents:status`

Show current workflow progress.

### `/subagents:stop`

Stop workflow gracefully. State preserved for resume.

### `/subagents:resume`

Resume stopped workflow from last checkpoint.

**Options:**

- `--from-phase X.X` - Resume from specific phase
- `--retry-failed` - Retry failed phase/task
- `--restart-stage` - Restart current stage from first phase
- `--restart-previous` - Restart previous stage (fix root cause)

### `/subagents:configure`

Configure plugin settings (models, timeouts, severity thresholds).

**Options:**

- `--show` - Display current configuration
- `--reset` - Reset to defaults
- `--edit` - Open config file for editing

## Stages and Phases

### EXPLORE Stage

| Phase | Name    | Description                          |
| ----- | ------- | ------------------------------------ |
| 0     | Explore | Parallel codebase exploration (1-10) |

### PLAN Stage

| Phase | Name        | Description                              |
| ----- | ----------- | ---------------------------------------- |
| 1.1   | Brainstorm  | Standalone analysis and approach design   |
| 1.2   | Plan        | Parallel detailed planning (1-10 agents) |
| 1.3   | Plan Review | Validate plan (Codex MCP or Claude reviewer) |

### IMPLEMENT Stage

| Phase | Name                  | Description                                                      |
| ----- | --------------------- | ---------------------------------------------------------------- |
| 2.1   | Tasks (+ Tests)       | Wave-based parallel task execution with hybrid test writing      |
| 2.2   | Simplify              | Code simplification pass (thorough profile only)                 |
| 2.3   | Implementation Review | Review implementation + test quality (Codex MCP or Claude)       |

Note: Phase 2.2 only included in thorough pipeline profile.

### TEST Stage

| Phase | Name            | Description                                            |
| ----- | --------------- | ------------------------------------------------------ |
| 3.1   | Run Tests       | Execute lint/tests AND analyze failures (merged phase)  |
| 3.2   | Analyze         | Deep failure analysis (thorough profile only)          |
| 3.3   | Develop Tests   | Gap-filler: fill coverage gaps from hybrid test output  |
| 3.4   | Test Dev Review | Review test development quality                        |
| 3.5   | Test Review     | Final test stage review + coverage threshold check     |

Notes: Phase 3.1 produces both test results and failure analysis. Phase 3.2 only in thorough profile. Phase 3.3 reads testsWritten from Phase 2.1 to avoid duplicating tests already written by task agents.

### FINAL Stage

| Phase | Name         | Description                      |
| ----- | ------------ | -------------------------------- |
| 4.1   | Docs         | Update documentation             |
| 4.2   | Final Review | Final validation (Codex MCP or Claude) |
| 4.3   | Completion   | Git branch and PR creation       |

## Complexity Scoring

Tasks classified at runtime for agent routing:

| Level  | Agent (Codex mode)  | Agent (Claude mode) | Criteria                                 |
| ------ | ------------------- | ------------------- | ---------------------------------------- |
| Easy   | sonnet-task-agent   | sonnet-task-agent   | Single file, <50 LOC                     |
| Medium | opus-task-agent     | opus-task-agent     | 2-3 files, 50-200 LOC                    |
| Hard   | codex-task-agent    | opus-task-agent     | 4+ files, >200 LOC, security/concurrency |

## Hybrid Test-Alongside-Code

Task agents in Phase 2.1 write unit tests alongside their implementation code. Phase 3.3 then acts as a gap-filler — reading the `testsWritten` arrays from `2.1-tasks.json` and only writing tests for uncovered functionality.

Skip conditions for test writing in Phase 2.1:
- Config-only changes
- Generated code
- Documentation-only changes
- Test-file-only changes

## Pipeline Profiles

Profile auto-selected based on task complexity (or `--profile` override):

| Profile    | Phases | Stages                                    | When Used                              |
| ---------- | ------ | ----------------------------------------- | -------------------------------------- |
| `minimal`  | 5      | EXPLORE, IMPLEMENT, FINAL                 | Simple: typo, rename, config, single file |
| `standard` | 13     | EXPLORE, PLAN, IMPLEMENT, TEST, FINAL     | Medium: feature, bugfix, 2-5 files     |
| `thorough` | 15     | EXPLORE, PLAN, IMPLEMENT, TEST, FINAL     | Complex: architecture, security, 6+ files |

`thorough` adds Phase 2.2 (Simplify) and Phase 3.2 (Analyze Failures) over `standard`.

## Configuration

Configuration is stored in:

- **Global:** `~/.claude/subagents-config.json`
- **Project:** `.claude/subagents-config.json`

Project configuration overrides global.

### Default Configuration (Simplified View)

```json
{
  "version": "2.0",
  "defaults": {
    "model": "sonnet-4.5",
    "gitWorkflow": "branch+PR",
    "blockOnSeverity": "low"
  },
  "stages": {
    "EXPLORE": { "maxParallelAgents": 10 },
    "PLAN": { "planning": { "maxParallelAgents": 10 } },
    "IMPLEMENT": {
      "tasks": {
        "complexityModels": {
          "easy": "sonnet-task-agent",
          "medium": "opus-task-agent",
          "hard": "codex-task-agent"
        }
      }
    }
  },
  "compaction": {
    "betweenStages": true,
    "betweenPhases": false
  }
}
```

See the `configuration` skill for the full schema with per-stage options.

## Schedule & Stage Gates

All phases are pre-scheduled when a workflow starts. Stage transitions are enforced by gates that require review output files to exist before proceeding.

**Gates prevent review phases from being skipped.** If a review fails after max retries, the workflow blocks rather than silently skipping to the next stage.

View schedule progress with `/subagents:status`:
```
Schedule (5/15 phases):
  ✓ Phase 0   │ EXPLORE   │ Explore         │ completed
  ✓ Phase 1.1 │ PLAN      │ Brainstorm      │ completed
  ...
  · Phase 2.3 │ IMPLEMENT │ Impl Review     │ pending   [GATE]
```

Gates:
- EXPLORE → PLAN: requires `0-explore.md`
- PLAN → IMPLEMENT: requires `1.1-brainstorm.md`, `1.2-plan.md`, `1.3-plan-review.json`
- IMPLEMENT → TEST: requires `2.1-tasks.json`, `2.3-impl-review.json`
- TEST → FINAL: requires `3.1-test-results.json`, `3.3-test-dev.json`, `3.5-test-review.json`
- FINAL → COMPLETE: requires `4.2-final-review.json`

## State Management

Workflow state tracked in `.agents/tmp/state.json`:

- Current stage, phase, and task progress
- Stop/resume functionality with failure recovery
- Phase outputs in `.agents/tmp/phases/`
- Automatically excluded from git commits

## Model Namespaces

**Critical:** Model IDs and MCP Tool IDs are separate namespaces.

| Type      | Valid Values                                        | Usage                       |
| --------- | --------------------------------------------------- | --------------------------- |
| ModelId   | `sonnet-4.5`, `opus-4.5`, `haiku-4.5`, `inherit`    | Task tool `model` parameter |
| McpToolId | `codex-high`                                        | Review phase `tool` field   |

## License

MIT
