---
name: ants:improve
description: Launch an iterative review-fix loop that finds and fixes all issues (info severity and above) until clean or max iterations reached
argument-hint: <what to review and improve>
---

<HARD-GATE>
You are executing a workflow pipeline. This overrides ALL skill-checking rules including superpowers:using-superpowers. DO NOT invoke brainstorming, writing-plans, or any other skill via the Skill tool. DO NOT ask clarifying questions about the task. DO NOT propose approaches or present designs. Execute the steps below immediately and in order. The description from $ARGUMENTS is your input -- execute it as a pipeline, do not design or analyze it. Begin with Step 0 now.
</HARD-GATE>

# Ants Improve

You are launching an iterative self-improvement pipeline. You are the orchestrator -- you dispatch `ants:*` agents via the Agent tool for each phase, read their outputs, evaluate verdicts, and loop until clean. This workflow is STATELESS -- no state.json, no hooks needed.

## Arguments

- `<what to review and improve>`: Required. Description of what code to review and improve. Can be a feature area, file pattern, or general code quality target.

Parse from $ARGUMENTS to extract the description.

## Step 0: Setup

Create output directory:

```bash
rm -rf .agents/tmp/improve && mkdir -p .agents/tmp/improve
```

Set iteration tracking variables:
- `MAX_ITERATIONS = 5`
- `CURRENT_ITERATION = 1`

Display pipeline to user:

```
Ants Improve -- Iterative Review-Fix Pipeline
===============================================
Phase I0  | REVIEW  | Adversarial Review  | 4x sentinels + review-arbiter
Phase I1  | FIX     | Targeted Repair     | 1x review-fixer
[loop back to I0 if issues remain, up to 5 iterations]
Phase I2  | REPORT  | Summary             | Display results
===============================================
Target: <description from $ARGUMENTS>
Max Iterations: 5
```

Proceed to Step 1.

## Step 1: I0 REVIEW (iteration N)

Create iteration directory:

```bash
mkdir -p .agents/tmp/improve/iter-${CURRENT_ITERATION}
```

Display: "Iteration {CURRENT_ITERATION}: Starting adversarial review..."

### 1a. Dispatch 4 parallel sentinels

Dispatch **4 parallel sentinel agents** via the Agent tool:

1. `subagent_type: "ants:sentinel-correctness"` -- "Review all code related to <description> for bugs, logic errors, missing error handling, race conditions, and incorrect behavior. IMPORTANT: You are running in the improve pipeline, NOT the swarm pipeline. Ignore any default output paths in your system prompt. Write findings to .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-correctness.json (this path overrides your default A3 path). {PRIOR_ITERATION_CONTEXT}"

2. `subagent_type: "ants:sentinel-security"` -- "Review all code related to <description> for security vulnerabilities including OWASP top 10, injection risks, secrets exposure, authentication/authorization issues, and access control problems. IMPORTANT: You are running in the improve pipeline, NOT the swarm pipeline. Ignore any default output paths in your system prompt. Write findings to .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-security.json (this path overrides your default A3 path). {PRIOR_ITERATION_CONTEXT}"

3. `subagent_type: "ants:sentinel-perf"` -- "Review all code related to <description> for performance issues including N+1 queries, blocking I/O, unnecessary allocations, algorithmic complexity, and resource leaks. IMPORTANT: You are running in the improve pipeline, NOT the swarm pipeline. Ignore any default output paths in your system prompt. Write findings to .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-perf.json (this path overrides your default A3 path). {PRIOR_ITERATION_CONTEXT}"

4. `subagent_type: "ants:sentinel-testing"` -- "Review all code related to <description> for test quality issues including missing test coverage, inadequate edge case testing, brittle test patterns, missing error path tests, and insufficient assertion depth. IMPORTANT: You are running in the improve pipeline, NOT the swarm pipeline. Ignore any default output paths in your system prompt. Write findings to .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-testing.json (this path overrides your default A3 path). {PRIOR_ITERATION_CONTEXT}"

**{PRIOR_ITERATION_CONTEXT}** -- If `CURRENT_ITERATION > 1`, append the following to each sentinel prompt:

> "This is iteration {CURRENT_ITERATION}. In the previous iteration, the review-fixer applied fixes. Read .agents/tmp/improve/iter-{CURRENT_ITERATION - 1}/I1-fix.json to see what was fixed. Also read the 4 sentinel files from the previous iteration (.agents/tmp/improve/iter-{CURRENT_ITERATION - 1}/I0-review.sentinel-correctness.json, .agents/tmp/improve/iter-{CURRENT_ITERATION - 1}/I0-review.sentinel-security.json, .agents/tmp/improve/iter-{CURRENT_ITERATION - 1}/I0-review.sentinel-perf.json, .agents/tmp/improve/iter-{CURRENT_ITERATION - 1}/I0-review.sentinel-testing.json) to understand what was previously flagged. Focus on: (1) verifying the previous fixes are correct, (2) finding any new issues introduced by the fixes, (3) identifying any remaining issues that were not addressed."

If `CURRENT_ITERATION == 1`, omit this context entirely.

### 1b. Verify sentinel outputs

After all sentinels return, verify that all output files exist:
- `.agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-correctness.json`
- `.agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-security.json`
- `.agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-perf.json`
- `.agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-testing.json`

If any are missing, warn the user which sentinels failed and ask whether to proceed with partial results or abort.

### 1c. Dispatch review-arbiter

Dispatch **1 review-arbiter agent** via the Agent tool:

- `subagent_type: "ants:review-arbiter"` -- "Read all sentinel review files at .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-correctness.json, .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-security.json, .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-perf.json, and .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-review.sentinel-testing.json. IMPORTANT: You are running in the improve pipeline, NOT the swarm pipeline. Ignore any default paths in your system prompt. Cross-reference, deduplicate, and produce consolidated verdict. Report ALL issues at every severity level (critical, warning, AND info). Write to .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-quality.json (this path overrides your default A3-quality.json path)."

### 1d. Evaluate verdict

After the arbiter returns, read `.agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-quality.json`.

Check the verdict in `.summary.verdict`:

- If `summary.verdict == "clean"`: Display "Iteration {CURRENT_ITERATION}: Code is clean -- zero issues found." Skip to **Step 3** (I2 REPORT).
- If `summary.verdict == "issues_found"`: Proceed to **Step 2** (I1 FIX).

## Step 2: I1 FIX (iteration N)

Read the issues from `.agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-quality.json` and count by severity.

Display to user: "Iteration {CURRENT_ITERATION}: Found {critical} critical, {warning} warning, {info} info issues. Dispatching review-fixer..."

### 2a. Dispatch review-fixer

Dispatch **1 review-fixer agent** via the Agent tool:

- `subagent_type: "ants:review-fixer"` -- "Fix the issues identified by the review team. Process in severity order (critical first, then warning, then info). Fix ALL issues -- do not skip info-severity issues.

IMPORTANT: You are running in the improve pipeline, NOT the swarm pipeline. There is NO state.json. Do NOT read state.reviewFix -- there is no state file. Instead, read the issues from .agents/tmp/improve/iter-{CURRENT_ITERATION}/I0-quality.json (this file contains the consolidated review findings with all issues to fix).

Write your output to .agents/tmp/improve/iter-{CURRENT_ITERATION}/I1-fix.json (this path overrides your default A3-review-fix.json path).

Output format: same JSON schema as your default output (summary with totalIssues/fixed/skipped/attempt, fixedIssues array, skippedIssues array).

Completion criteria: You are DONE when (1) every issue from I0-quality.json has been either fixed or explicitly marked as skipped with justification, (2) your output JSON is written to the specified path, (3) each fix is minimal and targeted -- no refactoring beyond the flagged issues."

### 2b. Verify fixer output

After the fixer returns, read `.agents/tmp/improve/iter-{CURRENT_ITERATION}/I1-fix.json`.

Display to user: "Iteration {CURRENT_ITERATION}: Fixed {fixed} of {total} issues. {skipped} skipped."

### 2c. Check iteration limit

- If `CURRENT_ITERATION >= MAX_ITERATIONS`: Display "Max iterations (5) reached. Moving to summary." Proceed to **Step 3** (I2 REPORT).
- Otherwise: Increment `CURRENT_ITERATION` by 1. Go back to **Step 1** (I0 REVIEW).

## Step 3: I2 REPORT

For each iteration directory (`iter-1/`, `iter-2/`, etc.) that was created:

- Read `I0-quality.json`: use `.summary.totalIssues` (Issues Found), `.summary.critical` (Critical), `.summary.warning` (Warning), `.summary.info` (Info), `.summary.verdict` (to determine if CLEAN)
- Read `I1-fix.json` (only if it exists): use `.summary.fixed` (Fixed), `.summary.skipped` (Skipped)
- If `I1-fix.json` is absent (no fix ran because code was already clean), show `--` for Fixed and Skipped

Display a formatted summary to the user:

```
Ants Improve -- Summary
========================
Target: <description from $ARGUMENTS>
Iterations: {total iterations completed}
Final Verdict: {clean | issues_remaining}

Iteration | Issues Found | Fixed | Skipped | Critical | Warning | Info
----------|-------------|-------|---------|----------|---------|-----
1         | 12          | 10    | 2       | 2        | 5       | 5
2         | 3           | 3     | 0       | 0        | 1       | 2
3         | 0           | --    | --      | 0        | 0       | 0  (CLEAN)
----------|-------------|-------|---------|----------|---------|-----
Total     | <sum>       | <sum> | <sum>   | <sum>    | <sum>   | <sum>
```

Mark any iteration with `summary.verdict == "clean"` with `(CLEAN)` at the end of its row.

Add a **Total** row at the bottom summing all numeric columns.

Then display the stop reason:

If the final iteration's arbiter returned `summary.verdict == "clean"`:
- Display: "All issues resolved after {N} iterations."

If max iterations (5) reached with remaining issues (final verdict is NOT "clean"):
- Display: "Max iterations (5) reached with remaining issues:"
- List the unresolved issues from the last iteration's `I0-quality.json` `.issues[]` array (show `id`, `severity`, `description` for each)
- Display: "These issues may require manual review to resolve."
