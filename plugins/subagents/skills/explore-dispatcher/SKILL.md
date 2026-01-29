---
name: explore-dispatcher
description: Dispatch parallel Explore agents to gather codebase context
---

# Explore Dispatcher

Dispatch 1-10 parallel Explore agents based on task complexity.

## When to Use

Phase 0 of workflow, before brainstorming.

## Complexity-Based Agent Count

Analyze task description to determine agent count:

| Complexity | Signals                                 | Agent Count |
| ---------- | --------------------------------------- | ----------- |
| Simple     | typo, rename, single file, small fix    | 1-2         |
| Medium     | add feature, fix bug, refactor function | 3-5         |
| Complex    | auth, multi-system, architecture change | 6-10        |

## Query Generation

Generate focused explore queries based on task. Examples for "Add OAuth authentication":

1. "Find existing auth patterns, middleware, session handling"
2. "Find user model, database schema, existing routes"
3. "Find test patterns for auth, existing test utilities"
4. "Find environment config, secrets handling patterns"
5. "Find API route structure and error handling patterns"

## Dispatch Process

1. Analyze task complexity → determine agent count
2. Generate explore queries (one per agent)
3. Dispatch all Explore agents in parallel using Task tool:

```
Task(
  description: "Explore: {query summary}",
  prompt: "{full query}",
  subagent_type: "Explore",
  model: config.stages.EXPLORE.model
)
```

4. Wait for all agents to complete
5. Aggregate results to `.agents/tmp/phases/0-explore.md`

## Output Format

Write aggregated findings to `.agents/tmp/phases/0-explore.md`:

```markdown
# Explore Findings

## Query 1: {query}

{findings}

## Query 2: {query}

{findings}

...

## Summary

- Key patterns found: ...
- Relevant files: ...
- Considerations: ...
```

## Update State

After completion:

- Set `stages.EXPLORE.status: "completed"`
- Set `stages.EXPLORE.agentCount: {count}`
- Set `files.explore: ".agents/tmp/phases/0-explore.md"`

## Error Handling

If any Explore agent fails:

1. Record partial results from successful agents
2. Log failed queries
3. Continue with available findings (don't block workflow)
