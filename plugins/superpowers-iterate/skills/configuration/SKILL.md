---
name: configuration
description: Read, write, and merge iterate configuration from global and project files
---

# Configuration Management

Manage iteration workflow configuration for models, parallel agents, and review behavior.

## Config File Locations

- **Global:** `~/.claude/iterate-config.json`
- **Project:** `.claude/iterate-config.local.json`

Project config overrides global config, which overrides defaults.

## Default Configuration

```json
{
  "version": 2,
  "reviewDefaults": {
    "failOnSeverity": "LOW",
    "maxRetries": 10,
    "onMaxRetries": "stop",
    "parallelFixes": true
  },
  "phases": {
    "1": { "model": "inherit", "parallel": true, "parallelModel": "inherit" },
    "2": { "model": "inherit", "parallel": true, "parallelModel": "inherit" },
    "3": { "tool": "mcp__codex__codex", "onFailure": "restart" },
    "4": { "model": "inherit", "parallel": false },
    "5": { "model": "inherit", "onFailure": "mini-loop" },
    "6": { "model": null, "onFailure": "restart" },
    "7": { "model": "inherit", "parallel": false },
    "8": { "tool": "mcp__codex__codex", "onFailure": "restart" },
    "9": { "tool": "mcp__codex-high__codex" }
  }
}
```

**Note:** Review phases (3, 5, 8) inherit `failOnSeverity`, `maxRetries`, `onMaxRetries`, and `parallelFixes` from `reviewDefaults`. Phase 6 (Test) only inherits `maxRetries` and `onMaxRetries` (no severity filtering for test failures). Only `onFailure` and phase-specific settings (like `tool` or `model`) are specified per-phase.

## Reading Configuration

1. Start with default config (above)
2. Read global config from `~/.claude/iterate-config.json` if exists
3. Deep merge global over defaults (per-phase override)
4. Read project config from `.claude/iterate-config.local.json` if exists
5. Deep merge project over global (per-phase override)
6. Return merged config

## Merge Logic

Each phase is merged individually with this priority (highest wins):

1. Default `reviewDefaults` + default phase settings
2. Global `reviewDefaults` + global phase settings
3. Project `reviewDefaults` + project phase settings

**Example:**

```
defaults:  reviewDefaults.maxRetries=10, phases.3.onFailure=restart
global:    reviewDefaults.maxRetries=5
project:   phases.3.onFailure=mini-loop
result:    phases.3 = { onFailure: "mini-loop", maxRetries: 5, failOnSeverity: "LOW", ... }
```

To reset a value to default, delete the key from the config file.

## Writing Configuration

1. Determine target file (global or project)
2. If target directory doesn't exist, create with `mkdir -p`
3. If file exists, create backup with `.backup` suffix
4. Write JSON with 2-space indentation
5. Report success with backup location if created

## Validation Rules

**Phase-specific settings:**

| Phase     | Key            | Valid Values                                                   |
| --------- | -------------- | -------------------------------------------------------------- |
| 1,2,4,5,7 | model          | `inherit`, `sonnet`, `opus`, `haiku`                           |
| 1,2       | parallel       | `true`, `false`                                                |
| 1,2       | parallelModel  | `inherit`, `sonnet`, `opus`, `haiku`                           |
| 3,8       | tool           | `mcp__codex__codex`, `mcp__codex-high__codex`, `claude-review` |
| 3,5,6,8   | onFailure      | `mini-loop`, `restart`, `proceed`, `stop`                      |
| 3,5,8     | failOnSeverity | `LOW`, `MEDIUM`, `HIGH`, `NONE`                                |
| 3,5,6,8   | maxRetries     | positive integer or `null` (unlimited)                         |
| 3,5,6,8   | onMaxRetries   | `stop`, `ask`, `restart`, `proceed`                            |
| 3,5,8     | parallelFixes  | `true`, `false`                                                |
| 6         | model          | `null` only (bash phase, not configurable)                     |
| 9         | tool           | `mcp__codex-high__codex` only (not configurable)               |

**reviewDefaults keys:**

| Key            | Valid Values                           |
| -------------- | -------------------------------------- |
| failOnSeverity | `LOW`, `MEDIUM`, `HIGH`, `NONE`        |
| maxRetries     | positive integer or `null` (unlimited) |
| onMaxRetries   | `stop`, `ask`, `restart`, `proceed`    |
| parallelFixes  | `true`, `false`                        |

**`onMaxRetries` behaviors:**

- `stop`: Halt workflow, report what failed (default)
- `ask`: Prompt user to decide next action
- `restart`: Go back to Phase 1, start new iteration
- `proceed`: Continue to next phase with issues noted

## Error Handling

- Invalid JSON: warn user, use defaults for that file
- Unknown phase key: ignore and warn
- Invalid model/tool value: warn user, use default for that phase
- Unreadable file: warn user, continue with available config

## Platform Compatibility

Use `$HOME` environment variable for home directory path.
Works on Linux, macOS, and Windows with Git Bash.
