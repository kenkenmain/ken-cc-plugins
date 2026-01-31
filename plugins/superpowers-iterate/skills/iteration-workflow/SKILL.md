---
name: iteration-workflow
description: Ralph-style orchestrator loop — dispatches each iterate phase as a subagent, hooks enforce progression and iteration looping
---

# Iteration Workflow Orchestration

Dispatch each phase as a subagent. Hooks enforce output validation, gate checks, state advancement, iteration looping, and loop re-injection. This skill only handles the dispatch loop.

## Execution Flow (Ralph-Style)

The orchestrator uses the Ralph Loop pattern: the Stop hook re-injects the **full orchestrator prompt** (`prompts/orchestrator-loop.md`) every time Claude tries to stop. Claude reads state from disk and dispatches the current phase -- no conversation memory required.

```
Claude dispatches phase N as a subagent (Task tool)
  |
Subagent completes
  |
SubagentStop hook fires:
  - Validates output file exists in .agents/tmp/iterate/phases/
  - Checks gate if at stage boundary
  - Phase 8 special: evaluates iteration loop decision
    - If approved or max iterations reached: advance to Phase 9/C
    - If issues found and iterations remain: archive phase files, loop to Phase 1
  - Marks phase completed
  - Advances state to next phase
  - Exits silently (no stdout)
  |
Claude tries to stop (subagent done, nothing left to do)
  |
Stop hook fires:
  - Reads prompts/orchestrator-loop.md
  - Increments loopIteration in state
  - Returns {"decision":"block","reason":"<full orchestrator prompt>"}
  |
Claude receives complete orchestrator prompt
  - Reads .agents/tmp/iterate/state.json (now pointing to next phase)
  - Dispatches next phase as a subagent
  |
Repeat until SubagentStop marks workflow "completed" -> Stop hook allows exit
```

### Key Design: Separation of Concerns

- **SubagentStop hook** = pure side-effects (validate, advance state, iteration loop logic, exit silently)
- **Stop hook** = prompt re-injection (reads orchestrator-loop.md, blocks with full prompt)
- **Orchestrator prompt** = static, self-contained instructions (reads state, dispatches current phase)

## Phase Dispatch Mapping

| Phase | Stage     | Name         | Type     | subagent_type                      | model    | Notes                                      |
| ----- | --------- | ------------ | -------- | ---------------------------------- | -------- | ------------------------------------------ |
| 1     | PLAN      | Brainstorm   | dispatch | Explore + general-purpose          | config   | Parallel batch: multiple explore agents    |
| 2     | PLAN      | Plan         | dispatch | Plan                               | config   | Parallel batch: planning agents            |
| 3     | PLAN      | Plan Review  | review   | superpowers-iterate:codex-reviewer | inherit  | Dispatches to Codex MCP (codex-high)       |
| 4     | IMPLEMENT | Implement    | dispatch | superpowers-iterate:task-agent     | per-task | Wave-based: dispatch in dependency waves   |
| 5     | IMPLEMENT | Review       | review   | superpowers-iterate:codex-reviewer | inherit  | Dispatches to Codex MCP (codex-high)       |
| 6     | TEST      | Run Tests    | command  | Bash                               | --       | Single bash command                        |
| 7     | IMPLEMENT | Simplify     | subagent | code-simplifier:code-simplifier    | config   | Single agent                               |
| 8     | REVIEW    | Final Review | review   | superpowers-iterate:codex-reviewer | inherit  | Decision point: loop or advance            |
| 9     | FINAL     | Codex Final  | review   | superpowers-iterate:codex-reviewer | inherit  | Full mode only; uses codex-xhigh           |
| C     | FINAL     | Completion   | subagent | Bash                               | --       | Summary and cleanup                        |

## Iteration Loop Mechanics

The superpowers-iterate workflow repeats Phases 1-8 until Phase 8 finds zero issues or max iterations reached. This is handled entirely by hooks:

1. **Phase 8 SubagentStop**: Reads `8-final-review.json` to check review status
   - **Approved** (zero issues): Advance to Phase 9 (full mode) or Phase C (lite mode)
   - **Issues found + iterations remain**: Archive current phase files to `iter-{N}/`, reset `currentPhase` to 1, increment `currentIteration`
   - **Max iterations reached**: Advance to Phase 9 (full mode) or Phase C (lite mode)
2. **Phase file archival**: Before looping, all `*.md` and `*.json` files in `phases/` are moved to `phases/iter-{N}/`
3. **Mode awareness**: The `schedule` array in `state.json` determines which phases exist. In lite mode, Phase 9 is absent and Phase 8 advances directly to Completion (C)

The orchestrator skill does NOT implement loop logic -- it dispatches whatever `currentPhase` the state file says.

## Prompt Construction

For each phase dispatch, build the Task tool prompt as:

```
[PHASE {phase_id}] [ITERATION {iteration}]

{contents of the prompt template file from prompts/phases/}

## Task Context

Task: {value of state.json .task field}
Iteration: {currentIteration} of {maxIterations}
Mode: {mode}

## Input Files

{contents or summaries of the input files listed in the dispatch table}
```

The `[PHASE {id}]` and `[ITERATION {n}]` tags are required -- the PreToolUse hook validates them.

## Dispatch Rules

- **dispatch** phases (1, 2, 4): Read the prompt template for batch instructions. Dispatch multiple parallel subagents as specified in the template. Aggregate results into the expected output file.
- **subagent** phases (7, C): Dispatch a single subagent with the constructed prompt.
- **review** phases (3, 5, 8, 9): Dispatch via `superpowers-iterate:codex-reviewer` which routes to Codex MCP. Phase 9 uses `codex-xhigh`; all others use `codex-high`.
- **command** phases (6): Dispatch a Bash subagent to execute test/lint commands.

## Model Selection

- Phases marked `config`: Use the model from project configuration (`.claude/iterate-config.local.json` or `~/.claude/iterate-config.json`) or default to `inherit`.
- Phases marked `inherit`: Use the parent conversation's model.
- Phases marked `per-task`: Model varies per task based on complexity scoring.
- Phases marked `--`: Not applicable (Bash commands).

## Batch Phases (1, 2, 4)

These phases dispatch multiple parallel subagents. The workflow skill:

1. Reads the prompt template for dispatch instructions
2. Generates per-agent prompts (explore queries, plan areas, or task payloads)
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
- User intervention needed via `/superpowers-iterate:iterate-status`

## What This Skill Does NOT Do

- **Gate checks** --> handled by `on-subagent-stop.sh` hook
- **State updates** --> handled by `on-subagent-stop.sh` hook
- **Phase progression** --> handled by `on-subagent-stop.sh` hook
- **Iteration loop decisions** --> handled by `on-subagent-stop.sh` hook (Phase 8 logic)
- **Phase file archival** --> handled by `on-subagent-stop.sh` hook (on loop-back)
- **Stop prevention** --> handled by `on-stop.sh` hook
- **Dispatch validation** --> handled by `on-task-dispatch.sh` hook
- **Configuration loading** --> handled by `configuration` skill and hook scripts
