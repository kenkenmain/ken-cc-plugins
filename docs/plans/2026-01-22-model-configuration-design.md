# Model Configuration Design

## Problem Statement

The superpowers-iterate plugin currently has:

1. A hardcoded model ID (`claude-sonnet-4-20250514`) in the codex-reviewer agent
2. Documentation that mentions "sonnet subagents" without clear model configuration guidance

## Requirements

1. **Parallel agents** should use the latest Sonnet models via the `sonnet` alias
2. **Non-parallel agents** should inherit the user's model selection (via `/model` command, e.g., Opus 4.5)

## Design Decision

### Model Configuration Strategy

| Agent Type                              | Model Setting    | Rationale                                      |
| --------------------------------------- | ---------------- | ---------------------------------------------- |
| Parallel agents (research, exploration) | `model: sonnet`  | Latest Sonnet for cost-effective parallel work |
| Non-parallel agents (single tasks)      | `model: inherit` | Respects user's `/model` choice                |

### Files to Change

1. **`agents/codex-reviewer.md`**: Change `model: claude-sonnet-4-20250514` to `model: inherit`
    - This is a single-task agent (not parallel), should respect user's model choice

2. **`skills/iteration-workflow/SKILL.md`**: Update documentation to clarify:
    - Parallel agents dispatched via `superpowers:dispatching-parallel-agents` use `model: sonnet`
    - Single-task agents should use `model: inherit`

## Test Strategy

1. Verify plugin.json version is valid
2. Verify YAML frontmatter is valid in agent files
3. Manual verification that the documentation is clear
