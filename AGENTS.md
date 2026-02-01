# Superpowers Iterate Plugin - Agent Instructions

## Commands

```bash
# Iteration Workflow
/superpowers-iterate:iterate <task>                    # Full mode (Codex MCP)
/superpowers-iterate:iterate --lite <task>             # Lite mode (Claude only)
/superpowers-iterate:iterate --max-iterations 5 <task> # Limit iterations
/superpowers-iterate:iterate-status                    # Check progress
/superpowers-iterate:configure                         # Configure models per phase
/superpowers-iterate:configure --show                  # Show current config
/superpowers-iterate:configure --reset                 # Reset to defaults

# Subagents Workflow
/subagents:dispatch <task>                             # Start workflow
/subagents:dispatch <task> --no-worktree               # Without git worktree isolation
/subagents:dispatch <task> --no-test                   # Skip test stage
/subagents:dispatch <task> --no-web-search             # Disable library search

# Plugin Development
claude plugin install ./plugins/superpowers-iterate    # Install locally
claude plugin list                                     # List installed
```

## Project Structure

```
ken-cc-plugins/
├── plugins/
│   ├── subagents/
│   │   ├── .claude-plugin/plugin.json    # Plugin manifest
│   │   ├── commands/                      # Slash commands (dispatch, resume, status, stop)
│   │   ├── agents/                        # Agent definitions (init-claude, codex-reviewer, etc.)
│   │   ├── hooks/                         # Shell hooks (on-subagent-stop, on-stop, on-task-dispatch)
│   │   │   └── lib/                       # Shared bash libs (state.sh, gates.sh, schedule.sh, review.sh, fallback.sh)
│   │   ├── prompts/                       # Orchestrator + phase prompt templates
│   │   ├── skills/                        # workflow, state-manager, configuration
│   │   └── CLAUDE.md                      # Subagents-specific architecture docs
│   └── superpowers-iterate/
│       ├── .claude-plugin/plugin.json    # Plugin manifest (name, version)
│       ├── commands/                      # Slash commands (iterate.md, iterate-status.md)
│       ├── skills/iteration-workflow/     # Main skill (SKILL.md)
│       ├── skills/configuration/          # Config management (SKILL.md)
│       └── agents/                        # Agent definitions (codex-reviewer.md)
├── docs/plans/                            # Design docs and implementation plans
├── .agents/                               # Runtime state (iteration-state.json)
├── .github/workflows/                     # CI validation
├── AGENTS.md                              # This file - agent instructions
├── CLAUDE.md                              # Symlink to AGENTS.md
└── README.md                              # User-facing documentation
```

## Workflow Architecture

This plugin orchestrates a 9-phase development iteration:

```
Phase 1: Brainstorm    -> superpowers:brainstorming + parallel agents
Phase 2: Plan          -> superpowers:writing-plans + parallel agents
Phase 3: Plan Review   -> mcp__codex-high__codex (default, configurable via /configure)
Phase 4: Implement     -> superpowers:subagent-driven-development
Phase 5: Review        -> superpowers:requesting-code-review
Phase 6: Test          -> make lint && make test
Phase 7: Simplify      -> code-simplifier agent
Phase 8: Final Review  -> mcp__codex-high__codex (default, configurable via /configure)
Phase 9: Codex Final   -> mcp__codex-xhigh__codex (full mode only)
```

**Iteration Loop:** Phases 1-8 repeat until Phase 8 finds zero issues or max iterations reached.

## Model Configuration

| Phase | Activity     | Model     | MCP Tool                  | Rationale                            |
| ----- | ------------ | --------- | ------------------------- | ------------------------------------ |
| 1     | Brainstorm   | `inherit` | N/A                       | User controls via /configure         |
| 2     | Plan         | `inherit` | N/A                       | User controls via /configure         |
| 3     | Plan Review  | N/A       | `mcp__codex-high__codex`  | Medium reasoning for plan validation |
| 4     | Implement    | `inherit` | N/A                       | User controls quality                |
| 5     | Review       | `inherit` | N/A                       | Quick sanity check                   |
| 6     | Test         | N/A       | N/A                       | Bash commands                        |
| 7     | Simplify     | `inherit` | N/A                       | Code quality                         |
| 8     | Final Review | N/A       | `mcp__codex-high__codex`  | Medium reasoning for iteration       |
| 9     | Codex Final  | N/A       | `mcp__codex-xhigh__codex` | High reasoning for final validation  |

## Configuration

Configure models per phase via `/superpowers-iterate:configure` or edit JSON directly:

**Global:** `~/.claude/iterate-config.json`
**Project:** `.claude/iterate-config.local.json`

Project overrides global. See `plugins/superpowers-iterate/skills/configuration/SKILL.md` for schema.

## Code Style

- **Markdown:** Use YAML frontmatter, follow existing command/skill/agent structure
- **Naming:** kebab-case for commands, skills, agents (e.g., `iterate-status.md`)
- **Shell hooks:** `set -euo pipefail`, use `local var; var="$(cmd)"` (not `local var="$(cmd)"`), source libs from `$SCRIPT_DIR/lib/`
- **Shell validation:** Run `bash -n <script>` after modifying hook shell scripts
- **Init agent:** `init-claude.md` is the sole init agent — defaults to optimistic Codex config with runtime fallback
- **Git Commits:** Prefix with `feat|fix|docs|chore|ci`, include co-author line
- **Git Excludes:** Never commit `.agents/**`, `docs/plans/**`, `*.tmp`, `*.log`

## Model vs MCP Tool Namespaces

**Critical:** These are DIFFERENT namespaces. Never mix them in config.

| Type        | Valid Values                         | Usage                     |
| ----------- | ------------------------------------ | ------------------------- |
| `ModelId`   | `sonnet-4.5`, `opus-4.5`, `haiku-4.5`, `inherit` | Task tool `model` param   |
| `McpToolId` | `codex-high`, `codex-xhigh`          | Review phase `tool` field |

**Actual Anthropic API IDs:**

- `sonnet-4.5` → `claude-sonnet-4-5-20250929`
- `opus-4.5` → `claude-opus-4-5-20251101`
- `haiku-4.5` → `claude-haiku-4-5-20251001`

**bugFixer format:** `{ "type": "mcp"|"model", "tool": "<id>" }` - never bare strings

## State Management

State tracked in `.agents/iteration-state.json`:

```json
{
  "version": 3,
  "task": "<description>",
  "mode": "full",
  "maxIterations": 10,
  "currentIteration": 1,
  "currentPhase": 1,
  "startedAt": "ISO timestamp",
  "iterations": [
    {
      "iteration": 1,
      "startedAt": "ISO timestamp",
      "phases": {
        "1": { "status": "..." },
        "2": { "status": "..." },
        "3": { "status": "...", "planReviewIssues": [] },
        "4": { "status": "..." },
        "5": { "status": "..." },
        "6": { "status": "..." },
        "7": { "status": "..." },
        "8": { "status": "..." }
      },
      "phase8Issues": []
    }
  ],
  "phase9": { "status": "pending" }
}
```

## Boundaries

**Always:** Update state after each phase, follow phase progression, fix HIGH severity issues, validate plan before implementation, bump plugin.json version on changes

**Ask First:** Skipping phases, changing iteration count mid-workflow, modifying state file schema

**Never:** Skip Phase 8 decision point without approval, proceed with HIGH severity issues, commit secrets

## Plugin Management

Based on official Claude Code plugin docs (https://code.claude.com/docs/en/plugins, https://code.claude.com/docs/en/discover-plugins).

### Installing Plugins

```bash
# From official marketplace (auto-available)
/plugin install plugin-name@claude-plugins-official

# From a custom marketplace
/plugin install plugin-name@marketplace-name

# From local directory (development/testing)
claude --plugin-dir ./path/to/plugin

# With scope
claude plugin install plugin-name@marketplace --scope project
```

### Managing Plugins

```bash
/plugin                              # Interactive plugin manager UI
/plugin marketplace add owner/repo   # Add GitHub marketplace
/plugin marketplace add https://gitlab.com/org/repo.git  # Git URL
/plugin marketplace list             # List marketplaces
/plugin marketplace update name      # Refresh listings
/plugin disable plugin-name          # Disable without uninstalling
/plugin enable plugin-name           # Re-enable
/plugin uninstall plugin-name        # Remove completely
```

### Installation Scopes

| Scope   | Location                      | Shared?                     |
| ------- | ----------------------------- | --------------------------- |
| User    | `~/.claude/settings.json`     | No — personal, all projects |
| Project | `.claude/settings.json`       | Yes — committed to repo     |
| Local   | `.claude/settings.local.json` | No — personal, this project |
| Managed | Admin-controlled              | Yes — org-wide              |

### Plugin Structure

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json        # Manifest — ONLY this goes in .claude-plugin/
├── commands/              # Slash commands (Markdown files)
├── agents/                # Custom subagent definitions
├── skills/                # Agent skills (folders with SKILL.md)
├── hooks/
│   └── hooks.json         # Event hooks configuration
├── .mcp.json              # MCP server configs (optional)
└── .lsp.json              # LSP server configs (optional)
```

### Official Marketplace Categories

| Category              | Examples                                                   |
| --------------------- | ---------------------------------------------------------- |
| Code intelligence     | `typescript-lsp`, `pyright-lsp`, `rust-analyzer-lsp`       |
| External integrations | `github`, `gitlab`, `linear`, `slack`, `sentry`            |
| Dev workflows         | `commit-commands`, `pr-review-toolkit`, `plugin-dev`       |
| Output styles         | `explanatory-output-style`, `learning-output-style`        |

## Subagent Development Guidelines

Based on official Claude Code subagent API (https://code.claude.com/docs/en/sub-agents).

### File Format

Agent definitions are Markdown with YAML frontmatter. The body becomes the system prompt — this is ALL the agent receives (not the full Claude Code system prompt).

```markdown
---
name: my-agent
description: "When Claude should delegate to this agent"
tools: [Read, Glob, Grep]
model: sonnet
---

System prompt content here.
```

### Frontmatter Fields

| Field             | Required | Description                                                     |
| ----------------- | -------- | --------------------------------------------------------------- |
| `name`            | Yes      | Unique identifier, lowercase with hyphens                       |
| `description`     | Yes      | When Claude should delegate — be specific for routing           |
| `tools`           | No       | Allowlist of tools. Inherits all if omitted                     |
| `disallowedTools` | No       | Denylist — removed from inherited or specified tools            |
| `model`           | No       | `sonnet`, `opus`, `haiku`, or `inherit` (default: `inherit`)   |
| `permissionMode`  | No       | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan` |
| `skills`          | No       | Skills injected fully into agent context at startup             |
| `hooks`           | No       | Lifecycle hooks scoped to this agent                            |
| `color`           | No       | Background color for UI identification                          |

### Critical Constraints

- **No nesting:** Subagents cannot spawn other subagents
- **Isolated context:** Agents only receive their system prompt + basic env info
- **Skills must be explicit:** Agents don't inherit skills from parent — list in `skills:` frontmatter
- **`disallowedTools: [Task]`** prevents spawning subagents — use for leaf agents

### Agent Scopes (Priority Order)

| Location                   | Scope                   | Priority    |
| -------------------------- | ----------------------- | ----------- |
| `--agents` CLI flag        | Current session only    | 1 (highest) |
| `.claude/agents/`          | Current project         | 2           |
| `~/.claude/agents/`        | All user projects       | 3           |
| Plugin `agents/` directory | Where plugin is enabled | 4 (lowest)  |

### Model Selection

| Model     | When to use                                                  |
| --------- | ------------------------------------------------------------ |
| `haiku`   | Fast read-only exploration, low-latency search, cost control |
| `sonnet`  | Balanced — analysis, code review, moderate tasks             |
| `opus`    | Complex reasoning, thorough review, multi-file work          |
| `inherit` | Same model as parent conversation (default)                  |

## Hook Development Guidelines

Based on official Claude Code hooks API (https://code.claude.com/docs/en/hooks).

### Hook Types

| Type      | Description                                         | Key Fields         |
| --------- | --------------------------------------------------- | ------------------ |
| `command` | Shell script — receives JSON on stdin               | `command`, `async` |
| `prompt`  | Single-turn LLM eval — returns `{ok, reason}`      | `prompt`, `model`  |
| `agent`   | Multi-turn subagent with tools (Read, Grep, Glob)   | `prompt`, `model`  |

### Hook Events

| Event                | Can block? | Matcher input                                     |
| -------------------- | ---------- | ------------------------------------------------- |
| `SessionStart`       | No         | `startup`, `resume`, `clear`, `compact`           |
| `UserPromptSubmit`   | Yes        | (none)                                            |
| `PreToolUse`         | Yes        | Tool name (regex)                                 |
| `PermissionRequest`  | Yes        | Tool name                                         |
| `PostToolUse`        | No         | Tool name                                         |
| `PostToolUseFailure` | No         | Tool name                                         |
| `Notification`       | No         | Notification type                                 |
| `SubagentStart`      | No         | Agent type name                                   |
| `SubagentStop`       | Yes        | Agent type name                                   |
| `Stop`               | Yes        | (none)                                            |
| `PreCompact`         | No         | `manual`, `auto`                                  |
| `SessionEnd`         | No         | Exit reason                                       |

### Exit Codes

| Code  | Meaning                                                              |
| ----- | -------------------------------------------------------------------- |
| `0`   | Success — stdout parsed for JSON (`decision`, `reason`, etc.)        |
| `2`   | Blocking error — stderr fed to Claude, action blocked                |
| Other | Non-blocking error — stderr in verbose mode, execution continues     |

### Plugin Hook Config (`hooks/hooks.json`)

```json
{
  "description": "Description of hooks",
  "hooks": {
    "EventName": [
      {
        "matcher": "regex pattern",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/script.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- `${CLAUDE_PLUGIN_ROOT}` for plugin-relative paths
- `"$CLAUDE_PROJECT_DIR"` for project-relative paths (quote for spaces)
- Matchers are regex: `Edit|Write`, `mcp__.*`, `Notebook.*`
- Omit matcher or use `"*"` to match all occurrences

### JSON Output (stdout on exit 0)

| Field            | Description                                                     |
| ---------------- | --------------------------------------------------------------- |
| `decision`       | `"block"` prevents the action (PreToolUse, Stop, SubagentStop)  |
| `reason`         | Explanation shown to Claude when blocking                       |
| `continue`       | `false` stops Claude entirely (overrides `decision`)            |
| `stopReason`     | Message shown to user when `continue: false`                    |

Event-specific fields go in `hookSpecificOutput`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "explanation",
    "additionalContext": "context for Claude",
    "updatedInput": { "field": "modified value" }
  }
}
```

### Shell Conventions

- `set -euo pipefail` at top of every script
- `local var; var="$(cmd)"` not `local var="$(cmd)"` (avoids masking exit codes)
- Always run `bash -n <script>` after modifying shell scripts
- Source shared libs from `$SCRIPT_DIR/lib/`
