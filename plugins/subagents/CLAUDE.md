# Subagents Plugin - Agent Instructions

This plugin implements a 2-level agent architecture for Claude Code with file-based state transfer.

## Architecture Overview (v2)

```
Main Conversation (Orchestrator)
├── Dispatches parallel Explore agents (1-10)
├── Dispatches parallel Plan agents (1-10)
├── Dispatches parallel Task agents in waves
└── Coordinates via file-based state
```

**Key Design:** Main conversation handles all coordination inline via skills. Subagents are only spawned for parallel exploration, planning, and task execution.

## Workflow Stages

```
EXPLORE → PLAN → IMPLEMENT → TEST → FINAL
```

### EXPLORE Stage (Phase 0)

- Dispatches 1-10 parallel Explore agents based on task complexity
- Output: `.agents/tmp/phases/0-explore.md`

### PLAN Stage (Phases 1.1-1.3)

- 1.1: Inline brainstorming
- 1.2: Parallel Plan agents for detailed planning
- 1.3: Codex MCP review of plan
- Output: `.agents/tmp/phases/1.2-plan.md`

### IMPLEMENT Stage (Phases 2.1-2.3)

- 2.1: Wave-based task execution with dependency ordering
- 2.2: Code simplification pass
- 2.3: Codex MCP implementation review
- Output: `.agents/tmp/phases/2.1-tasks.json`

### TEST Stage (Phases 3.1-3.3)

- 3.1: Run lint and test commands
- 3.2: Analyze failures and optionally fix
- 3.3: Codex MCP test review

### FINAL Stage (Phases 4.1-4.3)

- 4.1: Documentation updates
- 4.2: Final Codex MCP review (codex-xhigh)
- 4.3: Git branch and PR creation

## State Management

State file: `.agents/tmp/state.json`

All phase outputs: `.agents/tmp/phases/`

State and phase files are excluded from git commits via `.gitignore`.

## Model vs MCP Tool Namespaces

**These are SEPARATE namespaces. Never mix them.**

| Type      | Valid Values                                        | Usage                       |
| --------- | --------------------------------------------------- | --------------------------- |
| ModelId   | `sonnet-4.5`, `opus-4.5`, `sonnet`, `opus`, `haiku` | Task tool `model` parameter |
| McpToolId | `codex-high`, `codex-xhigh`                         | Review phase `tool` field   |

## Complexity Scoring

Task complexity determines model selection:

| Level  | Model       | Criteria                                 |
| ------ | ----------- | ---------------------------------------- |
| Easy   | sonnet-4.5  | Single file, <50 LOC                     |
| Medium | opus-4.5    | 2-3 files, 50-200 LOC                    |
| Hard   | codex-xhigh | 4+ files, >200 LOC, security/concurrency |

## Context Compaction

Configurable compaction between stages and/or phases:

- `compaction.betweenStages: true` (default) - Compact after each stage
- `compaction.betweenPhases: false` (default) - Optional per-phase compaction

Compaction writes summary to file and clears conversation context.

## Commands

- `/subagents:dispatch <task>` - Start workflow
- `/subagents:stop` - Stop gracefully with checkpoint
- `/subagents:resume` - Resume from checkpoint
- `/subagents:status` - Show progress
- `/subagents:configure` - Configure settings

## Skills

- `workflow` - Main orchestration (replaces orchestrator agent)
- `state-manager` - File-based state persistence
- `explore-dispatcher` - Parallel Explore agent dispatch
- `plan-dispatcher` - Parallel Plan agent dispatch
- `task-dispatcher` - Wave-based Task agent dispatch
- `configuration` - Config loading and merging
