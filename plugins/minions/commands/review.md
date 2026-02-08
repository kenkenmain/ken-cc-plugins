---
name: minions:review
description: Launch a review-fix iteration workflow that reviews code, fixes all issues (LOW/MEDIUM/HIGH), and iterates up to 5 times with early termination when review finds zero issues
argument-hint: <task description>
---

# Minions Review

You are launching a review-fix iteration workflow. It dispatches 5 parallel review agents, then a fixer agent that resolves all reported issues (critical, warning, info), and repeats until clean or max iterations reached.

## Arguments

- `<task description>`: Required. The scope to review and fix.

Parse from `$ARGUMENTS` to extract the task description.

## Pipeline

```
R1 (5x reviewers, parallel) --> R2 (review-fixer)
        ^                            |
        +---- next iteration --------+
               (max 5 iterations)

R1 clean (0 issues) --> DONE
Iteration 5 with issues --> STOPPED
```

## Step 1: Initialize State

### 1a. Create directories

```bash
mkdir -p .agents/tmp/phases
rm -rf .agents/tmp/phases
mkdir -p .agents/tmp/phases/review-1
```

### 1b. Branch policy

The review pipeline does not create a feature branch. It reviews and fixes code in the current working directory on the current branch.

### 1c. Write state.json

Write `.agents/tmp/state.json` atomically with jq (`tmp` + `mv`). Generate:

- `ownerPpid` from `$PPID`
- `sessionId` from `head -c 8 /dev/urandom | xxd -p`

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "review",
  "status": "in_progress",
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "currentPhase": "R1",
  "iteration": 1,
  "maxIterations": 5,
  "ownerPpid": "<PPID value>",
  "sessionId": "<sessionId value>",
  "schedule": [
    { "phase": "R1", "name": "Review", "type": "dispatch" },
    { "phase": "R2", "name": "Fix", "type": "subagent" }
  ],
  "iterations": [
    {
      "iteration": 1,
      "startedAt": "<ISO timestamp>",
      "r1": { "status": "pending" },
      "r2": { "status": "pending" },
      "verdict": null
    }
  ],
  "files": [],
  "failure": null
}
```

## Step 2: Display Schedule

Show the user:

```
Minions Review -- Review-Fix Iteration Workflow
================================================
Phase R1  | Review  | critic || pedant || witness || sec || silent | dispatch (parallel)
Phase R2  | Fix     | review-fixer                                | subagent

Loop: R1 -> R2 -> R1 (max 5 iterations)
Early termination: R1 finds 0 issues at any severity

Severity policy: ALL issues fixed (critical, warning, info)
```

## Step 3: Initialize Task List

Create progress tasks:

1. `Execute R1: Review` (activeForm: `Reviewing code`)
2. `Execute R2: Fix` (activeForm: `Fixing issues`)

Set dependency: R2 blocked by R1.

## Step 4: Dispatch R1 (Review)

Dispatch these 5 agents IN PARALLEL with Task tool:

1. `critic` (`subagent_type: minions:critic`) -- correctness, bugs, security
2. `pedant` (`subagent_type: minions:pedant`) -- quality, style, complexity
3. `witness` (`subagent_type: minions:witness`) -- runtime verification
4. `security-reviewer` (`subagent_type: minions:security-reviewer`) -- deep security review
5. `silent-failure-hunter` (`subagent_type: minions:silent-failure-hunter`) -- silent failure analysis

Each reviewer receives:

- The task description
- The instruction to write output to `.agents/tmp/phases/review-1/r1-{agent-name}.json`
- The review schema with `summary.verdict` and structured `issues[]`

Expected output shape per reviewer:

```json
{
  "summary": {
    "verdict": "clean|issues_found",
    "critical": 0,
    "warning": 0,
    "info": 0
  },
  "issues": [
    {
      "severity": "critical|warning|info",
      "category": "string",
      "file": "path/to/file",
      "line": 42,
      "description": "what is wrong",
      "evidence": "code evidence",
      "suggestion": "how to fix"
    }
  ]
}
```

After all 5 complete, `on-subagent-stop-review.sh` aggregates verdicts and advances state. Then `on-stop-review.sh` injects the next orchestrator prompt.

## Phase Agent Mapping

| Phase | Agent | subagent_type |
| ----- | ----- | ------------- |
| R1 | critic | `minions:critic` |
| R1 | pedant | `minions:pedant` |
| R1 | witness | `minions:witness` |
| R1 | security-reviewer | `minions:security-reviewer` |
| R1 | silent-failure-hunter | `minions:silent-failure-hunter` |
| R2 | review-fixer | `minions:review-fixer` |
