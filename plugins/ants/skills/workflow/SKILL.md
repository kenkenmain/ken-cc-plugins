---
name: workflow
description: Ralph-style orchestrator loop -- dispatches each phase as a subagent, hooks enforce progression
---

# Workflow Orchestration

Dispatch each phase as a subagent. Hooks enforce output validation, gate checks, state advancement, and loop re-injection. This skill only handles the dispatch loop.

## Execution Flow (Ralph-Style)

The orchestrator uses the Ralph Loop pattern: the Stop hook generates a **phase-specific orchestrator prompt** every time Claude tries to stop. Claude reads state from disk and dispatches the current phase -- no conversation memory required.

```
Claude dispatches phase N as a subagent (Task tool)
  |
Subagent completes
  |
SubagentStop hook fires:
  - Validates output file exists
  - Checks gate if at stage boundary
  - Marks phase completed
  - Advances state to phase N+1 (or loop back if A4 verdict is "loop")
  - Exits silently (no stdout)
  |
Claude tries to stop (subagent done, nothing left to do)
  |
Stop hook fires:
  - Reads state.json to determine current phase
  - Generates phase-specific orchestrator prompt
  - Increments loopIteration in state
  - Returns {"decision":"block","reason":"<phase-specific orchestrator prompt>"}
  |
Claude receives phase-specific orchestrator prompt
  - Reads .agents/tmp/state.json (now pointing to phase N+1)
  - Dispatches phase N+1 as a subagent
  |
Repeat until SubagentStop marks workflow "completed" -> Stop hook allows exit
```

### Key Design: Separation of Concerns

- **SubagentStop hook** = pure side-effects (validate, advance state, exit silently)
- **Stop hook** = prompt re-injection (generates phase-specific prompt, reads state, blocks stop)
- **PreToolUse (Task) hook** = dispatch validation (ensures correct agent for current phase)
- **PreToolUse (Edit/Write) hook** = edit gate (controls which phases allow file modifications)

## Phase Dispatch Mapping

| Phase | Agent Type | Model | Notes |
|-------|-----------|-------|-------|
| A0 | `ants:forager` | haiku | Parallel batch: dispatch 2-4 foragers |
| A0 | `ants:cartographer` | sonnet | Single: deep architecture trace |
| A0 | `ants:explore-aggregator` | haiku | Single: merge temp files |
| A1 | `ants:architect` | sonnet | Single: plan with wave assignments |
| A2 | `ants:blueprint-reviewer` | sonnet | Single: validate plan |
| A3 | `ants:worker` | inherit | Parallel batch: one per task per wave |
| A3 | `ants:sentinel` | sonnet | Parallel: sentinel reviews per wave |
| A4 | `ants:queen` | sonnet | Single: merge tracks, render verdict |
| A5 | `ants:nurse` | sonnet | Single: update documentation |
| A5 | `ants:drone` | inherit | Single: commit and ship |

## Prompt Construction

For each phase dispatch, build the prompt as:

```
[PHASE {phase_id}]

{contents of prompts/{phase_id}-*.md}

## Task Context

Task: {state.task}

## Input Files

{contents or summaries of input files for this phase}
```

The `[PHASE {id}]` tag is used by the PreToolUse hook to validate dispatches.

## Stop Hook: Prompt Generation

The Stop hook reads `state.json` and generates a phase-specific prompt (~30-60 lines) for the orchestrator. The prompt contains:

1. **Current phase identifier** -- tells Claude which phase to dispatch next
2. **Agent type** -- which `ants:*` agent to spawn
3. **Input file paths** -- what the agent should read
4. **Output file path** -- where the agent should write results
5. **Loop context** -- if loop 2+, includes previous loop's feedback
6. **Task description** -- the original task from state

The prompt is self-contained: Claude does not need conversation memory to continue the workflow. It reads state from disk each time.

### Stop Hook Decision Logic

```
if state.status == "complete":
    allow stop (exit 0, no output)

if state.status == "blocked":
    allow stop with reason

if state.status == "in_progress":
    generate phase prompt for state.currentPhase
    return {"decision":"block","reason":"<prompt>"}
```

## SubagentStop Hook: Validation and Advancement

When a subagent completes, the SubagentStop hook:

1. **Identifies the completed phase** from the agent type name
2. **Validates output** -- checks that expected output file exists and is valid
3. **Checks gate** if at a stage boundary (e.g., PLAN -> BUILD requires A2 approval)
4. **Handles A4 verdict** -- if queen says "loop", resets currentPhase to A1 and increments loop counter
5. **Advances state** -- sets currentPhase to the next phase in the schedule
6. **Marks stage complete** if all phases in the stage are done
7. **Exits silently** (exit 0, no stdout) -- the Stop hook handles prompt injection

### A4 Verdict Handling

```
A4 sync output parsed:

if verdict == "ship":
    advance to A5

if verdict == "loop":
    if loop >= maxLoops:
        set status = "blocked"
        set failure = "Max loops reached"
    else:
        increment loop
        reset currentPhase to A1
        create new loop directory
```

### A3 Wave Synchronization

Phase A3 is special -- it has internal wave barriers:

```
SubagentStop detects A3 worker completion:
  - Track which wave the worker belongs to
  - When all workers in current wave complete:
      - Dispatch sentinel review for the wave
  - When sentinel review completes:
      - If more waves remain, dispatch next wave's workers
      - If all waves done, mark A3 complete
```

## Error Handling

The workflow skill does NOT handle errors directly. If a subagent fails:

- SubagentStop hook exits with code 2 (blocking error)
- Hook stderr message tells Claude what went wrong
- Claude retries the phase dispatch

If retries exhaust (hook keeps blocking):

- Stop hook prevents premature exit
- User intervention needed

## What This Skill Does NOT Do

- **Gate checks** -- handled by `on-subagent-stop.sh` hook
- **State updates** -- handled by `on-subagent-stop.sh` hook
- **Phase progression** -- handled by `on-subagent-stop.sh` hook
- **Stop prevention** -- handled by `on-stop.sh` hook
- **Dispatch validation** -- handled by `on-task-gate.sh` hook
- **Edit control** -- handled by `on-edit-gate.sh` hook

## Hook Responsibilities

| Hook | Event | Behavior |
|------|-------|----------|
| on-stop.sh | Stop | Generates phase-specific orchestrator prompt, blocks premature exit |
| on-subagent-stop.sh | SubagentStop | Validates output, checks gates, handles A4 verdict, advances phase |
| on-task-gate.sh | PreToolUse (Task) | Validates `ants:*` agent matches current phase |
| on-edit-gate.sh | PreToolUse (Edit/Write) | Allows edits in BUILD and SHIP stages; blocks in EXPLORE, PLAN, SYNC |
