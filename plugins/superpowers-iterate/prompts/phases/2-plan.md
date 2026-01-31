# Phase 2: Plan [PHASE 2]

## Subagent Config

- **Type:** dispatch (parallel planning agents)
- **Input:** `.agents/tmp/iterate/phases/1-brainstorm.md`
- **Output:** `.agents/tmp/iterate/phases/2-plan.md`

## Instructions

Create a detailed implementation plan with bite-sized tasks, each including TDD steps.

### Process

1. Read `.agents/tmp/iterate/phases/1-brainstorm.md`
2. **Launch parallel planning subagents** for independent plan components:
   - Plan core implementation tasks
   - Plan test coverage (TDD approach)
   - Plan integration points and edge cases
   - Plan documentation updates
   - Plan migration/upgrade paths (if applicable)
   - Plan performance considerations (if applicable)
3. Aggregate planning outputs into unified plan
4. Ensure every task follows TDD methodology
5. Order tasks by dependency (wave-based execution plan)
6. Score each task for complexity
7. Write plan to output file

### Task Format

Each task MUST include TDD steps:

1. **Step 1:** Write failing test
2. **Step 2:** Run test to verify it fails
3. **Step 3:** Write minimal implementation
4. **Step 4:** Run test to verify it passes
5. **Step 5:** Commit

Each task should be 2-5 minutes of work with exact file paths and complete code.

### Complexity Scoring

| Level  | Criteria                     | Execution                                  |
| ------ | ---------------------------- | ------------------------------------------ |
| Easy   | 1 file, <50 LOC              | superpowers-iterate:task-agent (sonnet)     |
| Medium | 2-3 files, 50-200 LOC        | superpowers-iterate:task-agent (opus)       |
| Hard   | 4+ files, >200 LOC, security | superpowers-iterate:codex-reviewer (codex)  |

### Wave-Based Execution Plan

Group tasks into dependency-ordered waves:

- **Wave 1:** Tasks with no dependencies (can run in parallel)
- **Wave 2:** Tasks depending on Wave 1 outputs
- **Wave N:** Continue until all tasks are scheduled

### Output Format

Write to `.agents/tmp/iterate/phases/2-plan.md`:

```markdown
# [Feature Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Test Strategy:** [Testing approach and frameworks]

---

## Wave 1: {description}

### Task 1: {name}
- **Complexity:** easy/medium/hard
- **Files:** {exact file paths}
- **Dependencies:** none
- **TDD Steps:**
  1. Write failing test in {test file}
  2. Run test: `{test command}` — expect FAIL
  3. Implement in {source file}
  4. Run test: `{test command}` — expect PASS
  5. Commit: `{commit message}`
- **Acceptance Criteria:**
  - {criterion 1}
  - {criterion 2}

### Task 2: {name}
...

## Wave 2: {description}

### Task 3: {name}
- **Dependencies:** Task 1, Task 2
...

---

## Summary

- **Total tasks:** {count}
- **Easy:** {count} | **Medium:** {count} | **Hard:** {count}
- **Estimated waves:** {count}
```
