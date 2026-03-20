# Shared Naming Contract -- Ants Agent Teams

> **Purpose:** Reference document standardizing naming, schemas, and routing patterns across all Agent Teams components. NOT a slash command. All commands, hooks, and agents MUST match these exact names. Mismatch causes routing failures.
>
> **v0.7.0 update:** SendMessage re-added to 16 agents as a live coordination overlay. The naming contracts, task IDs, routing patterns, and state schema defined in this document remain unchanged -- SendMessage is an additive communication channel that does not affect hook routing or task dependency chains.

---

## 1. State Schema v6

The v6 schema replaces `queenDispatched` with `teamCreated` and adds fields for Agent Teams delegate mode. Migration from v5 is handled by `migrate_state_v5_to_v6()` in `state.sh`.

```json
{
  "version": 6,
  "plugin": "ants",
  "pipeline": "swarm|sswarm|pswarm",
  "status": "in_progress|blocked|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID if available>",
  "currentPhase": "A0|A1|A2|A3|A4|A5|DONE|STOPPED|BLOCKED",
  "loop": 1,
  "maxLoops": 5,
  "teamName": "ants-<branch-slug>",
  "startedAt": "ISO timestamp",

  "teamCreated": false,
  "teammateCount": 0,
  "taskGraphVersion": 1,

  "needsA3Tasks": false,
  "needsA5Tasks": false,
  "needsLoopReset": false,
  "needsPswarmReset": false,

  "schedule": [
    {"phase": "A0", "stage": "EXPLORE", "label": "Colony Exploration", "type": "agents"},
    {"phase": "A1", "stage": "PLAN", "label": "Architect Plan", "type": "agents"},
    {"phase": "A2", "stage": "PLAN", "label": "Blueprint Review", "type": "agents"},
    {"phase": "A3", "stage": "BUILD", "label": "Dual-Track Execution", "type": "agents"},
    {"phase": "A4", "stage": "SYNC", "label": "Verdict", "type": "agents"},
    {"phase": "A5", "stage": "SHIP", "label": "Documentation + Ship", "type": "agents"}
  ],
  "phases": {
    "A0": {"status": "pending"},
    "A1": {"status": "pending"},
    "A2": {"status": "pending"},
    "A3": {"status": "pending"},
    "A4": {"status": "pending"},
    "A5": {"status": "pending"}
  },
  "taskPool": [],
  "circuitBreaker": {
    "consecutiveFailures": 0,
    "maxConsecutiveFailures": 5,
    "maxFixAttempts": 5,
    "maxStageRestarts": 2,
    "fixAttempts": {},
    "stageRestarts": 0
  },
  "failure": null,
  "worktreePath": null,
  "messages": [],
  "planApproved": false,
  "shutdown": false,
  "webhookUrl": null,
  "lintConfig": null,
  "configSnapshot": null,
  "compactMetadata": null,
  "webSearch": false
}
```

### New v6 Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `teamCreated` | boolean | false | Replaces `queenDispatched`. Set true after team creation + teammate spawn. |
| `teammateCount` | number | 0 | Number of teammates spawned (3 for swarm/pswarm, 5 for sswarm). |
| `taskGraphVersion` | number | 1 | Incremented on loop-back (`reset_phases_for_loop`) and pswarm run boundary (`reset_phases_for_pswarm`). Commands use this to detect when fresh TaskCreate calls are needed. |
| `needsA3Tasks` | boolean | false | Signal flag: set by `on-task-completed.sh` when A1 completes. Command creates A3 worker/sentinel/arbiter tasks. |
| `needsA5Tasks` | boolean | false | Signal flag: set by `on-task-completed.sh` when A4 verdict is clean. Command creates A5 nurse/drone tasks. |
| `needsLoopReset` | boolean | false | Signal flag: set by `on-task-completed.sh` when A4 verdict is `issues_found`. Command creates fresh A1-A4 tasks. |
| `needsPswarmReset` | boolean | false | Signal flag: set by `on-task-completed.sh` when A5 completes in pswarm and `pswarmRun < maxRuns`. Command creates fresh A0-A5 task graph. |

### Removed v5 Fields

| Field | Replacement |
|-------|-------------|
| `queenDispatched` | `teamCreated` (migrated automatically by `migrate_state_v5_to_v6`) |

### v5-to-v6 Migration

```bash
# In state.sh check_ants_workflow():
if [[ "$version" == "5" ]]; then
  migrate_state_v5_to_v6
  version="6"
fi
```

Migration jq expression:

```jq
.version = 6 |
.teamCreated = (.queenDispatched // false) |
del(.queenDispatched) |
.teammateCount //= 0 |
.taskGraphVersion //= 1
```

---

## 2. TaskCreate Subject Naming Convention

Subjects are the primary routing key in `on-task-completed.sh`. Every subject MUST start with `A{N} ` (phase prefix + space) to match the case statement routing.

### A0 -- EXPLORE

| Subject | Agent | Pipeline |
|---------|-------|----------|
| `"A0 Forager: Colony exploration {N}"` | `ants:forager` | all |
| `"A0 Cartographer: Deep architecture trace"` | `ants:cartographer` | all |
| `"A0 Explore Aggregator: Synthesize findings"` | `ants:explore-aggregator` | all |

### A1 -- PLAN

| Subject | Agent | Pipeline |
|---------|-------|----------|
| `"A1 Architect: Implementation plan"` | `ants:architect` | swarm, pswarm |
| `"A1 Architect {N}: Competing plan"` | `ants:architect` | sswarm |
| `"A1 Plan Arbiter: Consolidate plans"` | `ants:plan-arbiter` | sswarm |

### A2 -- PLAN (Review)

| Subject | Agent | Pipeline |
|---------|-------|----------|
| `"A2 Blueprint Reviewer: Validate plan"` | `ants:blueprint-reviewer` | swarm, pswarm |
| `"A2 Blueprint Reviewer {N}: Competing review"` | `ants:blueprint-reviewer` | sswarm |
| `"A2 Review Lead: Consolidate reviews"` | `ants:review-lead` | sswarm |

### A3 -- BUILD (Workers)

| Subject | Agent | Pipeline |
|---------|-------|----------|
| `"A3 Worker: {task_name}"` | `ants:worker` | all |

### A3 -- BUILD (Quality Track)

| Subject | Agent | Pipeline |
|---------|-------|----------|
| `"A3 Sentinel Correctness: Review"` | `ants:sentinel-correctness` | all |
| `"A3 Sentinel Security: Review"` | `ants:sentinel-security` | all |
| `"A3 Sentinel Perf: Review"` | `ants:sentinel-perf` | all |
| `"A3 Sentinel Style: Review"` | `ants:sentinel-style` | all |
| `"A3 Guardian: Write tests"` | `ants:guardian` | all |
| `"A3 Simplifier: Code cleanup"` | `ants:simplifier` | all |

### A3 -- BUILD (Consolidation)

| Subject | Agent | Pipeline |
|---------|-------|----------|
| `"A3 Arbiter: Consolidate reviews"` | `ants:review-arbiter` | all |
| `"A3 Review-Fixer: Apply targeted repairs"` | `ants:review-fixer` | all (optional) |

### A5 -- SHIP

| Subject | Agent | Pipeline |
|---------|-------|----------|
| `"A5 Nurse: Update documentation"` | `ants:nurse` | all |
| `"A5 Drone: Commit and ship"` | `ants:drone` | all |

### Subject Format Rules

1. Always starts with `A{N} ` (phase number + space).
2. Agent role name follows immediately after the phase prefix.
3. Colon separates role from description: `"A3 Worker: {task_name}"`.
4. `{N}` in forager/architect/reviewer subjects is a 1-indexed integer.
5. `{task_name}` in worker subjects comes from `A1-tasks.json` task descriptors.
6. No trailing periods or extra whitespace.

---

## 3. on-task-completed.sh Routing Patterns

The main `case` statement in `on-task-completed.sh` routes task subjects to handler functions. Patterns are matched with bash glob syntax (prefix match via `*` suffix).

```bash
case "$TASK_SUBJECT" in
  "A3 Guardian"*|"A3 guardian"*|"A3-guardian"*)
    phase="A3-guardian" ;;
  "A3 Worker"*|"A3 worker"*|"A3-worker"*)
    phase="A3-worker" ;;
  "A3 Sentinel"*|"A3 sentinel"*|"A3-sentinel"*)
    phase="A3-sentinel" ;;
  "A3 Simplifier"*|"A3 simplifier"*|"A3-simplifier"*)
    phase="A3-simplifier" ;;
  "A3 Review Arbiter"*|"A3 Arbiter"*|"A3 arbiter"*|"A3-arbiter"*)
    phase="A3-arbiter" ;;
  "A3 Review Fixer"*|"A3 review fixer"*|"A3-review-fixer"*|"A3 Review-Fixer"*)
    phase="A3-fixer" ;;
  "A3"*) phase="A3" ;;
  "A0 Forager"*|"A0 Cartographer"*) phase="A0-sub" ;;
  "A0 Explore Aggregator"*|"A0: Colony Exploration"*|"A0"*) phase="A0" ;;
  "A1 Architect"[[:space:]][0-9]*) phase="A1-sub" ;;
  "A1 Plan Arbiter"*) phase="A1" ;;
  "A1"*) phase="A1" ;;
  "A2 Blueprint Reviewer"[[:space:]][0-9]*) phase="A2-sub" ;;
  "A2 Review Lead"*) phase="A2" ;;
  "A2"*) phase="A2" ;;
  "A4"*) phase="A4" ;;
  "A5 Nurse"*|"A5 nurse"*|"A5-nurse"*) phase="A5-nurse" ;;
  "A5 Drone"*|"A5 drone"*|"A5-drone"*) phase="A5-drone" ;;
  "A5"*) phase="A5" ;;
  *)
    # Not an ants phase task, allow completion
    exit 0
    ;;
esac
```

### Pattern-to-Handler Mapping

| Pattern | Phase ID | Handler | Description |
|---------|----------|---------|-------------|
| `A0 Forager*` or `A0 Cartographer*` | `A0-sub` | (accept, no state change) | Individual A0 sub-task completed, awaiting aggregator |
| `A0 Explore Aggregator*` or `A0*` | `A0` | `handle_a0()` | Validates A0-explore.md, advances to A1 |
| `A1 Architect [0-9]*` | `A1-sub` | (accept, no state change) | Competing architect completed (sswarm), awaiting arbiter |
| `A1 Plan Arbiter*` or `A1*` | `A1` | `handle_a1()` | Validates A1-plan.md + A1-tasks.json, inits task pool, advances to A2 |
| `A2 Blueprint Reviewer [0-9]*` | `A2-sub` | (accept, no state change) | Competing reviewer completed (sswarm), awaiting lead |
| `A2 Review Lead*` or `A2*` | `A2` | `handle_a2()` | Validates A2-review.json, approved -> A3 or needs_revision -> loop to A1 |
| `A3 Worker*` | `A3-worker` | `handle_a3_worker()` | Updates task pool, checks build track completion |
| `A3 Sentinel*` | `A3-sentinel` | `handle_a3_sentinel()` | Marks sentinel output file, checks all sentinels done |
| `A3 Guardian*` | `A3-guardian` | `handle_a3_guardian()` | Marks guardian complete |
| `A3 Simplifier*` | `A3-simplifier` | `handle_a3_simplifier()` | Marks simplifier complete, checks all quality agents done |
| `A3 Review Arbiter*` or `A3 Arbiter*` | `A3-arbiter` | `handle_a3_arbiter()` | Consolidates quality verdict, evaluates A4 inline, sets signal flags |
| `A3 Review Fixer*` | `A3-fixer` | `handle_a3_fixer()` | Marks fixer complete |
| `A3*` (catch-all) | `A3` | `handle_a3_aggregate()` | Legacy fallback -- should not fire in v0.6 |
| `A4*` | `A4` | `handle_a4()` | Legacy compatibility shim -- verdict now inline in A3-arbiter |
| `A5 Nurse*` | `A5-nurse` | `handle_a5_nurse()` | Validates A5-docs.json, marks nurseDone for drone routing |
| `A5 Drone*` | `A5-drone` | `handle_a5()` | Validates A5-ship.json, marks workflow DONE or sets pswarm reset |
| `A5*` (catch-all) | `A5` | `handle_a5()` | Generic A5 fallback |

### Routing Precedence

The `A3` sub-patterns (Guardian, Worker, Sentinel, Simplifier, Arbiter, Fixer) MUST appear before the generic `A3*` catch-all in the case statement. Bash case statements use first-match semantics.

---

## 4. Task ID Patterns

Task IDs are used in `blockedBy` dependency chains and state tracking. They follow a consistent naming scheme.

### Linear Phases

| Task ID | Phase | Notes |
|---------|-------|-------|
| `A0-forager-{N}` | A0 | N = 1-based forager index |
| `A0-cartographer` | A0 | Single deep explorer |
| `A0-explore-aggregator` | A0 | blockedBy all foragers + cartographer |
| `A1-architect` | A1 | swarm/pswarm only |
| `A1-architect-{N}` | A1 | sswarm: N = 1,2,3 |
| `A1-plan-arbiter` | A1 | sswarm: blockedBy all architects |
| `A2-blueprint-reviewer` | A2 | swarm/pswarm only |
| `A2-reviewer-{N}` | A2 | sswarm: N = 1,2,3 |
| `A2-review-lead` | A2 | sswarm: blockedBy all reviewers |
| `A5-nurse` | A5 | blockedBy A3-arbiter |
| `A5-drone` | A5 | blockedBy A5-nurse |

### A3 Dynamic Tasks (created after A1 completes)

| Task ID | Agent | Notes |
|---------|-------|-------|
| `A3-worker-{id}` | `ants:worker` | id from A1-tasks.json task descriptors |
| `A3-sentinel-correctness` | `ants:sentinel-correctness` | blockedBy all workers |
| `A3-sentinel-security` | `ants:sentinel-security` | blockedBy all workers |
| `A3-sentinel-perf` | `ants:sentinel-perf` | blockedBy all workers |
| `A3-sentinel-style` | `ants:sentinel-style` | blockedBy all workers |
| `A3-guardian` | `ants:guardian` | blockedBy all workers |
| `A3-simplifier` | `ants:simplifier` | blockedBy all workers |
| `A3-arbiter` | `ants:review-arbiter` | blockedBy all sentinels + guardian + simplifier |
| `A3-review-fixer` | `ants:review-fixer` | optional: blockedBy A3-arbiter |

---

## 5. Teammate Count Recommendations

| Pipeline | Teammates | Rationale |
|----------|-----------|-----------|
| `swarm` | 3 | Linear phases (A0-A5), moderate parallelism at A0 and A3 |
| `sswarm` | 5 | Competing agents at A1 (3 architects) and A2 (3 reviewers) need more concurrency |
| `pswarm` | 3 | Same as swarm per run; persistent multi-run loop |

---

## 6. Preflight Check

Before creating an Agent Team, commands MUST verify the experimental flag is set:

```bash
if [[ "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" != "1" ]]; then
  echo "ERROR: Agent Teams requires CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"
  echo "Set this environment variable before running the swarm command."
  exit 1
fi
```

This check runs in the command template (swarm.md, sswarm.md, pswarm.md) as Step 0.

---

## 7. Agent Teams Signal Flag Protocol

Hooks are shell scripts and CANNOT call Claude tools (TaskCreate, TaskGet, etc.). Dynamic task creation requires a handoff between hooks and the command.

### Protocol

```
1. Hook detects state transition (e.g., A1 complete, A4 verdict clean)
2. Hook sets signal flag in state.json (e.g., needsA3Tasks = true)
3. Hook advances currentPhase and updates phase statuses
4. Command's monitoring loop reads state.json on each cycle
5. Command detects signal flag == true
6. Command calls TaskCreate for the required tasks
7. Command clears the signal flag (e.g., needsA3Tasks = false)
```

### Signal Flag Lifecycle

| Flag | Set By | When | Command Action |
|------|--------|------|----------------|
| `needsA3Tasks` | `handle_a1()` in on-task-completed.sh | A1 plan + A1-tasks.json validated | Call `teams_add_a3_subtasks()`, TaskCreate for each A3 task |
| `needsA5Tasks` | `handle_a3_arbiter()` in on-task-completed.sh | A4 verdict is `clean` (evaluated inline) | Call `teams_create_verdict_tasks()`, TaskCreate for A5-nurse + A5-drone |
| `needsLoopReset` | `handle_a3_arbiter()` in on-task-completed.sh | A4 verdict is `issues_found` + budget not exhausted | Call `teams_create_phase_tasks()` for fresh A1-A4, TaskCreate for each |
| `needsPswarmReset` | `handle_a5()` in on-task-completed.sh | A5 complete in pswarm + `pswarmRun < maxRuns` | Call `teams_create_pswarm_run_tasks()`, TaskCreate for fresh A0-A5 |

### Command Monitoring Loop Pseudocode

```
while status != "complete" AND status != "blocked" AND status != "stopped":
  read state.json
  if needsA3Tasks:
    tasks = teams_add_a3_subtasks(A1-tasks.json)
    for task in tasks: TaskCreate(task)
    clear needsA3Tasks
  if needsA5Tasks:
    tasks = teams_create_verdict_tasks()
    for task in tasks: TaskCreate(task)
    clear needsA5Tasks
  if needsLoopReset:
    tasks = teams_create_phase_tasks() [A1-A4 subset]
    for task in tasks: TaskCreate(task)
    clear needsLoopReset
  if needsPswarmReset:
    tasks = teams_create_pswarm_run_tasks()
    for task in tasks: TaskCreate(task)
    clear needsPswarmReset
  sleep/wait cycle
```

---

## 8. Dependency Chains

### swarm / pswarm Task Graph

```
A0-forager-1 ─────────┐
A0-forager-2 ─────────┤
A0-cartographer ──────┤
                       └─► A0-explore-aggregator ─► A1-architect ─► A2-blueprint-reviewer
                                                                           │
                                    [needsA3Tasks flag triggers TaskCreate] │
                                                                           ▼
                              A3-worker-1 ──────────┐
                              A3-worker-2 ──────────┤
                              A3-worker-N ──────────┤
                                                     └─► A3-sentinel-correctness ──┐
                                                     └─► A3-sentinel-security ─────┤
                                                     └─► A3-sentinel-perf ─────────┤
                                                     └─► A3-sentinel-style ────────┤
                                                     └─► A3-guardian ──────────────┤
                                                     └─► A3-simplifier ────────────┤
                                                                                    └─► A3-arbiter
                                                                                          │
                                          [A4 verdict evaluated inline by handle_a3_arbiter]
                                                                                          │
                                                          [needsA5Tasks or needsLoopReset]│
                                                                                          ▼
                                                                                  A5-nurse ─► A5-drone
```

### sswarm Task Graph (A1 and A2 differ)

```
A0-explore-aggregator ─► A1-architect-1 ──┐
                         A1-architect-2 ──┤
                         A1-architect-3 ──┤
                                           └─► A1-plan-arbiter ─► A2-reviewer-1 ──┐
                                                                   A2-reviewer-2 ──┤
                                                                   A2-reviewer-3 ──┤
                                                                                    └─► A2-review-lead
                                                                                          │
                                                                     [A3-A5 same as swarm]│
```

---

## 9. Output File Paths

Output files follow a strict naming convention within `.agents/tmp/phases/`.

### A0 (not loop-scoped)

| File | Written By |
|------|-----------|
| `.agents/tmp/phases/A0-explore.forager.{N}.tmp` | forager |
| `.agents/tmp/phases/A0-explore.cartographer.tmp` | cartographer |
| `.agents/tmp/phases/A0-explore.md` | explore-aggregator |

### A1-A5 (loop-scoped: `.agents/tmp/phases/loop-{loop}/`)

| File | Written By |
|------|-----------|
| `A1-plan.md` | architect (swarm) or plan-arbiter (sswarm) |
| `A1-tasks.json` | architect (swarm) or plan-arbiter (sswarm) |
| `A1-plan.architect.{N}.tmp` | architect N (sswarm only) |
| `A1-tasks.architect.{N}.tmp` | architect N (sswarm only) |
| `A2-review.json` | blueprint-reviewer (swarm) or review-lead (sswarm) |
| `A2-review.reviewer.{N}.tmp` | reviewer N (sswarm only) |
| `A3-build.json` | worker result aggregation |
| `A3-review.sentinel-correctness.json` | sentinel-correctness |
| `A3-review.sentinel-security.json` | sentinel-security |
| `A3-review.sentinel-perf.json` | sentinel-perf |
| `A3-review.sentinel-style.json` | sentinel-style |
| `A3-quality.json` | review-arbiter |
| `A4-queen-verdict.json` | handle_a3_arbiter() in on-task-completed.sh |
| `A5-docs.json` | nurse |
| `A5-ship.json` | drone |

---

## 10. Cross-Component Reference Index

This section maps which components reference which contracts from this document.

| Component | References |
|-----------|-----------|
| `commands/swarm.md` | State Schema v6, Teammate Count (3), Preflight Check, Signal Flag Protocol, Dependency Chains (swarm) |
| `commands/sswarm.md` | State Schema v6, Teammate Count (5), Preflight Check, Signal Flag Protocol, Dependency Chains (sswarm) |
| `commands/pswarm.md` | State Schema v6, Teammate Count (3), Preflight Check, Signal Flag Protocol, needsPswarmReset |
| `hooks/on-task-completed.sh` | Routing Patterns, Subject Naming, Signal Flags (set side), Output File Paths |
| `hooks/on-teammate-idle.sh` | Task ID Patterns, State Schema v6 (teamCreated), Subject Naming |
| `hooks/lib/teams.sh` | Task ID Patterns, Subject Naming, Dependency Chains, Agent type mapping |
| `hooks/lib/state.sh` | State Schema v6, Migration (v5->v6) |
| `hooks/lib/dag.sh` | taskGraphVersion increment on reset |
