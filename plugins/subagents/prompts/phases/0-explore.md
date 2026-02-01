# Phase 0: Explore [PHASE 0]

## Subagent Config

- **Primary:** subagents:explorer (parallel batch, 1-10 agents)
- **Supplementary:** `subagents:deep-explorer` (1 agent, parallel with primary)
- **Output:** `.agents/tmp/phases/0-explore.md`

## Dispatch Instructions

1. Determine complexity and agent count (simple: 1-2, medium: 3-5, complex: 6-10)
2. Generate one focused query per agent
3. Dispatch all explorer agents **and** `subagents:deep-explorer` in parallel
4. The deep explorer traces execution paths and maps architecture layers — complements the breadth-first primary explorers
5. Aggregate results into output file: primary results first, then a `## Architecture Analysis` section from deep-explorer

## Input Files

- Task description (from state.json `.task`)

## Output File

- `.agents/tmp/phases/0-explore.md`
