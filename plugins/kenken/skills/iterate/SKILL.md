---
name: iterate
description: Ralph-style orchestrator loop — dispatches each phase as a subagent, hooks enforce progression
argument-hint: <task description>
---

# kenken Iterate Workflow

Dispatch each phase as a subagent. Hooks enforce output validation, gate checks, state advancement, and loop re-injection. This skill only handles the dispatch loop.

## Execution Flow (Ralph-Style)

The orchestrator uses the Ralph Loop pattern: the Stop hook re-injects the **full orchestrator prompt** (`prompts/orchestrator-loop.md`) every time Claude tries to stop. Claude reads state from disk and dispatches the current phase -- no conversation memory required.

```
Claude dispatches phase N as a subagent (Task tool)
  |
Subagent completes
  |
SubagentStop hook fires:
  - Validates output file exists
  - Checks gate if at stage boundary
  - Marks phase completed
  - Advances state to phase N+1
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
  - Reads .agents/tmp/kenken/state.json (now pointing to phase N+1)
  - Dispatches phase N+1 as a subagent
  |
Repeat until SubagentStop marks workflow "completed" -> Stop hook allows exit
```

### Key Design: Separation of Concerns

- **SubagentStop hook** = pure side-effects (validate, advance state, exit silently)
- **Stop hook** = prompt re-injection (reads orchestrator-loop.md, blocks with full prompt)
- **Orchestrator prompt** = static, self-contained instructions (reads state, dispatches current phase)

## Phase Dispatch Mapping

14 phases across 4 stages: PLAN (1.1-1.3), IMPLEMENT (2.1-2.3), TEST (3.1-3.5, optional), FINAL (4.1-4.3).

| Phase | Stage     | Name           | Type     | subagent_type                      | model    | Notes                          |
| ----- | --------- | -------------- | -------- | ---------------------------------- | -------- | ------------------------------ |
| 1.1   | PLAN      | Brainstorm     | dispatch | Explore + general-purpose          | config   | Parallel batch                 |
| 1.2   | PLAN      | Plan           | dispatch | Plan                               | config   | Parallel batch                 |
| 1.3   | PLAN      | Plan Review    | review   | kenken:codex-reviewer              | inherit  | Codex MCP (codex-high)         |
| 2.1   | IMPLEMENT | Implementation | dispatch | kenken:task-agent                  | per-task | Wave-based dependency ordering |
| 2.2   | IMPLEMENT | Simplify       | subagent | code-simplifier:code-simplifier    | config   | Single agent                   |
| 2.3   | IMPLEMENT | Impl Review    | review   | kenken:codex-reviewer              | inherit  | Codex MCP (codex-high)         |
| 3.1   | TEST      | Test Plan      | subagent | general-purpose                    | config   | Single agent                   |
| 3.2   | TEST      | Write Tests    | subagent | general-purpose                    | config   | Single agent                   |
| 3.3   | TEST      | Coverage       | command  | Bash                               | --       | Coverage commands              |
| 3.4   | TEST      | Run Tests      | command  | Bash                               | --       | Test/lint commands             |
| 3.5   | TEST      | Test Review    | review   | kenken:codex-reviewer              | inherit  | Codex MCP (codex-high)         |
| 4.1   | FINAL     | Final Review   | review   | kenken:codex-reviewer              | inherit  | Codex MCP (codex-xhigh)       |
| 4.2   | FINAL     | Extensions     | subagent | general-purpose                    | config   | Extension loop-back logic      |
| 4.3   | FINAL     | Completion     | subagent | Bash                               | --       | Git operations                 |

### TEST Stage (Optional)

The TEST stage (phases 3.1-3.5) can be disabled via configuration (`stages.test.enabled: false`). When disabled, the schedule skips directly from phase 2.3 to phase 4.1. The schedule is built at initialization time and reflected in the state file.

### Phase 4.2 Extension Loop-Back

Phase 4.2 (Extensions) can loop back to phase 1.1 if the user accepts a suggested extension. The SubagentStop hook detects this and resets the schedule to restart from PLAN stage with the new extension task.

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

Prompt templates live in `prompts/phases/` (14 files, one per phase). Input files for each phase are defined in `hooks/lib/schedule.sh` via `get_phase_input_files`.

## Batch Phases (1.1, 1.2, 2.1)

These phases dispatch multiple parallel subagents. The workflow skill:

1. Reads the prompt template for dispatch instructions
2. Generates per-agent prompts (queries, plan areas, or task payloads)
3. Dispatches all agents in parallel
4. Aggregates results into the expected output file
5. Then the SubagentStop hook fires to validate and advance

Phase 2.1 uses wave-based execution: tasks are dispatched in dependency waves, with each wave completing before the next begins.

## Error Handling

The workflow skill does NOT handle errors directly. If a subagent fails:

- SubagentStop hook exits with code 2 (blocking error)
- Hook stderr message tells Claude what went wrong
- Claude retries the phase dispatch

If retries exhaust (hook keeps blocking):

- Stop hook prevents premature exit
- User intervention needed via `/kenken:resume`

## State and Paths

- **State file:** `.agents/tmp/kenken/state.json`
- **Phase outputs:** `.agents/tmp/kenken/phases/`
- **Prompt templates:** `prompts/phases/`
- **Orchestrator prompt:** `prompts/orchestrator-loop.md`
- **Config:** `.claude/kenken-config.json` (project), `~/.claude/kenken-config.json` (global)

## What This Skill Does NOT Do

- **Gate checks** -- handled by `on-subagent-stop.sh` hook
- **State updates** -- handled by `on-subagent-stop.sh` hook
- **Phase progression** -- handled by `on-subagent-stop.sh` hook
- **Stop prevention** -- handled by `on-stop.sh` hook
- **Dispatch validation** -- handled by `on-task-dispatch.sh` hook
- **Schedule management** -- handled by `hooks/lib/schedule.sh`
- **Configuration loading** -- handled by `kenken:configure` skill
- **Inline phase execution** -- all work dispatched to subagents via Task tool
