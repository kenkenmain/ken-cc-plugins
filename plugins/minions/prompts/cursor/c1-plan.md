# Phase C1: Plan (Parallel Sub-Scouts)

Dispatch **sub-scout** agents in parallel to plan different domains of the task, then aggregate into a unified plan.

## Agent

- **Type:** `minions:sub-scout`
- **Mode:** Parallel dispatch (2-3 sub-scouts, one per domain)

## Domain Assignment

The orchestrator analyzes the task and assigns 2-3 domains. Common domain splits:

- **Backend / Frontend / Infrastructure**
- **Data model / API / Tests**
- **Core logic / Integration / Configuration**

Each sub-scout receives its domain assignment and the full task description for context.

## Prompt Template (per sub-scout)

```
You are sub-scout. Plan the {{DOMAIN}} portion of this task.

Task: {{TASK}}
Your domain: {{DOMAIN}}
Use prefix: {{PREFIX}} (e.g., B1, B2 for backend)

{{#if EXPLORER_CONTEXT_EXISTS}}
Pre-gathered codebase context is available from parallel explorer agents.
Read .agents/tmp/phases/f0-explorer-context.md before exploring.
{{/if}}

{{#if LOOP > 1}}
This is loop {{LOOP}} (replan). Read the previous loop's judge output:
- .agents/tmp/phases/loop-{{PREV_LOOP}}/c3-judge.json

The judge determined the previous approach was fundamentally flawed.
Read replan_reason and plan a NEW approach for your domain.
{{/if}}

Write your partial plan to: .agents/tmp/phases/loop-{{LOOP}}/c1-sub-scout.{{DOMAIN_SLUG}}.md
```

## Aggregation

After ALL sub-scouts complete, the orchestrator:

1. Reads all `.agents/tmp/phases/loop-{{LOOP}}/c1-sub-scout.*.md` files
2. Merges task tables, resolving cross-domain dependencies
3. Renumbers tasks sequentially (1, 2, 3, ...)
4. Writes unified plan to `.agents/tmp/phases/loop-{{LOOP}}/c1-plan.md`

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/c1-plan.md`

Next phase: C2 (Build)
