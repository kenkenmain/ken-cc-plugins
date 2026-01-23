---
name: configuration
description: Read, write, and merge iterate configuration from global and project files
---

# Configuration Management

Manage iteration workflow configuration for models and parallel agents.

## Config File Locations

- **Global:** `~/.claude/iterate-config.json`
- **Project:** `.claude/iterate-config.local.json`

Project config overrides global config, which overrides defaults.

## Default Configuration

```json
{
  "version": 1,
  "phases": {
    "1": { "model": "inherit", "parallel": true, "parallelModel": "inherit" },
    "2": { "model": "inherit", "parallel": true, "parallelModel": "inherit" },
    "3": { "tool": "mcp__codex__codex" },
    "4": { "model": "inherit", "parallel": false },
    "5": { "model": "inherit", "parallel": false },
    "6": { "model": null },
    "7": { "model": "inherit", "parallel": false },
    "8": { "tool": "mcp__codex__codex" },
    "9": { "tool": "mcp__codex-high__codex" }
  }
}
```

## Reading Configuration

1. Start with default config (above)
2. Read global config from `~/.claude/iterate-config.json` if exists
3. Deep merge global over defaults (per-phase override)
4. Read project config from `.claude/iterate-config.local.json` if exists
5. Deep merge project over global (per-phase override)
6. Return merged config

## Merge Logic (Per-Phase Deep Merge)

Each phase's config is merged individually:

```
Default:  { "phases": { "1": { "model": "inherit", "parallel": true } } }
Global:   { "phases": { "1": { "model": "sonnet" } } }
Project:  { "phases": { "1": { "parallel": false } } }
Result:   { "phases": { "1": { "model": "sonnet", "parallel": false } } }
```

To "unset" a value back to default: delete the key from config file.

## Writing Configuration

1. Determine target file (global or project)
2. If target directory doesn't exist, create with `mkdir -p`
3. If file exists, create backup with `.backup` suffix
4. Write JSON with 2-space indentation
5. Report success with backup location if created

## Validation Rules

**Valid model values:** `inherit`, `sonnet`, `opus`, `haiku`
**Valid model for Phase 6:** `null` only (bash phase)

**Valid tool values for Phases 3, 8:** `mcp__codex__codex`, `mcp__codex-high__codex`, `claude-review`
**Valid tool for Phase 9:** `mcp__codex-high__codex` only (not configurable)

**Phase-specific rules:**

- Phases 1, 2, 4, 5, 7: model must be inherit/sonnet/opus/haiku
- Phase 6: model is always null (bash only, not configurable)
- Phases 3, 8: tool can be codex/codex-high/claude-review
- Phase 9: tool is fixed to `mcp__codex-high__codex`

## Error Handling

- Invalid JSON: warn user, use defaults for that file
- Unknown phase key: ignore and warn
- Invalid model/tool value: warn user, use default for that phase
- Unreadable file: warn user, continue with available config

## Platform Compatibility

Use `$HOME` environment variable for home directory path.
Works on Linux, macOS, and Windows with Git Bash.
