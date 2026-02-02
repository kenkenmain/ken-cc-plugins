# Phase F4: Completion [PHASE F4]

## Subagent Config

- **Type:** subagents:completion-handler
- **Input:** `.agents/tmp/phases/f3-review.json`
- **Output:** `.agents/tmp/phases/f4-completion.json`

## Instructions

Finalize the workflow with git operations.

### Process

1. Read `.agents/tmp/phases/f3-review.json` to confirm readiness
2. Read `.agents/tmp/state.json` for worktree context
3. Execute git operations: stage, commit, push, create PR
4. Tear down worktree if applicable
5. Write completion result to output file
