# Phase C3: Judge

Dispatch a single **judge** agent to evaluate the implementation and deliver a verdict.

## Agent

- **Type:** `minions:judge`
- **Mode:** Single subagent (foreground)

## Process

1. Read `.agents/tmp/phases/loop-{{LOOP}}/c2-tasks.json` (or `c2.5-fixes.json` if fix cycle) for changed files
2. Dispatch the judge agent with the file list
3. Judge reviews across 5 dimensions: correctness, quality, runtime, security, error handling
4. Judge writes verdict to `c3-judge.json`

## Prompt Template

```
Review the implementation from loop {{LOOP}}.

Task: {{TASK}}
Changed files (from c2-tasks.json or c2.5-fixes.json):
{{FILES_CHANGED}}

{{#if FIX_CYCLE > 0}}
This is fix cycle {{FIX_CYCLE}}/{{MAX_FIX_CYCLES}}.
Read .agents/tmp/phases/loop-{{LOOP}}/c2.5-fixes.json for what was fixed.
Focus on whether the fixes are correct and complete.
{{/if}}

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/c3-judge.json
```

## Verdict Schema

`.agents/tmp/phases/loop-{{LOOP}}/c3-judge.json`

```json
{
  "reviewed_at": "ISO timestamp",
  "loop": 1,
  "fix_cycle": 0,
  "files_reviewed": ["src/auth.ts"],
  "verdict": "approve|fix|replan",
  "confidence": 0.85,
  "issues": [
    {
      "severity": "critical|warning|info",
      "dimension": "correctness|quality|runtime|security|error_handling",
      "file": "src/auth.ts",
      "line": 42,
      "description": "...",
      "evidence": "...",
      "fix_hint": "..."
    }
  ],
  "summary": {
    "critical": 0,
    "warning": 0,
    "info": 0,
    "total_issues": 0,
    "tests_pass": true,
    "lint_clean": true
  },
  "replan_reason": null
}
```

## Verdict Logic

| Verdict | Condition | Next Phase |
|---------|-----------|------------|
| `approve` | No critical/warning issues, tests pass | C4 (Ship) |
| `fix` | Specific, fixable issues exist | C2.5 (Fix) → C3 (re-judge) |
| `replan` | Fundamental approach is wrong | C1 (re-plan from scratch) |

## Limits

- **Max fix cycles (C2.5→C3):** 5 per loop
- **Max replans (C1→C2→C3):** 3 total

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/c3-judge.json` with `verdict: "approve"`

Next phase: C4 (Ship) — or C2.5 if `fix`, or C1 if `replan`
