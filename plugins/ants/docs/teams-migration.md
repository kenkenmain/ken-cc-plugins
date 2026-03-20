# Agent Teams -- Architecture Reference

> **Status: IMPLEMENTED** -- v0.7.0 uses Agent Teams delegate mode with Command-as-Active-Lead and dual-channel communication (file-based artifacts + SendMessage live coordination overlay).

## Migration History

### v0.2 (Foundation)
- Hook infrastructure introduced: TeammateIdle, TaskCompleted, edit gate, circuit breaker
- Hooks provided supplementary gates only; orchestrator drove all phase transitions
- State schema v2-v3

### v0.3 (Intended Delegate Mode)
- Designed for pure Agent Teams delegate mode: lead creates team, enters delegate mode, hooks drive everything
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` auto-set by commands
- TeammateIdle and TaskCompleted hooks designed as primary workflow drivers
- State schema v3 (teamName added, dispatchMode/agentTeamsAvailable removed)
- **Never fully implemented in production** -- hooks lacked the ability to call TaskCreate for dynamic tasks

### v0.4-v0.5 (Orchestrator-Driven Dispatch)
- Production workaround: queen agent as persistent central dispatcher via SendMessage
- Queen dispatched each phase, received results, evaluated A4 verdict internally
- Hooks reverted to supplementary gates (edit control, lint-on-save, config snapshots)
- TeammateIdle simplified to kickoff-only; TaskCompleted simplified to validation-only
- sswarm added with competing agents coordinated via SendMessage spawn order
- State schema v4-v5 (queenDispatched, worktreePath, webhookUrl, etc.)

### v0.6 (True Agent Teams Delegate Mode with Command-as-Active-Lead)
- Commands create Agent Teams with dependency-chain task graphs via TaskCreate
- Commands enter a **monitoring loop** (not pure delegate mode) because hooks are shell scripts that cannot call Claude tools like TaskCreate
- TeammateIdle hook rewritten as **full task router**: routes sequential phases, A3 dual-track (worker pool + quality agents), sswarm competing slots, pswarm run boundaries
- TaskCompleted hook enhanced to **validate AND advance state**: advances currentPhase, sets signal flags, evaluates A4 verdict inline when A3 arbiter completes
- A4 verdict moves from queen agent to TaskCompleted hook (inline in handle_a3_arbiter)
- SendMessage eliminated from dispatch coordination; replaced by task dependencies (blockedBy chains) and file-based input
- Queen repurposed as A4 verdict evaluator / team lead initializer (no longer persistent dispatcher)
- State schema v6 (teamCreated, teammateCount, taskGraphVersion, signal flags)

## v0.6.0 Architecture

```
/ants:swarm "add auth module"
         |
swarm.md command:
  0. Check CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  1. Initialize state.json v6 (teamCreated, teammateCount, taskGraphVersion)
  2. Display schedule
  3. Create team + TaskCreate with dependency chains:
     A0 (no deps) -> A1 -> A2 -> [A3 dynamic] -> [A4 inline] -> [A5 dynamic]
  4. Spawn 3-5 teammates
  5. Enter monitoring loop:
     - Read state.json each cycle
     - If needsA3Tasks: TaskCreate for A3 worker/sentinel/arbiter tasks, clear flag
     - If needsA5Tasks: TaskCreate for A5 nurse/drone tasks, clear flag
     - If needsLoopReset: TaskCreate for fresh A1-A4 tasks, clear flag
     - If needsPswarmReset: TaskCreate for fresh A0-A5 task graph, clear flag
     - If status == "complete" or "blocked": exit loop
         |
TeammateIdle hook (on-teammate-idle.sh) -- Full Task Router:
  - Teammate goes idle
  - Hook checks preconditions (shutdown, terminal status, circuit breaker)
  - Routes by currentPhase: A0-A5, sswarm variants, pswarm boundary
  - A3: dual-track routing (worker pool -> quality agents -> arbiter)
  - Returns exit 2 with task prompt (assign work)
  - Returns exit 0 if no work available (allow idle)
         |
TaskCompleted hook (on-task-completed.sh) -- Quality Gate + State Advancement:
  - Teammate marks task complete
  - Hook validates output (file exists, valid JSON, stage gates)
  - Advances state (currentPhase, phase statuses)
  - A3 Arbiter: evaluates A4 verdict INLINE
    - Clean verdict -> sets needsA5Tasks flag, advances to A5
    - Issues found -> sets needsLoopReset flag, resets to A1
  - A5 complete in pswarm -> sets needsPswarmReset flag
  - Exit 0 = accept | Exit 2 = reject with feedback
```

## Signal Flag Protocol

Hooks are shell scripts and CANNOT call Claude tools (TaskCreate, TaskGet, etc.). Dynamic task creation requires a handoff between hooks and the command's monitoring loop.

| Flag | Set By | When | Command Action |
|------|--------|------|----------------|
| `needsA3Tasks` | handle_a1() | A1 plan validated | TaskCreate for A3 worker/sentinel/arbiter tasks |
| `needsA5Tasks` | handle_a3_arbiter() | A4 verdict is clean (inline) | TaskCreate for A5 nurse/drone tasks |
| `needsLoopReset` | handle_a3_arbiter() | A4 verdict is issues_found | TaskCreate for fresh A1-A4 tasks |
| `needsPswarmReset` | handle_a5() | A5 complete in pswarm, pswarmRun < maxRuns | TaskCreate for fresh A0-A5 task graph |

## Key Files

| File | Purpose |
|------|---------|
| `hooks/on-teammate-idle.sh` | Full task router -- assigns next ready phase/task to idle teammates |
| `hooks/on-task-completed.sh` | Quality gate + state advancement -- validates output, advances state, evaluates A4 inline, sets signal flags |
| `hooks/on-stop.sh` | Allows lead to stop freely (teammates continue) |
| `hooks/on-subagent-stop.sh` | No-op (exit 0) |
| `hooks/lib/teams.sh` | Task graph generation, prompt building, dispatch helpers |
| `hooks/lib/state.sh` | State management with v1->v6 auto-migration |
| `hooks/lib/dag.sh` | Phase reset functions (loop-back, pswarm run boundary) with taskGraphVersion tracking |
| `commands/swarm.md` | Agent Teams initialization + monitoring loop (3 teammates) |
| `commands/sswarm.md` | Agent Teams with competing agent task graph (5 teammates) |
| `commands/pswarm.md` | Agent Teams with persistent multi-run monitoring loop (3 teammates) |
| `docs/shared-teams-init.md` | Naming contract -- task IDs, subjects, state schema, routing patterns |

## Changes from v0.5.6

| Component | v0.5.6 (Orchestrator-Driven) | v0.6.0 (Agent Teams Delegate) |
|-----------|------------------------------|-------------------------------|
| Commands | Dispatch queen agent, wait for completion | Create team + TaskCreate + monitoring loop |
| TeammateIdle hook | Simplified kickoff-only | Full task router (all phases, A3 dual-track, sswarm competing slots) |
| TaskCompleted hook | Validation-only quality gate | Validates + advances state + evaluates A4 inline + sets signal flags |
| A4 Verdict | Queen evaluates internally via SendMessage | TaskCompleted hook evaluates inline when A3 arbiter completes |
| sswarm coordination | SendMessage spawn order (leads first, then feeders) | Task dependency chains (blockedBy), file-based input |
| Queen agent | Persistent central dispatcher, A0->A5 orchestrator | A4 verdict evaluator / team lead initializer (edge case only) |
| State schema | v5 (queenDispatched) | v6 (teamCreated, teammateCount, taskGraphVersion, signal flags) |
| SendMessage | Required for sswarm leads, queen dispatch | Retained for optional peer communication only |
| Agent tools | SendMessage in 18 agents | SendMessage removed from all agents |

### v0.7.0 (Dual-Channel Communication)

| Component | v0.6.0 | v0.7.0 |
|-----------|--------|--------|
| SendMessage | Removed from all agents | Re-added to 16 agents as live coordination overlay |
| Communication model | File-based only | Dual-channel: files (source of truth for hooks) + SendMessage (live coordination) |
| Agent prompts | No SendMessage protocol | Communication Protocol section with golden rule: write files first, then SendMessage |
| Hook prompt templates | File-only references | Acknowledge dual-channel model |

## What Was Preserved

The following v0.5 subsystems are preserved unchanged in v0.6:

- **Circuit breaker** -- consecutive failures, per-phase fix budgets, stage restart limits
- **Task pool** -- self-organizing A3 worker dispatch with dependency-driven readiness
- **Edit gate** -- file edit control (A3/A5 only, `.agents/` always allowed)
- **Lint-on-save** -- PostToolUse hook for language-aware linting during BUILD/SHIP
- **Webhooks** -- fire-and-forget HTTP notifications for lifecycle events
- **Plan approval** -- A1 gate requiring explicit plan approval before A2
- **Graceful shutdown** -- shutdown flag checked by hooks
- **Worktree isolation** -- git worktree support for concurrent workflows

## Removed Files (from v0.2)

| File | Reason |
|------|--------|
| `hooks/on-teams-stub.sh` | Replaced by real TeammateIdle/TaskCompleted handlers |
| `hooks/on-task-gate.sh` | Task tool dispatch no longer used -- teammates are spawned via team API |
