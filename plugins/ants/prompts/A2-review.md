# [PHASE A2] Blueprint Review

Dispatch the **blueprint-reviewer** agent to validate the architect's plan before execution begins.

## Agent

- **Type:** `ants:blueprint-reviewer`
- **Mode:** Single subagent (foreground)
- **Read-only:** Does not modify any files

## Prompt Template

```
You are blueprint-reviewer. Review the architect's implementation plan for completeness, feasibility, and dependency correctness.

Task: {{TASK}}

Plan file: .agents/tmp/phases/loop-{{LOOP}}/A1-plan.md
Review criteria: Read this file's Review Criteria section for guidance.

Review the plan and return structured JSON output.

Write your output to: .agents/tmp/phases/loop-{{LOOP}}/A2-review.json
```

## Review Criteria

The blueprint-reviewer evaluates the plan on four dimensions:

### 1. Completeness
- Every task has all required fields: ID, Description, Files, Complexity, Dependencies, Acceptance Criteria
- Acceptance criteria are measurable and verifiable
- Plan covers the full scope of the original task

### 2. Feasibility
- Referenced files exist or are clearly marked as new
- Complexity estimates are realistic
- Dependencies are satisfiable (no circular references)

### 3. Dependency Correctness
- Foundation tasks (no dependencies) exist so work can start immediately
- Dependency references are valid (reference existing task IDs)
- No circular dependencies
- Enough parallelism (not everything serialized into a single chain)
- No two concurrently-executable tasks touch the same file (would conflict in parallel execution)
- No hidden dependencies not captured in the Dependencies column

### 4. Risk
- Shared state or concurrency-sensitive code is identified
- Security-sensitive operations are flagged
- Integration risks between dependent tasks are noted

## Output

**IMPORTANT:** Use `status` as the top-level verdict field (not `verdict`). The hook validates `.status` as the canonical field. Using `verdict` is a legacy pattern and should not be used in new output.

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
  "dependencySummary": {
    "foundationTasks": 0,
    "dependentTasks": 0,
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
