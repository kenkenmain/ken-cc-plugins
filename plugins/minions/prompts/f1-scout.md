# Phase F1: Scout

Dispatch the **scout** agent to explore the codebase and write an implementation plan.

## Agent

- **Type:** `minions:scout`
- **Mode:** Single subagent (foreground)

## Prompt Template

```
You are scout. Explore the codebase and write an implementation plan.

Task: {{TASK}}

{{#if LOOP > 1}}
This is loop {{LOOP}}. Read the previous loop's review outputs and plan targeted fixes:
- .agents/tmp/phases/loop-{{PREV_LOOP}}/f3-critic.json
- .agents/tmp/phases/loop-{{PREV_LOOP}}/f3-pedant.json
- .agents/tmp/phases/loop-{{PREV_LOOP}}/f3-witness.json

Focus on fixing the issues found. Do NOT re-plan the entire feature.
{{/if}}

Write your plan to: .agents/tmp/phases/loop-{{LOOP}}/f1-plan.md
Create the directory first: mkdir -p .agents/tmp/phases/loop-{{LOOP}}
```

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/f1-plan.md`

Next phase: F2 (Build)
