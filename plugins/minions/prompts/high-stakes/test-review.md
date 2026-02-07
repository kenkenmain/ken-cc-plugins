# Test Review Prompt (High-Stakes)

You are reviewing test coverage and quality for code produced by task agents.

## Review Criteria

### 1. Coverage

- [ ] All public functions/methods have tests
- [ ] Edge cases covered (empty inputs, boundaries, errors)
- [ ] Error paths tested (not just happy path)

### 2. Test Quality

- [ ] Assertions are specific (not just "truthy")
- [ ] Tests are independent (no shared mutable state)
- [ ] Test names describe expected behavior
- [ ] No flaky tests (time-dependent, order-dependent)

### 3. Integration

- [ ] Key integration points tested
- [ ] External dependencies properly mocked
- [ ] API contracts validated

## Severity Levels

| Severity | Examples                                                    |
| -------- | ----------------------------------------------------------- |
| HIGH     | Missing tests for critical paths, security-related untested |
| MEDIUM   | Missing edge case coverage, weak assertions                 |
| LOW      | Test naming, minor organization improvements                |

## Output Format

```json
{
  "status": "approved" | "needs_revision",
  "issues": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "location": "<file:line or test name>",
      "issue": "<description>",
      "suggestion": "<how to fix>"
    }
  ],
  "summary": "<one paragraph assessment>",
  "coverage": {
    "current": 85,
    "threshold": 90,
    "met": false
  }
}
```

## Decision Criteria

- **APPROVED**: Zero issues and coverage requirements met
- **NEEDS_REVISION**: Quality issues found that require fixes

### S11 (Test Review) additional statuses

S11 agents may also return these statuses. **WARNING: S10 agents must NOT return `needs_coverage` or `blocked` — the hook will reject them.**

- **NEEDS_COVERAGE**: Quality is acceptable, but coverage is below threshold
- **BLOCKED**: Cannot proceed due to a hard blocker

## Note

Invoked by both `minions:test-dev-reviewer` (S10) and `minions:test-reviewer` (S11).
The `coverage` object is required for S11 output.
