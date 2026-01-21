---
description: Start 8-phase iteration workflow for a task (brainstorm->plan->implement->review->test->simplify->codex-review->codex-final)
argument-hint: <task-description>
allowed-tools: Task, Read, Write, Edit, Grep, Glob, Bash, TodoWrite, Skill, mcp__codex__codex, mcp__codex-high__codex, mcp__codex-xhigh__codex, mcp__lsp__get_diagnostics, mcp__lsp__get_hover, mcp__lsp__goto_definition, mcp__lsp__find_references, mcp__lsp__get_completions
---

# Iteration Workflow

Starting 8-phase iteration workflow for: **$ARGUMENTS**

## Context

- **Task:** $ARGUMENTS
- **Working Directory:** Use `pwd` to determine
- **Branch:** Use `git branch --show-current` to determine

## Instructions

Follow the iteration-workflow skill from this plugin exactly. The 8 mandatory phases are:

| Phase | Name         | Integration                                      |
|-------|--------------|--------------------------------------------------|
| 1     | Brainstorm   | `superpowers:brainstorming` + N parallel subagents |
| 2     | Plan         | `superpowers:writing-plans` + N parallel subagents |
| 3     | Implement    | `superpowers:subagent-driven-development` + LSP tools |
| 4     | Review       | `superpowers:requesting-code-review` (3 rounds)  |
| 5     | Test         | `make lint && make test`                         |
| 6     | Simplify     | `code-simplifier:code-simplifier` plugin         |
| 7     | Final Review | `mcp__codex-high__codex` (3 rounds)              |
| 8     | Codex        | `mcp__codex-xhigh__codex` final validation       |

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
  "version": 1,
  "task": "$ARGUMENTS",
  "currentPhase": 1,
  "startedAt": "ISO timestamp",
  "phases": {
    "1": { "status": "pending" },
    "2": { "status": "pending" },
    "3": { "status": "pending" },
    "4": { "status": "pending" },
    "5": { "status": "pending" },
    "6": { "status": "pending" },
    "7": { "status": "pending" },
    "8": { "status": "pending" }
  }
}
```

## Phase Execution

Follow the `iteration-workflow` skill from this plugin for detailed phase instructions.

**Key rules:**

- Never skip phases (all 8 mandatory)
- Meet exit criteria before advancing
- Fix HIGH/Critical issues immediately
- Use TodoWrite to track progress
- Re-run tests after any code changes
- Use LSP diagnostics before committing

## Completion

After Phase 8:

1. Update state file to show all phases complete
2. Summarize what was accomplished
3. Suggest next steps (commit, PR, etc.)
4. Optionally use `superpowers:finishing-a-development-branch`

**IMPORTANT:** Never skip phases. All 8 are mandatory for quality assurance.
