---
name: workflow
description: Agent Teams delegate mode -- teammates self-claim tasks, hooks enforce quality gates
---

# Workflow Orchestration (Agent Teams)

Ants uses Agent Teams delegate mode exclusively. The lead creates a team, populates a shared task list with dependency chains, spawns teammates, and enters delegate mode. Teammates self-claim work. TeammateIdle hooks assign tasks, TaskCompleted hooks enforce quality gates.

## Execution Flow (Agent Teams)

```
Lead creates team and populates shared task list (A0→A1→A2→A3→A4→A5)
  |
Lead spawns 3-5 teammates and enters delegate mode
  |
Teammate goes idle
  |
TeammateIdle hook fires:
  - Checks circuit breaker
  - Reads state.json to find next ready phase
  - Generates phase-specific execution prompt
  - Returns exit 2 with prompt → teammate starts working
  |
Teammate completes task
  |
TaskCompleted hook fires:
  - Validates output file exists and is valid
  - Checks stage gates at boundaries
  - Handles A4 queen verdict (ship/loop/block)
  - Updates circuit breaker (success/failure)
  - Advances state to next phase
  - Exit 0 = accept | Exit 2 = reject with feedback
  |
Repeat until workflow complete or blocked
```

### Key Design: Separation of Concerns

- **TaskCompleted hook** = quality gate (validate output, advance state, handle verdict)
- **TeammateIdle hook** = task router (find next ready phase, generate prompt, assign work)
- **PreToolUse (Edit/Write) hook** = edit gate (controls which phases allow file modifications)
- **Stop hook** = minimal (allows lead to stop freely, teammates continue independently)

## Phase Dispatch Mapping

| Phase | Agent Type | Model | Notes |
|-------|-----------|-------|-------|
| A0 | `ants:forager` | haiku | Parallel batch: dispatch 2-4 foragers |
| A0 | `ants:cartographer` | sonnet | Single: deep architecture trace |
| A0 | `ants:explore-aggregator` | haiku | Single: merge temp files |
| A1 | `ants:architect` | sonnet | Single: plan with task assignments |
| A2 | `ants:blueprint-reviewer` | sonnet | Single: validate plan |
| A3 | `ants:worker` | inherit | Parallel batch: one per task from pool |
| A3 | `ants:sentinel-correctness` | sonnet | Adversarial: bugs, logic errors |
| A3 | `ants:sentinel-security` | sonnet | Adversarial: OWASP, injection, secrets |
| A3 | `ants:sentinel-perf` | sonnet | Adversarial: N+1, blocking I/O, complexity |
| A3 | `ants:review-arbiter` | sonnet | Consolidates sentinel findings |
| A3 | `ants:review-fixer` | inherit | Targeted fixes for review issues |
| A4 | `ants:queen` | sonnet | Single: merge tracks, render verdict |
| A5 | `ants:nurse` | sonnet | Single: update documentation |
| A5 | `ants:drone` | inherit | Single: commit and ship |

## TeammateIdle Hook: Task Assignment

When a teammate goes idle, the hook:

1. Checks circuit breaker — if tripped, allows idle (workflow blocks)
2. Reads `state.json` to find current phase
3. If phase is ready, generates a teammate execution prompt
4. Returns exit 2 with prompt to keep teammate working
5. If no tasks ready (complete/blocked/waiting), allows idle (exit 0)

## TaskCompleted Hook: Quality Gate

When a teammate marks a task complete, the hook:

1. Identifies the completed phase from task subject
2. Validates output file exists and is valid JSON
3. Phase-specific validation:
   - **A0**: A0-explore.md exists → advance to A1
   - **A1**: A1-plan.md exists → advance to A2 (also checks A1-tasks.json for dynamic A3 sub-tasks)
   - **A2**: A2-review.json verdict — if needs_revision with HIGH issues → loop back to A1; else → advance to A3
   - **A3**: Workers update task pool, sentinels write markers, arbiter consolidates quality
   - **A4**: Parse queen verdict — clean → A5, issues_found → loop to A1, budget exhausted → block
   - **A5**: A5-ship.json with commit_sha → workflow DONE
4. Updates circuit breaker (success/failure tracking)
5. Exit 0 = accept, Exit 2 = reject with feedback

## A4 Verdict Handling

```
A4 verdict == "clean"         →  Advance to A5 (ship)
A4 verdict == "issues_found"  →  Return to A1 (re-plan fixes)
                                  Circuit breaker checks:
                                  - stageRestarts < maxStageRestarts
                                  - consecutiveFailures < maxConsecutiveFailures
                                  If either exceeded: block workflow
```

## Hook Responsibilities

| Hook | Event | Behavior |
|------|-------|----------|
| on-teammate-idle.sh | TeammateIdle | Finds next ready task, generates prompt, assigns work (exit 2) |
| on-task-completed.sh | TaskCompleted | Validates output, checks gates, handles verdict, advances phase |
| on-edit-gate.sh | PreToolUse (Edit/Write) | Allows edits in BUILD and SHIP stages; blocks in EXPLORE, PLAN, SYNC |
| on-stop.sh | Stop | Allows lead to stop (teammates continue independently) |
| on-subagent-stop.sh | SubagentStop | No-op (exit 0) — TaskCompleted handles validation |
| on-post-edit-lint.sh | PostToolUse (Edit/Write) | Runs language-aware lint after edits during BUILD/SHIP (advisory, non-blocking) |
| on-subagent-start.sh | SubagentStart | Injects workflow context (phase, loop, status, stage) into subagents |
| on-config-change.sh | ConfigChange | Snapshots configuration changes to state.json configSnapshot field |
| on-pre-compact.sh | PreCompact | Saves critical workflow metadata before context compaction |
