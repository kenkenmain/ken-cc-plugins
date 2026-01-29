---
description: Configure complexity scoring, models, and workflow options
argument-hint: [--show | --reset | --edit]
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, Glob
---

# Configure Subagents Workflow

Configure complexity scoring, model assignments, and workflow options.

## Arguments

- `--show`: Show current merged configuration
- `--reset`: Reset configuration to defaults
- `--edit`: Open config file in editor

Parse from $ARGUMENTS to determine mode.

## Step 1: Load Configuration

Merge configuration: defaults → global → project

1. Hardcoded defaults
2. Global: `~/.claude/subagents-config.json`
3. Project: `.claude/subagents-config.json`

## Step 2: Handle --show

Display merged config and exit:

```
Complexity Scoring:
  Easy: sonnet  Medium: opus  Hard: opus + codex-xhigh

Stages:
  PLAN:      planReview=codex-high
  IMPLEMENT: useComplexityScoring=true
  TEST:      coverageThreshold=80%
  FINAL:     codexFinal=codex-xhigh

Defaults: blockOnSeverity=low, gitWorkflow=branch+PR

Config: Global [exists/not found] | Project [exists/not found]
```

## Step 3: Handle --reset

Ask which config to reset (global/project/both), delete selected file(s), confirm, and exit.

## Step 4: Handle --edit

Ask which config to edit (global/project), create with defaults if needed, display path for manual editing, and exit.

## Step 5: Interactive Configuration

Use AskUserQuestion to configure:

### Complexity Scoring

- question: "Configure complexity scoring models?"
- header: "Complexity"
- options:
  - label: "Easy tasks model"
    description: "Currently: sonnet"
  - label: "Medium tasks model"
    description: "Currently: opus"
  - label: "Hard tasks model"
    description: "Currently: opus + codex-xhigh review"

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

## Step 6: Save Configuration

Ask save location (global/project). Create directory if needed, backup existing file, write config with 2-space indentation, confirm success.
