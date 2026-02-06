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
| S0    | `minions:explorer`         | inherit  | Parallel batch: dispatch 1-10 agents     |
| S1    | `minions:brainstormer`     | inherit  | Single agent                             |
| S2    | `minions:planner`          | inherit  | Parallel batch: dispatch 1-10 agents     |
| S3    | `minions:plan-reviewer`    | inherit  | plan-reviewer                            |
| S4    | `minions:task-agent`       | inherit  | Parallel batch: dispatch per-task               |
| S5    | `minions:simplifier`       | inherit  | Single agent                             |
| S6    | `minions:impl-reviewer`    | inherit  | impl-reviewer                            |
| S7    | `state.testDeveloper`      | inherit  | Dynamic: test-developer                  |
| S8    | `state.failureAnalyzer`    | inherit  | Dynamic: failure-analyzer                |
| S9    | `state.testDeveloper`      | inherit  | Dynamic: test-developer                  |
| S10   | `minions:test-dev-reviewer` | inherit  | test-dev-reviewer                        |
| S11   | `minions:test-reviewer`    | inherit  | test-reviewer; coverage loop             |
| S12   | `state.docUpdater`         | inherit  | Dynamic: doc-updater                     |
| S13   | `minions:final-reviewer`   | inherit  | final-reviewer                           |
| S14   | `minions:shipper`          | inherit  | Single agent                             |

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

## Batch Phases (S0, S2, S4)

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
