---
name: superlaunch
description: Claude-only 4-phase workflow with loop-back — dispatches phases as subagents, hooks enforce progression
---

# Superlaunch Workflow

Claude-only 4-phase workflow adapted from subagents fdispatch-claude. Dispatches each phase as a subagent. Hooks enforce output validation, gate checks, state advancement, and loop re-injection. This skill documents the orchestration pattern.

## Execution Flow (Ralph-Style)

The orchestrator uses the Ralph Loop pattern: the Stop hook generates a **phase-specific orchestrator prompt** every time Claude tries to stop. Claude reads state from disk and dispatches the current phase — no conversation memory required.

```
Claude dispatches phase F{N} as a subagent (Task tool)
  |
Subagent completes
  |
SubagentStop hook fires:
  - Validates output file exists
  - Checks gate at phase boundary
  - Marks phase completed
  - Advances state to F{N+1}
  - Exits silently (no stdout)
  |
Claude tries to stop (subagent done)
  |
Stop hook fires:
  - Generates phase-specific prompt
  - Returns {"decision":"block","reason":"<prompt>"}
  |
Claude receives prompt -> reads state -> dispatches F{N+1}
  |
Repeat until F4 completes or loop limit reached
```

## Pipeline

```
Explorers (4x haiku, parallel) -> F1 (scout) -> F2 (builder) -> F3 (5 reviewers parallel)
                                      ^                              |
                                      +-------- if issues ----------+
                                                (max 10 loops)

All clean -> F4 (shipper)
Loop 10 hit -> stop and report
```

## Phase Dispatch Mapping

| Phase | Agent | subagent_type | model | Notes |
|-------|-------|---------------|-------|-------|
| Pre-F1 | explorer-files | `minions:explorer-files` | haiku | Parallel batch (4 agents) |
| Pre-F1 | explorer-architecture | `minions:explorer-architecture` | haiku | Parallel batch |
| Pre-F1 | explorer-tests | `minions:explorer-tests` | haiku | Parallel batch |
| Pre-F1 | explorer-patterns | `minions:explorer-patterns` | haiku | Parallel batch |
| F1 | scout | `minions:scout` | inherit | Single agent, writes f1-plan.md |
| F2 | builder (per task) | `minions:builder` | inherit | Parallel batch, writes f2-tasks.json |
| F3 | critic | `minions:critic` | inherit | Parallel batch (5 agents) |
| F3 | pedant | `minions:pedant` | inherit | Parallel batch |
| F3 | witness | `minions:witness` | inherit | Parallel batch |
| F3 | security-reviewer | `minions:security-reviewer` | inherit | Parallel batch |
| F3 | silent-failure-hunter | `minions:silent-failure-hunter` | inherit | Parallel batch |
| F4 | shipper | `minions:shipper` | inherit | Single agent, writes f4-ship.json |

## Gate Requirements

| Transition | Required Files | Validated By |
|------------|---------------|--------------|
| F1 -> F2 | `loop-{N}/f1-plan.md` | on-subagent-stop.sh (scout case) |
| F2 -> F3 | `loop-{N}/f2-tasks.json` | on-subagent-stop.sh (builder case) |
| F3 -> F4 | `loop-{N}/f3-verdict.json` with `verdict: clean` | on-subagent-stop.sh (reviewer case) |
| F4 -> DONE | `f4-ship.json` | on-subagent-stop.sh (shipper case) |

## Loop-Back Behavior

After F3 completes, the SubagentStop hook aggregates all 5 reviewer outputs into `f3-verdict.json`:

- **If `verdict: clean`**: Advance to F4 (shipper)
- **If `verdict: issues_found` AND `loop < maxLoops` (default 10)**:
  - Increment loop counter
  - Reset currentPhase to F1
  - Create new loop directory (`loop-{N+1}/`)
  - Scout reads previous loop's review outputs for targeted fixes
- **If `verdict: issues_found` AND `loop >= maxLoops`**:
  - Set status to "stopped", currentPhase to "STOPPED"
  - Report remaining issues to user

## State Schema (v1)

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "superlaunch",
  "status": "in_progress|stopped|complete",
  "task": "<description>",
  "startedAt": "<ISO>",
  "updatedAt": "<ISO>",
  "currentPhase": "F1|F2|F3|F4|DONE|STOPPED",
  "loop": 1,
  "maxLoops": 10,
  "ownerPpid": "<PPID>",
  "sessionId": "<hex>",
  "branch": "feat/minions-<slug>",
  "schedule": [
    { "phase": "F1", "name": "Scout", "type": "subagent" },
    { "phase": "F2", "name": "Build", "type": "dispatch" },
    { "phase": "F3", "name": "Review", "type": "dispatch" },
    { "phase": "F4", "name": "Ship", "type": "subagent" }
  ],
  "loops": [
    {
      "loop": 1,
      "startedAt": "<ISO>",
      "f1": { "status": "pending|complete" },
      "f2": { "status": "pending|complete" },
      "f3": { "status": "pending|complete", "verdict": "clean|issues_found" }
    }
  ],
  "files": [],
  "failure": null
}
```

## Hook Responsibilities

| Hook | Event | Responsibility |
|------|-------|---------------|
| on-stop.sh | Stop | Generate phase-specific orchestrator prompt (Ralph-style loop driver). Reads state.currentPhase, builds prompt for that phase, blocks stop with prompt injection. |
| on-subagent-stop.sh | SubagentStop | Validate output files exist, check gates, advance state to next phase, handle loop-back logic (F3 verdict aggregation). |
| on-task-gate.sh | PreToolUse (Task) | Validate Task dispatches match expected phase. Reserved for dispatch ordering enforcement. |
| on-edit-gate.sh | PreToolUse (Edit/Write) | Block direct code edits during workflow. Force edits through subagent dispatch. |
| on-launch-init.sh | UserPromptSubmit | Detect existing state, warn on stale/active workflows, inject resume/clean prompts. |

## What This Skill Does NOT Do

- **Gate checks** -> handled by `on-subagent-stop.sh` hook
- **State updates** -> handled by `on-subagent-stop.sh` hook
- **Phase progression** -> handled by `on-subagent-stop.sh` hook
- **Stop prevention** -> handled by `on-stop.sh` hook
- **Dispatch validation** -> handled by `on-task-gate.sh` hook
- **Source file protection** -> handled by `on-edit-gate.sh` hook

This skill documents the workflow pattern for reference and injection into agent contexts. All enforcement logic lives in the hooks.
