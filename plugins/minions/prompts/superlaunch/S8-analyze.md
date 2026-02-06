# Phase S8: Analyze [PHASE S8]

## Subagent Config

- **Type:** `minions:failure-analyzer` (reads from `state.failureAnalyzer`)
- **Output:** `.agents/tmp/phases/S8-analysis.md`

## Input Files

- `.agents/tmp/phases/S7-test-results.json`

## Instructions

Analyze test and lint failures from Phase S7:

- Identify root causes for each failure
- Apply fixes directly to the codebase
- Re-run failing tests to verify fixes work
- If a failure cannot be fixed, document the reason

Write a structured analysis to `.agents/tmp/phases/S8-analysis.md` with:
- List of failures analyzed
- Fixes applied (file, change description)
- Remaining unfixed failures (if any) with reasons
