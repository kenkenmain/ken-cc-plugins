# [PHASE A4] Synchronize Tracks

Dispatch the **queen** agent to merge build track and quality track results and render a verdict.

## Agent

- **Type:** `ants:queen`
- **Mode:** Single subagent (foreground)

## Prerequisites

- A3 (Build Track) must have completed: `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json` exists
- A3 (Quality Track) must have completed: `.agents/tmp/phases/loop-{{LOOP}}/A3-quality.json` exists

## Process

1. Read build track output from `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json`
2. Read quality track output from `.agents/tmp/phases/loop-{{LOOP}}/A3-quality.json`
3. Cross-reference issues against implementation
4. Render verdict: `clean` or `issues_found`
5. Write output to `.agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json`

## Prompt Template

```
You are queen. Synchronize the build and quality track results for loop {{LOOP}}.

Task: {{TASK}}

Read:
- .agents/tmp/phases/loop-{{LOOP}}/A3-build.json (build track output)
- .agents/tmp/phases/loop-{{LOOP}}/A3-quality.json (quality track output)

Cross-reference all issues against the implementation. Decide: clean or issues_found.

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json
```

## Decision Rules

| Condition | Verdict | Next Phase |
|-----------|---------|------------|
| Quality clean, build complete | `clean` | A5 (Ship) |
| Only `info` issues, build complete | `clean` | A5 (Ship) |
| Any `critical` or `warning` unresolved | `issues_found` | A1 (Plan) |
| Build track incomplete | `issues_found` | A1 (Plan) |
| Loop count = max loops | `issues_found` | Workflow ends with report |

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json` with `verdict: "clean"` to advance.

Next phase: A5 (Ship) if verdict is `clean`, or A1 (Plan) if verdict is `issues_found`.
