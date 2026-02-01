# Phase 0: Explore [PHASE 0]

## Subagent Config

- **Primary:** subagents:explorer (parallel batch, 1-10 agents)
- **Supplementary:** `subagents:deep-explorer` — deep architecture tracing (execution paths, layer mapping, dependencies)
- **Supplementary:** `subagents:brainstormer` — synthesizes explore results into 2-3 implementation approaches
- **Output:** `.agents/tmp/phases/0-explore.md` (primary) + `.agents/tmp/phases/1.1-brainstorm.md` (brainstormer)

## Dispatch Instructions

1. Determine complexity and agent count (simple: 1-2, medium: 3-5, complex: 6-10)
2. Generate one focused query per agent
3. Dispatch all explorer agents, the deep explorer, **and** the brainstormer in parallel
4. The deep explorer traces execution paths and maps architecture layers — complements the breadth-first primary explorers
5. The brainstormer reads explore output and produces implementation strategy analysis
6. Aggregate results into output file: primary results first, then a `## Architecture Analysis` section from deep explorer

## Input Files

- Task description (from state.json `.task`)

## Output File

- `.agents/tmp/phases/0-explore.md`
- `.agents/tmp/phases/1.1-brainstorm.md` (written by brainstormer supplementary)
