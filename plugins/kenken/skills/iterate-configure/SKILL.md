---
name: iterate-configure
description: Configure models, tools, and options for kenken workflow
argument-hint: [--show | --reset]
---

# kenken Configure

> **For Claude:** This skill manages kenken configuration. Parse arguments and execute accordingly.

## Arguments

| Argument  | Action                           |
| --------- | -------------------------------- |
| (none)    | Interactive configuration wizard |
| `--show`  | Display current merged config    |
| `--reset` | Reset config to defaults         |

## --show

Display current configuration by:

1. Load global config from `~/.claude/kenken-config.json` (if exists)
2. Load project config from `.claude/kenken-config.json` (if exists)
3. Merge: project overrides global
4. Display formatted output:

```
kenken Configuration

Block on severity: low

PLAN Stage:
  brainstorm: model=inherit, parallel=true
  writePlan: model=inherit, parallel=true
  planReview: tool=mcp__codex-high__codex

IMPLEMENT Stage:
  implementation: model=inherit, enforceLogging=true
  simplify: model=inherit
  implementReview: tool=mcp__codex-high__codex

TEST Stage: [disabled]
  instructions: (not configured)
  commands: lint=make lint, test=make test, coverage=make coverage
  coverageThreshold: 80%
  testPlan: model=inherit
  testImplementation: model=inherit
  testReview: tool=mcp__codex-high__codex

FINAL Stage:
  codexFinal: tool=mcp__codex-xhigh__codex (fixed)
  suggestExtensions: enabled=true, maxSuggestions=3

Config files:
  Global: ~/.claude/kenken-config.json [found/not found]
  Project: .claude/kenken-config.json [found/not found]
```

## --reset

Ask user which config to reset:

1. Use AskUserQuestion:
   - "Which configuration to reset?"
   - Options: Global, Project, Both

2. Delete selected file(s)

3. Confirm: "Reset complete. Using defaults."

## Interactive Wizard (no arguments)

### Step 1: Show current config

Display current values (as in --show).

### Step 2: Select stages to configure

Use AskUserQuestion with multiSelect:

- "Which stages do you want to configure?"
- Options: PLAN Stage, IMPLEMENT Stage, TEST Stage, FINAL Stage

### Step 3: Configure selected stages

**For PLAN Stage:**

Ask for each phase:

- brainstorm: model (see Model Names section), parallel (true/false)
- writePlan: model, parallel
- planReview: tool (mcp**codex**codex/mcp**codex-high**codex/claude-review)

Common model options: `inherit`, `sonnet`, `opus`, `haiku`, `opus-4.5`, `sonnet-4`, `sonnet-3.5`

**For IMPLEMENT Stage:**

- implementation: model, enforceLogging (true/false)
- simplify: model
- implementReview: tool

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
- (codexFinal tool is fixed, not configurable)

### Step 4: Save location

Ask: "Where to save?"

- Global (~/.claude/kenken-config.json)
- Project (.claude/kenken-config.json)

### Step 5: Save and confirm

1. Create directory if needed
2. Backup existing file (.backup)
3. Merge new values with existing
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
      "implementation": { "model": "inherit", "enforceLogging": true },
      "simplify": { "model": "inherit" },
      "implementReview": { "tool": "mcp__codex-high__codex", "maxRetries": 3 }
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
      "testImplementation": { "model": "inherit" },
      "runTests": { "timeout": 300 },
      "testReview": { "tool": "mcp__codex-high__codex", "maxRetries": 3 }
    },
    "final": {
      "codexFinal": { "tool": "mcp__codex-xhigh__codex" },
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

| Setting            | Default                   |
| ------------------ | ------------------------- |
| blockOnSeverity    | `low`                     |
| All models         | `inherit`                 |
| Review tools       | `mcp__codex-high__codex`  |
| Final tool         | `mcp__codex-xhigh__codex` |
| Test stage         | disabled                  |
| Coverage threshold | 80%                       |
| Max retries        | 3                         |
| Extensions         | enabled                   |
| Test instructions  | (must be provided)        |
| Branch format      | `{type}/{slug}`           |
| Default type       | `feat`                    |
| Main branch        | `auto` (detect)           |

## Validation Rules

| Setting         | Valid Values                                                                    |
| --------------- | ------------------------------------------------------------------------------- |
| blockOnSeverity | `high`, `medium`, `low` (blocks on specified level and above)                   |
| model           | `inherit`, or any valid model name (see Model Names below)                      |
| tool (review)   | `mcp__codex-high__codex`, `mcp__codex-xhigh__codex`, `claude-review` (see note) |
| tool (final)    | `mcp__codex-xhigh__codex` only (fixed)                                          |
| threshold       | 0-100                                                                           |
| maxRetries      | 1-10                                                                            |
| timeout         | 60-3600 (seconds)                                                               |
| maxSuggestions  | 1-5                                                                             |
| instructions    | non-empty string (required when test.enabled=true)                              |
| commands.\*     | valid shell command string                                                      |
| coverageFormat  | `auto`, `lcov`, `cobertura`, `json`                                             |
| branchFormat    | string with placeholders: `{type}`, `{slug}`, `{date}`, `{user}`                |
| defaultType     | `feat`, `fix`, `chore`, `refactor`, `docs`, `test`                              |
| mainBranch      | `auto`, `main`, `master`, or custom branch name                                 |

**Note on `claude-review`:** This option uses the `superpowers:requesting-code-review` skill instead of Codex MCP. It's available as a fallback when Codex MCP is not configured, or for users who prefer Claude-native reviews. No additional dependencies required.

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
