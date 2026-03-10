# kenken Plugin -- Architecture Reference

Internal architecture documentation for agents working within or alongside the kenken plugin.

## Overview

The kenken plugin provides a 4-stage iterative development workflow for Claude Code. It orchestrates structured software delivery through PLAN, IMPLEMENT, TEST (optional), and FINAL stages, each composed of sequential phases. The workflow leverages Codex MCP tools for review gates and supports configurable model selection, bug-fixer delegation, and git integration (commit or branch+PR).

**Version:** 2.6.1
**Plugin manifest:** `.claude-plugin/plugin.json`
**State file:** `.agents/kenken-state.json`
**Config files:** `~/.claude/kenken-config.json` (global), `.claude/kenken-config.json` (project; overrides global)

## Workflow Stages and Phases

```
Stage 1: PLAN
  1.1 Brainstorm        -- superpowers:brainstorming + parallel agents
  1.2 Write Plan        -- superpowers:writing-plans, Task API format
  1.3 Plan Review       -- Codex MCP gate (configurable tool)

Stage 2: IMPLEMENT
  2.1 Implementation    -- Claude subagents or Codex MCP (configurable implementer)
  2.2 Code Simplify     -- code-simplifier plugin
  2.3 Implement Review  -- Codex MCP gate (configurable tool + bugFixer)

Stage 3: TEST (optional, disabled by default)
  3.1 Test Plan         -- Analyze testable units
  3.2 Write Tests       -- Framework-aware test authoring
  3.3 Coverage Check    -- Threshold enforcement (default 80%)
  3.4 Run Tests         -- Execute and classify failures
  3.5 Test Review       -- Codex MCP gate

Stage 4: FINAL
  4.1 Codex Final       -- mcp__codex-xhigh__codex (fixed, high reasoning)
  4.2 Suggest Extensions -- Propose 2-3 next steps to user
  4.3 Completion        -- Git workflow: no-op / commit / branch+PR
```

Review phases (1.3, 2.3, 3.5, 4.1) act as quality gates. HIGH severity issues block advancement. The bugFixer config determines who fixes issues found by reviews (claude, codex-high, or codex-xhigh).

## Skill List

| Skill               | Path                              | Description                                                                                      |
| -------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------ |
| `iterate`            | `skills/iterate/SKILL.md`        | Core orchestrator. Drives all 4 stages sequentially, manages state transitions, dispatches review gates, handles resume from checkpoint. Contains 6 prompt templates in `prompts/`. |
| `iterate-status`     | `skills/iterate-status/SKILL.md` | Reads `.agents/kenken-state.json` and renders a formatted progress view with stage/phase status icons, retry counts, and elapsed time. Read-only, no side effects. |
| `iterate-resume`     | `skills/iterate-resume/SKILL.md` | Resumes an interrupted iteration. Offers three choices: resume from saved phase, restart current stage, or start fresh. Recommends IMPLEMENT restart when TEST fails due to code logic errors. |
| `iterate-configure`  | `skills/iterate-configure/SKILL.md` | Configuration management. Supports `--show` (display merged config), `--reset` (delete config files), and interactive wizard (stage-by-stage settings). Validates model names, tool IDs, and thresholds. |
| `gh-repo-setup`      | `skills/gh-repo-setup/SKILL.md`  | GitHub repository bootstrapper. Creates or configures repos with GitFlow branches, branch protection, squash-merge-only, issue/PR templates, label-triggered CI, Dependabot, and `.agents`/`.claude` directory structure. |

### Prompt Templates (under `skills/iterate/prompts/`)

| Template               | Used In    | Lines | Purpose                                       |
| ---------------------- | ---------- | ----- | --------------------------------------------- |
| `brainstorm.md`        | Phase 1.1  | 81    | Problem analysis and solution design prompt    |
| `plan-review.md`       | Phase 1.3  | 68    | Plan quality validation prompt for Codex       |
| `implementation.md`    | Phase 2.1  | 88    | Implementation execution prompt                |
| `implement-review.md`  | Phase 2.3  | 85    | Code quality review prompt for Codex           |
| `test-review.md`       | Phase 3.5  | 83    | Test quality review prompt for Codex           |
| `final-review.md`      | Phase 4.1  | 95    | Final validation prompt (high reasoning)       |

## Agent Roster

| Agent             | File                          | Model     | Tools                                              | Role                                                                                     |
| ----------------- | ----------------------------- | --------- | -------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `codex-reviewer`  | `agents/codex-reviewer.md`    | `inherit` | Bash, Read, Grep, mcp__codex-high__codex, mcp__codex-xhigh__codex | Wraps Codex MCP calls for all review phases (1.3, 2.3, 3.5, 4.1). Loads prompt templates, fills placeholders, parses issues by severity. Falls back to `superpowers:requesting-code-review` when `claude-review` is configured. |

The plugin has a single agent. All other work is performed by the main Claude session using skills and external plugin dependencies (superpowers, code-simplifier).

## Command Reference

Commands are exposed as slash commands via the skills system. The plugin does not have dedicated `commands/` directory files; commands map directly to skills.

| Command                      | Skill              | Arguments               | Description                          |
| ---------------------------- | ------------------ | ----------------------- | ------------------------------------ |
| `/kenken:iterate`            | `iterate`          | `<task description>`    | Start a new 4-stage iteration        |
| `/kenken:iterate-status`     | `iterate-status`   | (none)                  | Display current workflow progress    |
| `/kenken:iterate-resume`     | `iterate-resume`   | (none)                  | Resume interrupted workflow          |
| `/kenken:iterate-configure`  | `iterate-configure`| `[--show \| --reset]`   | Manage workflow configuration        |
| `/kenken:gh-repo-setup`      | `gh-repo-setup`    | `[--existing] [name]`   | Set up GitHub repo with best practices|

## State Management

### State File: `.agents/kenken-state.json`

```json
{
  "version": 1,
  "task": "task description",
  "startedAt": "ISO timestamp",
  "currentStage": "IMPLEMENT",
  "currentPhase": "2.1",
  "stages": {
    "plan":      { "status": "completed" },
    "implement": { "status": "in_progress", "phase": "2.1", "retryCount": 0, "maxRetries": 3 },
    "test":      { "status": "pending", "enabled": true },
    "final":     { "status": "pending" }
  },
  "extensions": []
}
```

State is updated after every phase transition. Recovery behavior:
- Missing file: start fresh
- Corrupt JSON: backup to `.backup`, start fresh, inform user
- Schema version mismatch: ask user to migrate or reset

### Log Files: `.agents/logs/`

| File pattern                   | Content                |
| ------------------------------ | ---------------------- |
| `test-run-{timestamp}.log`     | Test execution output  |
| `coverage-{timestamp}.log`     | Coverage report        |
| `errors/errors-{timestamp}.log`| Extracted error details|
| `errors/error-summary.json`    | Indexed error lookup   |

## External Dependencies

| Dependency                          | Required For                     |
| ----------------------------------- | -------------------------------- |
| `superpowers:brainstorming`         | Phase 1.1                        |
| `superpowers:writing-plans`         | Phase 1.2                        |
| `superpowers:subagent-driven-development` | Phase 2.1 (claude mode)    |
| `superpowers:dispatching-parallel-agents` | Phases 1.1, 1.2             |
| `superpowers:requesting-code-review`| Review phases (claude-review fallback) |
| `code-simplifier:code-simplifier`   | Phase 2.2                        |
| `mcp__codex-high__codex`            | Review gates (configurable)      |
| `mcp__codex-xhigh__codex`           | Final review (fixed)             |
| `gh` CLI                            | gh-repo-setup skill              |

## Key Design Decisions

- **Sequential phase execution only.** Parallel implementation subagents are explicitly prohibited to avoid file conflicts.
- **Review gates are blocking.** HIGH severity issues from any review phase must be fixed before advancing.
- **Test stage is opt-in.** Disabled by default (`stages.test.enabled: false`). When enabled, auto-detects test framework if not configured.
- **Test failure classification.** Errors in test files loop back to Phase 3.2; errors in source files restart the IMPLEMENT stage.
- **Final review tool is fixed.** Phase 4.1 always uses `mcp__codex-xhigh__codex` regardless of configuration.
- **Config merging precedence.** defaults < global (`~/.claude/`) < project (`.claude/`). Config is loaded fresh on every invocation.
