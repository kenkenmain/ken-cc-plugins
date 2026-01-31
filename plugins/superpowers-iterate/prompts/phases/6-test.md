# Phase 6: Run Tests [PHASE 6]

## Subagent Config

- **Type:** command (Bash)
- **Input:** config test commands
- **Output:** `.agents/tmp/iterate/phases/6-test-results.json`

## Instructions

Run lint and test commands, capture results as structured JSON.

### Process

1. Run lint command (default: `make lint`)
   - Capture exit code, stdout, stderr
   - If fails: attempt to fix issues, re-run until pass
2. Run test command (default: `make test`)
   - Capture exit code, stdout, stderr
   - If fails: attempt to fix issues, re-run until pass
3. Compute overall pass/fail status
4. Write structured results to output file

### Commands

```bash
# Lint
make lint 2>&1
LINT_EXIT=$?

# Test
make test 2>&1
TEST_EXIT=$?
```

### Retry on Failure

If lint or test fails:

1. Analyze the error output
2. Attempt automated fix (lint auto-fix, test fix)
3. Re-run the failed command
4. Record each attempt in the output

Maximum retry attempts per command: 3

### Output Format

Write to `.agents/tmp/iterate/phases/6-test-results.json`:

```json
{
  "lint": {
    "exitCode": 0,
    "passed": true,
    "stdout": "...",
    "stderr": "",
    "attempts": 1
  },
  "test": {
    "exitCode": 0,
    "passed": true,
    "stdout": "...",
    "stderr": "",
    "attempts": 1
  },
  "allPassed": true,
  "summary": "Lint passed, all tests passed."
}
```

### If Tests Fail After Retries

If tests still fail after maximum retries:

```json
{
  "lint": { "exitCode": 1, "passed": false, "stdout": "...", "stderr": "...", "attempts": 3 },
  "test": { "exitCode": 0, "passed": true, "stdout": "...", "stderr": "", "attempts": 1 },
  "allPassed": false,
  "summary": "Lint failed after 3 attempts. Tests passed."
}
```

The SubagentStop hook will handle the failure — either block advancement or proceed based on configuration.
