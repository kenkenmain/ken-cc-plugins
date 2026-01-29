# Subagents Plugin

2-level agent architecture with parallel subagents and file-based state transfer for Claude Code.

## Overview

Orchestrates complex tasks through a main conversation that dispatches parallel subagents for exploration, planning, and task execution.

```
┌─────────────────────────────────────────────────────┐
│ Main Conversation (Orchestrator)                    │
│   ├─ EXPLORE stage (parallel Explore agents)        │
│   ├─ PLAN stage (parallel Plan agents)              │
│   ├─ IMPLEMENT stage (parallel Task agents)         │
│   ├─ TEST stage                                     │
│   └─ FINAL stage                                    │
└─────────────────────────────────────────────────────┘
         │
         ▼ Dispatches via Task tool
┌─────────────────────────────────────────────────────┐
│ Parallel Subagents (minimal context)                │
│   ├─ Explore agents (1-10, codebase exploration)    │
│   ├─ Plan agents (1-10, detailed planning)          │
│   └─ Task agents (wave-based, implementation)       │
└─────────────────────────────────────────────────────┘
```

## Installation

```bash
claude plugin install ./plugins/subagents
```

## Commands

### `/subagents:dispatch <task>`

Start a new workflow.

**Options:**

- `--no-test` - Skip TEST stage
- `--stage <name>` - Start from specific stage (EXPLORE, PLAN, IMPLEMENT, TEST, FINAL)
- `--plan <path>` - Use external plan file (for starting at IMPLEMENT)

```
/subagents:dispatch Add user authentication with OAuth support
/subagents:dispatch --no-test Refactor the payment module
/subagents:dispatch --stage IMPLEMENT --plan docs/plans/my-plan.md Continue from plan
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
| 1.1   | Brainstorm  | Inline analysis and approach design      |
| 1.2   | Plan        | Parallel detailed planning (1-10 agents) |
| 1.3   | Plan Review | Validate plan via Codex MCP              |

### IMPLEMENT Stage

| Phase | Name                  | Description                         |
| ----- | --------------------- | ----------------------------------- |
| 2.1   | Tasks                 | Wave-based parallel task execution  |
| 2.2   | Simplify              | Code simplification pass            |
| 2.3   | Implementation Review | Review implementation via Codex MCP |

### TEST Stage

| Phase | Name        | Description              |
| ----- | ----------- | ------------------------ |
| 3.1   | Run Tests   | Execute lint and tests   |
| 3.2   | Analyze     | Analyze failures and fix |
| 3.3   | Test Review | Validate test coverage   |

### FINAL Stage

| Phase | Name         | Description                      |
| ----- | ------------ | -------------------------------- |
| 4.1   | Docs         | Update documentation             |
| 4.2   | Final Review | Final validation via codex-xhigh |
| 4.3   | Completion   | Git branch and PR creation       |

## Complexity Scoring

Tasks classified at runtime for model selection:

| Level  | Execution               | Criteria                                 |
| ------ | ----------------------- | ---------------------------------------- |
| Easy   | Task agent (sonnet-4.5) | Single file, <50 LOC                     |
| Medium | Task agent (opus-4.5)   | 2-3 files, 50-200 LOC                    |
| Hard   | Codex MCP (codex-xhigh) | 4+ files, >200 LOC, security/concurrency |

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
    "PLAN": { "maxParallelAgents": 10 },
    "IMPLEMENT": {
      "complexityModels": {
        "easy": "sonnet-4.5",
        "medium": "opus-4.5",
        "hard": "codex-xhigh"
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
| ModelId   | `sonnet-4.5`, `opus-4.5`, `sonnet`, `opus`, `haiku` | Task tool `model` parameter |
| McpToolId | `codex-high`, `codex-xhigh`                         | Review phase `tool` field   |

## License

MIT
