---
description: Start 9-phase iteration workflow for a task (brainstorm->plan->plan-review->implement->review->test->simplify->final-review->codex-final)
argument-hint: [--max-iterations N] <task-description>
allowed-tools: Task, Read, Write, Edit, Grep, Glob, Bash, TodoWrite, Skill, mcp__codex__codex, mcp__codex-high__codex, mcp__lsp__get_diagnostics, mcp__lsp__get_hover, mcp__lsp__goto_definition, mcp__lsp__find_references, mcp__lsp__get_completions
---

# Iteration Workflow

Starting 9-phase iteration workflow for: **$ARGUMENTS**

## Options

- `--max-iterations N`: Maximum review iterations in Phase 8 (default: 10)
- `--lite`: Use lite mode (no Codex required, uses Claude reviews instead)

Parse from $ARGUMENTS: extract options and remaining text as the task.

## Context

- **Task:** Extracted from $ARGUMENTS (after parsing options)
- **Max Iterations:** Parsed from --max-iterations or default 10
- **Mode:** Full (default) or Lite (--lite flag)
- **Working Directory:** Use `pwd` to determine
- **Branch:** Use `git branch --show-current` to determine

## Modes

| Mode           | Phase 3 Tool        | Phase 8 Tool                         | Phase 9                  | Requires                      |
| -------------- | ------------------- | ------------------------------------ | ------------------------ | ----------------------------- |
| Full (default) | `mcp__codex__codex` | `mcp__codex__codex`                  | `mcp__codex-high__codex` | Codex MCP servers             |
| Lite (--lite)  | Claude code-review  | `superpowers:requesting-code-review` | Skipped                  | superpowers + code-simplifier |

## Instructions

Follow the iteration-workflow skill from this plugin exactly. The 9 mandatory phases are:

| Phase | Name         | Integration                                             |
| ----- | ------------ | ------------------------------------------------------- |
| 1     | Brainstorm   | `superpowers:brainstorming` + N parallel subagents      |
| 2     | Plan         | `superpowers:writing-plans` + N parallel subagents      |
| 3     | Plan Review  | `mcp__codex__codex` (validates plan before implementation) |
| 4     | Implement    | `superpowers:subagent-driven-development` + LSP tools   |
| 5     | Review       | `superpowers:requesting-code-review` (1 round)          |
| 6     | Test         | `make lint && make test`                                |
| 7     | Simplify     | `code-simplifier:code-simplifier` plugin                |
| 8     | Final Review | `mcp__codex__codex` - decision point                    |
| 9     | Codex        | `mcp__codex-high__codex` final validation               |

**Iteration Loop:** Phases 1-8 repeat until Phase 8 finds zero issues or --max-iterations reached. Phase 9 runs once at the end.

## Required Prerequisites

Before starting, ensure these are installed:

- **superpowers plugin**: `claude plugin install superpowers@superpowers-marketplace`
- **code-simplifier plugin**: `claude plugin install code-simplifier`
- **LSP plugins** (per language): `claude plugin install typescript-lsp`, `pyright-lsp`, etc.
- **Codex MCP servers**: Run `make codex` or configure manually

## LSP Tools Available

Subagents have access to LSP for code intelligence:

- `mcp__lsp__get_diagnostics` - Get errors/warnings for a file
- `mcp__lsp__get_hover` - Get type info and documentation
- `mcp__lsp__goto_definition` - Jump to symbol definition
- `mcp__lsp__find_references` - Find all references to a symbol
- `mcp__lsp__get_completions` - Get code completions

## State Management

Track progress in `.agents/iteration-state.json`:

```json
{
  "version": 3,
  "task": "$ARGUMENTS",
  "mode": "full",
  "maxIterations": 10,
  "currentIteration": 1,
  "currentPhase": 1,
  "startedAt": "ISO timestamp",
  "iterations": [
    {
      "iteration": 1,
      "phases": {
        "1": { "status": "pending" },
        "2": { "status": "pending" },
        "3": { "status": "pending", "planReviewIssues": [] },
        "4": { "status": "pending" },
        "5": { "status": "pending" },
        "6": { "status": "pending" },
        "7": { "status": "pending" },
        "8": { "status": "pending" }
      },
      "phase8Issues": []
    }
  ],
  "phase9": { "status": "pending" }
}
```

## Phase Execution

Follow the `iteration-workflow` skill from this plugin for detailed phase instructions.

**Key rules:**

- Never skip phases (all 9 mandatory)
- Meet exit criteria before advancing
- Fix HIGH/Critical issues immediately
- Use TodoWrite to track progress
- Re-run tests after any code changes
- Use LSP diagnostics before committing

## Completion

After Phase 9:

1. Update state file to show all phases complete
2. Summarize what was accomplished
3. Suggest next steps (commit, PR, etc.)
4. Optionally use `superpowers:finishing-a-development-branch`

**IMPORTANT:** Never skip phases. All 9 are mandatory for quality assurance.
