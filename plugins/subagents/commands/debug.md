---
description: Search for multiple bug fix solutions in parallel using subagents
argument-hint: <bug description> [--solutions N] [--test] [--auto]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion
---

# Debug with Parallel Solutions

Search for multiple bug fix solutions in parallel. Each solution agent independently investigates the bug from a different angle, then results are ranked and the best solution is presented for approval.

## Arguments

- `<bug description>`: Required. Describes the bug -- can include error messages, failing test names, stack traces, or reproduction steps
- `--solutions N`: Optional. Number of parallel solution agents to dispatch (default: 3, min: 2, max: 10)
- `--test`: Optional. Each solution agent runs tests after applying its fix to validate the solution
- `--auto`: Optional. Automatically apply the top-ranked solution without asking for user confirmation

Parse from $ARGUMENTS to extract bug description and flags.

## Step 1: Parse Arguments

Extract from `$ARGUMENTS`:

1. Scan for `--solutions N` flag. If found, extract integer N. Validate: 2 <= N <= 10. If invalid, display error and exit:
   ```
   Invalid --solutions value: {N}. Must be between 2 and 10.
   ```
2. Scan for `--test` flag (boolean presence).
3. Scan for `--auto` flag (boolean presence).
4. Everything remaining after removing flags is the `<bug description>`.
5. If bug description is empty, display error and exit:
   ```
   Usage: /subagents:debug <bug description> [--solutions N] [--test] [--auto]

   Example: /subagents:debug "TypeError: Cannot read property 'id' of null in UserService.getProfile()"
   ```

Store parsed values:
- `bugDescription`: string (the full bug description text)
- `solutionCount`: integer (default 3)
- `runTests`: boolean (default false)
- `autoApply`: boolean (default false)

## Step 2: Check for Active Workflow

Read `.agents/tmp/state.json` to check if a subagents workflow is currently running.

If the file exists AND `status` is `"in_progress"`:
```
Warning: A subagents workflow is currently active (Phase {currentPhase}).
The debug command operates independently and will NOT interfere with the workflow,
but file changes from debug solutions may conflict with workflow changes.

Continue anyway?
```
Use AskUserQuestion to confirm. If user declines, exit.

If no state file exists, or status is not `in_progress`, proceed without warning.

## Step 3: Display Plan and Invoke Skill

Display the debug plan to the user:

```
Parallel Debug Session
======================
Bug: {bugDescription (truncated to 120 chars)}
Solutions: {solutionCount} parallel agents
Test after fix: {yes|no}
Auto-apply: {yes|no}

Phases:
  1. Context Gathering    - analyze bug and affected files
  2. Hypothesis Generation - generate {solutionCount} distinct solution angles
  3. Parallel Search       - dispatch {solutionCount} solution-searcher agents
  4. Ranking              - evaluate and rank all solutions
  5. Selection            - present results for approval
  6. Application          - apply chosen solution
```

Then invoke the `parallel-debug` skill with the following context:
- Bug description: `{bugDescription}`
- Solution count: `{solutionCount}`
- Run tests: `{runTests}`
- Auto-apply: `{autoApply}`

## Step 4: Handle Solution Selection

After the parallel-debug skill completes its ranking phase, it presents ranked solutions. If `--auto` is NOT set, handle user interaction:

Use AskUserQuestion to present the ranked solutions:

```
question: "Which solution should be applied?"
header: "Solutions"
options:
  - label: "Solution 1: {hypothesis} (Score: {overallScore}/10)"
    description: "{fix.description}"
  - label: "Solution 2: {hypothesis} (Score: {overallScore}/10)"
    description: "{fix.description}"
  - label: "Solution 3: {hypothesis} (Score: {overallScore}/10)"
    description: "{fix.description}"
  - label: "Show detailed diffs"
    description: "View full diff output for all solutions before choosing"
  - label: "None - cancel"
    description: "Do not apply any solution"
```

If "Show detailed diffs" selected:
1. Display the full patch for each solution (from the solution-searcher output)
2. Re-ask the question (without the "Show detailed diffs" option)

If "None - cancel" selected:
```
Debug session cancelled. No changes applied.
Solution details are available in the conversation above for reference.
```

If a solution is selected, proceed to Step 5.

If `--auto` is set, skip the question and use solution #1 (the top-ranked one).

## Step 5: Apply Solution and Display Summary

After the chosen solution is applied by the parallel-debug skill:

```
Debug Session Complete
=====================
Bug: {bugDescription (truncated)}
Solution Applied: #{rank} - {hypothesis}
Confidence: {confidence}/10

Files Modified:
  - {file1}
  - {file2}

{if --test was used:}
Test Results: {passed|failed}
  Passed: {passCount}
  Failed: {failCount}
{end if}

{if tests failed:}
Warning: Some tests still fail after applying this solution.
Consider running /subagents:debug again with a more specific bug description,
or manually review the changes.
{end if}
```

## Step 6: Error Handling

Handle errors at each phase:

**Argument parsing errors:** Display usage and exit immediately.

**No hypotheses generated:** If the skill cannot generate solution hypotheses from the bug description:
```
Could not generate solution hypotheses from the bug description.
Try providing more context:
  - Error message or stack trace
  - Failing test name
  - Steps to reproduce
  - Relevant file paths
```

**All solution agents failed:** If every solution-searcher agent fails:
```
All {solutionCount} solution agents failed to produce a fix.
This may indicate the bug requires manual investigation.

Agent errors:
  Agent 1: {error summary}
  Agent 2: {error summary}
  Agent 3: {error summary}
```

**Solution application failed:** If the chosen solution cannot be applied cleanly:
```
Failed to apply solution #{rank}: {error}
The solution may have file conflicts. Try:
  1. /subagents:debug with fewer --solutions
  2. Manually applying the suggested changes (shown above)
```
