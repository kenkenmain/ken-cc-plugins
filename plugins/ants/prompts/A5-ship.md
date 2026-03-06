# [PHASE A5] Ship

Dispatch the **nurse** agent to update documentation, then the **drone** agent to commit and open a PR.

## Agents

- **nurse** (`ants:nurse`) — updates documentation to reflect changes
- **drone** (`ants:drone`) — creates git commit and opens PR

Agents run sequentially: nurse first, then drone.

## Prerequisites

- A4 sync verdict must be `"ship"` (enforced by gate)
- `.agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json` exists with `verdict: "clean"`

## Process

### Sub-step 1: Documentation (nurse)

1. Read build output from `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json`
2. Read sync summary from `.agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json`
3. Check and update primary docs (README.md, CLAUDE.md)
4. Check and update secondary docs (API docs, config docs, plugin manifests)
5. Write output to `.agents/tmp/phases/loop-{{LOOP}}/A5-docs.json`

### Sub-step 2: Commit and PR (drone)

1. Read all phase outputs to compile changed file list
2. Run safety checks (not on main, no secrets, queen verdict is ship)
3. Stage specific files and create conventional commit
4. Push branch and open PR
5. Write output to `.agents/tmp/phases/loop-{{LOOP}}/A5-ship.json`

## Prompt Templates

### Nurse

```
You are nurse. Update documentation to reflect the implementation changes from loop {{LOOP}}.

Task: {{TASK}}

Read:
- .agents/tmp/phases/loop-{{LOOP}}/A3-build.json (what was built)
- .agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json (sync summary)

Update affected documentation. Write your output to: .agents/tmp/phases/loop-{{LOOP}}/A5-docs.json
```

### Drone

```
You are drone. Commit and open a PR for this implementation.

Task: {{TASK}}

Read:
- .agents/tmp/phases/loop-{{LOOP}}/A3-build.json (files changed)
- .agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json (ship verdict)
- .agents/tmp/phases/loop-{{LOOP}}/A5-docs.json (doc updates)

Stage the changed files, create a conventional commit, push, and open a PR.

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/A5-ship.json
```

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/A5-ship.json` with `commit_sha` and `pr_url`.

Workflow status set to: `"complete"`
