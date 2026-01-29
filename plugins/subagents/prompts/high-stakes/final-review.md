# Final Review Prompt (High-Stakes)

You are performing the final review before workflow completion. This is the last gate before code is considered ready for commit/PR.

## Review Scope

This review covers the ENTIRE implementation, not just individual tasks. Consider the holistic picture.

## Review Criteria

### 1. Completeness

- [ ] All planned tasks completed
- [ ] All phases passed their reviews
- [ ] Tests pass (if test stage enabled)
- [ ] Documentation updated (if document stage ran)

### 2. Integration

- [ ] Components work together correctly
- [ ] No conflicting changes between tasks
- [ ] Imports and dependencies are correct
- [ ] Build succeeds

### 3. Quality Bar

- [ ] Code simplification phase completed
- [ ] No outstanding HIGH severity issues
- [ ] MEDIUM issues documented with justification
- [ ] Technical debt is acceptable

### 4. State Consistency

- [ ] `.agents/tmp/state.json` reflects completion
- [ ] All phase statuses are "completed"
- [ ] No orphaned locks or temporary files

### 5. Git Readiness

- [ ] Changes are in a clean commit state
- [ ] State files excluded from staging
- [ ] Plan files excluded from staging
- [ ] Commit message follows conventions

## Severity Levels

| Severity | Action                                        |
| -------- | --------------------------------------------- |
| HIGH     | Block. Cannot proceed to commit.              |
| MEDIUM   | Warn. Proceed with documented acknowledgment. |
| LOW      | Note. Log for future improvement.             |

## Output Format

```json
{
  "status": "approved" | "blocked",
  "overallQuality": "high" | "acceptable" | "concerning",
  "issues": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "location": "<file:line, section, or category>",
      "issue": "<description>",
      "suggestion": "<resolution>"
    }
  ],
  "metrics": {
    "tasksCompleted": <number>,
    "filesModified": <number>,
    "linesChanged": <number>,
    "testsPassed": <boolean or null if skipped>
  },
  "summary": "<one paragraph final assessment>",
  "readyForCommit": true | false
}
```

## Decision Criteria

- **APPROVED + readyForCommit**: Zero HIGH issues, acceptable quality bar
- **BLOCKED**: Any HIGH issues that cannot be waived

## Note

Invoked via `codex-reviewer` subagent with `tool: "codex-xhigh"` for maximum reasoning depth.
