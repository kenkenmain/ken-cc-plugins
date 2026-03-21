# [PHASE A5 — SUB-PHASE] Chronicle — Workflow Retrospective

Dispatch the **chronicler** agent after the drone ships to capture workflow metrics, learnings, and recommendations.

## Agent

- **chronicler** (`ants:chronicler`) x 1 — post-ship workflow learning capture
- **Model:** sonnet

The chronicler runs as a **sub-phase within A5**, after the drone writes `A5-ship.json` and before A5 is marked complete. This is NOT a separate phase — it uses marker files (`.chronicler.dispatched` / `.chronicler.done`) within the A5 dispatch flow.

## Dispatch Timing

The chronicler is dispatched when:
1. The drone's task completes successfully (`A5-ship.json` with `commit_sha` exists)
2. The `.chronicler.dispatched` marker does not yet exist

If the chronicler has already been dispatched (marker exists), skip dispatch.

## Chronicler Dispatch Template

```
You are the colony's chronicler. Capture workflow metrics, learnings, and recommendations from this run.

Task: {{TASK}}

Read all available workflow artifacts:

Global:
- .agents/tmp/phases/A0-explore.md (exploration report)
- .agents/tmp/phases/A0-strategy.md (strategy analysis, if exists)
- .agents/tmp/state.json (workflow state: loop count, circuit breaker, pipeline)

Per loop (use Glob to discover: .agents/tmp/phases/loop-*/):
- loop-{N}/A1-plan.md (architect plan)
- loop-{N}/A1-tasks.json (task descriptors)
- loop-{N}/A1-inspection.json (inspector triage, if exists)
- loop-{N}/A2-review.json (blueprint review)
- loop-{N}/A3-review.sentinel-*.json (sentinel findings)
- loop-{N}/A3-quality.json (arbiter verdict)
- loop-{N}/A4-queen-verdict.json (ship/loop verdict)
- loop-{N}/A5-ship.json (ship result)

Extract metrics, identify patterns, and write actionable recommendations.

Output file: .agents/tmp/phases/A5-chronicle.md

After writing A5-chronicle.md, use SendMessage to notify the team.
Write the file FIRST, then send the message. Files are the source of truth.

SendMessage recipient: "team"
Message: "Chronicle complete. [N] loops, [N] total issues ([N] critical, [N] warning). Top learning: [summary]. Chronicle at .agents/tmp/phases/A5-chronicle.md"
```

## Output Path

- `.agents/tmp/phases/A5-chronicle.md` — workflow retrospective (top-level, not inside a loop directory)

## Expected Output Structure

```markdown
# Workflow Chronicle

## Run Summary
- Pipeline: [swarm/sswarm/pswarm]
- Task: [brief description]
- Total loops: [N]
- Final verdict: [shipped/blocked]
- Commit: [SHA]

## Metrics

### Task Metrics
| Metric | Value |
|--------|-------|
| Tasks planned | [N] |
| Tasks completed | [N] |

### Issue Metrics
| Sentinel | Critical | Warning | Info | Total |
|----------|----------|---------|------|-------|
| correctness | ... | ... | ... | ... |
| security | ... | ... | ... | ... |
| [etc.] | ... | ... | ... | ... |

### Loop History
| Loop | Tasks | A2 Verdict | Issues | A4 Verdict |
|------|-------|------------|--------|------------|
| 1 | [N] | [approved] | [N] | [ship/loop] |

## Learnings
### [Learning Title]
**Observation:** [what happened]
**Evidence:** [which files/loops/sentinels]
**Implication:** [what it means for future runs]

## Recommendations
| Priority | Recommendation | Evidence |
|----------|---------------|----------|
| high | [action] | [what led to this] |
```

## Gate

No hard gate. Chronicle output is **supplementary, not required**. If the chronicler fails or times out, A5 is marked complete without a chronicle file. The workflow finishes normally — the chronicle is a nice-to-have that improves future runs.

## pswarm Integration

In pswarm mode, the chronicler's output is injected into the next run's A0 exploration context. Future foragers and strategists read the previous run's chronicle to avoid repeating mistakes and build on learnings.

## Next Phase

After the chronicler completes (or times out), A5 is marked complete and the workflow transitions to:
- **swarm/sswarm:** Status set to `"complete"` (DONE)
- **pswarm:** `needsPswarmReset` flag set if `pswarmRun < maxRuns`, creating a fresh A0-A5 task graph
