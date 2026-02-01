# Complexity Scoring Prompt

You are classifying tasks for appropriate model assignment. Analyze each task and assign a complexity level.

## Classification Criteria

| Level  | Execution                    | Criteria                                          |
| ------ | ---------------------------- | ------------------------------------------------- |
| Easy   | task-agent → codex-high      | Single file, <50 LOC changes, well-defined scope  |
| Medium | task-agent → codex-high      | 2-3 files, 50-200 LOC, moderate dependencies      |
| Hard   | task-agent → codex-high      | 4+ files, >200 LOC, security/concurrency concerns |

## Task Analysis Checklist

For each task, evaluate:

1. **File Count**: How many files will be modified?
2. **LOC Estimate**: Approximate lines of code to change?
3. **Dependencies**: Does this task depend on other tasks?
4. **Risk Factors**:
   - Security implications (auth, crypto, input validation)
   - Concurrency/race conditions
   - Data integrity concerns
   - API contract changes

## Output Format

For each task, return:

```json
{
  "taskId": "<id>",
  "complexity": "easy" | "medium" | "hard",
  "reasoning": "<one line explanation>",
  "execution": "codex-mcp",
  "model": null
}
```

Note: All tasks are dispatched via task-agent (thin wrapper) to `codex-high` MCP, so `model` is always null. Complexity scoring is used for tracking and logging.

## Guidelines

- When uncertain, classify higher (prefer medium over easy, hard over medium)
- Security tasks: minimum medium
- Shared state/concurrency: always hard
- New features: typically medium or hard
- Bug fixes: varies by scope
