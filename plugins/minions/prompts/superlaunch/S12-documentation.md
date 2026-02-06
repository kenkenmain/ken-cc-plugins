# Phase S12: Documentation [PHASE S12]

## Subagent Config

- **Primary:** `minions:doc-updater` (reads from `state.docUpdater`) — updates code documentation (READMEs, API docs, inline docs)
- **Supplementary:** `minions:claude-md-updater` — updates CLAUDE.md with session learnings
- **Output:** `.agents/tmp/phases/S12-docs.md`

## Dispatch Instructions

Dispatch both agents **in parallel**. They operate independently:
- Primary doc updater (`state.docUpdater`) updates README.md, API docs, config docs, and reports to `.agents/tmp/phases/S12-docs.md`
- `claude-md-updater` updates CLAUDE.md files directly (no output file — it edits in place)

## Input Files

- `.agents/tmp/phases/S2-plan.md`
- `.agents/tmp/phases/S4-tasks.json`

## Output File

- `.agents/tmp/phases/S12-docs.md`
