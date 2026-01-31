# Phase C: Completion [PHASE C]

## Subagent Config

- **Type:** subagent (Bash)
- **Input:** `8-final-review.json` or `9-codex-final.json`
- **Output:** `.agents/tmp/iterate/phases/C-completion.json`

## Instructions

Summarize all work done across all iterations, list files changed, and suggest next steps.

### Process

1. Read the final review result:
   - **Full mode:** `.agents/tmp/iterate/phases/9-codex-final.json`
   - **Lite mode:** `.agents/tmp/iterate/phases/8-final-review.json`
2. Read iteration state from `.agents/iteration-state.json`
3. Gather summary data:
   - Total iterations run
   - Issues found and fixed per iteration
   - Final status (clean or with noted issues)
4. Collect all files modified across all iterations:
   ```bash
   git diff --name-only $(git merge-base HEAD main)..HEAD
   ```
5. Update state file to show workflow complete
6. Write completion result to output file

### Completion Checklist

- [ ] All phases completed successfully
- [ ] No HIGH severity issues remaining
- [ ] `make lint` passes
- [ ] `make test` passes
- [ ] State file updated to complete
- [ ] Completion summary written

### Output Format

Write to `.agents/tmp/iterate/phases/C-completion.json`:

```json
{
  "status": "completed",
  "mode": "full" | "lite",
  "totalIterations": 1,
  "iterationSummaries": [
    {
      "iteration": 1,
      "phase8Issues": 0,
      "issuesFixed": 0,
      "decision": "advance"
    }
  ],
  "filesChanged": [
    "path/to/file1.ts",
    "path/to/file2.md"
  ],
  "testsPass": true,
  "lintPass": true,
  "finalQuality": "excellent" | "good" | "acceptable",
  "summary": "Iteration workflow complete after {N} iteration(s). {description of what was accomplished}.",
  "nextSteps": [
    "Create a git commit with the changes",
    "Create a pull request for review",
    "Run integration tests if applicable",
    "Update documentation if needed"
  ]
}
```

### Announcements

On completion, announce:

```
Iteration workflow complete after {N} iteration(s)!

Summary:
- {Total tasks implemented}
- {Total issues found and fixed}
- {Final quality assessment}

Files changed:
- {list of files}

Suggested next steps:
- {next step 1}
- {next step 2}
```

### Optional Post-Completion

If configured, use `superpowers:finishing-a-development-branch` for merge preparation:
- Create feature branch (if not already on one)
- Stage changed files (exclude `.agents/**`)
- Create commit with summary
- Push and create PR
