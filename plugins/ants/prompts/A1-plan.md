# [PHASE A1] Architect — Plan

Dispatch the **architect** agent to explore the codebase and write a dual-track implementation plan.

## Agent

- **Type:** `ants:architect`
- **Mode:** Single subagent (foreground)

## Prompt Template

```
You are architect. Explore the codebase and write an implementation plan with wave assignments for dual-track execution.

Task: {{TASK}}

{{#if EXPLORER_CONTEXT_EXISTS}}
Pre-gathered codebase context is available from parallel explorer agents.
Read .agents/tmp/phases/A0-explore.md before exploring.
Use this context to skip redundant exploration and focus on planning.
{{/if}}

{{#if LOOP > 1}}
This is loop {{LOOP}}. Read the previous loop's review outputs and plan targeted fixes:
- .agents/tmp/phases/loop-{{PREV_LOOP}}/A2-review.json
- .agents/tmp/phases/loop-{{PREV_LOOP}}/A4-verdict.json (if exists)

Focus on fixing the issues found. Do NOT re-plan the entire feature.
{{/if}}

Write your plan to: .agents/tmp/phases/loop-{{LOOP}}/A1-plan.md
Create the directory first: mkdir -p .agents/tmp/phases/loop-{{LOOP}}
```

## Output

File: `.agents/tmp/phases/loop-{{LOOP}}/A1-plan.md`

Must contain:
- Summary and chosen approach
- Task table with columns: ID, Description, Files, Wave, Complexity, Dependencies, Acceptance Criteria
- Wave summary (Wave 1 foundation tasks, Wave 2 dependent tasks)

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/A1-plan.md` with a valid task table containing wave assignments.

The architect's Stop hook validates:
1. Task table exists with numbered tasks
2. Each task has wave assignment (1 or 2)
3. Wave 1 tasks have no dependencies
4. Each task has acceptance criteria
5. Each task lists files to create or modify

Next phase: A2 (Blueprint Review)
