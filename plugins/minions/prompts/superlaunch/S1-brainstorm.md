# Phase S1: Brainstorm [PHASE S1]

## Subagent Config

- **Type:** minions:brainstormer (standalone subagent)
- **Output:** `.agents/tmp/phases/S1-brainstorm.md`

## Dispatch Instructions

1. Dispatch `minions:brainstormer` as a single agent
2. Pass the task description and input file path
3. The brainstormer reads exploration findings and evaluates 2-3 implementation approaches
4. Write structured output with selected approach and implementation areas

The brainstormer agent follows a structured analysis process to evaluate approaches and select the best one.

## Input Files

- `.agents/tmp/phases/S0-explore.md` — exploration findings from Phase S0

## Output File

- `.agents/tmp/phases/S1-brainstorm.md` — structured markdown with selected approach and implementation areas
