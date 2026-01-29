# Subagents v2: Flattened Architecture

## Summary

Redesign the subagents plugin to work within Claude Code's constraint that subagents cannot spawn other subagents. The new architecture uses a two-level model (orchestrator + task agents) with file-based state transfer and configurable context compaction.

## Problem Statement

The current 4-tier hierarchical architecture (Orchestrator → Stage → Phase → Task) assumed nested subagent spawning. Claude Code does not support this—subagents can only be dispatched from the main conversation. The intermediate tiers (Stage, Phase agents) execute but cannot delegate further, making the hierarchy ineffective.

**Evidence:** Subagent transcripts show `isSidechain: true` but no nested agent spawning. Stage agents did the work inline instead of delegating to phase/task agents.

## Design Goals

1. Work within Claude Code's single-level subagent model
2. Preserve parallel execution for independent work
3. Maintain context isolation between stages
4. Support failure recovery and resumption
5. Keep the phased workflow structure (it's useful)

## Architecture

### Two-Level Model

```
Orchestrator (main conversation)
│
├── Inline coordination via skills
│   - configuration (load/merge config)
│   - complexity-scorer (determine agent counts)
│   - Plan review via Codex MCP
│
└── Parallel subagent dispatch
    - Explore agents (Phase 0)
    - Plan agents (Phase 1.2)
    - Task agents (Phase 2.1)
```

### Workflow Stages

```
EXPLORE Stage (new)
  └── Phase 0: Parallel Explore
      ├── 1-10 Explore agents (sonnet)
      ├── Orchestrator determines count based on task complexity
      └── Output: .agents/phases/0-explore.md

PLAN Stage
  ├── Phase 1.1: Brainstorm (inline)
  │   └── Orchestrator analyzes explore findings, determines approach
  ├── Phase 1.2: Parallel Plan
  │   ├── 1-10 Plan agents (sonnet)
  │   ├── Each plans a specific aspect (db, api, ui, tests, etc.)
  │   └── Output: .agents/phases/1.2-plan.md (merged)
  └── Phase 1.3: Plan Review
      └── Codex MCP review

IMPLEMENT Stage
  ├── Phase 2.1: Parallel Task Execution
  │   ├── Task agents dispatched in waves
  │   ├── Wave 1: independent tasks (parallel)
  │   ├── Wave 2: dependent tasks (after wave 1)
  │   └── Output: .agents/phases/2.1-tasks.json
  ├── Phase 2.2: Simplify (inline or agent)
  └── Phase 2.3: Implementation Review
      └── Codex MCP review

TEST Stage
  ├── Phase 3.1: Run Tests (bash)
  ├── Phase 3.2: Analyze Failures (inline)
  └── Phase 3.3: Test Review
      └── Codex MCP review

FINAL Stage
  ├── Phase 4.1: Documentation Updates
  ├── Phase 4.2: Final Review (codex-xhigh)
  └── Phase 4.3: Completion (git commit/PR)
```

## File-Based State Transfer

### Rationale

Instead of passing context through conversation, use files as the primary state mechanism:

- Files persist across sessions (resume-friendly)
- Easy to inspect and debug
- Natural context isolation (only load what you need)
- No compaction API needed

### Directory Structure

```
.agents/
├── state.json                    # Current phase, status, file pointers
└── phases/
    ├── 0-explore.md              # Explore findings
    ├── 1.1-brainstorm.md         # Approach decisions
    ├── 1.2-plan.md               # Merged implementation plan
    ├── 1.3-plan-review.json      # Review results
    ├── 2.1-tasks.json            # Task definitions + results
    ├── 2.2-simplify.md           # Simplification notes
    ├── 2.3-impl-review.json      # Implementation review
    ├── 3.1-test-results.json     # Test output
    └── 4.1-final-review.json     # Final review
```

### State File Schema

```json
{
    "version": 2,
    "task": "Add OAuth authentication with Google and GitHub",
    "status": "in_progress",

    "currentStage": "IMPLEMENT",
    "currentPhase": "2.1",

    "stages": {
        "EXPLORE": {
            "status": "completed",
            "completedAt": "2026-01-29T10:00:00Z",
            "agentCount": 5
        },
        "PLAN": {
            "status": "completed",
            "completedAt": "2026-01-29T10:05:00Z",
            "phases": {
                "1.1": { "status": "completed" },
                "1.2": { "status": "completed", "agentCount": 4 },
                "1.3": { "status": "completed", "issues": 0 }
            }
        },
        "IMPLEMENT": {
            "status": "in_progress",
            "phases": {
                "2.1": {
                    "status": "in_progress",
                    "waves": [
                        {
                            "tasks": ["task-1", "task-2", "task-3"],
                            "status": "completed"
                        },
                        {
                            "tasks": ["task-4", "task-5"],
                            "status": "in_progress"
                        }
                    ]
                },
                "2.2": { "status": "pending" },
                "2.3": { "status": "pending" }
            }
        },
        "TEST": { "status": "pending" },
        "FINAL": { "status": "pending" }
    },

    "files": {
        "explore": ".agents/phases/0-explore.md",
        "plan": ".agents/phases/1.2-plan.md",
        "tasks": ".agents/phases/2.1-tasks.json"
    },

    "compaction": {
        "lastCompactedAt": "PLAN",
        "history": ["EXPLORE", "PLAN"]
    },

    "startedAt": "2026-01-29T09:55:00Z",
    "updatedAt": "2026-01-29T10:12:00Z"
}
```

## Context Compaction

### Strategy

- **Between stages:** Compact by default (write to file, clear conversation)
- **Between phases:** Share context within stage (configurable)

### Compaction Process

1. Write stage output to `.agents/phases/{stage}-output.md`
2. Update `state.json` with file pointer
3. Clear conversation context
4. Next stage reads only required files

### Configuration

```json
{
    "compaction": {
        "betweenStages": true,
        "betweenPhases": false
    }
}
```

| Setting         | Default | Effect                               |
| --------------- | ------- | ------------------------------------ |
| `betweenStages` | `true`  | Compact after each stage             |
| `betweenPhases` | `false` | If `true`, compact after every phase |

## Parallel Agent Dispatch

All parallel agent models are configurable with explicit version support.

### Model Configuration

| Alias        | Resolves To                  | Notes                           |
| ------------ | ---------------------------- | ------------------------------- |
| `sonnet-4.5` | `claude-sonnet-4-5-20250514` | **Default** - recommended       |
| `sonnet`     | `claude-sonnet-4-20250514`   | Sonnet 4.0                      |
| `opus-4.5`   | `claude-opus-4-5-20251101`   | Opus 4.5                        |
| `opus`       | `claude-opus-4-20250514`     | Opus 4.0                        |
| `haiku`      | `claude-3-5-haiku-20241022`  | Haiku 3.5 (fast/cheap)          |
| `inherit`    | (parent model)               | Use parent conversation's model |

**Codex MCP Tools** (extended reasoning):

| Alias         | MCP Tool                  | Notes                              |
| ------------- | ------------------------- | ---------------------------------- |
| `codex-high`  | `mcp__codex-high__codex`  | Medium extended reasoning          |
| `codex-xhigh` | `mcp__codex-xhigh__codex` | High extended reasoning (for hard) |

You can also specify full model IDs directly (e.g., `claude-sonnet-4-5-20250514`).

**Default for all parallel agents:** `sonnet-4.5`

### Explore Agents

- **When:** Phase 0, before brainstorming
- **Model:** Configurable (default: `sonnet-4.5`)
- **Count:** 1-10, determined by task complexity
- **Purpose:** Gather codebase context in parallel

```json
{
    "stages": {
        "EXPLORE": {
            "enabled": true,
            "model": "sonnet-4.5",
            "maxParallelAgents": 10
        }
    }
}
```

**Complexity signals for agent count:**

- Simple (typo, rename): 1-2 agents
- Medium (add feature, fix bug): 3-5 agents
- Complex (auth, refactor, multi-system): 6-10 agents

### Plan Agents

- **When:** Phase 1.2, after brainstorming
- **Model:** Configurable (default: `sonnet-4.5`)
- **Count:** 1-10, based on identified plan areas
- **Mode:** `parallel` (default) or `single`

```json
{
    "stages": {
        "PLAN": {
            "planning": {
                "model": "sonnet-4.5",
                "maxParallelAgents": 10,
                "mode": "parallel"
            }
        }
    }
}
```

### Task Agents

- **When:** Phase 2.1, implementation
- **Model:** Configurable, or use complexity scoring (default: `sonnet-4.5` for easy, `opus-4.5` for medium, `codex-xhigh` for hard)
- **Dispatch:** Waves based on dependencies

```
Wave 1: [task-1, task-2, task-3] (independent, parallel)
Wave 2: [task-4, task-5] (depend on wave 1, parallel after wave 1 completes)
```

## Failure Handling

### Failure State

```json
{
    "failure": {
        "phase": "2.1",
        "error": "Task agent timeout on task-3",
        "failedAt": "2026-01-29T10:15:00Z",
        "context": {
            "completedTasks": ["task-1", "task-2"],
            "failedTask": "task-3",
            "pendingTasks": ["task-4", "task-5"]
        }
    }
}
```

### Retry Configuration

```json
{
    "retries": {
        "maxPerPhase": 3,
        "maxPerTask": 2,
        "backoffSeconds": [5, 15, 30]
    }
}
```

### Resume Behavior

`/subagents:resume` command:

1. Reads `state.json`
2. Finds failure point
3. Offers options:
    - Retry failed phase/task
    - Skip to next phase
    - Abort workflow

## Configuration Schema

### Full Config Example

```json
{
    "version": "2.0",
    "defaults": {
        "model": "sonnet-4.5"
    },
    "stages": {
        "EXPLORE": {
            "enabled": true,
            "model": "sonnet-4.5",
            "maxParallelAgents": 10
        },
        "PLAN": {
            "enabled": true,
            "brainstorm": { "inline": true },
            "planning": {
                "model": "sonnet-4.5",
                "maxParallelAgents": 10,
                "mode": "parallel"
            },
            "review": { "tool": "codex-high", "maxRetries": 3 }
        },
        "IMPLEMENT": {
            "enabled": true,
            "tasks": {
                "maxParallelAgents": 10,
                "useComplexityScoring": true,
                "complexityModels": {
                    "easy": "sonnet-4.5",
                    "medium": "opus-4.5",
                    "hard": "codex-xhigh"
                }
            },
            "review": {
                "tool": "codex-high",
                "maxRetries": 3
            }
        },
        "TEST": {
            "enabled": true,
            "commands": {
                "lint": "make lint",
                "test": "make test"
            },
            "review": { "tool": "codex-high" }
        },
        "FINAL": {
            "enabled": true,
            "review": { "tool": "codex-xhigh" },
            "git": {
                "workflow": "branch+PR",
                "excludePatterns": [".agents/**", "docs/plans/**"]
            }
        }
    },
    "compaction": {
        "betweenStages": true,
        "betweenPhases": false
    },
    "retries": {
        "maxPerPhase": 3,
        "maxPerTask": 2,
        "backoffSeconds": [5, 15, 30]
    }
}
```

## Migration from v1

### Files to Remove

- `agents/orchestrator.md` (orchestration moves to main conversation)
- `agents/stage-agent.md` (stages handled inline)
- `agents/phase-agent.md` (phases handled inline)
- `skills/orchestration/` (replaced by new flow)
- `skills/stage-coordinator/` (no longer needed)
- `skills/phase-executor/` (no longer needed)

### Files to Keep

- `agents/task-agent.md` (the workers)
- `skills/configuration/` (config loading)
- `skills/complexity-scorer/` (determine agent counts)
- `skills/task-dispatcher/` (wave-based dispatch)
- `skills/plan-writer/` (plan output format)

### Files to Create/Update

- `skills/workflow/` (new main workflow skill)
- `skills/explore-dispatcher/` (parallel explore)
- `skills/plan-dispatcher/` (parallel plan)
- Update `commands/dispatch.md` for new flow

## Implementation Plan

### Phase 1: Core Infrastructure

1. Update state.json schema to v2
2. Implement file-based state transfer
3. Add compaction logic
4. Update configuration schema

### Phase 2: Parallel Explore

1. Create explore-dispatcher skill
2. Implement complexity-based agent count
3. Aggregate explore outputs to file

### Phase 3: Parallel Plan

1. Create plan-dispatcher skill
2. Implement planning modes (parallel/single)
3. Merge plan outputs

### Phase 4: Task Execution

1. Update task-dispatcher for wave-based execution
2. Integrate with complexity scoring
3. Handle task dependencies

### Phase 5: Failure Handling

1. Implement retry logic
2. Update resume command
3. Add failure state tracking

### Phase 6: Cleanup

1. Remove deprecated files
2. Update documentation
3. Update tests

## Open Questions

1. Should explore queries be cached for similar tasks?
2. Should we support "dry run" mode to preview agent dispatch?
3. How to handle partial compaction (keep some context)?
