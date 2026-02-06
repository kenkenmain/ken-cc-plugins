# Phase S11: Test Review [PHASE S11]

## Subagent Config

- **Type:** `minions:test-reviewer`
- **Input:** `.agents/tmp/phases/S7-test-results.json`, `.agents/tmp/phases/S8-analysis.md`, `.agents/tmp/phases/S9-test-dev.json`
- **Output:** `.agents/tmp/phases/S11-test-review.json`

## Instructions

Final review of the entire TEST stage — all test results, analysis, and developed tests. Includes coverage threshold check.

### Process

1. Read test results from `.agents/tmp/phases/S7-test-results.json`
2. Read failure analysis from `.agents/tmp/phases/S8-analysis.md`
3. Read test development results from `.agents/tmp/phases/S9-test-dev.json`
4. **Run test suite with coverage** to get current coverage numbers:
   ```bash
   make test-coverage 2>&1 || npm run test -- --coverage 2>&1 || pytest --cov 2>&1
   ```
5. **Check coverage against threshold** (`state.coverageThreshold`, default 90%)
6. Evaluate overall test quality, coverage, and CI completeness
7. Write structured JSON result to `.agents/tmp/phases/S11-test-review.json`

### Output

Write JSON to `.agents/tmp/phases/S11-test-review.json`:

```json
{
  "status": "approved | needs_coverage | blocked",
  "coverage": {
    "current": 87.3,
    "threshold": 90,
    "met": false
  },
  "issues": [],
  "summary": "..."
}
```

### Decision

- `approved` + `coverage.met: true` -> proceed to FINAL stage
- `needs_coverage` + `coverage.met: false` -> **loop back to Phase S9** (SubagentStop hook handles this)
- `blocked` (quality issues unrelated to coverage) -> enter review-fix cycle
