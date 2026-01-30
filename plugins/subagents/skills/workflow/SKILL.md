---
name: workflow
description: Ralph-style orchestrator loop — dispatches each phase as a subagent, hooks enforce progression
---

# Workflow Orchestration

Dispatch each phase as a subagent. Hooks enforce output validation, gate checks, state advancement, and loop re-injection. This skill only handles the dispatch loop.

## Execution Flow (Ralph-Style)

The orchestrator uses the Ralph Loop pattern: the Stop hook re-injects the **full orchestrator prompt** (`prompts/orchestrator-loop.md`) every time Claude tries to stop. Claude reads state from disk and dispatches the current phase — no conversation memory required.

```
Claude dispatches phase N as a subagent (Task tool)
  ↓
Subagent completes
  ↓
SubagentStop hook fires:
  - Validates output file exists
  - Checks gate if at stage boundary
  - Marks phase completed
  - Advances state to phase N+1
  - Exits silently (no stdout)
  ↓
Claude tries to stop (subagent done, nothing left to do)
  ↓
Stop hook fires:
  - Reads prompts/orchestrator-loop.md
  - Increments loopIteration in state
  - Returns {"decision":"block","reason":"<full orchestrator prompt>"}
  ↓
Claude receives complete orchestrator prompt
  - Reads .agents/tmp/state.json (now pointing to phase N+1)
  - Dispatches phase N+1 as a subagent
  ↓
Repeat until SubagentStop marks workflow "completed" → Stop hook allows exit
```

### Key Design: Separation of Concerns

- **SubagentStop hook** = pure side-effects (validate, advance state, exit silently)
- **Stop hook** = prompt re-injection (reads orchestrator-loop.md, blocks with full prompt)
- **Orchestrator prompt** = static, self-contained instructions (reads state, dispatches current phase)

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
