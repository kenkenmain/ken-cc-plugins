---
name: minions-local-outside-function
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: plugins/minions/hooks/.*\.sh$
  - field: new_text
    operator: regex_match
    pattern: "^\\s*local\\s+\\w+"
---

**`local` keyword detected — verify it's inside a function!**

In bash, `local` is only valid inside functions. Using `local` in the main script body or inside a `case` block (outside a function) is undefined behavior and may cause errors on strict bash implementations.

**Check:** Confirm this `local` declaration is inside a `function_name() { ... }` block.
