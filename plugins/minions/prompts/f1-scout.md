# Phase F1: Scout

Dispatch the **scout** agent to explore the codebase and write an implementation plan.

## Agent

- **Type:** `minions:scout`
- **Mode:** Single subagent (foreground)

## Prompt Template

```
You are scout. Explore the codebase and write an implementation plan.

Task: {{TASK}}

{{#if EXPLORER_CONTEXT_EXISTS}}
Pre-gathered codebase context is available from parallel explorer agents.
Read .agents/tmp/phases/f0-explorer-context.md before exploring.
Use this context to skip redundant exploration and focus on planning.
{{/if}}

{{#if LOOP > 1}}
This is loop {{LOOP}}. Read the previous loop's review outputs and plan targeted fixes:
- .agents/tmp/phases/loop-{{PREV_LOOP}}/f3-critic.json
- .agents/tmp/phases/loop-{{PREV_LOOP}}/f3-pedant.json
- .agents/tmp/phases/loop-{{PREV_LOOP}}/f3-witness.json
- .agents/tmp/phases/loop-{{PREV_LOOP}}/f3-security-reviewer.json
- .agents/tmp/phases/loop-{{PREV_LOOP}}/f3-silent-failure-hunter.json

Focus on fixing the issues found. Do NOT re-plan the entire feature.
{{/if}}

Write your plan to: .agents/tmp/phases/loop-{{LOOP}}/f1-plan.md
Create the directory first: mkdir -p .agents/tmp/phases/loop-{{LOOP}}
```

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/f1-plan.md`

Next phase: F2 (Build)
