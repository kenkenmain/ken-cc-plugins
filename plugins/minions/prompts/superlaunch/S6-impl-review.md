# Phase S6: Impl Review [PHASE S6]

## Subagent Config

- **Primary:** `minions:impl-reviewer`
- **Supplementary (parallel):**
  - `minions:critic` — correctness, bugs, logic errors, code quality
  - `minions:silent-failure-hunter` — silent failures, swallowed errors, bad fallbacks
  - `minions:type-reviewer` — type design, encapsulation, invariants
- **Input:** `.agents/tmp/phases/S2-plan.md`, git diff
- **Output:** `.agents/tmp/phases/S6-impl-review.json`

## Instructions

Review implementation against the plan. Dispatch primary reviewer and supplementary agents in parallel.

### Process

1. Read the plan from `.agents/tmp/phases/S2-plan.md`
2. Get list of modified files from `.agents/tmp/phases/S4-tasks.json`
3. Check `S4-tasks.json` for `testsWritten` entries — include test quality in review scope
4. Dispatch primary reviewer and all supplementary agents **in parallel**
5. Aggregate issues from all agents into a single `issues[]` array, tagging each with `"source"` field
6. Write structured JSON result to `.agents/tmp/phases/S6-impl-review.json`

### Output

Write JSON to `.agents/tmp/phases/S6-impl-review.json` with: `status`, `issues[]`, `filesReviewed`, `summary`

Each issue in `issues[]` includes `"source": "<agent-type>"`.

### If Issues Found

The SubagentStop hook enters a review-fix cycle: fix, re-review, repeat until approved or max retries.
