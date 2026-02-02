---
description: Create a git worktree and start a subagent workflow (persists across Claude restarts)
argument-hint: <task description> [--claude] [--no-worktree] [--no-test] [--profile minimal|standard|thorough]
allowed-tools: Bash, Read, Write, AskUserQuestion, Skill
---

# Initialize and Dispatch

Create a git worktree for isolated development, then start a subagent workflow. The worktree is tied to the terminal — it persists across Claude restarts.

## Arguments

- `<task description>`: Required. The task to execute
- `--claude`: Optional. Use Claude-only mode (no Codex CLI) — dispatches via `dispatch-claude`
- `--no-worktree`: Optional. Skip worktree creation, work in current directory
- All other flags are passed through to dispatch (`--no-test`, `--profile`, `--stage`, `--plan`)

Parse from $ARGUMENTS to extract task description and flags.

## Step 1: Check for Existing Worktree

Before creating anything, check if a worktree already exists for this project:

```bash
# Check if we're already IN a worktree
git rev-parse --git-common-dir 2>/dev/null
git worktree list 2>/dev/null
```

```bash
# Check for marker file in project dir
cat .agents/worktree.json 2>/dev/null
```

**If worktree already exists and is valid:**
- Display: `Reusing existing worktree at {path} (branch: {branch})`
- Skip to Step 4 (dispatch)

**If worktree marker exists but directory is gone:**
- Clean up stale marker
- Proceed with creation

## Step 2: Create Worktree

**Skip if `--no-worktree` is set.**

```bash
# Slugify task for branch name
SLUG=$(echo "<task>" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 -]//g' | tr ' ' '-' | cut -c1-50)
BRANCH="subagents/${SLUG}"

# Worktree path: sibling directory
REPO_NAME=$(basename "$(pwd)")
WORKTREE_PATH="../${REPO_NAME}--subagent"

# Create worktree with new branch
git worktree add -b "$BRANCH" "$WORKTREE_PATH"
```

If creation fails (branch exists, path occupied):
- Try reusing existing: `git worktree add "$WORKTREE_PATH" "$BRANCH"`
- If still fails, ask user what to do

## Step 3: Write Markers

**In the original project dir** — `.agents/worktree.json`:

```bash
mkdir -p .agents
```

```json
{
  "path": "/absolute/path/to/repo--subagent",
  "branch": "subagents/task-slug",
  "task": "<task description>",
  "originalDir": "/absolute/path/to/original",
  "createdAt": "ISO timestamp"
}
```

**In the worktree dir** — `.subagent-origin`:

```json
{
  "originalDir": "/absolute/path/to/original",
  "branch": "subagents/task-slug",
  "task": "<task description>"
}
```

The `.subagent-origin` file lets Claude detect it's in a worktree on restart and find the original project.

Display:

```
Worktree ready:
  Path:   {absolute worktree path}
  Branch: {branch name}

This worktree persists across Claude restarts.
```

## Step 4: Dispatch Workflow

Pass the task and remaining flags through to the appropriate dispatch command:

**If `--claude` is set:**

```
Skill: subagents:dispatch-claude
Args: <task description> --no-worktree [remaining flags]
```

**Otherwise:**

```
Skill: subagents:dispatch
Args: <task description> --no-worktree [remaining flags]
```

Always pass `--no-worktree` to dispatch since this command already created the worktree. The dispatch command will detect the existing worktree from `.agents/worktree.json`.

## If `--no-worktree`

Skip Steps 2-3. Create `.agents/` directory structure:

```bash
mkdir -p .agents/tmp/phases
```

Then dispatch without `--no-worktree` override (let dispatch handle it normally).
