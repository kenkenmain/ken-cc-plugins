# Phase F3: Review

Dispatch **critic**, **pedant**, and **witness** agents in parallel to review the implementation.

## Agents

- **critic** (`minions:critic`) — correctness: bugs, security, error handling
- **pedant** (`minions:pedant`) — quality: naming, style, tests, comments
- **witness** (`minions:witness`) — runtime: run code, observe behavior, capture evidence

All 3 run in parallel.

## Process

1. Read `.agents/tmp/phases/loop-{{LOOP}}/f2-tasks.json` for the list of changed files
2. Dispatch all 3 agents simultaneously, passing the file list to each
3. Wait for all 3 to complete
4. Aggregate verdicts into `f3-verdict.json`

## Prompt Template (shared context)

```
Review the implementation from loop {{LOOP}}.

Changed files (from f2-tasks.json):
{{FILES_CHANGED}}

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/f3-{{AGENT_NAME}}.json
```

## Aggregation

After all 3 complete, write:

`.agents/tmp/phases/loop-{{LOOP}}/f3-verdict.json`

```json
{
  "critic": { "verdict": "clean|issues_found", "issues": N },
  "pedant": { "verdict": "clean|issues_found", "issues": N },
  "witness": { "verdict": "clean|issues_found", "issues": N },
  "overall_verdict": "clean|issues_found",
  "total_issues": N
}
```

## Verdict Logic

- `overall_verdict` is `"clean"` only if ALL 3 agents report `"clean"`
- ANY agent reporting `"issues_found"` makes the overall verdict `"issues_found"`
- Info-level issues do NOT count — only critical and warning

## Loop-Back

- **Clean:** Advance to F4 (Ship)
- **Issues found + loop < max:** Loop back to F1 (Scout re-plans fixes)
- **Issues found + loop = max:** Stop workflow and report remaining issues

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/f3-verdict.json` with `overall_verdict: "clean"`

Next phase: F4 (Ship) — or F1 if looping back
