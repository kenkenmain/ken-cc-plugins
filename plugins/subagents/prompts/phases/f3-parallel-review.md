# Phase F3: Parallel Review [PHASE F3]

## Subagent Config

**When `codexAvailable: true` (Codex mode):**
- **Primary:** `subagents:codex-unified-reviewer` (single agent covering all review areas)
- **Supplementary:** None — unified reviewer handles code quality, error handling, type design, test coverage, and comments in a single Codex MCP call
- The unified reviewer writes `f3-review.json` directly using the Write tool. No aggregation step needed.

**When `codexAvailable: false` (Claude-only mode):**
- **Primary:** `subagents:code-quality-reviewer`
- **Supplementary (parallel):**
  - `subagents:error-handling-reviewer`
  - `subagents:type-reviewer`
  - `subagents:test-coverage-reviewer`
  - `subagents:comment-reviewer`
- After all 5 complete, dispatch `subagents:review-aggregator` to merge temp files into `f3-review.json`.

- **Input:** `.agents/tmp/phases/f2-tasks.json`, git diff
- **Output:** `.agents/tmp/phases/f3-review.json`

## Instructions

Read `state.codexAvailable` to determine which review path to use.

### Process

**Codex mode (`codexAvailable: true`):**
1. Get list of modified files from `.agents/tmp/phases/f2-tasks.json`
2. Dispatch `subagents:codex-unified-reviewer` — a single agent that covers all 5 review areas in one Codex MCP call
3. The unified reviewer writes `f3-review.json` directly using the Write tool
4. No aggregation step needed

**Claude-only mode (`codexAvailable: false`):**
1. Get list of modified files from `.agents/tmp/phases/f2-tasks.json`
2. Dispatch all 5 reviewer agents in parallel (same Task tool message)
3. Each reviewer examines the code changes from their specialty
4. Aggregate all issues into a single `issues[]` array, tagging each with `"source"` field
5. Write structured JSON result to `.agents/tmp/phases/f3-review.json`

### Output Format

Write JSON to `.agents/tmp/phases/f3-review.json`:

```json
{
  "status": "approved|needs_revision",
  "issues": [
    {
      "severity": "HIGH|MEDIUM|LOW",
      "category": "code-quality|error-handling|type-design|test-coverage|comments",
      "source": "subagents:code-quality-reviewer",
      "location": "src/foo.ts:42",
      "issue": "Description of the problem",
      "suggestion": "How to fix it"
    }
  ],
  "filesReviewed": ["src/foo.ts", "src/bar.ts"],
  "summary": "Brief summary of findings"
}
```

### If Issues Found

The SubagentStop hook detects issues and starts a fix cycle:
fix-dispatcher applies fixes -> review re-runs -> repeat until approved or max 3 iterations.
