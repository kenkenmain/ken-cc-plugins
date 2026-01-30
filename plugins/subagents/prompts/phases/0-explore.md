# Phase 0: Explore [PHASE 0]

## Subagent Config

- **Type:** Explore (parallel batch, 1-10 agents)
- **Output:** `.agents/tmp/phases/0-explore.md`

## Instructions

Analyze the task and dispatch 1-10 parallel Explore agents to gather codebase context.

### Agent Count by Complexity

| Complexity | Signals                          | Count |
| ---------- | -------------------------------- | ----- |
| Simple     | typo, rename, single file        | 1-2   |
| Medium     | add feature, fix bug, refactor   | 3-5   |
| Complex    | auth, multi-system, architecture | 6-10  |

### Process

1. Read the task description from state
2. Determine complexity and agent count
3. Generate one focused query per agent
4. Dispatch all Explore agents in parallel
5. Aggregate results into `.agents/tmp/phases/0-explore.md`

### Output Format

Write to `.agents/tmp/phases/0-explore.md`:

```
# Explore Findings

## Query 1: {query}
{findings}

## Summary
- Key patterns: ...
- Relevant files: ...
```

### Error Handling

If any agent fails, record partial results. Do not block on individual failures.
