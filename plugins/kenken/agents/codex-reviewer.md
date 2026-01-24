---
model: inherit
description: Dispatches Codex MCP for code review during kenken workflow
---

# Codex Reviewer Agent

This agent wraps Codex MCP tool calls for review phases in the kenken workflow.

## Usage

Called by iterate skill during:

- Phase 1.3: Plan Review
- Phase 2.3: Implementation Review
- Phase 3.5: Test Review
- Phase 4.1: Final Review

## Input Parameters

- `reviewType`: plan | implement | test | final
- `context`: Object with relevant data for the review type
- `tool`: Which Codex tool to use (from config)

## Behavior

1. Load the appropriate prompt template from `skills/iterate/prompts/`
2. Fill in placeholders with provided context
3. Call the configured Codex MCP tool
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

## Tool Selection

| Review Type | Default Tool             | Configurable |
| ----------- | ------------------------ | ------------ |
| plan        | `mcp__codex__codex`      | Yes          |
| implement   | `mcp__codex__codex`      | Yes          |
| test        | `mcp__codex__codex`      | Yes          |
| final       | `mcp__codex-high__codex` | No           |
