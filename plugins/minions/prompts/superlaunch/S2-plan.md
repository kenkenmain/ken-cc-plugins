# Phase S2: Plan [PHASE S2]

## Subagent Config

- **Primary:** minions:planner (parallel batch, 1-10 agents)
- **Supplementary:** `minions:architecture-analyst` (1 agent, parallel with primary)
- **Aggregator:** `minions:plan-aggregator`
- **Output:** `.agents/tmp/phases/S2-plan.md` (written by aggregator, NOT by orchestrator)

## Dispatch Instructions

### Step 1: Dispatch Primary + Supplementary Agents

1. Read brainstorm results to identify implementation areas
2. For each planner agent i (1-indexed, matching area number), include in its dispatch prompt:
   `Temp output file: .agents/tmp/phases/S2-plan.planner.{i}.tmp`
3. For architecture-analyst, include in its dispatch prompt:
   `Temp output file: .agents/tmp/phases/S2-plan.architecture-analyst.tmp`
4. Dispatch one planner agent per area **and** `minions:architecture-analyst` in a single parallel Task tool message

### Step 2: Dispatch Aggregator

5. **After ALL Step 1 agents complete**, dispatch `minions:plan-aggregator`
6. The aggregator reads all `S2-plan.*.tmp` files, renumbers tasks, resolves dependencies, and writes `S2-plan.md`

**Do NOT read any agent results.** The aggregator handles all merging, renumbering, and writing.

## Input Files

- `.agents/tmp/phases/S0-explore.md`
- `.agents/tmp/phases/S1-brainstorm.md`

## Output File

- `.agents/tmp/phases/S2-plan.md` (written by the aggregator agent)
