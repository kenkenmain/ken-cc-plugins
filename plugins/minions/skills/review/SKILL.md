---
name: review
description: Review-fix iteration loop -- dispatches review agents then review-fixer, iterating up to 5 times with early termination on zero issues
---

# Review-Fix Iteration Loop

Dispatch 5 parallel review agents, aggregate their findings, then dispatch a fixer agent to resolve ALL issues (including info-level). Iterate up to 5 times. Early termination happens only when the review phase finds zero issues across all reviewers.

## Execution Flow (Ralph-Style)

The review pipeline follows the same Ralph Loop pattern used by other minions workflows.

```
Orchestrator dispatches R1 (5 parallel review agents)
  |
Each reviewer writes to .agents/tmp/phases/review-{N}/r1-{agent}.json
  |
SubagentStop hook fires:
  - waits for all 5 outputs
  - validates JSON
  - aggregates into r1-verdict.json
  - clean (0 issues) => currentPhase = DONE
  - issues + iteration < max => currentPhase = R2
  - issues + iteration == max => currentPhase = STOPPED
  |
Stop hook fires:
  - R1 => inject review-dispatch prompt
  - R2 => inject fixer-dispatch prompt
  - DONE/STOPPED => allow stop
  |
review-fixer agent runs in R2:
  - reads all r1-*.json files for current iteration
  - applies targeted fixes for critical/warning/info
  - writes r2-fix-summary.md
  |
SubagentStop hook fires for review-fixer:
  - marks R2 complete
  - increments iteration
  - creates next review-{N+1} directory
  - sets currentPhase = R1
  |
Repeat until DONE or STOPPED
```

### Key Design: Separation Of Concerns

- `on-subagent-stop-review.sh` handles side-effects only (validate output, aggregate verdicts, advance state).
- `on-stop-review.sh` handles prompt reinjection only (phase-specific orchestrator instructions).
- Orchestrator remains stateless and always reads `.agents/tmp/state.json`.

## Phase Dispatch Mapping

| Phase | subagent_type | model | Notes |
| ----- | ------------- | ----- | ----- |
| R1 | `minions:critic`, `minions:pedant`, `minions:witness`, `minions:security-reviewer`, `minions:silent-failure-hunter` | inherit | Parallel review batch |
| R2 | `minions:review-fixer` | inherit | Single write-enabled fixer |

## Phase Details

### R1 -- Review Phase

- Dispatches 5 review agents in parallel.
- Agents are read-only (`Read`, `Glob`, `Grep`, `Bash`; no `Edit`/`Write`/`Task`).
- Each agent writes structured JSON to `.agents/tmp/phases/review-{iteration}/r1-{agent}.json`.
- Output schema includes:
  - `issues[]` with `severity`, `category`, `file`, `line`, `description`, `evidence`, `suggestion`
  - `summary` with `critical`, `warning`, `info`, `verdict`
- `on-subagent-stop-review.sh` aggregates all 5 into `r1-verdict.json`.
- Any issue at any severity triggers R2.

### R2 -- Fix Phase

- Dispatches `minions:review-fixer`.
- Agent is write-enabled (`Read`, `Write`, `Edit`, `Glob`, `Grep`, `Bash`; no `Task`).
- Reads all current iteration `r1-*.json` review outputs.
- Applies targeted fixes for critical, warning, and info issues.
- Writes a summary to `.agents/tmp/phases/review-{iteration}/r2-fix-summary.md`.
- Hooks manage state transitions; agent only fixes and reports.

## State Schema (Review Pipeline)

```json
{
  "plugin": "minions",
  "pipeline": "review",
  "status": "in_progress",
  "task": "<description>",
  "ownerPpid": "<session pid>",
  "sessionId": "<session id>",
  "iteration": 1,
  "maxIterations": 5,
  "currentPhase": "R1",
  "startedAt": "<ISO timestamp>",
  "updatedAt": "<ISO timestamp>",
  "iterations": [
    {
      "iteration": 1,
      "startedAt": "<ISO timestamp>",
      "r1": { "status": "pending" },
      "r2": { "status": "pending" },
      "verdict": null
    }
  ]
}
```

Field highlights:

- `pipeline: "review"` enables review-specific hook delegation.
- `iteration` and `maxIterations` control bounded looping.
- `currentPhase` drives dispatch (`R1`, `R2`, `DONE`, `STOPPED`).
- `iterations[]` keeps per-iteration status and audit history.

## State Flow

```
R1 (review) --[0 issues]-----------------> DONE
R1 (review) --[issues, iter < max]-------> R2 (fix) -> iteration++ -> R1
R1 (review) --[issues, iter == max]------> STOPPED
```

## Output File Layout

```
.agents/tmp/phases/
  review-1/
    r1-critic.json
    r1-pedant.json
    r1-witness.json
    r1-security-reviewer.json
    r1-silent-failure-hunter.json
    r1-verdict.json
    r2-fix-summary.md
  review-2/
    ...
```

## Prompt Construction

- R1 prompt instructs 5 parallel reviewers and target output paths.
- R2 prompt instructs `review-fixer` to read all current `r1-*.json` files and fix every issue.
- Prompts include `[PHASE R1]` / `[PHASE R2]` tags for phase clarity in orchestration output.

## Key Design Decisions

- All severities must be fixed; no severity threshold gating.
- Reuses existing launch reviewers to avoid duplicated reviewer agents.
- Adds one new fixer agent only (`review-fixer`).
- Keeps pipeline intentionally simple: review, fix, repeat.
- Uses per-iteration directories for clean auditability and replay/debugging.

## Error Handling

- If reviewer output is missing or invalid, SubagentStop exits with code 2 and blocks progression.
- If reviewer verdict fields are malformed, fail-safe defaults force `issues_found`.
- If fixer introduces regressions, the next R1 pass catches them.
- Loop is bounded by `maxIterations` (default: 5), then transitions to `STOPPED`.

## What This Skill Does NOT Do

- Verdict aggregation (hook: `on-subagent-stop-review.sh`).
- State updates and phase progression (hook: `on-subagent-stop-review.sh`).
- Stop interception and prompt reinjection (hook: `on-stop-review.sh`).
- Task dispatch validation (hook: `on-task-gate-review.sh`).
- Edit permission gating (hook: `on-edit-gate-review.sh`).

## Integration Points

- `on-stop.sh` delegates to `on-stop-review.sh` when `pipeline == "review"`.
- `on-subagent-stop.sh` delegates to `on-subagent-stop-review.sh` when `pipeline == "review"`.
- `on-task-gate.sh` delegates to `on-task-gate-review.sh` when `pipeline == "review"`.
- `on-edit-gate.sh` delegates to `on-edit-gate-review.sh` when `pipeline == "review"`.
- `/minions:review` initializes review state and starts R1.
