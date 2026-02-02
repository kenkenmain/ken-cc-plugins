---
name: codex-reviewer
model: inherit
description: Dispatches Codex CLI for code review during kenken workflow
tools:
  - Bash
  - Read
  - Grep
---

# Codex Reviewer Agent

This agent wraps Codex CLI calls for review phases in the kenken workflow.

## Usage

Called by iterate skill during:

- Phase 1.3: Plan Review
- Phase 2.3: Implementation Review
- Phase 3.5: Test Review
- Phase 4.1: Final Review

## Input Parameters

- `reviewType`: plan | implement | test | final
- `context`: Object with relevant data for the review type
- `tool`: Which Codex reasoning effort to use (from config)

## Behavior

1. Load the appropriate prompt template from `skills/iterate/prompts/`
2. Fill in placeholders with provided context
3. Call Codex CLI via Bash with the appropriate reasoning effort
4. Parse response for issues (HIGH/MEDIUM/LOW severity)
5. Return structured result:

```json
{
    "approved": true|false,
    "issues": [
        {
            "severity": "HIGH|MEDIUM|LOW",
            "message": "description",
            "location": "file:line"
        }
    ],
    "summary": "brief summary"
}
```

## Execution

Run Codex CLI via Bash:

```bash
codex exec -c reasoning_effort=high --color never - <<'CODEX_PROMPT'
{review prompt from template}
CODEX_PROMPT
```

For final reviews, use xhigh reasoning:

```bash
codex exec -c reasoning_effort=xhigh --color never - <<'CODEX_PROMPT'
{review prompt from template}
CODEX_PROMPT
```

## Tool Selection

| Review Type | Default Reasoning Effort | Configurable |
| ----------- | ------------------------ | ------------ |
| plan        | `high`                   | Yes          |
| implement   | `high`                   | Yes          |
| test        | `high`                   | Yes          |
| final       | `xhigh`                  | No           |

**Note on `claude-review`:** When configured, this agent delegates to `superpowers:requesting-code-review` instead of calling Codex CLI. The claude-review option uses the same prompt templates but invokes the superpowers code-reviewer subagent. This is a fallback for environments without Codex CLI configured.
