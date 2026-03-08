# [PHASE A2] Blueprint Review

Dispatch the **blueprint-reviewer** agent to validate the architect's plan before execution begins.

## Agent

- **Type:** `ants:blueprint-reviewer`
- **Mode:** Single subagent (foreground)
- **Read-only:** Does not modify any files

## Prompt Template

```
You are blueprint-reviewer. Review the architect's implementation plan for completeness, feasibility, and wave correctness.

Task: {{TASK}}

Plan file: .agents/tmp/phases/loop-{{LOOP}}/A1-plan.md
Review criteria: Read this file's Review Criteria section for guidance.

Review the plan and return structured JSON output.

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/A2-review.json
```

## Review Criteria

The blueprint-reviewer evaluates the plan on four dimensions:

### 1. Completeness
- Every task has all required fields: ID, Description, Files, Wave, Complexity, Dependencies, Acceptance Criteria
- Acceptance criteria are measurable and verifiable
- Plan covers the full scope of the original task

### 2. Feasibility
- Referenced files exist or are clearly marked as new
- Complexity estimates are realistic
- Dependencies are satisfiable (no circular references)

### 3. Wave Correctness
- Wave 1 tasks have zero dependencies
- Wave 2 tasks only depend on Wave 1 or earlier Wave 2 tasks
- No two tasks in the same wave touch the same file (would conflict in parallel execution)
- Wave split is balanced (not everything in one wave)
- Dual-track execution is actually possible

### 4. Risk
- Shared state or concurrency-sensitive code is identified
- Security-sensitive operations are flagged
- Integration risks between waves are noted

## Output

File: `.agents/tmp/phases/loop-{{LOOP}}/A2-review.json`

```json
{
  "status": "approved|needs_revision",
  "issues": [
    {
      "severity": "HIGH|MEDIUM|LOW",
      "location": "Task ID or section",
      "issue": "Description",
      "suggestion": "Fix"
    }
  ],
  "waveSummary": {
    "wave1Tasks": 0,
    "wave2Tasks": 0,
    "parallelismScore": "good|fair|poor",
    "notes": "Dual-track readiness assessment"
  },
  "summary": "Overall assessment"
}
```

## Verdict Logic

- **approved** (no HIGH issues): Advance to Phase A3 (Build)
- **needs_revision** (any HIGH issue): Loop back to Phase A1 with review feedback

## Gate

Output required: `.agents/tmp/phases/loop-{{LOOP}}/A2-review.json` with valid `status` field.

Next phase: A3 (Dual-Track Build) -- or A1 if looping back
