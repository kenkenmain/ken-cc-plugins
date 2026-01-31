---
description: Configure models, tools, and options for the kenken workflow
argument-hint: [--show | --reset | --edit]
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, Glob, Skill
---

# Configure kenken Workflow

Configure models, review tools, test settings, and workflow options for the kenken iterative development workflow.

## Arguments

- `--show`: Show current merged configuration
- `--reset`: Reset configuration to defaults
- `--edit`: Open config file in editor

Parse from $ARGUMENTS to determine mode.

## Step 1: Load Configuration

Merge configuration from three layers: defaults -> global -> project

1. Hardcoded defaults (see Full Config Schema below)
2. Global: `~/.claude/kenken-config.json`
3. Project: `.claude/kenken-config.json`

Project overrides global. Global overrides defaults.

## Step 2: Handle --show

Display merged config and exit:

```
kenken Configuration
=====================

Block on severity: {blockOnSeverity}

PLAN Stage:
  brainstorm:  model={model}, parallel={parallel}
  writePlan:   model={model}, parallel={parallel}
  planReview:  tool={tool}

IMPLEMENT Stage:
  implementation:  model={model}, implementer={implementer}, bugFixer={bugFixer}, enforceLogging={enforceLogging}
  simplify:        model={model}, bugFixer={bugFixer}
  implementReview: tool={tool}, bugFixer={bugFixer}

TEST Stage: [{enabled/disabled}]
  instructions: {instructions or "(not configured)"}
  commands:     lint={lint}, test={test}, coverage={coverage}
  coverageThreshold: {threshold}%
  testPlan:     model={model}
  testImplementation: model={model}
  testReview:   tool={tool}

FINAL Stage:
  codexFinal:        tool=mcp__codex-xhigh__codex (fixed)
  suggestExtensions: enabled={enabled}, maxSuggestions={maxSuggestions}

Git:
  branchFormat: {branchFormat}
  defaultType:  {defaultType}
  mainBranch:   {mainBranch}

Config files:
  Global:  ~/.claude/kenken-config.json [{found/not found}]
  Project: .claude/kenken-config.json [{found/not found}]
```

## Step 3: Handle --reset

Ask which config to reset:

1. Use AskUserQuestion:
   - "Which configuration to reset?"
   - Options: Global, Project, Both

2. Delete selected file(s)

3. Confirm: "Reset complete. Using defaults."

## Step 4: Handle --edit

Ask which config to edit:

1. Use AskUserQuestion:
   - "Which configuration to edit?"
   - Options: Global (`~/.claude/kenken-config.json`), Project (`.claude/kenken-config.json`)

2. Create with defaults if the file does not exist

3. Display path for manual editing, and exit

## Step 5: Interactive Configuration (no arguments)

### Step 5.1: Show current config

Display current values (as in --show).

### Step 5.2: Select stages to configure

Use AskUserQuestion with multiSelect:

- "Which stages do you want to configure?"
- Options: PLAN Stage, IMPLEMENT Stage, TEST Stage, FINAL Stage

### Step 5.3: Configure selected stages

**For PLAN Stage:**

Ask for each phase:

- brainstorm: model (see Model Names section), parallel (true/false)
- writePlan: model, parallel
- planReview: tool (mcp__codex-high__codex / mcp__codex-xhigh__codex / claude-review)

Common model options: `inherit`, `sonnet`, `opus`, `haiku`, `opus-4.5`, `sonnet-4`, `sonnet-3.5`

**For IMPLEMENT Stage:**

- implementation: model, implementer (claude/codex-high/codex-xhigh), bugFixer (claude/codex-high/codex-xhigh), enforceLogging (true/false)
- simplify: model, bugFixer
- implementReview: tool, bugFixer

**For TEST Stage:**

- enabled: true/false
- instructions: (freeform text - project-specific testing guidance)
- commands.lint: command to run linting
- commands.test: command to run tests
- commands.coverage: command to generate coverage
- coverageThreshold: threshold (0-100)
- coverageFormat: auto/lcov/cobertura/json
- runTests: timeout (seconds)
- testReview: tool

**For FINAL Stage:**

- suggestExtensions: enabled (true/false), maxSuggestions (1-5)
- (codexFinal tool is fixed at mcp__codex-xhigh__codex, not configurable)

### Step 5.4: Save location

Ask: "Where to save?"

- Global (`~/.claude/kenken-config.json`)
- Project (`.claude/kenken-config.json`)

### Step 5.5: Save and confirm

1. Create directory if needed
2. Backup existing file (.backup)
3. Merge new values with existing config
4. Write JSON with 2-space indent
5. Confirm with summary of changes

## Full Config Schema

```json
{
  "version": 1,
  "blockOnSeverity": "low",
  "stages": {
    "plan": {
      "brainstorm": { "model": "inherit", "parallel": true },
      "writePlan": { "model": "inherit", "parallel": true },
      "planReview": { "tool": "mcp__codex-high__codex", "maxRetries": 3 }
    },
    "implement": {
      "implementation": {
        "model": "inherit",
        "implementer": "claude",
        "bugFixer": "codex-high",
        "enforceLogging": true
      },
      "simplify": { "model": "inherit", "bugFixer": "codex-high" },
      "implementReview": {
        "tool": "mcp__codex-high__codex",
        "bugFixer": "codex-high",
        "maxRetries": 3
      }
    },
    "test": {
      "enabled": false,
      "instructions": "",
      "commands": {
        "lint": "make lint",
        "test": "make test",
        "coverage": "make coverage"
      },
      "coverageThreshold": 80,
      "coverageFormat": "auto",
      "testPlan": { "model": "inherit" },
      "testImplementation": { "model": "inherit", "bugFixer": "codex-high" },
      "runTests": { "timeout": 300 },
      "testReview": {
        "tool": "mcp__codex-high__codex",
        "bugFixer": "codex-high",
        "maxRetries": 3
      }
    },
    "final": {
      "codexFinal": {
        "tool": "mcp__codex-xhigh__codex",
        "bugFixer": "codex-high"
      },
      "suggestExtensions": { "enabled": true, "maxSuggestions": 3 }
    }
  },
  "git": {
    "branchFormat": "{type}/{slug}",
    "defaultType": "feat",
    "mainBranch": "auto"
  },
  "logging": {
    "directory": ".agents/logs",
    "retainDays": 7,
    "extractErrors": true
  }
}
```

## Defaults Summary

| Setting            | Default                    |
| ------------------ | -------------------------- |
| blockOnSeverity    | `low`                      |
| All models         | `inherit`                  |
| Implementer        | `claude`                   |
| Bug fixer          | `codex-high`               |
| Review tools       | `mcp__codex-high__codex`   |
| Final tool         | `mcp__codex-xhigh__codex`  |
| Test stage         | disabled                   |
| Coverage threshold | 80%                        |
| Max retries        | 3                          |
| Extensions         | enabled                    |
| Test instructions  | (must be provided)         |
| Branch format      | `{type}/{slug}`            |
| Default type       | `feat`                     |
| Main branch        | `auto` (detect)            |

## Validation Rules

| Setting         | Valid Values                                                                    |
| --------------- | ------------------------------------------------------------------------------- |
| blockOnSeverity | `high`, `medium`, `low` (blocks on specified level and above)                   |
| model           | `inherit`, or any valid model name (see Model Names below)                      |
| implementer     | `claude`, `codex-high`, `codex-xhigh` (who writes initial code)                |
| bugFixer        | `claude`, `codex-high`, `codex-xhigh` (who fixes issues found by reviews)      |
| tool (review)   | `mcp__codex-high__codex`, `mcp__codex-xhigh__codex`, `claude-review` (see note)|
| tool (final)    | `mcp__codex-xhigh__codex` only (fixed)                                         |
| threshold       | 0-100                                                                           |
| maxRetries      | 1-10                                                                            |
| timeout         | 60-3600 (seconds)                                                               |
| maxSuggestions  | 1-5                                                                             |
| instructions    | non-empty string (required when test.enabled=true)                              |
| commands.*      | valid shell command string                                                      |
| coverageFormat  | `auto`, `lcov`, `cobertura`, `json`                                             |
| branchFormat    | string with placeholders: `{type}`, `{slug}`, `{date}`, `{user}`               |
| defaultType     | `feat`, `fix`, `chore`, `refactor`, `docs`, `test`                              |
| mainBranch      | `auto`, `main`, `master`, or custom branch name                                 |

**Note on `claude-review`:** This option uses the `superpowers:requesting-code-review` skill instead of Codex MCP. It is available as a fallback when Codex MCP is not configured, or for users who prefer Claude-native reviews. No additional dependencies required.

## Model Names

The `model` field accepts several formats:

### Short Names (latest version)

- `sonnet` - Claude Sonnet (latest)
- `opus` - Claude Opus (latest)
- `haiku` - Claude Haiku (latest)

### Versioned Names (specific version)

- `opus-4.5` - Claude Opus 4.5
- `opus-4` - Claude Opus 4
- `sonnet-4` - Claude Sonnet 4
- `sonnet-3.5` - Claude Sonnet 3.5
- `haiku-3.5` - Claude Haiku 3.5

### Full Model IDs

For maximum control, use the full model identifier:

- `claude-opus-4-5-20251101`
- `claude-sonnet-4-20250514`
- `claude-sonnet-3-5-20241022`

### Special Value

- `inherit` - Use the current session's model (recommended default)
