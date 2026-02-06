# Phase S7: Run Tests [PHASE S7]

## Subagent Config

- **Type:** `minions:test-developer` (reads from `state.testDeveloper`)
- **Primary Output:** `.agents/tmp/phases/S7-test-results.json`
- **Secondary Output:** `.agents/tmp/phases/S8-analysis.md`

## Input Files

- Test commands from config (default: `make lint`, `make test`)

## Output Files

- `.agents/tmp/phases/S7-test-results.json` — structured test results
- `.agents/tmp/phases/S8-analysis.md` — failure analysis with fixes applied

The test-developer agent handles both test execution and failure analysis in a single phase. Both output files are produced by the same agent.
