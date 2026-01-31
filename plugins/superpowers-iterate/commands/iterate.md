---
description: Start 9-phase iteration workflow for a task (brainstorm->plan->plan-review->implement->review->test->simplify->final-review->codex-final)
argument-hint: [--max-iterations N] <task-description>
allowed-tools: Task, Read, Write, Edit, Grep, Glob, Bash, TodoWrite, Skill, mcp__codex-high__codex, mcp__codex-xhigh__codex, mcp__lsp__get_diagnostics, mcp__lsp__get_hover, mcp__lsp__goto_definition, mcp__lsp__find_references, mcp__lsp__get_completions
---

# Iteration Workflow

Starting 9-phase iteration workflow for: **$ARGUMENTS**

## Options

- `--max-iterations N`: Maximum iterations before stopping (default: 10)
- `--lite`: Use lite mode (no Codex required, uses Claude reviews instead)

Parse from $ARGUMENTS: extract options and remaining text as the task.

## Modes

- **Full (default):** Uses Codex MCP for Phases 3, 8, 9
- **Lite (`--lite`):** Uses Claude reviews, skips Phase 9

## Instructions

Follow the `iteration-workflow` skill from this plugin exactly for detailed phase instructions.

**The 9 Phases:** Brainstorm -> Plan -> Plan Review -> Implement -> Review -> Test -> Simplify -> Final Review -> Codex Final

**Iteration Loop:** Phases 1-8 repeat until Phase 8 finds zero issues or --max-iterations reached.

**Key rules:**

- Never skip phases (all 8 phases per iteration are mandatory)
- Phase 9 runs once at the end (full mode only, skipped in lite mode)
- Fix HIGH/Critical issues immediately
- Re-run tests after any code changes
- Use LSP tools for code intelligence during implementation

## Completion

After Phase 9 (or Phase 8 in lite mode):

1. Update state file to show all phases complete
2. Summarize what was accomplished
3. Suggest next steps (commit, PR, etc.)
4. Optionally use `superpowers:finishing-a-development-branch`

**IMPORTANT:** Never skip phases within an iteration. All 8 iteration phases are mandatory.
