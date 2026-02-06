# Phase S14: Completion [PHASE S14]

## Subagent Config

- **Type:** minions:shipper
- **Output:** `.agents/tmp/phases/S14-completion.json`

## Supplementary Agent

- **Type:** minions:retrospective-analyst
- Runs in parallel with shipper
- Analyzes workflow metrics (restart history, fix attempts, coverage loops)
- Writes learnings to project CLAUDE.md under `## Workflow Learnings`

## Input Files

- `.agents/tmp/phases/S13-final-review.json`
- `.agents/tmp/state.json` (for retrospective analysis)

## Output File

- `.agents/tmp/phases/S14-completion.json`
