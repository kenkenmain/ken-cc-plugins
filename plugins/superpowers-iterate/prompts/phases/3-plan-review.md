# Phase 3: Plan Review [PHASE 3]

## Subagent Config

- **Type:** review (codex-reviewer -> codex-high MCP)
- **Input:** `.agents/tmp/iterate/phases/2-plan.md`
- **Output:** `.agents/tmp/iterate/phases/3-plan-review.json`

## Instructions

Review the implementation plan using Codex MCP before implementation begins.

### Process

1. Read `.agents/tmp/iterate/phases/2-plan.md`
2. Dispatch to `superpowers-iterate:codex-reviewer` which routes to Codex MCP (codex-high)
3. Write review result to output file

### Codex Dispatch

```
mcp__codex-high__codex(
  prompt: "Review the implementation plan at .agents/tmp/iterate/phases/2-plan.md

Validate:
- Task granularity (each task should be 2-5 minutes of work)
- TDD steps included for each task
- File paths are specific and accurate
- Plan follows DRY, YAGNI principles
- Test strategy is comprehensive
- Dependencies and task order are correct
- Edge cases are covered
- Wave-based execution order is valid (no circular dependencies)
- Complexity scoring is appropriate per task

Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
If you find NO issues, explicitly state: 'Plan looks good to proceed.'

Return JSON: { status, issues[], summary }",
  cwd: "{project dir}"
)
```

### Lite Mode

In lite mode, dispatch a code-reviewer subagent via `superpowers:requesting-code-review` instead of Codex MCP. Review the plan document with the same validation criteria.

### Output Format

Write to `.agents/tmp/iterate/phases/3-plan-review.json`:

```json
{
  "status": "approved" | "needs_revision",
  "issues": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "description": "...",
      "location": "file:line or task reference",
      "suggestion": "..."
    }
  ],
  "summary": "..."
}
```

### If Issues Found

If status is `needs_revision` with HIGH or MEDIUM issues:

1. Fix issues in the plan based on suggestions
2. Re-run plan review
3. Repeat until approved or max retries reached (config: `retries.maxPerPhase`)

If only LOW issues found:

- Note them for awareness
- Proceed to Phase 4
