# Configure Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `/superpowers-iterate:configure` command for configuring models and parallel agents per phase.

**Architecture:** Interactive wizard using AskUserQuestion, config stored in JSON files (global + project), merged at runtime with project overriding global.

**Tech Stack:** Markdown commands, JSON config files, AskUserQuestion tool

---

## Task 1: Create Configuration Skill

**Files:**

- Create: `plugins/superpowers-iterate/skills/configuration/SKILL.md`

**Step 1: Create skill directory and file**

Create the configuration skill that handles reading, writing, and merging config:

````markdown
---
name: configuration
description: Read, write, and merge iterate configuration from global and project files
---

# Configuration Management

## Config File Locations

- **Global:** `~/.claude/iterate-config.json`
- **Project:** `.claude/iterate-config.local.json`

## Default Configuration

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
````

## Reading Configuration

1. Start with default config
2. Read global config from `~/.claude/iterate-config.json` if exists
3. Merge global over defaults (global values override defaults)
4. Read project config from `.claude/iterate-config.local.json` if exists
5. Merge project over global (project values override global)
6. Return merged config

## Writing Configuration

When saving config:

1. Determine target file (global or project)
2. If file exists, create backup with `.backup` suffix
3. Write JSON with 2-space indentation
4. Report success with backup location if created

## Validation Rules

**Valid model values:** `inherit`, `sonnet`, `opus`, `haiku`
**Valid model values for Phase 6 only:** `null` (no model needed for bash)
**Valid tool values for Phases 3, 8:** `mcp__codex__codex`, `mcp__codex-high__codex`, `claude-review`
**Valid tool values for Phase 9:** `mcp__codex-high__codex` only (or skip in lite mode)
**Valid phase keys:** `1`, `2`, `3`, `4`, `5`, `6`, `7`, `8`, `9`

**Phase-specific validation:**

- Phases 1, 2, 4, 5, 7: model must be inherit/sonnet/opus/haiku (not null)
- Phase 6: model is always null (bash only)
- Phases 3, 8: tool can be codex/codex-high/claude-review
- Phase 9: tool must be mcp**codex-high**codex (highest reasoning for final validation)

**Error handling:**

- If config file is invalid JSON: warn user, use defaults
- If unknown phase key: ignore and warn
- If invalid model/tool value: warn user, use default for that phase
- If file unreadable: warn user, continue with available config

## Merge Logic (Deep Merge)

Merge is **per-phase deep merge**:

1. Start with defaults
2. For each phase in global config: override defaults for that phase only
3. For each phase in project config: override global for that phase only

Example:

```
Default:  { "phases": { "1": { "model": "inherit", "parallel": true } } }
Global:   { "phases": { "1": { "model": "sonnet" } } }
Project:  { "phases": { "1": { "parallel": false } } }
Result:   { "phases": { "1": { "model": "sonnet", "parallel": false } } }
```

To "unset" a value back to default: delete the key from config file (not set to null).

## Directory Creation

If target directory doesn't exist:

- For `~/.claude/`: create directory with `mkdir -p`
- For `.claude/`: create directory with `mkdir -p`

## Platform Compatibility

Use `$HOME` environment variable for home directory (works on Linux, macOS, Windows with Git Bash).

````

**Step 2: Commit**

```bash
git add plugins/superpowers-iterate/skills/configuration/SKILL.md
git commit -m "feat: add configuration skill for reading/writing iterate config"
````

---

## Task 2: Create Configure Command

**Files:**

- Create: `plugins/superpowers-iterate/commands/configure.md`

**Step 1: Create the configure command**

```markdown
---
description: Configure models and parallel agents for each iteration phase
argument-hint: [--show | --reset]
allowed-tools: Read, Write, Edit, AskUserQuestion, Bash, Glob
---

# Configure Iteration Workflow

Configure which models each phase uses and whether parallel agents are enabled.

## Arguments

- `--show`: Show current configuration without prompting
- `--reset`: Reset configuration to defaults

Parse from $ARGUMENTS to determine mode.

## Step 1: Load Current Configuration

Load configuration skill from this plugin to understand config structure.

Read config files in order (later overrides earlier):

1. Default values (from skill)
2. Global: `~/.claude/iterate-config.json`
3. Project: `.claude/iterate-config.local.json`

## Step 2: Handle --show Flag

If `--show` in arguments:

Display current merged config:
```

Current Configuration (merged from defaults + global + project):

Phase 1 (Brainstorm): model=inherit, parallel=true, parallelModel=inherit
Phase 2 (Plan): model=inherit, parallel=true, parallelModel=inherit
Phase 3 (Plan Review): tool=mcp**codex**codex
Phase 4 (Implement): model=inherit
Phase 5 (Review): model=inherit
Phase 6 (Test): [bash - no model config]
Phase 7 (Simplify): model=inherit
Phase 8 (Final Review): tool=mcp**codex**codex
Phase 9 (Codex Final): tool=mcp**codex-high**codex

Config files:

- Global: ~/.claude/iterate-config.json [exists/not found]
- Project: .claude/iterate-config.local.json [exists/not found]

```

Exit after showing.

## Step 3: Handle --reset Flag

If `--reset` in arguments:

Use AskUserQuestion:
- question: "Which configuration do you want to reset to defaults?"
- header: "Reset"
- options:
  - label: "Global config"
    description: "Delete ~/.claude/iterate-config.json"
  - label: "Project config"
    description: "Delete .claude/iterate-config.local.json"
  - label: "Both"
    description: "Delete both config files"

Delete selected file(s) and confirm. Exit after reset.

## Step 4: Interactive Configuration

Show current config (as in --show), then ask what to configure.

Use AskUserQuestion with multiSelect:
- question: "Which phases do you want to configure?"
- header: "Phases"
- multiSelect: true
- options (show current values):
  - label: "Phase 1: Brainstorm (model=inherit, parallel=true)"
    description: "Configure model and parallel agents"
  - label: "Phase 2: Plan (model=inherit, parallel=true)"
    description: "Configure model and parallel agents"
  - label: "Phase 3: Plan Review (tool=mcp__codex__codex)"
    description: "Configure review tool"
  - label: "Phase 4: Implement (model=inherit)"
    description: "Configure model"
  - label: "Phase 5: Review (model=inherit)"
    description: "Configure model"
  - label: "Phase 7: Simplify (model=inherit)"
    description: "Configure model"
  - label: "Phase 8: Final Review (tool=mcp__codex__codex)"
    description: "Configure review tool"

Note: Phase 6 (Test) is bash-only, Phase 9 (Codex Final) is fixed to mcp__codex-high__codex.

## Step 5: Configure Each Selected Phase

For each selected phase, ask appropriate questions:

### For Phases 1, 2 (Parallel phases)

Ask model:
- question: "Model for Phase N (Brainstorm/Plan)?"
- header: "Model"
- options:
  - label: "inherit (Recommended)"
    description: "Use your current /model setting"
  - label: "sonnet"
    description: "Force Claude Sonnet (cost-effective)"
  - label: "opus"
    description: "Force Claude Opus (highest quality)"
  - label: "haiku"
    description: "Force Claude Haiku (fastest)"

Ask parallel:
- question: "Enable parallel agents for Phase N?"
- header: "Parallel"
- options:
  - label: "Yes (Recommended)"
    description: "Dispatch multiple agents for faster exploration"
  - label: "No"
    description: "Use single sequential agent"

If parallel enabled, ask parallel model:
- question: "Model for parallel agents in Phase N?"
- header: "Agent Model"
- options: (same as model options above)

### For Phases 3, 8 (MCP review phases)

Ask tool:
- question: "Tool for Phase N (Plan Review/Final Review)?"
- header: "Tool"
- options:
  - label: "mcp__codex__codex (Recommended)"
    description: "Codex with medium reasoning"
  - label: "mcp__codex-high__codex"
    description: "Codex with high reasoning"
  - label: "claude-review"
    description: "Use Claude code review (no Codex required)"

### For Phase 9 (Codex Final)

Phase 9 uses `mcp__codex-high__codex` only (highest reasoning for final validation).
No configuration option - this is fixed to ensure quality.
In lite mode, Phase 9 is skipped entirely.

### For Phases 4, 5, 7 (Sequential phases)

Ask model:
- question: "Model for Phase N (Implement/Review/Simplify)?"
- header: "Model"
- options: (same as parallel phase model options)

## Step 6: Ask Where to Save

Use AskUserQuestion:
- question: "Where should the configuration be saved?"
- header: "Location"
- options:
  - label: "Global (all projects)"
    description: "~/.claude/iterate-config.json"
  - label: "This project only"
    description: ".claude/iterate-config.local.json"

## Step 7: Save Configuration

1. Determine target file based on user choice
2. Read existing file if present
3. Create backup with `.backup` suffix if file exists
4. Merge new values into existing config (or create new)
5. Write JSON with 2-space indentation
6. Confirm success:

```

Configuration saved to [file path]
Backup created: [file path].backup (if applicable)

Changes:

- Phase 1: model=sonnet (was: inherit)
- Phase 3: tool=claude-review (was: mcp**codex**codex)

Run `/superpowers-iterate:configure --show` to see full config.

```

```

**Step 2: Commit**

```bash
git add plugins/superpowers-iterate/commands/configure.md
git commit -m "feat: add configure command for iteration workflow"
```

---

## Task 3: Update SKILL.md to Read Configuration

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md`

**Step 1: Add config reading at workflow start**

Add a new section after "State Management" that reads config at workflow start:

```markdown
## Configuration Loading

At workflow start, load configuration:

1. Read default config (hardcoded in this skill)
2. Read `~/.claude/iterate-config.json` if exists, merge over defaults
3. Read `.claude/iterate-config.local.json` if exists, merge over global
4. Store merged config in memory for phase execution

Use configuration values when:

- Dispatching parallel agents (Phases 1, 2): Use `phases.N.parallelModel`
- Selecting MCP tools (Phases 3, 8, 9): Use `phases.N.tool`
- Dispatching single agents (Phases 4, 5, 7): Use `phases.N.model`

If `phases.N.parallel` is false for Phases 1 or 2, use single sequential agent instead.
```

**Step 2: Update Phase 1 instructions to use config**

Find the Phase 1 section and update to reference config:

```markdown
**Model selection:**

- If config `phases.1.parallel` is true: dispatch parallel agents with `phases.1.parallelModel`
- If config `phases.1.parallel` is false: use single agent with `phases.1.model`
- Default: parallel=true, parallelModel=inherit
```

**Step 3: Update Phase 2 instructions similarly**

**Step 4: Update Phase 3 to use configured tool**

```markdown
**Tool selection:**

- Use tool from config `phases.3.tool`
- If `claude-review`: use `superpowers:requesting-code-review` instead of Codex
- Default: mcp**codex**codex
```

**Step 5: Update Phases 4, 5, 7 to use configured model**

**Step 6: Update Phases 8, 9 to use configured tool**

**Step 7: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat: update iteration workflow to read config for models and tools"
```

---

## Task 4: Update Documentation

**Files:**

- Modify: `plugins/superpowers-iterate/README.md`
- Modify: `AGENTS.md`

**Step 1: Update plugin README.md**

Add new section after Commands:

````markdown
### `/superpowers-iterate:configure`

Configure models and parallel agents for each phase:

```bash
/superpowers-iterate:configure              # Interactive wizard
/superpowers-iterate:configure --show       # Show current config
/superpowers-iterate:configure --reset      # Reset to defaults
```
````

**Configuration files:**

- Global: `~/.claude/iterate-config.json`
- Project: `.claude/iterate-config.local.json`

Project config overrides global config.

````

**Step 2: Update AGENTS.md**

Add Configuration section after Model Configuration:

```markdown
## Configuration

Configure models per phase via `/superpowers-iterate:configure` or edit JSON directly:

**Global:** `~/.claude/iterate-config.json`
**Project:** `.claude/iterate-config.local.json`

Schema: See `docs/plans/2026-01-23-configure-command-design.md`
````

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/README.md AGENTS.md
git commit -m "docs: add configure command documentation"
```

---

## Task 5: Bump Plugin Version

**Files:**

- Modify: `plugins/superpowers-iterate/.claude-plugin/plugin.json`

**Step 1: Update version**

Change version from `1.4.0` to `1.5.0` and update description:

```json
{
    "name": "superpowers-iterate",
    "version": "1.5.0",
    "description": "Orchestrates iterative 9-phase workflow with configurable models and full/lite modes."
}
```

**Step 2: Commit**

```bash
git add plugins/superpowers-iterate/.claude-plugin/plugin.json
git commit -m "chore: bump plugin version to 1.5.0"
```

---

## Task 6: Sync CLAUDE.md with AGENTS.md

**Files:**

- Modify: `CLAUDE.md`

**Step 1: Copy AGENTS.md content to CLAUDE.md**

Since CLAUDE.md is a real file copy (not symlink), update it to match AGENTS.md:

```bash
cp AGENTS.md CLAUDE.md
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "chore: sync CLAUDE.md with AGENTS.md"
```

---

## Summary

| Task | Description                              | Files                                |
| ---- | ---------------------------------------- | ------------------------------------ |
| 1    | Create configuration skill               | `skills/configuration/SKILL.md`      |
| 2    | Create configure command                 | `commands/configure.md`              |
| 3    | Update iteration workflow to read config | `skills/iteration-workflow/SKILL.md` |
| 4    | Update documentation                     | `README.md`, `AGENTS.md`             |
| 5    | Bump plugin version                      | `plugin.json`                        |
| 6    | Sync CLAUDE.md                           | `CLAUDE.md`                          |
