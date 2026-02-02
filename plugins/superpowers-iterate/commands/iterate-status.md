---
description: Check current phase and progress of iteration workflow
allowed-tools: Read, Bash
---

# Iteration Status

Check the current iteration state from `.agents/iteration-state.json`.

## Actions

1. Read the state file:

   ```bash
   cat .agents/iteration-state.json 2>/dev/null || echo '{"status": "no active iteration"}'
   ```

2. If an iteration is active, report:
   - **Task:** What is being worked on
   - **Current Phase:** Which of the 9 phases (with name and integration)
   - **Started:** When the iteration began
   - **Completed Phases:** List of finished phases
   - **Next Steps:** What needs to happen to advance

3. If no iteration is active:
   - Report "No active iteration"
   - Suggest: "Use `/superpowers-iterate:iterate <task>` to start a new iteration"

## Phase Reference

| Phase | Name         | Integration                                        |
| ----- | ------------ | -------------------------------------------------- |
| 1     | Brainstorm   | `superpowers:brainstorming` + N parallel subagents |
| 2     | Plan         | `superpowers:writing-plans` + N parallel subagents |
| 3     | Plan Review  | `codex-high` (validates plan)          |
| 4     | Implement    | `superpowers:subagent-driven-development` + LSP    |
| 5     | Review       | `superpowers:requesting-code-review` (1 round)     |
| 6     | Test         | `make lint && make test`                           |
| 7     | Simplify     | `code-simplifier:code-simplifier` plugin           |
| 8     | Final Review | `codex-high` (decision point)          |
| 9     | Codex Final  | `codex-xhigh` (full mode only)         |
