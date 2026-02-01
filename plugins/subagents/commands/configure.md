---
description: Configure complexity scoring, models, and workflow options
argument-hint: [--show | --reset | --edit]
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, Glob, Skill
---

# Configure Subagents Workflow

Configure complexity scoring, model assignments, and workflow options.

## Arguments

- `--show`: Show current merged configuration
- `--reset`: Reset configuration to defaults
- `--edit`: Open config file in editor

Parse from $ARGUMENTS to determine mode.

## Step 1: Load Configuration

Use `configuration` skill to merge: defaults → global → project

1. Hardcoded defaults (v2.0)
2. Global: `~/.claude/subagents-config.json`
3. Project: `.claude/subagents-config.json`

## Step 2: Handle --show

Display merged config and exit:

```
Complexity Scoring:
  Easy: sonnet-task-agent (direct execution, model=sonnet)
  Medium: opus-task-agent (direct execution, model=opus)
  Hard: codex-task-agent (codex-high MCP wrapper)

Stages:
  EXPLORE:   enabled=true, maxParallelAgents=10
  PLAN:      review=codex-high
  IMPLEMENT: useComplexityScoring=true, maxParallelAgents=10
  TEST:      enabled=true, lint="make lint", test="make test"
  FINAL:     review=codex-high, git.workflow=branch+PR

Compaction:
  betweenStages: true
  betweenPhases: false

Defaults: blockOnSeverity=low, model=sonnet-4.5

Config: Global [exists/not found] | Project [exists/not found]
```

## Step 3: Handle --reset

Ask which config to reset (global/project/both), delete selected file(s), confirm, and exit.

## Step 4: Handle --edit

Ask which config to edit (global/project), create with defaults if needed, display path for manual editing, and exit.

## Step 5: Interactive Configuration

Use AskUserQuestion to configure:

### Complexity Scoring

- question: "Configure complexity scoring?"
- header: "Complexity"
- options:
  - label: "Easy tasks"
    description: "Currently: sonnet-task-agent (direct, model=sonnet)"
  - label: "Medium tasks"
    description: "Currently: opus-task-agent (direct, model=opus)"
  - label: "Hard tasks"
    description: "Currently: codex-task-agent (codex-high MCP)"

### Test Stage

- question: "Enable TEST stage by default?"
- header: "Test"
- options:
  - label: "Yes (Recommended)"
  - label: "No"

### Git Workflow

- question: "Default git workflow?"
- header: "Git"
- options:
  - label: "branch+PR (Recommended)"
  - label: "commit only"
  - label: "none"

### Context Compaction

- question: "Configure context compaction?"
- header: "Compaction"
- options:
  - label: "Between stages only (Recommended)"
    description: "Compact after each stage completes"
  - label: "Between stages and phases"
    description: "More aggressive, may lose context"
  - label: "Disabled"
    description: "Keep full context (may hit limits)"

## Step 6: Save Configuration

Ask save location (global/project). Create directory if needed, backup existing file, write config with 2-space indentation, confirm success.
