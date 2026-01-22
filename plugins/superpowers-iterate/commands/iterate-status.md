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
   - **Current Phase:** Which of the 8 phases (with name and integration)
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
| 3     | Implement    | `superpowers:subagent-driven-development` + LSP    |
| 4     | Review       | `superpowers:requesting-code-review` (1 round)     |
| 5     | Test         | `make lint && make test`                           |
| 6     | Simplify     | `code-simplifier:code-simplifier` plugin           |
| 7     | Final Review | `mcp__codex-high__codex` (1 round)                 |
| 8     | Codex        | `mcp__codex-high__codex` final validation          |
