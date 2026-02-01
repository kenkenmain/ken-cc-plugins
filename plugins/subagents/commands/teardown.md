---
description: Commit, push to GitHub, create PR, and remove worktree
argument-hint: [--no-pr] [--force]
allowed-tools: Bash, Read, Write, AskUserQuestion
---

# Teardown Worktree Session

Finalize work by committing changes, pushing to GitHub, optionally creating a PR, and cleaning up the worktree.

## Arguments

- `--no-pr`: Optional. Push branch but skip PR creation
- `--force`: Optional. Skip confirmation prompts

Parse from $ARGUMENTS to extract flags.

## Step 1: Detect Context

Determine if we're in a worktree or the original project:

```bash
# Check for .subagent-origin (we're in a worktree)
cat .subagent-origin 2>/dev/null
```

```bash
# Check for .agents/worktree.json (we're in the original dir)
cat .agents/worktree.json 2>/dev/null
```

```bash
# Git worktree detection
git rev-parse --git-common-dir 2>/dev/null
git worktree list 2>/dev/null
```

Set variables:
- `WORKTREE_PATH`: where code changes live
- `ORIGINAL_DIR`: the original project directory
- `BRANCH`: the feature branch name

If no worktree detected, operate on current directory as a normal branch.

## Step 2: Review Changes

Show the user what will be committed:

```bash
git -C "$WORKTREE_PATH" status
git -C "$WORKTREE_PATH" diff --stat
```

Unless `--force`, ask for confirmation:

Ask: "Ready to commit and push these changes?"

## Step 3: Commit

```bash
cd "$WORKTREE_PATH"

# Stage all changes EXCEPT .agents/ and docs/plans/
git add -A
git reset -- '.agents/**' 'docs/plans/**' '*.tmp' '*.log' '.subagent-origin'

# Get a summary for the commit message
git diff --cached --stat
```

Build a commit message from the branch name and changed files:

```bash
git commit -m "$(cat <<'EOF'
{type}: {description from branch name}

{summary of changes}

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

## Step 4: Push to GitHub

```bash
git -C "$WORKTREE_PATH" push -u origin "$BRANCH"
```

If push fails (no remote, auth issues), display the error and ask the user to fix it.

## Step 5: Create PR

**Skip if `--no-pr` is set.**

```bash
cd "$WORKTREE_PATH"

gh pr create --title "{short title}" --body "$(cat <<'EOF'
## Summary
{bullet points of what changed}

## Test plan
{how to verify the changes}

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Display the PR URL.

If `gh` is not available or PR creation fails, display a warning and continue with cleanup.

## Step 6: Clean Up Worktree

```bash
# Return to original directory
cd "$ORIGINAL_DIR"

# Remove the worktree
git worktree remove "$WORKTREE_PATH"
```

If removal fails (uncommitted changes), warn but continue:

```bash
# Force remove if needed
git worktree remove --force "$WORKTREE_PATH"
```

Clean up markers:

```bash
rm -f "$ORIGINAL_DIR/.agents/worktree.json"
```

Safe-delete the local branch (only if PR was created and branch was pushed):

```bash
# -d only deletes if fully merged/pushed — safe
git branch -d "$BRANCH" 2>/dev/null || true
```

## Step 7: Summary

Display completion summary:

```
Teardown complete
=================
 ✓ Committed:  {commit hash} ({files changed} files)
 ✓ Pushed:     origin/{branch}
 ✓ PR created: {url}
 ✓ Worktree:   removed
 ✓ Branch:     cleaned up

Now in: {original directory}
```

If no worktree was used:

```
Teardown complete
=================
 ✓ Committed:  {commit hash}
 ✓ Pushed:     origin/{branch}
 ✓ PR created: {url}
```
