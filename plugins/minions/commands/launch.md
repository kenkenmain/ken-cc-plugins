---
name: minions:launch
description: Launch a 4-phase development workflow with personality-driven agents and loop-back issue resolution
argument-hint: <task description>
---

# Minions Launch

You are launching a 4-phase development workflow with personality-driven agents.

## Arguments

- `<task description>`: Required. The task to execute.

Parse from $ARGUMENTS to extract the task description.

## Pipeline

```
F1 (scout) → F2 (builder) → F3 (critic ∥ pedant ∥ witness)
     ↑                              │
     └──────── if any issues ───────┘
               (max 10 loops)

All clean → F4 (shipper)
Loop 10 hit → stop and report
```

## Step 1: Initialize State

Create directories and write state file inline. No init agent needed.

### 1a. Create directories

```bash
mkdir -p .agents/tmp/phases
rm -f .agents/tmp/phases/*.tmp
```

### 1b. Capture session PID

```bash
echo $PPID
```

Store the output as `ownerPpid`.

### 1c. Write state.json

Write `.agents/tmp/state.json` with the following structure. Use Bash with jq for atomic write (write to tmp file, then mv):

```json
{
  "version": 1,
  "plugin": "minions",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "F1",
  "loop": 1,
  "maxLoops": 10,
  "ownerPpid": "<PPID value>",
  "schedule": [
    { "phase": "F1", "name": "Scout", "type": "subagent" },
    { "phase": "F2", "name": "Build", "type": "dispatch" },
    { "phase": "F3", "name": "Review", "type": "dispatch" },
    { "phase": "F4", "name": "Ship", "type": "subagent" }
  ],
  "loops": [
    {
      "loop": 1,
      "startedAt": "<ISO timestamp>",
      "f1": { "status": "pending" },
      "f2": { "status": "pending" },
      "f3": { "status": "pending" }
    }
  ],
  "files": [],
  "failure": null
}
```

## Step 2: Display Schedule

Show the user the planned execution:

```
Minions Launch — 4-Phase Workflow
====================================
Phase F1  │ Scout    │ Explore + brainstorm + plan       │ subagent
Phase F2  │ Build    │ Implement tasks (parallel)         │ dispatch
Phase F3  │ Review   │ critic ∥ pedant ∥ witness          │ dispatch
Phase F4  │ Ship     │ Docs + commit + PR                 │ subagent

Loop: F1 → F2 → F3 (if issues, back to F1, max 10 loops)

Gates:
  F1 → F2:  requires f1-plan.md
  F2 → F3:  requires f2-tasks.json
  F3 → F4:  requires f3-verdict.json with verdict: clean
```

## Step 3: Initialize Task List

Create tasks for progress tracking:

1. **TaskCreate:** "Execute F1: Scout" (activeForm: "Scouting codebase")
2. **TaskCreate:** "Execute F2: Build" (activeForm: "Building implementation")
3. **TaskCreate:** "Execute F3: Review" (activeForm: "Reviewing implementation")
4. **TaskCreate:** "Execute F4: Ship" (activeForm: "Shipping implementation")

Set dependencies: F2 blocked by F1, F3 blocked by F2, F4 blocked by F3.

## Step 4: Dispatch F1 (Scout)

Create the loop directory and dispatch scout:

```bash
mkdir -p .agents/tmp/phases/loop-1
```

Dispatch the **scout** agent (subagent_type: `minions:scout`) with the task description.

Scout must write its plan to `.agents/tmp/phases/loop-1/f1-plan.md`.

After scout completes, the Stop hook (`on-stop.sh`) drives the orchestrator to dispatch F2, then F3, and handles loop-back automatically.

## Loop Behavior

- After F3, if any reviewer reports `issues_found`, the workflow loops back to F1
- Scout re-plans based on the previous loop's F3 outputs (targeted fixes, not full re-plan)
- Builders implement the fix plan
- Reviewers verify again
- This continues until F3 is clean or loop 10 is reached
- At loop 10 with issues: workflow stops, reports remaining issues to user

## Phase Agent Mapping

| Phase | Agent | subagent_type |
|-------|-------|---------------|
| F1 | scout | `minions:scout` |
| F2 | builder (per task) | `minions:builder` |
| F3 | critic | `minions:critic` |
| F3 | pedant | `minions:pedant` |
| F3 | witness | `minions:witness` |
| F4 | shipper | `minions:shipper` |
