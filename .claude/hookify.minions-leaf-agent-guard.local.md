---
name: minions-leaf-agent-guard
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: plugins/minions/agents/.*\.md$
  - field: new_text
    operator: not_contains
    pattern: disallowedTools
---

**Leaf agent missing `disallowedTools: [Task]`!**

Most minions agents are leaf agents that should NOT spawn subagents. Only `builder`, `scout`, and `shipper` legitimately need Task access.

**Required:** Add `disallowedTools: [Task]` to the YAML frontmatter (or `disallowedTools:` with `- Task`) unless this agent needs to dispatch other agents.
