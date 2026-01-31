# Plan Review Prompt (High-Stakes)

You are reviewing an implementation plan for a 2-level agent workflow. This is a blocking review - issues found here MUST be resolved before implementation proceeds.

## Review Criteria

### 1. Completeness

- [ ] All user requirements addressed
- [ ] Entry/exit criteria defined for each phase
- [ ] Error handling specified
- [ ] Rollback strategy documented

### 2. Technical Correctness

- [ ] Model IDs are valid (`sonnet-4.5`, `opus-4.5`, `haiku-4.5`, `inherit` for Task tool)
- [ ] MCP tool IDs are valid (`codex-high`, `codex-xhigh`)
- [ ] Context isolation rules are enforceable
- [ ] Dependencies between tasks are correctly ordered

### 3. Architecture

- [ ] 2-level architecture properly maintained (main conversation + parallel subagents)
- [ ] Context flows via file-based state transfer
- [ ] State management is atomic and recoverable
- [ ] Wave-based parallel execution boundaries are clear

### 4. Security & Safety

- [ ] No sensitive data in inter-agent messages
- [ ] Git excludes state files and plans from commits
- [ ] Stop/resume preserves integrity
- [ ] Resource limits defined

## Severity Levels

| Severity | Action Required                               |
| -------- | --------------------------------------------- |
| HIGH     | Block. Must fix before implementation.        |
| MEDIUM   | Should fix. May proceed with documented risk. |
| LOW      | Note for future. Does not block.              |

## Output Format

```json
{
  "status": "approved" | "needs_revision",
  "issues": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "location": "<section or line>",
      "issue": "<description>",
      "suggestion": "<how to fix>"
    }
  ],
  "summary": "<one paragraph assessment>"
}
```

## Decision Criteria

- **APPROVE**: Zero HIGH issues, MEDIUM issues have mitigations documented
- **NEEDS_REVISION**: Any HIGH issues OR multiple unmitigated MEDIUM issues
