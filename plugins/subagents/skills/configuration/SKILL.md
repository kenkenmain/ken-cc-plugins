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
  "version": "1.1",
  "defaults": {
    "model": "sonnet",
    "testStage": true,
    "gitWorkflow": "branch+PR",
    "blockOnSeverity": "low"
  },
  "complexityScoring": {
    "easy": { "model": "sonnet" },
    "medium": { "model": "opus" },
    "hard": { "model": "opus", "needsCodexReview": true }
  },
  "stages": {
    "PLAN": {
      "enabled": true,
      "planReview": { "tool": "codex-high", "maxRetries": 3 }
    },
    "IMPLEMENT": {
      "enabled": true,
      "useComplexityScoring": true,
      "implementReview": {
        "tool": "codex-high",
        "bugFixer": { "type": "mcp", "tool": "codex-high" },
        "maxRetries": 3
      }
    },
    "TEST": {
      "enabled": true,
      "commands": {
        "lint": "make lint",
        "test": "make test",
        "coverage": "make coverage"
      },
      "coverageThreshold": 80,
      "testReview": {
        "tool": "codex-high",
        "blockOnSeverity": "low",
        "maxRetries": 3
      }
    },
    "FINAL": {
      "enabled": true,
      "documentUpdates": { "enabled": true, "model": "sonnet" },
      "codexFinal": {
        "tool": "codex-xhigh",
        "bugFixer": { "type": "mcp", "tool": "codex-high" }
      },
      "completion": {
        "git": {
          "enabled": true,
          "workflow": "branch+PR",
          "branchFormat": "{type}/{slug}",
          "defaultType": "feat",
          "excludePatterns": [".agents/**", "docs/plans/**", "*.tmp", "*.log"]
        }
      }
    }
  },
  "parallelism": {
    "maxParallelTasks": 5
  }
}
```

## Reading Configuration

Start with defaults, deep merge global config, deep merge project config, return result.

## Merge Logic

Deep recursive merge. Example: defaults provide "easy: sonnet", global overrides to "easy: haiku", project adds "medium: sonnet".

## Writing Configuration

Determine target, create directory if needed, backup existing file, write JSON with 2-space indentation, report success.

## Model Namespace (ModelId)

For Task tool dispatch. Valid values:

| Short Name | Full Model ID               |
| ---------- | --------------------------- |
| `sonnet`   | `claude-sonnet-4-20250514`  |
| `opus`     | `claude-opus-4-20250514`    |
| `haiku`    | `claude-3-5-haiku-20241022` |
| `inherit`  | Use session's current model |

## MCP Tool Namespace (McpToolId)

For review phases using Codex MCP. Valid values:

| Short Name    | Full Tool ID              |
| ------------- | ------------------------- |
| `codex-high`  | `mcp__codex-high__codex`  |
| `codex-xhigh` | `mcp__codex-xhigh__codex` |

**Critical:** ModelId and McpToolId are DIFFERENT namespaces. Never mix them.

## bugFixer Format

Structured format: `{ "type": "mcp|model", "tool": "codex-high|codex-xhigh|sonnet|opus" }`

## Validation Rules

| Setting             | Valid Values                  |
| ------------------- | ----------------------------- |
| `blockOnSeverity`   | `high`, `medium`, `low`       |
| `gitWorkflow`       | `none`, `commit`, `branch+PR` |
| `coverageThreshold` | 0-100 (percentage)            |
| `maxParallelTasks`  | 1-10                          |

## Error Handling

Invalid JSON or values: warn and use defaults. Unknown keys: ignore and warn. Unreadable files: warn and continue.
