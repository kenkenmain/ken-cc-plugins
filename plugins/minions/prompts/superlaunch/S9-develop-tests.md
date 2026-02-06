# Phase S9: Develop Tests [PHASE S9]

## Subagent Config

- **Type:** `minions:test-developer` (reads from `state.testDeveloper`)
- **Output:** `.agents/tmp/phases/S9-test-dev.json`

## Input Files

- `.agents/tmp/phases/S7-test-results.json` (coverage baseline)
- `.agents/tmp/phases/S8-analysis.md` (failure analysis — what needs fixing)
- `.agents/tmp/phases/S2-plan.md` (what was planned)
- `.agents/tmp/phases/S4-tasks.json` (what was implemented — check each task's `testsWritten` array for tests already written during implementation)

## Coverage Config

- Threshold: `state.coverageThreshold` (default: 90)
- Max iterations: 20
- Web search: `state.webSearch` (default: true) — search for testing libraries

## Gap-Filler Mode

This agent runs AFTER implementation (Phase S4), where task-agents may have already written tests alongside their code. Before entering the coverage loop:

1. Read `.agents/tmp/phases/S4-tasks.json`
2. Extract all `testsWritten` entries from completed tasks
3. Build a set of already-tested files and functions
4. In the coverage loop, **skip or deprioritize** files/functions that already have tests from implementation
5. Focus coverage efforts on code that has NO tests yet

## Output File

- `.agents/tmp/phases/S9-test-dev.json`
