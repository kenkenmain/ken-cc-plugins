# [PHASE A4] Synchronize Tracks

Dispatch the **queen** agent to read the arbiter's consolidated quality verdict and the build track results, then render a ship/loop decision.

## Agent

- **Type:** `ants:queen`
- **Mode:** Single subagent (foreground)

## Prerequisites

- A3 (Build Track) must have completed: `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json` exists
- A3 (Quality Track) must have completed: `.agents/tmp/phases/loop-{{LOOP}}/A3-quality.json` exists (arbiter's consolidated verdict)

## Process

1. Read build track output from `.agents/tmp/phases/loop-{{LOOP}}/A3-build.json`
2. Read arbiter's consolidated quality verdict from `.agents/tmp/phases/loop-{{LOOP}}/A3-quality.json`
3. Cross-reference issues against implementation
4. Check circuit breaker state for loop-back feasibility
5. Render verdict: `clean` or `issues_found`
6. Write output to `.agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json`

## Prompt Template

```
You are queen. Synchronize the build and quality track results for loop {{LOOP}}.

Task: {{TASK}}

Read:
- .agents/tmp/phases/loop-{{LOOP}}/A3-build.json (build track output)
- .agents/tmp/phases/loop-{{LOOP}}/A3-quality.json (arbiter's consolidated quality verdict)

The quality verdict was produced by the review-arbiter after consolidating findings
from three specialist sentinels (correctness, security, performance). It contains
deduplicated, cross-referenced issues with severity classifications.

Cross-reference all issues against the implementation. Decide: clean or issues_found.

Circuit breaker context:
- Current loop: {{LOOP}} of {{MAX_LOOPS}}
- Stage restarts so far: {{STAGE_RESTARTS}} of {{MAX_STAGE_RESTARTS}}
- Consecutive failures: {{CONSECUTIVE_FAILURES}} of {{MAX_CONSECUTIVE_FAILURES}}

If recommending issues_found, verify the circuit breaker has budget remaining
for another loop-back. If the budget is exhausted, note this in your verdict
so the orchestrator can block the workflow instead of looping.

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json
```

## Verdict Format

```json
{
  "verdict": "clean|issues_found",
  "loop": 1,
  "buildTrackSummary": {
    "status": "complete",
    "filesChanged": ["src/auth.ts", "src/db.ts"],
    "testsAdded": 3
  },
  "qualityTrackSummary": {
    "verdict": "clean",
    "critical": 0,
    "warning": 1,
    "info": 3
  },
  "circuitBreaker": {
    "loopBudgetRemaining": true,
    "stageRestartsRemaining": 2,
    "consecutiveFailuresRemaining": 5
  },
  "summary": "Build complete. 1 warning (minor naming convention) does not warrant a loop-back.",
  "recommendation": "clean"
}
```

## Decision Rules

| Condition | Verdict | Next Phase |
|-----------|---------|------------|
| Quality clean, build complete | `clean` | A5 (Ship) |
| Only `info` issues, build complete | `clean` | A5 (Ship) |
| Any `critical` or `warning` unresolved | `issues_found` | A1 (Plan) |
| Build track incomplete | `issues_found` | A1 (Plan) |
| Circuit breaker: loop budget exhausted | `issues_found` + `loopBudgetRemaining: false` | Workflow blocks |
| Circuit breaker: stage restarts exhausted | `issues_found` + `stageRestartsRemaining: 0` | Workflow blocks |
| Loop count = max loops | `issues_found` | Workflow blocks with report |

When the circuit breaker indicates no budget remains, the orchestrator (SubagentStop hook) reads `circuitBreaker.loopBudgetRemaining` from the verdict and halts the workflow with `status: "blocked"` instead of looping back to A1.

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/A4-queen-verdict.json` with `verdict: "clean"` to advance.

Next phase: A5 (Ship) if verdict is `clean`, or A1 (Plan) if verdict is `issues_found` and circuit breaker has budget.
