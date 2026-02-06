---
name: workflow
description: Ralph-style orchestrator loop — dispatches each phase as a subagent, hooks enforce progression
---

# Workflow Orchestration

Dispatch each phase as a subagent. Hooks enforce output validation, gate checks, state advancement, and loop re-injection. This skill only handles the dispatch loop.

## Execution Flow (Ralph-Style)

The orchestrator uses the Ralph Loop pattern: the Stop hook generates a **phase-specific orchestrator prompt** (~40-70 lines) via `generate_sl_prompt()` in `superlaunch.sh` every time Claude tries to stop. Claude reads state from disk and dispatches the current phase — no conversation memory required.

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
  - Generates phase-specific prompt via generate_sl_prompt() in superlaunch.sh
  - Increments loopIteration in state
  - Returns {"decision":"block","reason":"<phase-specific orchestrator prompt>"}
  ↓
Claude receives phase-specific orchestrator prompt
  - Reads .agents/tmp/state.json (now pointing to phase N+1)
  - Dispatches phase N+1 as a subagent
  ↓
Repeat until SubagentStop marks workflow "completed" → Stop hook allows exit
```

### Key Design: Separation of Concerns

- **SubagentStop hook** = pure side-effects (validate, advance state, exit silently)
- **Stop hook** = prompt re-injection (generates phase-specific prompt via superlaunch.sh, ~40-70 lines)
- **Orchestrator prompt** = phase-specific, generated per-iteration (reads state, dispatches current phase)

## Phase Dispatch Mapping

| Phase | subagent_type              | model    | Notes                                    |
| ----- | -------------------------- | -------- | ---------------------------------------- |
| 0     | minions:explorer           | config   | Parallel batch: dispatch 1-10 agents     |
| 1.1   | minions:brainstormer       | config   | Single agent                             |
| 1.2   | minions:planner            | config   | Parallel batch: dispatch 1-10 agents     |
| 1.3   | `state.reviewer`           | inherit  | Dynamic: claude-reviewer                 |
| 2.1   | complexity-routed agents   | per-task | Easy→sonnet-task-agent, Medium→opus-task-agent, Hard→opus-task-agent |
| 2.2   | minions:simplifier         | config   | Single agent                             |
| 2.3   | `state.reviewer`           | inherit  | Dynamic: claude-reviewer                 |
| 3.1   | `state.testDeveloper`      | config   | Dynamic: test-developer                  |
| 3.2   | `state.failureAnalyzer`    | config   | Dynamic: failure-analyzer                |
| 3.3   | `state.testDeveloper`      | config   | Dynamic: test-developer                  |
| 3.4   | `state.reviewer`           | review-tier | Dynamic: claude-reviewer              |
| 3.5   | `state.reviewer`           | review-tier | Dynamic: claude-reviewer; coverage loop |
| 4.1   | `state.docUpdater`         | config   | Dynamic: doc-updater                     |
| 4.2   | `state.reviewer`           | inherit  | Dynamic: claude-reviewer                 |
| 4.3   | minions:completion-handler | config   | Single agent                             |

## Prompt Construction

For each phase dispatch, build the prompt as:

```
[PHASE {phase_id}]

{contents of prompts/superlaunch/{phase_id}-*.md}

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
- User intervention needed

## What This Skill Does NOT Do

- **Gate checks** → handled by `on-subagent-stop.sh` hook
- **State updates** → handled by `on-subagent-stop.sh` hook
- **Phase progression** → handled by `on-subagent-stop.sh` hook
- **Stop prevention** → handled by `on-stop.sh` hook
- **Dispatch validation** → handled by `on-task-gate.sh` hook
