# fdispatch — Fast Dispatch Pipeline

**Date:** 2026-02-02
**Status:** Design
**Plugin:** subagents

## Overview

`fdispatch` is a faster alternative to the standard `dispatch` workflow that collapses 13 phases into 4 phases by combining related stages into single agents and eliminating sequential bottlenecks.

**Standard dispatch:** 13 phases across 5 stages (EXPLORE → PLAN → IMPLEMENT → TEST → FINAL)
**Fast dispatch:** 5 phases across 4 stages (PLAN → IMPLEMENT → REVIEW → COMPLETE)

## Commands

```
/subagents:fdispatch <task>         # Codex MCP defaults
/subagents:fdispatch-claude <task>  # Claude-only mode
```

**Supported flags:**
- `--no-worktree` — skip git worktree creation
- `--no-web-search` — disable library search

No `--stage`, `--plan`, `--profile`, or `--no-test` flags. Fixed structure for speed.

## Phase Structure

```
Phase F1   │ PLAN      │ Explore + Brainstorm + Write Plan  │ single opus agent
Phase F2   │ IMPLEMENT │ Parallel Implement + Test           │ multi-agent dispatch
Phase F3   │ REVIEW    │ Parallel Specialized Review         │ multi-agent dispatch
           │           │ (fix cycle runs within F3 if needed)│
Phase F4   │ COMPLETE  │ Git Commit + PR                     │ single agent (completion-handler)
```

## Gates

```
PLAN → IMPLEMENT:    requires f1-plan.md
IMPLEMENT → REVIEW:  requires f2-tasks.json
REVIEW → COMPLETE:   requires f3-review.json (no HIGH issues, or max fix iterations hit)
COMPLETE → DONE:     requires f4-completion.json
```

## Phase Details

### F1: Combined Explore + Brainstorm + Plan

**Agent:** `fast-planner.md` (opus model)
**Tools:** Read, Glob, Grep, Write, Bash, WebSearch

Single agent that:
1. **Explores** — reads codebase structure, finds relevant files
2. **Brainstorms** — synthesizes 2-3 approaches, selects best with rationale
3. **Plans** — produces structured implementation plan with task breakdown

**Output:** `f1-plan.md`
```markdown
## Codebase Analysis
[Brief analysis of relevant code]

## Approach
[Chosen approach with rationale]

## Tasks
| ID | Description | Files | Complexity | Dependencies |
|----|-------------|-------|------------|--------------|
| 1  | ...         | ...   | easy       | none         |
| 2  | ...         | ...   | medium     | 1            |
```

**Replaces:** Phase 0 (explore batch + aggregator) + Phase 1.1 (brainstormer) + Phase 1.2 (planner batch + aggregator) + Phase 1.3 (plan review)

### F2: Parallel Implement + Test

**Agents:** Complexity-routed task agents (same as current Phase 2.1)
- Easy (1 file, <50 LOC) → `sonnet-task-agent`
- Medium (2-3 files) → `opus-task-agent`
- Hard (4+ files) → `codex-task-agent` (Codex) / `opus-task-agent` (Claude)

Each task agent:
1. Reads relevant source files
2. Implements changes
3. Writes unit tests alongside
4. Runs tests to verify

**Execution:** Wave-based — independent tasks run in parallel, dependent tasks wait.

**Output:** `f2-tasks.json`
```json
{
  "tasks": [
    {
      "id": 1,
      "status": "completed",
      "filesModified": ["src/foo.ts"],
      "testsWritten": ["src/foo.test.ts"],
      "testsPassed": true
    }
  ],
  "summary": { "total": 3, "completed": 3, "failed": 0 }
}
```

**Replaces:** Phase 2.1 (task execution) + Phase 3.1-3.5 (test stages) — tests are written inline by each task agent.

### F3: Parallel Specialized Review

**Agents (all dispatched in parallel):**
1. `code-quality-reviewer` — bugs, logic errors, style violations
2. `error-handling-reviewer` — silent failures, swallowed errors
3. `type-reviewer` — type design quality (typed languages only)
4. `test-coverage-reviewer` — test completeness and edge cases
5. `comment-reviewer` — comment accuracy and maintainability

Each reviewer writes results to a temp file. The orchestrator aggregates into `f3-review.json`.

**Output:** `f3-review.json`
```json
{
  "issues": [
    { "severity": "HIGH", "category": "code-quality", "file": "src/foo.ts", "line": 42, "description": "..." },
    { "severity": "MEDIUM", "category": "error-handling", "file": "src/bar.ts", "line": 15, "description": "..." }
  ],
  "pass": false,
  "summary": { "high": 1, "medium": 1, "low": 0 }
}
```

**Replaces:** Phase 2.3 (implementation review) + Phase 4.2 (final review). All specialized reviewers run once, in parallel.

### Fix Cycle (within F3)

When F3 review finds HIGH or MEDIUM issues, the review-fix cycle runs within F3:
1. `fix-dispatcher` reads issues from `state.reviewFix`
2. Applies fixes directly (Edit/Write tools)
3. F3 re-runs for re-review

**Max iterations:** 3 (`reviewPolicy.maxFixAttempts`). After that, proceed to F4 with warnings logged.

### F4: Completion

**Agent:** `completion-handler` (existing)

1. Git add + commit with co-author line
2. Push to remote
3. Create PR (if worktree mode)

**Output:** `f4-completion.json`

## State Schema

```json
{
  "version": 2,
  "plugin": "subagents",
  "pipeline": "fdispatch",
  "task": "<description>",
  "status": "in_progress",
  "codexAvailable": true,
  "ownerPpid": "<session PID>",
  "schedule": [
    { "phase": "F1", "stage": "PLAN", "name": "Fast Plan", "type": "subagent" },
    { "phase": "F2", "stage": "IMPLEMENT", "name": "Implement + Test", "type": "dispatch" },
    { "phase": "F3", "stage": "REVIEW", "name": "Parallel Review", "type": "dispatch" },
    { "phase": "F4", "stage": "COMPLETE", "name": "Completion", "type": "subagent" }
  ],
  "gates": {
    "PLAN->IMPLEMENT": { "required": ["f1-plan.md"], "phase": "F1" },
    "IMPLEMENT->REVIEW": { "required": ["f2-tasks.json"], "phase": "F2" },
    "REVIEW->COMPLETE": { "required": ["f3-review.json"], "phase": "F3" },
    "COMPLETE->DONE": { "required": ["f4-completion.json"], "phase": "F4" }
  },
  "fixCycle": { "iteration": 0, "maxIterations": 3 },
  "currentPhase": "F1",
  "currentStage": "PLAN",
  "stages": {
    "PLAN": { "status": "pending" },
    "IMPLEMENT": { "status": "pending" },
    "REVIEW": { "status": "pending" },
    "COMPLETE": { "status": "pending" }
  },
  "files": {},
  "startedAt": "<ISO timestamp>",
  "updatedAt": null
}
```

The `pipeline: "fdispatch"` field distinguishes from regular dispatch state.

## Hook Compatibility

Reuses existing hooks with targeted additions:

### `hooks/lib/schedule.sh`
Add `generate_phase_prompt()` cases for F-prefixed phases:
- `F1` → read task, instruct fast-planner agent dispatch
- `F2` → read f1-plan.md, parse tasks, dispatch implementation agents
- `F3` → read f2-tasks.json, dispatch parallel reviewer agents (fix cycle runs within F3)
- `F4` → dispatch completion-handler

### `hooks/on-subagent-stop.sh`
Add F3 review-fix cycle handling:
- After F3: check if issues found → start fix cycle within F3 (same as standard review phases)
- Fix-dispatcher runs, then F3 re-dispatches for re-review
- After max iterations (3): advance to F4 with warnings

### `hooks/on-stop.sh`
No changes needed — delegates to `generate_phase_prompt()` which handles F-phases.

### `gates.sh`
No changes needed — reads gates from state.json dynamically.

## Files to Create

| File | Purpose |
|------|---------|
| `commands/fdispatch.md` | Codex MCP fast dispatch command |
| `commands/fdispatch-claude.md` | Claude-only fast dispatch command |
| `agents/fast-planner.md` | Combined explore+brainstorm+plan agent (opus) |
| `prompts/phases/f1-fast-plan.md` | F1 phase prompt template |
| `prompts/phases/f2-implement-test.md` | F2 phase prompt template |
| `prompts/phases/f3-parallel-review.md` | F3 phase prompt template |
| `prompts/phases/f4-completion.md` | F4 completion prompt template |

## Files to Modify

| File | Change |
|------|--------|
| `hooks/lib/schedule.sh` | Add `generate_phase_prompt()` cases for F-phases |
| `hooks/on-subagent-stop.sh` | Add F3 review-fix cycle condition |
| `hooks/on-task-dispatch.sh` | Add F2, F3 to batch phase allowlist |
| `.claude-plugin/plugin.json` | Version bump |

## Agents Reused (No Changes)

- `sonnet-task-agent.md`, `opus-task-agent.md`, `codex-task-agent.md` — implementation
- `code-quality-reviewer.md`, `error-handling-reviewer.md`, `type-reviewer.md`, `test-coverage-reviewer.md`, `comment-reviewer.md` — review
- `fix-dispatcher.md` — fix cycle
- `completion-handler.md` — git operations

## Comparison

| Aspect | Standard dispatch | Fast dispatch |
|--------|-------------------|---------------|
| Phases | 13 (standard profile) | 5 |
| Explore | Parallel batch + aggregator | Inline in F1 agent |
| Planning | Brainstorm → parallel planners → aggregator → review | Single opus agent |
| Implementation | Wave dispatch → review | Wave dispatch (with inline tests) |
| Testing | Separate stage (4 phases) | Inline per task agent |
| Review | Per-stage reviews + final | Single parallel review pass |
| Fix cycles | 10 per review × 3 restarts | 3 iterations max |
| Completion | Doc update + final review + commit | Commit only |
| Documentation | Dedicated phase | Skipped |
