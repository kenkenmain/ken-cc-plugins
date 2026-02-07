---
name: minions-task-agent-safety
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: plugins/minions/agents/task-agent\.md$
  - field: new_text
    operator: not_contains
    pattern: "hooks:"
---

**task-agent.md missing safety hooks!**

The `task-agent` should have safety hooks matching `builder.md` for parity:
- **PreToolUse(Bash):** Block git commands to prevent unauthorized repo changes
- **Stop:** Completion validation gate to verify task output quality

See `builder.md` lines 28-39 for the reference implementation.
