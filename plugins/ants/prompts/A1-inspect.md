# [PHASE A1 — SUB-PHASE] Inspector — Plan Triage

Dispatch the **inspector** agent after the architect writes the plan to evaluate complexity and risk, then either auto-approve or flag for human review.

## Agent

- **inspector** (`ants:inspector`) x 1 — automated plan triage
- **Model:** haiku (fast evaluation)

The inspector runs as a **sub-phase within A1**, after the architect writes `A1-plan.md` and `A1-tasks.json`, and before A1 is marked complete. This is NOT a separate phase — it uses marker files (`.inspector.dispatched` / `.inspector.done`) within the A1 dispatch flow.

## Dispatch Timing

The inspector is dispatched when:
1. The architect's task completes successfully (plan + tasks files exist)
2. The `.inspector.dispatched` marker does not yet exist

If the inspector has already been dispatched (marker exists), skip dispatch.

## Inspector Dispatch Template

```
You are the colony's inspector. Evaluate the architect's plan for complexity and risk.

Task: {{TASK}}

Read the plan and task descriptors:
- .agents/tmp/phases/loop-{{LOOP}}/A1-plan.md
- .agents/tmp/phases/loop-{{LOOP}}/A1-tasks.json

Evaluate the plan against these auto-approval criteria:
1. Task count <= 15
2. Max dependency depth <= 4
3. No circular dependencies
4. All tasks have acceptance criteria
5. All tasks have files_owned
6. No high-risk file patterns (auth, security, hooks/*.sh, state.sh, circuit-breaker.sh)
7. No overlapping file ownership between tasks

If ALL criteria pass: decision = "approved"
If ANY criterion fails: decision = "needs_review"

Output file: .agents/tmp/phases/loop-{{LOOP}}/A1-inspection.json

After writing A1-inspection.json, use SendMessage to notify the team.
Write the file FIRST, then send the message. Files are the source of truth.

SendMessage recipient: "team"
For approved: "Plan inspection complete. Decision: APPROVED (confidence: [N]/10, risk: [N]/10). [task_count] tasks, depth [N]."
For flagged: "Plan inspection complete. Decision: NEEDS REVIEW (confidence: [N]/10, risk: [N]/10). [task_count] tasks. Flags: [concerns]."
```

## Output Path

- `.agents/tmp/phases/loop-{{LOOP}}/A1-inspection.json`

## Expected Output Structure

```json
{
  "decision": "approved|needs_review",
  "confidence": 8,
  "risk_score": 3,
  "task_count": 7,
  "max_dependency_depth": 2,
  "high_risk_files": [],
  "overlapping_ownership": [],
  "missing_acceptance_criteria": [],
  "missing_files_owned": [],
  "circular_dependencies": false,
  "reasons": ["reason 1", "reason 2"]
}
```

## Gate

The TaskCompleted hook reads `A1-inspection.json` and acts on the `decision` field:

- **`"approved"`**: Sets `planApproved = true` in state.json. The workflow advances to A2 without waiting for manual approval.
- **`"needs_review"`**: Leaves `planApproved = false`. The workflow holds at A1 until the user manually sets `planApproved = true`.

If the inspector fails or times out, the workflow falls back to the existing behavior: `planApproved = false`, requiring manual approval.

## Next Phase

After the inspector completes (or times out), A1 is marked complete and the workflow advances to A2 (Blueprint Review). The inspector's auto-approval only skips the manual gate — the blueprint-reviewer always runs.
