# Phase 8: Final Review [PHASE 8]

## Subagent Config

- **Type:** review (superpowers-iterate:codex-reviewer -> codex-high MCP)
- **Input:** all review JSONs from current iteration
- **Output:** `.agents/tmp/iterate/phases/8-final-review.json`

## Instructions

Perform thorough final review that determines whether to loop back to Phase 1 or proceed to completion. This is the iteration decision point.

**CRITICAL:** The output MUST include structured JSON with `status` and `issues[]` fields. The SubagentStop hook reads `status` from this JSON to decide whether to loop back to Phase 1 or advance to Phase 9/Completion.

### Process

1. Check current iteration count against `maxIterations` from state
2. Gather all prior phase outputs for context:
   - `.agents/tmp/iterate/phases/2-plan.md` (plan)
   - `.agents/tmp/iterate/phases/3-plan-review.json` (plan review)
   - `.agents/tmp/iterate/phases/4-tasks.json` (implementation)
   - `.agents/tmp/iterate/phases/5-review.json` (code review)
   - `.agents/tmp/iterate/phases/6-test-results.json` (test results)
   - `.agents/tmp/iterate/phases/7-simplify.md` (simplification)
3. Dispatch to `superpowers-iterate:codex-reviewer` which routes to Codex MCP (codex-high)
4. Evaluate review results and write decision to output file

### Codex Dispatch

```
mcp__codex-high__codex(
  prompt: "Iteration {N}/{max} final review for merge readiness. Run these commands first:
1. make lint
2. make test

Focus on:
- Documentation accuracy
- Edge cases and error handling
- Test coverage completeness
- Code quality and maintainability
- Merge readiness
- Correctness and logic errors

Plan: .agents/tmp/iterate/phases/2-plan.md
Tasks: .agents/tmp/iterate/phases/4-tasks.json
Test results: .agents/tmp/iterate/phases/6-test-results.json

Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
If you find NO issues, explicitly state: 'No issues found.'

Return JSON: { status: 'approved'|'needs_revision', issues[], summary }",
  cwd: "{project dir}"
)
```

### Lite Mode

In lite mode, dispatch a code-reviewer subagent via `superpowers:requesting-code-review` with:
- WHAT_WAS_IMPLEMENTED: Full description of all changes in this iteration
- PLAN_OR_REQUIREMENTS: Reference to plan file
- BASE_SHA and HEAD_SHA from git

### Decision Logic

**If ZERO issues found:**
- Set `status: "approved"`
- Set `issues: []`
- Announce: "Iteration {N} review found no issues. Proceeding to completion."
- **Full mode:** Advance to Phase 9
- **Lite mode:** Advance to Completion (C)

**If ANY issues found (HIGH, MEDIUM, or LOW):**
- Set `status: "needs_revision"`
- Populate `issues[]` with all findings
- Announce: "Iteration {N} found {count} issues. Fixing and starting new iteration."
- **Fix ALL issues using configured bugFixer** (config: `phases.8.bugFixer`):
  - `claude`: Dispatch Claude subagent with issue details
  - `codex-high` (default): Invoke `mcp__codex-high__codex` with fix prompt
  - `codex-xhigh`: Invoke `mcp__codex-xhigh__codex` with fix prompt
- Re-run `make lint && make test`
- **If currentIteration < maxIterations:** Loop back to Phase 1
- **If currentIteration >= maxIterations:** Proceed despite issues

### Output Format

**CRITICAL: This format is read by the SubagentStop hook to control the iteration loop.**

Write to `.agents/tmp/iterate/phases/8-final-review.json`:

```json
{
  "status": "approved" | "needs_revision",
  "iteration": 1,
  "maxIterations": 10,
  "issues": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "description": "...",
      "location": "file:line",
      "suggestion": "...",
      "fixed": true | false
    }
  ],
  "testsPass": true,
  "lintPass": true,
  "summary": "...",
  "decision": "advance" | "loop" | "max_iterations_reached"
}
```

### Decision Field Values

| `decision`              | Meaning                                                     |
| ----------------------- | ----------------------------------------------------------- |
| `advance`               | Zero issues found, proceed to Phase 9 or Completion         |
| `loop`                  | Issues found, iterations remaining, loop to Phase 1         |
| `max_iterations_reached`| Issues found but max iterations hit, proceed with warnings  |
