# Complexity Scoring Prompt

You are classifying tasks for appropriate model assignment. Analyze each task and assign a complexity level.

## Classification Criteria

| Level  | Agent               | Execution                       | Criteria                                          |
| ------ | ------------------- | ------------------------------- | ------------------------------------------------- |
| Easy   | sonnet-task-agent   | direct (model=sonnet)           | Single file, <50 LOC changes, well-defined scope  |
| Medium | opus-task-agent     | direct (model=opus)             | 2-3 files, 50-200 LOC, moderate dependencies      |
| Hard   | codex-task-agent    | codex-high MCP                  | 4+ files, >200 LOC, security/concurrency concerns |

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
  "execution": "direct" | "codex-mcp",
  "model": "sonnet" | "opus" | null,
  "agent": "sonnet-task-agent" | "opus-task-agent" | "codex-task-agent"
}
```

Mapping (Codex mode — `codexAvailable: true`):
- Easy → `"execution": "direct", "model": "sonnet", "agent": "sonnet-task-agent"`
- Medium → `"execution": "direct", "model": "opus", "agent": "opus-task-agent"`
- Hard → `"execution": "codex-mcp", "model": null, "agent": "codex-task-agent"`

Mapping (Claude mode — `codexAvailable: false`):
- Easy → `"execution": "direct", "model": "sonnet", "agent": "sonnet-task-agent"`
- Medium → `"execution": "direct", "model": "opus", "agent": "opus-task-agent"`
- Hard → `"execution": "direct", "model": "opus", "agent": "opus-task-agent"`

Check `codexAvailable` in `state.json` to determine hard task routing.

## Guidelines

- When uncertain, classify higher (prefer medium over easy, hard over medium)
- Security tasks: minimum medium
- Shared state/concurrency: always hard
- New features: typically medium or hard
- Bug fixes: varies by scope
