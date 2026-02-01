---
name: parallel-debug
description: "Use when debugging a bug with multiple parallel solution approaches. Dispatches N solution-searcher agents in parallel, each investigating a different angle, then ranks results and applies the chosen solution."
---

# Parallel Debug Skill

Orchestrate parallel debugging by dispatching multiple solution-searcher agents, each exploring a different hypothesis about a bug's root cause. After all agents complete, rank the solutions and apply the best one.

This skill runs within a single conversation -- no hooks, no state file, no Ralph Loop. It is completely independent of the 15-phase workflow.

## Configuration Defaults

- `defaultSolutions`: 3 (number of parallel agents)
- `maxSolutions`: 10
- `defaultRunTests`: false
- `defaultAutoApply`: false

## Flow

The skill executes 7 phases sequentially:

```
Phase 1: Context Gathering    -- analyze bug and find relevant files
Phase 2: Hypothesis Generation -- generate N distinct solution angles
Phase 3: Parallel Dispatch     -- dispatch N solution-searcher agents
Phase 4: Result Aggregation    -- collect and merge all agent outputs
Phase 5: Ranking               -- dispatch solution-ranker to evaluate
Phase 6: Presentation          -- display ranked results to user
Phase 7: Application           -- apply the chosen solution's patch
```

## Phase 1: Context Gathering

Read the bug description provided by the command. Analyze it to identify:

1. **Error type and message** -- extract from the bug description (e.g., TypeError, AssertionError, test failure name)
2. **File references** -- any file paths mentioned in the description or stack trace
3. **Function/class names** -- identifiers mentioned in the error
4. **Search the codebase** -- use Grep to find files containing the error message, function names, or class names mentioned in the bug description. Use Glob to find test files related to the affected code.
5. **Compile context summary**:
   - Bug description (as provided)
   - Error output (if stack trace was included)
   - Relevant source files (found via search, max 10)
   - Related test files (found via search)
   - Test command (detected from Makefile, package.json, or pyproject.toml; fall back to `make test`)

## Phase 2: Hypothesis Generation

Based on the gathered context, generate N distinct solution hypotheses (where N = `solutionCount` from the command arguments).

Each hypothesis must represent a genuinely different angle of attack. Example angle categories:

- **Null/undefined handling** -- missing null checks, optional chaining, default values
- **Async/timing issues** -- race conditions, missing await, callback ordering
- **Type mismatches** -- wrong types, implicit coercion, schema mismatches
- **Logic errors** -- off-by-one, wrong operator, inverted condition
- **Missing validation** -- unchecked input, boundary conditions
- **Configuration problems** -- wrong env var, missing config, stale cache
- **Import/dependency issues** -- wrong import path, circular dependency, version mismatch
- **State management** -- stale state, mutation side effects, initialization order
- **Error handling gaps** -- swallowed errors, missing try/catch, wrong error type

For each hypothesis, produce:

```json
{
  "angleId": "solution-1",
  "description": "Investigate whether the user object is null due to missing error propagation in the database query layer",
  "targetFiles": ["src/repositories/UserRepository.ts", "src/services/UserService.ts"],
  "priority": "high"
}
```

Guidelines:
- The first hypothesis should be the most likely root cause based on the error analysis
- Subsequent hypotheses should explore progressively less obvious angles
- Each hypothesis must target at least 1 specific file
- Do NOT generate duplicate or overlapping hypotheses
- Priority: `high` (most likely), `medium` (plausible), `low` (creative/lateral)

## Phase 3: Parallel Dispatch

For each hypothesis, dispatch a `subagents:solution-searcher` agent via the Task tool.

**CRITICAL: All dispatches must happen in a SINGLE message** (multiple Task tool calls). This triggers parallel execution.

### Git Isolation Strategy

Since all agents modify files in the same working tree, isolation is essential:

1. **Before dispatch:** Check for uncommitted changes with `git status --porcelain`. If changes exist, run `git stash push -u -m "parallel-debug-session"` to stash both tracked and untracked changes. Record that a stash was created.
2. **Agent instructions:** Each agent is instructed to:
   a. Apply its fix
   b. Run tests (if `runTests` is true)
   c. Capture the diff with `git diff`
   d. Restore the working tree with `git checkout . && git clean -fd` (reverts tracked files AND removes untracked files created by the fix)
   e. Include the patch in its JSON output
3. **After all agents complete:** Verify the working tree is clean with `git status --porcelain`. If any files remain, run `git checkout . && git clean -fd` as a safety net.
4. **Restore user changes:** If a stash was created in step 1, run `git stash pop` to restore the user's uncommitted work.

### Agent Payload

For each hypothesis, construct:

```json
{
  "searchId": "solution-1",
  "bugDescription": "<from Phase 1 context>",
  "errorOutput": "<from Phase 1 context, if available>",
  "angle": "<hypothesis description from Phase 2>",
  "targetFiles": ["<files from Phase 2 hypothesis>"],
  "runTests": false,
  "testCommand": "<detected in Phase 1>",
  "constraints": {
    "maxReadFiles": 15,
    "maxWriteFiles": 5
  }
}
```

Set `runTests` to the value from command arguments.

## Phase 4: Result Aggregation

After all agents complete:

1. Collect the JSON output from each solution-searcher agent.
2. Parse each result. If an agent returned malformed JSON, record it as a failed result with `status: "failed"` and `error: "Malformed JSON output"`.
3. Write aggregated results to `.agents/tmp/debug-solutions.json`:

```json
{
  "bugDescription": "<original bug description>",
  "solutionCount": 3,
  "completedCount": 2,
  "failedCount": 1,
  "solutions": [
    { "searchId": "solution-1", "status": "completed", ... },
    { "searchId": "solution-2", "status": "completed", ... },
    { "searchId": "solution-3", "status": "failed", ... }
  ]
}
```

4. If ALL agents failed or returned `no_fix_found`, report to the user and exit:
   ```
   All {N} solution agents failed to produce a fix.
   This may indicate the bug requires manual investigation.
   ```

## Phase 5: Ranking

Dispatch a single `subagents:solution-ranker` agent via the Task tool.

The prompt for the ranker must include:
- The path to `.agents/tmp/debug-solutions.json`
- Instructions to read that file and evaluate all solutions

The ranker returns ranked JSON with scores, rationale, and a recommendation.

## Phase 6: Presentation

Parse the ranker's output and present results:

```
Parallel Debug Results
======================
{completedCount} solutions found, ranked by quality:

#1 [Score: 8.5/10] {hypothesis}
   Confidence: {confidence}/10 | Tests: {passed/failed/not run}
   Files: {filesModified joined}
   Fix: {fix.description}
   Strengths: {strengths joined}

#2 [Score: 6.3/10] {hypothesis}
   Confidence: {confidence}/10 | Tests: {passed/failed/not run}
   Files: {filesModified joined}
   Fix: {fix.description}
   Weaknesses: {weaknesses joined}

Recommendation: Solution #1 -- {recommendation.summary}
Caveats: {caveats joined}
```

If `--auto` is set, skip to Phase 7 with the top-ranked solution.

Otherwise, return control to the command's Step 4 for user selection via AskUserQuestion.

## Phase 7: Application

After the user (or `--auto`) selects a solution:

1. **Retrieve the patch** from the selected solution's `patch` field in the aggregated results.
2. **Apply the patch** using `git apply` via Bash. If `git apply` fails (e.g., context mismatch), fall back to manually re-applying the edits using Edit tool based on the solution's `fix.filesModified` and `fix.description`.
3. **Verify** the applied changes by running `git diff` and confirming the expected files were modified.
4. **Run tests** (optional) -- if `--test` was set and the solution's test results show passing, offer to re-run tests to confirm the applied patch works.
5. **Report** the final state back to the command for summary display.

## Error Handling

- **Fewer than N agents succeed:** Rank only the successful ones. Mention failed agents in the summary.
- **Zero fixes produced:** Report that no solutions were found. Suggest the user provide more context.
- **Git isolation fails:** If `git stash create` or `git checkout .` fails, fall back to single-agent mode (dispatch agents one at a time, restoring between each).
- **Patch application fails:** If `git apply` fails for the chosen solution, display the patch content and suggest manual application.
- **Malformed agent output:** Record as failed with error details, continue with remaining agents.

## What This Skill Does NOT Do

- **Persistent state** -- no `.agents/tmp/state.json` is created. All state is in-conversation.
- **Hook interaction** -- this skill is completely independent of on-stop.sh, on-subagent-stop.sh, and on-task-dispatch.sh.
- **Ralph Loop** -- no orchestrator loop. The skill runs sequentially within one conversation turn.
- **Workflow integration** -- this skill does not participate in the 15-phase dispatch workflow. It is standalone.
