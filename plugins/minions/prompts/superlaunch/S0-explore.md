# Phase S0: Explore [PHASE S0]

## Subagent Config

- **Primary:** minions:explorer (parallel batch, 1-10 agents)
- **Supplementary:** `minions:deep-explorer` — deep architecture tracing (execution paths, layer mapping, dependencies)
- **Aggregator:** `minions:explore-aggregator`
- **Output:** `.agents/tmp/phases/S0-explore.md` (written by aggregator, NOT by orchestrator)

## Dispatch Instructions

### Step 1: Dispatch Primary + Supplementary Agents

1. Determine complexity and agent count (simple: 1-2, medium: 3-5, complex: 6-10)
2. Generate one focused query per agent
3. For each explorer agent i (1-indexed), include in its dispatch prompt:
   `Temp output file: .agents/tmp/phases/S0-explore.explorer.{i}.tmp`
4. For deep-explorer, include in its dispatch prompt:
   `Temp output file: .agents/tmp/phases/S0-explore.deep-explorer.tmp`
5. Dispatch all explorer agents **and** the deep explorer in a single parallel Task tool message

### Step 2: Dispatch Aggregator

6. **After ALL Step 1 agents complete**, dispatch `minions:explore-aggregator`
7. The aggregator reads all `S0-explore.*.tmp` files, merges them, and writes `S0-explore.md`

**Do NOT read any agent results.** The aggregator handles all merging and writing.

## Input Files

- Task description (from state.json `.task`)

## Output File

- `.agents/tmp/phases/S0-explore.md` (written by the aggregator agent)
