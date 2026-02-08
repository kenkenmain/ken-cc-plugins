---
name: minions-silent-defaults
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: plugins/minions/hooks/.*\.sh$
  - field: new_text
    operator: regex_match
    pattern: \|\|\s*echo\s*["']0["']
---

**Silent default to 0 detected in hook script!**

Defaulting to 0 without logging a warning is a silent failure pattern.
This was identified as a HIGH severity issue in the minions plugin:
- `_issue_count()` silently returns 0 when schema doesn't match
- This causes false "clean" verdicts in F3 aggregation

**Required:** Always log a WARNING to stderr when falling back to a default value.
