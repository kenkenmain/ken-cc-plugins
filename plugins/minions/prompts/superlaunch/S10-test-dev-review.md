# Phase S10: Test Dev Review [PHASE S10]

## Subagent Config

- **Primary:** `minions:test-dev-reviewer`
- **Input:** `.agents/tmp/phases/S9-test-dev.json`, `.agents/tmp/phases/S7-test-results.json`
- **Output:** `.agents/tmp/phases/S10-test-dev-review.json`

## Instructions

Review the tests and CI configuration written by the test-developer agent.

### Process

1. Read test development results from `.agents/tmp/phases/S9-test-dev.json`
2. Read original test results from `.agents/tmp/phases/S7-test-results.json`
3. Review test quality: meaningful assertions, no false positives, good coverage of edge cases
4. Review CI configuration: correct setup, appropriate triggers, coverage enforcement
5. Verify coverage threshold was met (or acceptable reason why not)
6. Write structured JSON result to `.agents/tmp/phases/S10-test-dev-review.json`

### Output

Write JSON to `.agents/tmp/phases/S10-test-dev-review.json` with:
- `status`: `approved | needs_revision` (do NOT use `needs_coverage` or `blocked`)
- `issues[]`
- `summary`

### If Issues Found

The SubagentStop hook enters a review-fix cycle: fix, re-review, repeat until approved or max retries.
