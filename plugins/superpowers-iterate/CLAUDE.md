# superpowers-iterate -- Architecture Reference

Internal architecture documentation for agents working within the superpowers-iterate plugin. For user-facing docs, see README.md.

## Overview

superpowers-iterate orchestrates a 9-phase iterative development workflow. Phases 1-8 form a loop that repeats until Phase 8 (Final Review) finds zero issues or `maxIterations` is reached. Phase 9 runs once at the end in full mode only.

The plugin supports two modes:

- **Full mode (default):** Uses Codex MCP servers (`mcp__codex-high__codex`, `mcp__codex-xhigh__codex`) for review phases 3, 8, and 9.
- **Lite mode (`--lite`):** Substitutes Claude-based reviews for all Codex phases; skips Phase 9 entirely.

## Plugin Structure

```
plugins/superpowers-iterate/
  .claude-plugin/plugin.json       # Manifest (v1.9.1)
  agents/
    codex-reviewer.md              # Codex MCP review specialist
  commands/
    iterate.md                     # /superpowers-iterate:iterate
    iterate-status.md              # /superpowers-iterate:iterate-status
    configure.md                   # /superpowers-iterate:configure
  skills/
    iteration-workflow/SKILL.md    # Core 9-phase orchestration logic
    configuration/SKILL.md         # Config loading, merging, validation
  README.md                        # User-facing documentation
  CLAUDE.md                        # This file
```

## Phase Table

| Phase | Name           | Purpose                                    | Model / Tool (default)              | Configurable? |
|-------|----------------|--------------------------------------------|-------------------------------------|---------------|
| 1     | Brainstorm     | Explore problem space, generate approaches | `inherit` + parallel subagents      | model, parallel |
| 2     | Plan           | Detailed TDD implementation plan           | `inherit` + parallel subagents      | model, parallel |
| 3     | Plan Review    | Validate plan before implementation        | `mcp__codex-high__codex`            | tool          |
| 4     | Implement      | TDD-style code implementation              | `inherit` (claude implementer)      | model, implementer, bugFixer |
| 5     | Review         | Quick 1-round code review                  | `inherit`                           | model, bugFixer |
| 6     | Test           | `make lint && make test`                   | N/A (bash only)                     | No            |
| 7     | Simplify       | Reduce bloat via code-simplifier plugin    | `inherit`                           | model, bugFixer |
| 8     | Final Review   | Decision point: loop or complete           | `mcp__codex-high__codex`            | tool, bugFixer |
| 9     | Codex Final    | Final validation (full mode only)          | `mcp__codex-xhigh__codex`           | No (fixed)    |

### Phase Dependencies

- Phases 1 and 2 can use parallel subagents (configurable via `parallel` flag).
- Phase 4 implementation subagents run sequentially to avoid file conflicts; reviewer subagents can run in parallel.
- Phase 6 is pure bash -- no model involvement.
- Phase 9 is skipped entirely in lite mode.

### Iteration Loop Logic

```
Start -> Phase 1 -> Phase 2 -> ... -> Phase 8
  |                                      |
  |   Phase 8 finds issues AND           |
  |   currentIteration < maxIterations   |
  +<-------------------------------------+
  |
  Phase 8 finds 0 issues OR maxIterations reached
  |
  v
  Phase 9 (full mode) -> Completion
  Completion (lite mode)
```

Phase 8 is the sole decision point. ANY issues found (HIGH, MEDIUM, or LOW) trigger a loop back to Phase 1, provided iterations remain. Issues are fixed via the configured `bugFixer` before looping.

## Agent Roster

### codex-reviewer

- **File:** `agents/codex-reviewer.md`
- **Model:** `inherit`
- **Tools:** `Bash`, `Read`, `Grep`, `mcp__codex-high__codex`, `mcp__codex-xhigh__codex`
- **Role:** Invokes Codex MCP for Phase 8 final review. Selects `codex-high` for standard tasks, `codex-xhigh` for complex analysis. Outputs severity-categorized findings (HIGH/MEDIUM/LOW) with file:line references and a PASS/NEEDS_FIXES recommendation.

## State Schema

State is persisted at `.agents/iteration-state.json` with the version 3 schema:

```json
{
  "version": 3,
  "task": "description of the task",
  "mode": "full | lite",
  "maxIterations": 10,
  "currentIteration": 1,
  "currentPhase": 1,
  "startedAt": "ISO-8601 timestamp",
  "iterations": [
    {
      "iteration": 1,
      "startedAt": "ISO-8601 timestamp",
      "phases": {
        "1": { "status": "complete | in_progress | pending" },
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
  "phase9": { "status": "pending | in_progress | complete" }
}
```

### Key Fields

| Field              | Type     | Description                                                |
|--------------------|----------|------------------------------------------------------------|
| `version`          | number   | Schema version, currently `3`                              |
| `mode`             | string   | `"full"` or `"lite"`                                       |
| `maxIterations`    | number   | Upper bound on iteration loops (default 10)                |
| `currentIteration` | number   | Which iteration loop is active (1-based)                   |
| `currentPhase`     | number   | Phase within the current iteration (1-8, or 9 post-loop)  |
| `iterations[]`     | array    | One entry per iteration with per-phase status              |
| `phase8Issues`     | array    | Issues found by Phase 8 review in a given iteration        |
| `phase9`           | object   | Status of the one-shot Phase 9 (full mode only)            |

### Resumption

On interrupted workflows, the orchestrator reads `currentIteration` and `currentPhase` to resume from the exact point of failure. No phase is re-run if already marked `complete`.

## Configuration

### File Locations

| Scope   | Path                                   | Priority |
|---------|----------------------------------------|----------|
| Default | Hardcoded in `configuration` skill     | Lowest   |
| Global  | `~/.claude/iterate-config.json`        | Middle   |
| Project | `.claude/iterate-config.local.json`    | Highest  |

Merge order: defaults -> global -> project (per-phase deep merge).

### Default Config

```json
{
  "version": 1,
  "blockOnSeverity": "low",
  "phases": {
    "1": { "model": "inherit", "parallel": true, "parallelModel": "inherit" },
    "2": { "model": "inherit", "parallel": true, "parallelModel": "inherit" },
    "3": { "tool": "mcp__codex-high__codex" },
    "4": { "model": "inherit", "parallel": false, "implementer": "claude", "bugFixer": "codex-high" },
    "5": { "model": "inherit", "parallel": false, "bugFixer": "codex-high" },
    "6": { "model": null },
    "7": { "model": "inherit", "parallel": false, "bugFixer": "codex-high" },
    "8": { "tool": "mcp__codex-high__codex", "bugFixer": "codex-high" },
    "9": { "tool": "mcp__codex-xhigh__codex" }
  }
}
```

### Model vs Tool Namespaces

These are separate namespaces and must not be confused:

- **Model IDs** (`model` field): `inherit`, `sonnet`, `opus`, `haiku`, `opus-4.5`, `sonnet-4`, etc.
- **MCP Tool IDs** (`tool` field): `mcp__codex-high__codex`, `mcp__codex-xhigh__codex`, `claude-review`
- **bugFixer values**: `claude`, `codex-high`, `codex-xhigh` -- these map to either subagent dispatch or MCP tool invocation.

### Validation

| Phase     | Configurable Keys                     | Constraints                                |
|-----------|---------------------------------------|--------------------------------------------|
| 1, 2      | `model`, `parallel`, `parallelModel`  | `parallel` is boolean                      |
| 3         | `tool`                                | MCP tool ID or `claude-review`             |
| 4         | `model`, `implementer`, `bugFixer`    | `implementer`: claude/codex-high/codex-xhigh |
| 5, 7      | `model`, `bugFixer`                   | Standard model IDs                         |
| 6         | None                                  | Bash-only phase                            |
| 8         | `tool`, `bugFixer`                    | MCP tool ID or `claude-review`             |
| 9         | None                                  | Fixed to `mcp__codex-xhigh__codex`         |

## External Dependencies

| Dependency                | Required For     | Notes                           |
|---------------------------|------------------|---------------------------------|
| superpowers plugin        | Phases 1,2,4,5   | brainstorming, writing-plans, subagent-driven-development, requesting-code-review |
| code-simplifier plugin    | Phase 7          | From claude-plugins-official marketplace |
| Codex MCP servers         | Phases 3,8,9     | Full mode only; lite mode substitutes Claude reviews |
| LSP plugins               | Phase 4          | Optional; typescript-lsp, pyright-lsp, etc. |
| `make lint`, `make test`  | Phase 6          | Project must provide these targets |

## Invariants

- All 8 iteration phases are mandatory per iteration -- no skipping.
- Phase 9 runs exactly once, after the loop exits.
- Phase 8 is the only decision point that can trigger a loop-back.
- State file must be updated after every phase transition.
- HIGH severity issues from Phase 8 must be fixed before looping or completing.
- Implementation subagents (Phase 4) must run sequentially to prevent file conflicts.
