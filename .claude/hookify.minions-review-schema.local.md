---
name: minions-review-schema
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: plugins/minions/agents/(critic|pedant|witness|security-reviewer|silent-failure-hunter|impl-reviewer|plan-reviewer|test-reviewer|final-reviewer|test-dev-reviewer)\.md$
  - field: new_text
    operator: not_contains
    pattern: summary
---

**Reviewer agent output schema must include `summary` field!**

All minions reviewer agents must output JSON with a consistent `summary` object containing:
- `critical`: number of critical issues
- `warning`: number of warning issues
- `info`: number of info issues
- `verdict`: "clean" | "issues_found"

The `_issue_count()` helper in `on-subagent-stop.sh` depends on `.summary.critical + .summary.warning + .summary.info`.
