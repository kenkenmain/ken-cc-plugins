# Phase S13: Final Review [PHASE S13]

## Subagent Config

- **Primary:** `minions:final-reviewer`
- **Supplementary (parallel):**
  - `minions:pedant` — code quality, naming, style, test coverage gaps, comments
  - `minions:security-reviewer` — security vulnerabilities, OWASP, injection, access control
  - `minions:silent-failure-hunter` — silent failures, error handling gaps
- **Input:** all phase outputs
- **Output:** `.agents/tmp/phases/S13-final-review.json`

## Instructions

Perform final holistic review of the entire implementation. Dispatch primary reviewer and supplementary agents in parallel.

### Process

1. Read all phase outputs: plan (S2), tasks (S4), test results (S7), prior reviews
2. Dispatch primary reviewer and all supplementary agents **in parallel**
3. Aggregate issues from all agents into a single `issues[]` array, tagging each with `"source"` field
4. Write structured JSON result to `.agents/tmp/phases/S13-final-review.json`

### Output

Write JSON to `.agents/tmp/phases/S13-final-review.json` with: `status`, `overallQuality`, `issues[]`, `metrics`, `summary`, `readyForCommit`

Each issue in `issues[]` includes `"source": "<agent-type>"`.

### Decision

- `approved` + `readyForCommit: true` -> proceed to completion
- `blocked` -> halt workflow, report to user
