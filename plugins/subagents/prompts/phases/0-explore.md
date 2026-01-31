# Phase 0: Explore [PHASE 0]

## Subagent Config

- **Type:** subagents:explorer (parallel batch, 1-10 agents)
- **Output:** `.agents/tmp/phases/0-explore.md`

## Dispatch Instructions

1. Determine complexity and agent count (simple: 1-2, medium: 3-5, complex: 6-10)
2. Generate one focused query per agent
3. Dispatch all explorer agents in parallel
4. Aggregate results into output file

## Input Files

- Task description (from state.json `.task`)

## Output File

- `.agents/tmp/phases/0-explore.md`
