# Configure Command Design

## Summary

Add a `/superpowers-iterate:configure` command that allows users to configure which models each phase uses and whether parallel agents are enabled, with global and project-level defaults.

## Command Structure

```bash
/superpowers-iterate:configure              # Interactive wizard
/superpowers-iterate:configure --show       # Show current config
/superpowers-iterate:configure --reset      # Reset to defaults
```

## Configuration Hierarchy

```
Global defaults:     ~/.claude/iterate-config.json
Project overrides:   .claude/iterate-config.local.json
Runtime merge:       project values override global values
```

## Configuration Schema

```json
{
    "version": 1,
    "phases": {
        "1": {
            "model": "inherit",
            "parallel": true,
            "parallelModel": "inherit"
        },
        "2": {
            "model": "inherit",
            "parallel": true,
            "parallelModel": "inherit"
        },
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

### Phase Types

| Type       | Phases  | Config Options                          |
| ---------- | ------- | --------------------------------------- |
| Parallel   | 1, 2    | `model`, `parallel`, `parallelModel`    |
| MCP        | 3, 8, 9 | `tool` (codex/codex-high/claude-review) |
| Sequential | 4, 5, 7 | `model`, `parallel: false`              |
| Bash       | 6       | None (no model needed)                  |

### Model Options

- `inherit` - Use user's current `/model` setting (default)
- `sonnet` - Force Claude Sonnet
- `opus` - Force Claude Opus
- `haiku` - Force Claude Haiku

### Tool Options (MCP Phases)

- `mcp__codex__codex` - Codex medium reasoning
- `mcp__codex-high__codex` - Codex high reasoning
- `claude-review` - Use Claude code review (like --lite mode)

## Interactive Wizard Flow

### Step 1: Show Current Config

```
Current Configuration:
Phase 1 (Brainstorm):   model=inherit, parallel=true
Phase 2 (Plan):         model=inherit, parallel=true
Phase 3 (Plan Review):  tool=mcp__codex__codex
Phase 4 (Implement):    model=inherit
Phase 5 (Review):       model=inherit
Phase 6 (Test):         [bash - no model]
Phase 7 (Simplify):     model=inherit
Phase 8 (Final Review): tool=mcp__codex__codex
Phase 9 (Codex Final):  tool=mcp__codex-high__codex
```

### Step 2: Ask What to Configure

Multi-select with AskUserQuestion:

- "Which phases do you want to configure?"
- Options show current values in labels

### Step 3: Configure Each Selected Phase

For parallel phases (1, 2):

1. "Model for Phase N?" → inherit/sonnet/opus/haiku
2. "Enable parallel agents?" → yes/no
3. If parallel: "Model for parallel agents?" → inherit/sonnet/opus/haiku

For MCP phases (3, 8, 9):

1. "Tool for Phase N?" → codex/codex-high/claude-review

For sequential phases (4, 5, 7):

1. "Model for Phase N?" → inherit/sonnet/opus/haiku

### Step 4: Ask Where to Save

- "Global (all projects)" → `~/.claude/iterate-config.json`
- "This project only" → `.claude/iterate-config.local.json`

### Step 5: Confirm and Save

1. Create backup if file exists (`.backup` suffix)
2. Write new config
3. Show summary of changes

## Files to Create

1. `commands/configure.md` - The configure command
2. `skills/configuration/SKILL.md` - Config reading/writing logic

## Files to Modify

1. `skills/iteration-workflow/SKILL.md` - Read config at workflow start
2. `AGENTS.md` - Document config locations and schema
3. `README.md` - Add configure command docs
4. `plugin.json` - Version bump to 1.5.0

## References

- [statusline-tools setup.md](~/.claude/plugins/cache/claude-settings/statusline-tools) - Interactive wizard pattern
- [hookify configure.md](~/.claude/plugins/marketplaces/claude-plugins-official/plugins/hookify) - Multi-select toggle pattern
- [Claude Code Plugin Docs](https://code.claude.com/docs/en/plugins)
