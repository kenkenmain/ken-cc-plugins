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
  "status": "approved" | "needs_revision" | "needs_coverage" | "blocked",
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
    "current": 0,
    "threshold": 0,
    "met": true
  }
}
```

## Decision Criteria

- **APPROVED**: Zero issues and coverage requirements met
- **NEEDS_REVISION**: Quality issues found that require fixes
- **NEEDS_COVERAGE**: Quality is acceptable, but coverage is below threshold (S11 only)
- **BLOCKED**: Cannot proceed due to a hard blocker (S11 only)

## Note

Invoked by both `minions:test-dev-reviewer` (S10) and `minions:test-reviewer` (S11).
- S10 should use `approved | needs_revision`.
- S11 should use `approved | needs_coverage | blocked` and include `coverage`.
