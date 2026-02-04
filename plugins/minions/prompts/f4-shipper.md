# Phase F4: Ship

Dispatch the **shipper** agent to update docs, commit, and open a PR.

## Agent

- **Type:** `minions:shipper`
- **Mode:** Single subagent (foreground)

## Prerequisites

- F3 verdict must be `"clean"` (enforced by on-task-gate.sh)

## Process

1. Read `.agents/tmp/phases/loop-{{LOOP}}/f2-tasks.json` for the list of changed files
2. Update documentation (README, CHANGELOG, inline docs)
3. Create git commit with conventional commit message
4. Push and open PR

## Prompt Template

```
You are shipper. Finalize and deliver this implementation.

Task: {{TASK}}

Read .agents/tmp/phases/loop-{{LOOP}}/f2-tasks.json for the list of changed files.
Update documentation, create a git commit, and open a PR.

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/f4-ship.json
```

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/f4-ship.json`

Workflow status set to: `"complete"`
