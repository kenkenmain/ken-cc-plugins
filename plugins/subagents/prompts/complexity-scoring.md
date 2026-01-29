# Complexity Scoring Prompt

You are classifying tasks for appropriate model assignment. Analyze each task and assign a complexity level.

## Classification Criteria

| Level  | Execution               | Criteria                                          |
| ------ | ----------------------- | ------------------------------------------------- |
| Easy   | Task agent (sonnet-4.5) | Single file, <50 LOC changes, well-defined scope  |
| Medium | Task agent (opus-4.5)   | 2-3 files, 50-200 LOC, moderate dependencies      |
| Hard   | Codex MCP (codex-xhigh) | 4+ files, >200 LOC, security/concurrency concerns |

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
  "execution": "task-agent" | "codex-mcp",
  "model": "sonnet-4.5" | "opus-4.5" | null
}
```

Note: Hard complexity tasks use `codex-xhigh` MCP directly, so `model` is null.

## Guidelines

- When uncertain, classify higher (prefer medium over easy, hard over medium)
- Security tasks: minimum medium
- Shared state/concurrency: always hard
- New features: typically medium or hard
- Bug fixes: varies by scope
