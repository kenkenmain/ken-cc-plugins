---
name: configuration
description: Load, merge, and validate subagents configuration from global and project files
---

# Configuration Management

Manage subagents workflow configuration for complexity scoring, models, and workflow options.

## Config Locations

- **Global:** `~/.claude/subagents-config.json`
- **Project:** `.claude/subagents-config.json`

Project overrides global, which overrides defaults.

## Default Configuration

```json
{
  "version": "2.0",
  "defaults": {
    "model": "sonnet-4.5",
    "gitWorkflow": "branch+PR",
    "blockOnSeverity": "low"
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
      "review": {
        "tool": "codex-high",
        "bugFixer": "codex-high",
        "maxRetries": 3
      }
    },
    "IMPLEMENT": {
      "enabled": true,
      "tasks": {
        "maxParallelAgents": 10,
        "useComplexityScoring": true,
        "complexityModels": {
          "easy": "codex-high",
          "medium": "codex-high",
          "hard": "codex-high"
        }
      },
      "review": {
        "tool": "codex-high",
        "bugFixer": "codex-high",
        "maxRetries": 3
      }
    },
    "TEST": {
      "enabled": true,
      "commands": { "lint": "make lint", "test": "make test" },
      "review": {
        "tool": "codex-high",
        "bugFixer": "codex-high",
        "maxRetries": 3
      }
    },
    "FINAL": {
      "enabled": true,
      "review": { "tool": "codex-high", "bugFixer": "codex-high", "maxRetries": 3 },
      "git": {
        "workflow": "branch+PR",
        "excludePatterns": [".agents/**"]
      }
    }
  },
  "pipeline": {
    "defaultProfile": null,
    "profiles": {
      "minimal": { "phases": 5, "stages": ["EXPLORE", "IMPLEMENT", "FINAL"] },
      "standard": { "phases": 13, "stages": ["EXPLORE", "PLAN", "IMPLEMENT", "TEST", "FINAL"] },
      "thorough": { "phases": 15, "stages": ["EXPLORE", "PLAN", "IMPLEMENT", "TEST", "FINAL"] }
    }
  },
  "supplementaryPolicy": "on-issues",
  "compaction": {
    "betweenStages": true,
    "betweenPhases": false
  },
  "retries": {
    "maxPerPhase": 3,
    "maxPerStage": 3,
    "maxPerTask": 2,
    "backoffSeconds": [5, 15, 30]
  }
}
```

## Reading Configuration

Start with defaults, deep merge global config, deep merge project config, return result.

## Merge Logic

Deep recursive merge. Example: defaults provide "easy: codex-high", global overrides to "easy: codex-high", project keeps same.

## Writing Configuration

Determine target, create directory if needed, backup existing file, write JSON with 2-space indentation, report success.

## Model Namespace (ModelId)

For Task tool dispatch. Valid values:

| Alias        | Full Model ID                |
| ------------ | ---------------------------- |
| `sonnet-4.5` | `claude-sonnet-4-5-20250929` |
| `opus-4.5`   | `claude-opus-4-5-20251101`   |
| `haiku-4.5`  | `claude-haiku-4-5-20251001`  |
| `inherit`    | Use session's current model  |

## MCP Tool Namespace (McpToolId)

For review phases using Codex MCP. Valid values:

| Short Name    | Full Tool ID              |
| ------------- | ------------------------- |
| `codex-high`  | `mcp__codex-high__codex`  |

**Critical:** ModelId and McpToolId are DIFFERENT namespaces. Never mix them.

## blockOnSeverity

Controls which Codex review issues trigger automatic fixes. Default: `low` (strictest).

| Value    | Behavior                                          |
| -------- | ------------------------------------------------- |
| `low`    | Fix ALL issues (LOW, MEDIUM, HIGH) before proceed |
| `medium` | Fix MEDIUM and HIGH issues only                   |
| `high`   | Fix HIGH issues only                              |

When an issue meets the threshold:

1. Dispatch `bugFixer` (default: codex-high) to fix
2. Re-run Codex review
3. Repeat until no blocking issues or max retries

## bugFixer

Tool used to fix issues found by Codex reviews. Default: `codex-high`.

Can be either an MCP tool (codex-high) or a model (sonnet-4.5, opus-4.5, haiku-4.5).

Configured per review phase:

```json
"review": { "tool": "codex-high", "bugFixer": "codex-high", "maxRetries": 3 }
```

## Validation Rules

| Setting                    | Valid Values                          |
| -------------------------- | ------------------------------------- |
| `blockOnSeverity`          | `high`, `medium`, `low`               |
| `gitWorkflow`              | `none`, `commit`, `branch+PR`         |
| `maxParallelAgents`        | 1-10                                  |
| `bugFixer`                 | ModelId or McpToolId                  |
| `pipeline.defaultProfile`  | `minimal`, `standard`, `thorough`, `null` |
| `supplementaryPolicy`      | `on-issues`, `always`                 |

## Error Handling

Invalid JSON or values: warn and use defaults. Unknown keys: ignore and warn. Unreadable files: warn and continue.
