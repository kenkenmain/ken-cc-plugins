---
name: workflow
description: Agent Teams delegate mode with Command-as-Active-Lead monitoring loop -- TeammateIdle routes tasks, TaskCompleted validates and advances state, commands create dynamic tasks via signal flags
---

# Workflow Orchestration (Agent Teams)

Ants uses Agent Teams delegate mode with a **Command-as-Active-Lead** model. The command (lead) creates a team, populates a shared task list with dependency chains, spawns teammates, then enters a **monitoring loop** -- not pure delegate mode. The monitoring loop reads state.json signal flags set by hooks and performs dynamic TaskCreate calls (hooks are shell scripts and cannot call Claude tools like TaskCreate). The TeammateIdle hook is the **full task router** for all phases (A0-A5), not just kickoff. The TaskCompleted hook **validates output AND advances state** (not validate-only). A4 verdict evaluation is performed **inline** by `handle_a3_arbiter()` in the TaskCompleted hook -- there is no separate verdict agent or phase dispatch.

## Execution Flow (Agent Teams)

```
Command creates team and populates shared task list (A0→A1→A2 dependency chain)
  |
Command spawns 3-5 teammates
  |
Command enters monitoring loop (NOT pure delegate mode):
  - Reads state.json each cycle
  - Checks signal flags: needsA3Tasks, needsA5Tasks, needsLoopReset, needsPswarmReset
  - When flag detected: calls TaskCreate for required tasks, clears flag
  - Exits when status == "complete" or "blocked" or "stopped"
  |
Meanwhile, teammates work via hook-driven cycle:
  |
  Teammate goes idle
    |
  TeammateIdle hook fires (FULL task router for ALL phases):
    - Checks circuit breaker, shutdown, terminal states
    - Reads state.json to find next ready phase/task
    - Routes by currentPhase: A0, A1, A2, A3 (worker pool + quality track), A5
    - Generates phase-specific execution prompt
    - Returns exit 2 with prompt → teammate starts working
    |
  Teammate completes task
    |
  TaskCompleted hook fires (validates AND advances state):
    - Identifies phase from task subject routing
    - Validates output file exists and is valid
    - Advances currentPhase to next phase in state.json
    - At A3 arbiter completion: evaluates A4 verdict INLINE
      - clean → sets needsA5Tasks signal flag, advances to A5
      - issues_found → sets needsLoopReset signal flag, resets to A1
    - At A1 completion: sets needsA3Tasks signal flag
    - Updates circuit breaker (success/failure)
    - Exit 0 = accept | Exit 2 = reject with feedback
    |
  Repeat until workflow complete or blocked
```

### Key Design: Separation of Concerns

- **Command monitoring loop** = dynamic task creator (reads signal flags, calls TaskCreate -- hooks cannot call Claude tools)
- **TaskCompleted hook** = quality gate + state advancer (validate output, advance currentPhase, evaluate A4 verdict inline, set signal flags)
- **TeammateIdle hook** = full task router for all phases (find next ready phase/task, generate prompt, assign work)
- **PreToolUse (Edit/Write) hook** = edit gate (controls which phases allow file modifications)
- **Stop hook** = minimal (allows lead to stop freely, teammates continue independently)

### Signal Flags (Hook-to-Command Communication)

Hooks are shell scripts and cannot call TaskCreate. When dynamic task creation is needed, hooks set signal flags in state.json that the command's monitoring loop detects and acts upon:

| Flag | Set By | When | Command Action |
|------|--------|------|----------------|
| `needsA3Tasks` | `handle_a1()` | A1 plan validated | Create A3 worker/sentinel/arbiter tasks |
| `needsA5Tasks` | `handle_a3_arbiter()` | A4 verdict clean (inline) | Create A5 nurse/drone tasks |
| `needsLoopReset` | `handle_a3_arbiter()` | A4 verdict issues_found (inline) | Create fresh A1-A4 tasks |
| `needsPswarmReset` | `handle_a5()` | A5 complete in pswarm, runs remaining | Create fresh A0-A5 task graph |

## Phase Dispatch Mapping

| Phase | Agent Type | Model | Notes |
|-------|-----------|-------|-------|
| A0 | `ants:forager` | haiku | Parallel batch: dispatch 2-4 foragers |
| A0 | `ants:cartographer` | sonnet | Single: deep architecture trace |
| A1 | `ants:architect` | sonnet | Single: plan with task assignments |
| A2 | `ants:blueprint-reviewer` | sonnet | Single: validate plan |
| A3 | `ants:worker` | inherit | Parallel batch: one per task from pool |
| A3 | `ants:sentinel-correctness` | sonnet | Adversarial: bugs, logic errors |
| A3 | `ants:sentinel-security` | sonnet | Adversarial: OWASP, injection, secrets |
| A3 | `ants:sentinel-perf` | sonnet | Adversarial: N+1, blocking I/O, complexity |
| A3 | `ants:review-arbiter` | sonnet | Consolidates sentinel findings |
| A3 | `ants:review-fixer` | inherit | Targeted fixes for review issues |
| A4 | TaskCompleted hook (inline) | -- | Evaluated inline by handle_a3_arbiter() when arbiter completes; no separate agent dispatch |
| A5 | `ants:nurse` | sonnet | Single: update documentation |
| A5 | `ants:drone` | inherit | Single: commit and ship |

## TeammateIdle Hook: Task Assignment

When a teammate goes idle, the hook:

1. Checks circuit breaker — if tripped, allows idle (workflow blocks)
2. Reads `state.json` to find current phase
3. If phase is ready, generates a teammate execution prompt
4. Returns exit 2 with prompt to keep teammate working
5. If no tasks ready (complete/blocked/waiting), allows idle (exit 0)

## TaskCompleted Hook: Quality Gate + State Advancer

When a teammate marks a task complete, the hook validates output AND advances state to the next phase:

1. Identifies the completed phase from task subject (case routing by `A{N} ...` prefix)
2. Validates output file exists and is valid JSON
3. Phase-specific validation and state advancement:
   - **A0**: A0-explore.md exists → advances currentPhase to A1
   - **A1**: A1-plan.md + A1-tasks.json exist → initializes task pool, sets `needsA3Tasks` signal flag, advances to A2
   - **A2**: A2-review.json verdict -- if needs_revision with HIGH issues → loop back to A1; else → advance to A3
   - **A3 Workers**: Update task pool, check build track completion
   - **A3 Sentinels/Guardian/Simplifier**: Mark agent complete, check if all quality agents done
   - **A3 Arbiter**: Consolidates quality, then evaluates **A4 verdict inline** -- clean → sets `needsA5Tasks` flag, advances to A5; issues_found → sets `needsLoopReset` flag, resets to A1
   - **A5**: A5-ship.json with commit_sha → workflow DONE (swarm/sswarm) or sets `needsPswarmReset` flag (pswarm)
4. Updates circuit breaker (success/failure tracking)
5. Exit 0 = accept, Exit 2 = reject with feedback

## A4 Verdict Handling (Inline in TaskCompleted Hook)

The A4 verdict is evaluated **inline** by `handle_a3_arbiter()` in `on-task-completed.sh` when the review-arbiter task completes. There is no separate A4 agent dispatch or verdict phase -- the arbiter's completion triggers immediate verdict evaluation within the same hook invocation.

```
A3 arbiter completes → handle_a3_arbiter() runs:
  1. Reads A3-quality.json
  2. Counts critical/warning issues
  3. Determines verdict: "clean" or "issues_found"
  4. Writes A4-queen-verdict.json

  verdict == "clean"         →  Sets needsA5Tasks signal flag, advances to A5
                                 Command monitoring loop creates A5 nurse/drone tasks
  verdict == "issues_found"  →  Circuit breaker checks:
                                  - stageRestarts < maxStageRestarts
                                  - consecutiveFailures < maxConsecutiveFailures
                                  If either exceeded: block workflow
                                  Otherwise: sets needsLoopReset flag, resets to A1
                                  Command monitoring loop creates fresh A1-A4 tasks
```

## Hook Responsibilities

| Hook | Event | Behavior |
|------|-------|----------|
| on-teammate-idle.sh | TeammateIdle | Full task router for all phases (A0-A5): finds next ready task/phase, generates prompt, assigns work (exit 2) |
| on-task-completed.sh | TaskCompleted | Validates output, advances state to next phase, evaluates A4 verdict inline at arbiter completion, sets signal flags for command monitoring loop |
| on-edit-gate.sh | PreToolUse (Edit/Write) | Allows edits in BUILD and SHIP stages; blocks in EXPLORE, PLAN, SYNC |
| on-stop.sh | Stop | Allows lead to stop (teammates continue independently) |
| on-subagent-stop.sh | SubagentStop | No-op (exit 0) — TaskCompleted handles validation |
| on-post-edit-lint.sh | PostToolUse (Edit/Write) | Runs language-aware lint after edits during BUILD/SHIP (advisory, non-blocking) |
| on-subagent-start.sh | SubagentStart | Injects workflow context (phase, loop, status, stage) into subagents |
| on-config-change.sh | ConfigChange | Snapshots configuration changes to state.json configSnapshot field |
| on-pre-compact.sh | PreCompact | Saves critical workflow metadata before context compaction |
