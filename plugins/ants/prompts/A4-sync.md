# [PHASE A4] Synchronize Tracks

Dispatch the **queen** agent to merge build track and quality track results and render a verdict.

## Agent

- **Type:** `ants:queen`
- **Mode:** Single subagent (foreground)

## Prerequisites

- A2 (Build Track) must have completed: `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json` exists
- A3 (Quality Track) must have completed: `.agents/tmp/phases/loop-{{LOOP}}/A3-quality.json` exists

## Process

1. Read build track output from `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json`
2. Read quality track output from `.agents/tmp/phases/loop-{{LOOP}}/A3-quality.json`
3. Cross-reference issues against implementation
4. Render verdict: `ship` or `loop`
5. Write output to `.agents/tmp/phases/loop-{{LOOP}}/A4-sync.json`

## Prompt Template

```
You are queen. Synchronize the build and quality track results for loop {{LOOP}}.

Task: {{TASK}}

Read:
- .agents/tmp/phases/loop-{{LOOP}}/A3-build.json (build track output)
- .agents/tmp/phases/loop-{{LOOP}}/A3-quality.json (quality track output)

Cross-reference all issues against the implementation. Decide: ship or loop.

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/A4-sync.json
```

## Decision Rules

| Condition | Verdict | Next Phase |
|-----------|---------|------------|
| Quality clean, build complete | `ship` | A5 (Ship) |
| Only `info` issues, build complete | `ship` | A5 (Ship) |
| Any `critical` or `warning` unresolved | `loop` | A1 (Plan) |
| Build track incomplete | `loop` | A1 (Plan) |
| Loop count = max loops | `stop` | Workflow ends with report |

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/A4-sync.json` with `verdict: "ship"` to advance.

Next phase: A5 (Ship) if verdict is `ship`, or A1 (Plan) if verdict is `loop`.
