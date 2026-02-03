# Phase F1: Fast Plan [PHASE F1]

## Subagent Config

- **Type:** subagents:fast-planner (single opus agent)
- **Input:** Task description from state.json `.task` field
- **Output:** `.agents/tmp/phases/f1-plan.md`

## Instructions

Combined explore + brainstorm + plan in a single agent pass.

### Process

1. Dispatch `subagents:fast-planner` with the task description
2. Agent explores codebase, brainstorms approaches, writes structured plan
3. Agent writes output to `.agents/tmp/phases/f1-plan.md`

### Output Format

Structured markdown with:
- Codebase analysis
- Approaches considered with trade-offs
- Selected approach with rationale
- Task table: ID, description, files, dependencies
- Detailed task descriptions with test expectations
