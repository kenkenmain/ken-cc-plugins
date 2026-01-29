# Subagents Plugin

4-tier hierarchical agent architecture with context isolation and complexity scoring for Claude Code.

## Overview

Multi-tier agent system that breaks complex tasks into focused work units with strictly limited context per tier.

```
┌─────────────────────────────────────────────────────┐
│ Tier 1: Orchestrator (full context)                 │
│   ├─ PLAN stage                                     │
│   ├─ IMPLEMENT stage                                │
│   ├─ TEST stage                                     │
│   └─ FINAL stage                                    │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│ Tier 2: Stage Agent (stage config only)             │
│   └─ Dispatches phases sequentially                 │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│ Tier 3: Phase Agent (phase config + task IDs)       │
│   ├─ Classifies task complexity dynamically         │
│   ├─ Builds dependency graph                        │
│   └─ Dispatches task agents in waves                │
└─────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────┐
│ Tier 4: Task Agent (single task context only)       │
│   └─ Executes one specific task                     │
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
- `--stage <name>` - Start from specific stage (PLAN, IMPLEMENT, TEST, FINAL)

```
/subagents:dispatch Add user authentication with OAuth support
/subagents:dispatch --no-test Refactor the payment module
```

### `/subagents:status`

Show current workflow progress.

### `/subagents:stop`

Stop workflow gracefully. State preserved for resume.

### `/subagents:resume`

Resume stopped workflow from last checkpoint.

### `/subagents:configure`

Configure plugin settings (models, timeouts, severity thresholds).

**Options:**

- `--show` - Display current configuration
- `--reset` - Reset to defaults

## Stages and Phases

### PLAN Stage

| Phase | Name        | Description                         |
| ----- | ----------- | ----------------------------------- |
| 1.1   | Brainstorm  | Generate implementation ideas       |
| 1.2   | Write Plan  | Create detailed implementation plan |
| 1.3   | Plan Review | Validate plan via codex-high        |

### IMPLEMENT Stage

| Phase | Name             | Description                           |
| ----- | ---------------- | ------------------------------------- |
| 2.0   | Classification   | Score task complexity dynamically     |
| 2.1   | Implementation   | Execute tasks with appropriate models |
| 2.2   | Simplify         | Refactor for clarity                  |
| 2.3   | Implement Review | Review implementation quality         |

### TEST Stage

| Phase | Name        | Description            |
| ----- | ----------- | ---------------------- |
| 3.1   | Test Plan   | Design test strategy   |
| 3.2   | Write Tests | Implement tests        |
| 3.3   | Test Review | Validate test coverage |

### FINAL Stage

| Phase | Name               | Description                      |
| ----- | ------------------ | -------------------------------- |
| 4.0   | Document Updates   | Update documentation             |
| 4.1   | Codex Final        | Final validation via codex-xhigh |
| 4.2   | Suggest Extensions | Propose future improvements      |
| 4.3   | Completion         | Finalize and cleanup             |

## Complexity Scoring

Tasks classified dynamically at runtime:

| Level  | Model                     | Criteria                                 |
| ------ | ------------------------- | ---------------------------------------- |
| Easy   | sonnet                    | Single file, <50 LOC                     |
| Medium | opus                      | 2-3 files, 50-200 LOC                    |
| Hard   | opus + codex-xhigh review | 4+ files, >200 LOC, security/concurrency |

## Context Isolation

Each tier receives minimal context:

| Field              | Max Length     | Description                       |
| ------------------ | -------------- | --------------------------------- |
| Task description   | 100 chars      | Brief summary                     |
| Instructions       | 2000 chars     | Implementation guidance           |
| Dependency outputs | 500 chars each | Summaries from prerequisite tasks |

## Configuration

Configuration is stored in:

- **Global:** `~/.claude/subagents-config.json`
- **Project:** `.claude/subagents-config.json`

Project configuration overrides global.

### Default Configuration (Simplified View)

```json
{
  "version": "1.1",
  "defaults": {
    "model": "sonnet",
    "testStage": true,
    "gitWorkflow": "branch+PR",
    "blockOnSeverity": "low"
  },
  "parallelism": {
    "maxParallelTasks": 5
  },
  "git": {
    "excludePatterns": [".agents/**", "docs/plans/**", "*.tmp", "*.log"]
  }
}
```

See the `configuration` skill for the full schema with per-stage options.

## State Management

Workflow state tracked in `.agents/subagents-state.json`:

- Current stage, phase, and task progress
- Stop/resume functionality
- Automatically excluded from git commits

## Model Namespaces

**Critical:** Model IDs and MCP Tool IDs are separate namespaces.

| Type      | Valid Values                         | Usage                       |
| --------- | ------------------------------------ | --------------------------- |
| ModelId   | `sonnet`, `opus`, `haiku`, `inherit` | Task tool `model` parameter |
| McpToolId | `codex-high`, `codex-xhigh`          | Review phase `tool` field   |

## License

MIT
