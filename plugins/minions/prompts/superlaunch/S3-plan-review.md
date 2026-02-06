# Phase S3: Plan Review [PHASE S3]

## Subagent Config

- **Type:** `minions:plan-reviewer`
- **Input:** `.agents/tmp/phases/S2-plan.md`
- **Output:** `.agents/tmp/phases/S3-plan-review.json`

## Instructions

Review the implementation plan for completeness, correctness, and feasibility.

### Process

1. Read the plan from `.agents/tmp/phases/S2-plan.md`
2. Evaluate: task coverage, dependency ordering, file targeting, acceptance criteria
3. Check for missing edge cases, security considerations, test strategy
4. Write structured JSON result to `.agents/tmp/phases/S3-plan-review.json`

### Output

Write JSON to `.agents/tmp/phases/S3-plan-review.json` with: `status`, `issues[]`, `summary`

### If Issues Found

If status is "needs_revision" with blocking issues, the SubagentStop hook enters a review-fix cycle.
