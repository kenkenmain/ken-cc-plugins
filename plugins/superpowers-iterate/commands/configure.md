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

Load and merge configuration using the `configuration` skill.

## Step 2: Handle --show Flag

If `--show` in arguments, display current merged config:

```
Current Configuration (merged from defaults + global + project):

Phase 1 (Brainstorm):   model=inherit, parallel=true, parallelModel=inherit
Phase 2 (Plan):         model=inherit, parallel=true, parallelModel=inherit
Phase 3 (Plan Review):  tool=mcp__codex__codex
Phase 4 (Implement):    model=inherit
Phase 5 (Review):       model=inherit
Phase 6 (Test):         [bash - no model config]
Phase 7 (Simplify):     model=inherit
Phase 8 (Final Review): tool=mcp__codex__codex
Phase 9 (Codex Final):  tool=mcp__codex-high__codex [fixed]

Config files:
- Global: ~/.claude/iterate-config.json [exists/not found]
- Project: .claude/iterate-config.local.json [exists/not found]
```

Exit after showing.

## Step 3: Handle --reset Flag

If `--reset` in arguments, use AskUserQuestion:

- question: "Which configuration do you want to reset to defaults?"
- header: "Reset"
- options:
  - label: "Global config"
    description: "Delete ~/.claude/iterate-config.json"
  - label: "Project config"
    description: "Delete .claude/iterate-config.local.json"
  - label: "Both"
    description: "Delete both config files"

Delete selected file(s) using Bash `rm` command. Confirm what was deleted. Exit after reset.

## Step 4: Interactive Configuration

Show current config (as in --show), then ask what to configure.

Use AskUserQuestion with multiSelect:

- question: "Which phases do you want to configure?"
- header: "Phases"
- multiSelect: true
- options (show current values in labels):
  - label: "Phase 1: Brainstorm (model=inherit, parallel=true)"
    description: "Configure model and parallel agents"
  - label: "Phase 2: Plan (model=inherit, parallel=true)"
    description: "Configure model and parallel agents"
  - label: "Phase 3: Plan Review (tool=codex)"
    description: "Configure review tool"
  - label: "Phase 4: Implement (model=inherit)"
    description: "Configure model"
  - label: "Phase 5: Review (model=inherit)"
    description: "Configure model"
  - label: "Phase 7: Simplify (model=inherit)"
    description: "Configure model"
  - label: "Phase 8: Final Review (tool=codex)"
    description: "Configure review tool"

Note: Phase 6 (Test) is bash-only. Phase 9 (Codex Final) is fixed to `mcp__codex-high__codex`.

## Step 5: Configure Each Selected Phase

For each selected phase, ask appropriate questions:

### For Phases 1, 2 (Parallel phases)

Ask three questions:

1. **Model:** inherit (recommended), sonnet, opus, or haiku
2. **Parallel agents:** Yes (recommended) or No
3. **Parallel model** (if parallel=Yes): inherit, sonnet, opus, or haiku

### For Phases 3, 8 (MCP review phases)

Ask which tool: codex (recommended), codex-high, or claude-review

**Tool name mapping when saving:**

| UI Label      | Config Value             |
| ------------- | ------------------------ |
| codex         | `mcp__codex__codex`      |
| codex-high    | `mcp__codex-high__codex` |
| claude-review | `claude-review`          |

### For Phases 4, 5, 7 (Sequential phases)

Ask which model: inherit (recommended), sonnet, opus, or haiku

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
2. Create target directory if needed (`mkdir -p`)
3. Read existing file if present
4. Create backup with `.backup` suffix if file exists
5. Merge new values into existing config (or create new with version: 1)
6. Write JSON with 2-space indentation
7. Confirm success:

```
Configuration saved to [file path]
Backup created: [file path].backup (if applicable)

Changes:
- Phase 1: model=sonnet (was: inherit)
- Phase 3: tool=claude-review (was: mcp__codex__codex)

Run `/superpowers-iterate:configure --show` to see full config.
```
