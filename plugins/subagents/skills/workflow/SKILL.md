---
name: workflow
description: Thin orchestrator loop — dispatches each phase as a subagent, hooks enforce progression
---

# Workflow Orchestration

Dispatch each phase as a subagent. SubagentStop hooks validate output, advance state, and inject next-phase instructions. This skill only handles the dispatch loop.

## Execution Flow

1. Read `.agents/tmp/state.json` for current phase
2. Read phase prompt template from `prompts/phases/{phase}-*.md`
3. Read input files listed in the template
4. Build subagent prompt: `[PHASE {id}] ` + template content + input file summaries
5. Dispatch as Task tool call with appropriate subagent_type
6. **SubagentStop hook fires automatically:**
   - Validates output file exists
   - Checks gate if at stage boundary
   - Advances state to next phase
   - Returns `decision: "block"` with next-phase instruction
7. Claude processes hook instruction → dispatches next phase
8. Repeat until hook signals workflow complete

## Phase Dispatch Mapping

| Phase | subagent_type                   | model    | Notes                                    |
| ----- | ------------------------------- | -------- | ---------------------------------------- |
| 0     | Explore                         | config   | Parallel batch: dispatch 1-10 agents     |
| 1.1   | general-purpose                 | config   | Single agent                             |
| 1.2   | Plan                            | config   | Parallel batch: dispatch 1-10 agents     |
| 1.3   | kenken:codex-reviewer           | inherit  | Dispatches to Codex MCP                  |
| 2.1   | subagents:task-agent            | per-task | Wave-based: dispatch in dependency waves |
| 2.2   | code-simplifier:code-simplifier | config   | Single agent                             |
| 2.3   | kenken:codex-reviewer           | inherit  | Dispatches to Codex MCP                  |
| 3.1   | Bash                            | —        | Single bash command                      |
| 3.2   | general-purpose                 | config   | Single agent                             |
| 3.3   | kenken:codex-reviewer           | inherit  | Dispatches to Codex MCP                  |
| 4.1   | general-purpose                 | config   | Single agent                             |
| 4.2   | kenken:codex-reviewer           | inherit  | Uses codex-xhigh for final               |
| 4.3   | Bash                            | —        | Git operations                           |

## Prompt Construction

For each phase dispatch, build the prompt as:

```
[PHASE {phase_id}]

{contents of prompts/phases/{phase_id}-*.md}

## Task Context

Task: {state.task}

## Input Files

{contents or summaries of input files for this phase}
```

The `[PHASE {id}]` tag is used by the PreToolUse hook to validate dispatches.

## Batch Phases (0, 1.2, 2.1)

These phases dispatch multiple parallel subagents. The workflow skill:

1. Reads the prompt template for dispatch instructions
2. Generates per-agent prompts (queries, plan areas, or task payloads)
3. Dispatches all agents in parallel
4. Aggregates results into the expected output file
5. Then the SubagentStop hook fires to validate and advance

## Error Handling

The workflow skill does NOT handle errors directly. If a subagent fails:

- SubagentStop hook exits with code 2 (blocking error)
- Hook stderr message tells Claude what went wrong
- Claude retries the phase dispatch

If retries exhaust (hook keeps blocking):

- Stop hook prevents premature exit
- User intervention needed via `/subagents:resume`

## Context Compaction

If configured (`compaction.betweenStages` or `compaction.betweenPhases`):

- After each stage/phase completion, compact context
- Phase outputs are persisted to files, so no data is lost
- Reduces context window usage for long workflows

## What This Skill Does NOT Do

- **Gate checks** → handled by `on-subagent-stop.sh` hook
- **State updates** → handled by `on-subagent-stop.sh` hook
- **Phase progression** → handled by `on-subagent-stop.sh` hook
- **Stop prevention** → handled by `on-stop.sh` hook
- **Dispatch validation** → handled by `on-task-dispatch.sh` hook
