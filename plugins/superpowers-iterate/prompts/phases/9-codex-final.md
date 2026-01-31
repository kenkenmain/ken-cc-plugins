# Phase 9: Codex Final [PHASE 9]

## Subagent Config

- **Type:** review (superpowers-iterate:codex-reviewer -> codex-xhigh MCP)
- **Input:** `.agents/tmp/iterate/phases/8-final-review.json`
- **Output:** `.agents/tmp/iterate/phases/9-codex-final.json`

## Instructions

Perform final validation using the highest reasoning tier (codex-xhigh). This phase runs only in full mode and is the last check before completion.

**Note:** This phase is skipped in lite mode. The `schedule` array in `state.json` will not include Phase 9 for lite mode workflows.

### Process

1. Read `.agents/tmp/iterate/phases/8-final-review.json` for context
2. Gather all iteration artifacts:
   - Plan: `.agents/tmp/iterate/phases/2-plan.md`
   - Implementation: `.agents/tmp/iterate/phases/4-tasks.json`
   - Test results: `.agents/tmp/iterate/phases/6-test-results.json`
   - Final review: `.agents/tmp/iterate/phases/8-final-review.json`
3. Dispatch to `superpowers-iterate:codex-reviewer` which routes to Codex MCP (**codex-xhigh** -- highest reasoning tier)
4. Evaluate findings and address HIGH severity issues
5. Write validation result to output file

### Codex Dispatch

```
mcp__codex-xhigh__codex(
  prompt: "Final validation review. This is the FINAL check before merge. Be thorough.

Run these commands first:
1. make lint
2. make test

Focus on:
- Correctness and logic errors
- Idempotency of operations
- Documentation accuracy
- Test coverage gaps
- Security concerns
- Edge cases missed in earlier reviews
- Race conditions or concurrency issues
- Error propagation and handling completeness

Plan: .agents/tmp/iterate/phases/2-plan.md
Tasks: .agents/tmp/iterate/phases/4-tasks.json
Test results: .agents/tmp/iterate/phases/6-test-results.json
Phase 8 review: .agents/tmp/iterate/phases/8-final-review.json

Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.

Return JSON: { status, issues[], overallQuality, summary, readyForCompletion }",
  cwd: "{project dir}"
)
```

### If HIGH Severity Issues Found

1. Address HIGH severity issues immediately
2. Re-run `make lint && make test`
3. Re-run Codex-xhigh review if significant changes were made
4. Repeat until no HIGH severity issues remain

### Output Format

Write to `.agents/tmp/iterate/phases/9-codex-final.json`:

```json
{
  "status": "approved" | "blocked",
  "issues": [
    {
      "severity": "HIGH" | "MEDIUM" | "LOW",
      "description": "...",
      "location": "file:line",
      "suggestion": "...",
      "fixed": true | false
    }
  ],
  "overallQuality": "excellent" | "good" | "acceptable" | "poor",
  "testsPass": true,
  "lintPass": true,
  "summary": "...",
  "readyForCompletion": true | false
}
```

### Decision

- `approved` + `readyForCompletion: true` -> Proceed to Completion (C)
- `blocked` -> Halt workflow, report HIGH severity issues to user
