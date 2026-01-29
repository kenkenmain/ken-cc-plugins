# Subagents Plugin - Agent Instructions

This plugin implements a 4-tier hierarchical agent architecture for Claude Code.

## Architecture Overview

```
Tier 1: Orchestrator  - Full conversation context, coordinates stages
Tier 2: Stage Agent   - Stage config only, executes phases sequentially
Tier 3: Phase Agent   - Phase config + task IDs, dispatches task agents
Tier 4: Task Agent    - Single task context only, executes one task
```

## Context Isolation

**Critical:** Context flows DOWNWARD only. Each tier receives minimal context:

| Field                | Max Length     | Passed To    |
| -------------------- | -------------- | ------------ |
| Task description     | 100 chars      | Task agents  |
| Instructions         | 2000 chars     | Task agents  |
| Dependency summaries | 500 chars each | Task agents  |
| Stage summary        | 1 paragraph    | Stage agents |
| Phase summary        | 1 paragraph    | Phase agents |

## Model vs MCP Tool Namespaces

**These are SEPARATE namespaces. Never mix them.**

| Type      | Valid Values                         | Usage                       |
| --------- | ------------------------------------ | --------------------------- |
| ModelId   | `sonnet`, `opus`, `haiku`, `inherit` | Task tool `model` parameter |
| McpToolId | `codex-high`, `codex-xhigh`          | Review phase `tool` field   |

## Complexity Scoring

Dynamic classification at runtime by the phase agent:

| Level  | Model                     | Criteria                                 |
| ------ | ------------------------- | ---------------------------------------- |
| Easy   | sonnet                    | Single file, <50 LOC                     |
| Medium | opus                      | 2-3 files, 50-200 LOC                    |
| Hard   | opus + codex-xhigh review | 4+ files, >200 LOC, security/concurrency |

## State Management

- State file: `.agents/subagents-state.json`
- Use atomic writes (temp file + rename)
- State files are excluded from git commits

## Commands

- `/subagents:dispatch <task>` - Start workflow
- `/subagents:stop` - Stop gracefully
- `/subagents:resume` - Resume from checkpoint
- `/subagents:status` - Show progress
- `/subagents:configure` - Configure settings
