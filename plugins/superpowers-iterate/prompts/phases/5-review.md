# Phase 5: Review [PHASE 5]

## Subagent Config

- **Type:** review (codex-reviewer -> codex-high MCP)
- **Input:** `.agents/tmp/iterate/phases/2-plan.md`, git diff
- **Output:** `.agents/tmp/iterate/phases/5-review.json`

## Instructions

Perform a quick code review sanity check (1 round) before the thorough Phase 8 review.

### Process

1. Get git SHAs for the changes:
   ```bash
   BASE_SHA=$(git merge-base HEAD main)
   HEAD_SHA=$(git rev-parse HEAD)
   ```
2. Read `.agents/tmp/iterate/phases/2-plan.md` for context
3. Dispatch to `superpowers-iterate:codex-reviewer` which routes to Codex MCP (codex-high)
4. Provide:
   - WHAT_WAS_IMPLEMENTED: Description of changes from Phase 4
   - PLAN_OR_REQUIREMENTS: Reference to plan file
   - BASE_SHA and HEAD_SHA
5. Categorize issues by severity
6. Fix issues using configured bugFixer
7. Re-run tests after fixes
8. Write review result to output file

### Codex Dispatch

```
mcp__codex-high__codex(
  prompt: "Quick code review for iteration changes.

Plan: .agents/tmp/iterate/phases/2-plan.md
Task results: .agents/tmp/iterate/phases/4-tasks.json
Git diff: BASE_SHA..HEAD_SHA

Focus on:
- Implementation matches plan
- Code correctness and logic errors
- Missing error handling
- Test coverage for new code
- Code style consistency

Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
This is a quick review — focus on critical and important issues only.

Return JSON: { status, issues[], filesReviewed, summary }",
  cwd: "{project dir}"
)
```

### Lite Mode

In lite mode, dispatch a code-reviewer subagent via `superpowers:requesting-code-review` with the same review context.

### Issue Categorization

| Category     | Action                         |
| ------------ | ------------------------------ |
| **Critical** | Must fix immediately           |
| **Important**| Fix now                        |
| **Minor**    | Note for Phase 8 final review  |

### Bug Fixer Dispatch

Based on config `phases.5.bugFixer`:

- `claude`: Dispatch Claude subagent with issue details
- `codex-high` (default): Invoke `mcp__codex-high__codex` with fix prompt
- `codex-xhigh`: Invoke `mcp__codex-xhigh__codex` with fix prompt

### Output Format

Write to `.agents/tmp/iterate/phases/5-review.json`:

```json
{
  "status": "approved" | "needs_fixes",
  "baseSha": "...",
  "headSha": "...",
  "issues": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "category": "critical" | "important" | "minor",
      "description": "...",
      "location": "file:line",
      "suggestion": "...",
      "fixed": true | false
    }
  ],
  "filesReviewed": ["..."],
  "summary": "..."
}
```
