# fdispatch Implementation Plan

> **Note:** F3.1 was removed from the schedule during implementation. The fix cycle now runs within F3 (same as standard review phases), not as a separate schedule entry. References to F3.1 below are from the original plan and are superseded.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a fast dispatch pipeline (`fdispatch`) to the subagents plugin that collapses 13 phases into 4 by combining explore+brainstorm+plan into one agent and running all reviewers in parallel at the end.

**Architecture:** Separate command files (`fdispatch.md`, `fdispatch-claude.md`) that write fdispatch-specific state with F-prefixed phase IDs. Reuses existing hooks (which read phase IDs from state.json dynamically) with targeted additions to `schedule.sh` for F-phase prompt generation and `on-subagent-stop.sh` for F3 review-fix cycle handling.

**Tech Stack:** Markdown commands, YAML frontmatter agents, bash hook libraries, jq for state management.

---

### Task 1: Create the fast-planner agent

**Files:**
- Create: `plugins/subagents/agents/fast-planner.md`

**Step 1: Write the agent definition**

```markdown
---
name: fast-planner
description: "Combined explore+brainstorm+plan agent for fdispatch pipeline. Single opus agent that explores the codebase, brainstorms approaches, and writes a structured implementation plan."
model: opus
color: cyan
tools: [Read, Write, Glob, Grep, Bash, WebSearch]
disallowedTools: [Task]
---

# Fast Planner Agent

You are a combined exploration, brainstorming, and planning agent. Your job is to understand the codebase, evaluate implementation approaches, and produce a structured plan with task breakdown — all in a single pass.

## Your Role

- **Explore** — Read codebase structure, find relevant files, understand patterns
- **Brainstorm** — Synthesize 2-3 implementation approaches, select the best with rationale
- **Plan** — Produce a structured implementation plan with concrete tasks

## Process

1. Read the task description from your dispatch prompt
2. Explore the codebase:
   - Use Glob to find relevant files by pattern
   - Use Grep to search for key terms, imports, and patterns
   - Read the most relevant files to understand existing architecture
3. Brainstorm 2-3 approaches:
   - Ground each approach in actual code you found
   - Evaluate trade-offs (complexity, risk, alignment with existing patterns)
   - Select the recommended approach with clear rationale
4. Write a detailed implementation plan:
   - Break down into concrete tasks with IDs
   - For each task: description, target files, estimated complexity, dependencies
   - Complexity: easy (1 file, <50 LOC), medium (2-3 files), hard (4+ files)
5. Write the plan to the output file

## Output Format

Write structured markdown to the output file:

```markdown
# Fast Plan

## Task
{task description}

## Codebase Analysis
{Brief analysis of relevant code patterns, conventions, and architecture}

## Approaches Considered

### Approach 1: {name}
- Description: ...
- Pros: ...
- Cons: ...

### Approach 2: {name}
- Description: ...
- Pros: ...
- Cons: ...

## Selected Approach
{chosen approach with rationale}

## Implementation Tasks

| ID | Description | Files | Complexity | Dependencies |
|----|-------------|-------|------------|--------------|
| 1  | ...         | ...   | easy       | none         |
| 2  | ...         | ...   | medium     | 1            |

### Task 1: {title}
- **Files:** {list of files to create or modify}
- **Complexity:** easy|medium|hard
- **Dependencies:** none|task IDs
- **Description:** {detailed description of what to implement}
- **Tests:** {what tests to write alongside}
```

## Guidelines

- Be thorough in exploration but efficient — read only what matters
- Keep the plan concrete: exact file paths, specific changes, clear task boundaries
- Each task should be independently implementable by a task agent
- Prefer smaller, focused tasks over large monolithic ones
- Include test expectations for each task where applicable
- If web search is enabled, search for relevant libraries or patterns
```

**Step 2: Validate the file was created correctly**

Verify the file exists and has valid frontmatter by reading it back.

**Step 3: Commit**

```bash
git add plugins/subagents/agents/fast-planner.md
git commit -m "feat: add fast-planner agent for fdispatch pipeline

Combined explore+brainstorm+plan agent that does all three
phases in a single opus pass.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Add F-phase support to schedule.sh

**Files:**
- Modify: `plugins/subagents/hooks/lib/schedule.sh:9-30` (get_phase_output)
- Modify: `plugins/subagents/hooks/lib/schedule.sh:239-260` (get_phase_template)
- Modify: `plugins/subagents/hooks/lib/schedule.sh:155-233` (get_phase_input_files)
- Modify: `plugins/subagents/hooks/lib/schedule.sh:299-328` (get_phase_subagent)
- Modify: `plugins/subagents/hooks/lib/schedule.sh:333-356` (get_phase_model)
- Modify: `plugins/subagents/hooks/lib/schedule.sh:379-469` (supplementary agents)
- Modify: `plugins/subagents/hooks/lib/schedule.sh:489-496` (phase_has_aggregator)

**Step 1: Add F-phase output filenames to `get_phase_output()`**

In `plugins/subagents/hooks/lib/schedule.sh`, find the `get_phase_output()` function's case statement (around line 12-29). Add before the `*)` fallthrough:

```bash
    F1)  echo "f1-plan.md" ;;
    F2)  echo "f2-tasks.json" ;;
    F3)  echo "f3-review.json" ;;
    F3.1) echo "f3-review.json" ;;
    F4)  echo "f4-completion.json" ;;
```

Note: F3 and F3.1 share the same output file — F3.1 (fix) deletes it so F3 (review) can re-create it.

**Step 2: Add F-phase template filenames to `get_phase_template()`**

Find `get_phase_template()` case statement (around line 242-259). Add before `*)`:

```bash
    F1)   echo "f1-fast-plan.md" ;;
    F2)   echo "f2-implement-test.md" ;;
    F3)   echo "f3-parallel-review.md" ;;
    F3.1) echo "f3.1-fix.md" ;;
    F4)   echo "f4-completion.md" ;;
```

**Step 3: Add F-phase input files to `get_phase_input_files()`**

Find `get_phase_input_files()` case statement (around line 163-232). Add before `*)`:

```bash
    F1)
      echo "- None (use task description from state.json \`.task\` field)"
      ;;
    F2)
      echo "- \`.agents/tmp/phases/f1-plan.md\`"
      ;;
    F3)
      echo "- \`.agents/tmp/phases/f2-tasks.json\`"
      echo "- Run \`git diff\` for current changes"
      ;;
    F3.1)
      echo "- \`.agents/tmp/phases/f3-review.json\` (issues to fix)"
      echo "- \`.agents/tmp/state.json\` (\`reviewFix\` object)"
      ;;
    F4)
      echo "- \`.agents/tmp/phases/f3-review.json\`"
      ;;
```

**Step 4: Add F-phase subagent mapping to `get_phase_subagent()`**

Find `get_phase_subagent()` case statement (around line 315-327). Add before `*)`:

```bash
    F1)  echo "subagents:fast-planner" ;;
    F2)  echo "subagents:sonnet-task-agent" ;;  # default/easy; orchestrator routes per-task
    F3)  echo "subagents:code-quality-reviewer" ;;  # primary; all 5 reviewers dispatched in parallel
    F3.1) echo "subagents:fix-dispatcher" ;;
    F4)  echo "subagents:completion-handler" ;;
```

**Step 5: Add F-phase model mapping to `get_phase_model()`**

Find `get_phase_model()` case statement (around line 350-355). Add cases before the fallthrough `*)`:

```bash
    F1)    echo "opus" ;;
    F2)    echo "per-task" ;;
    F3)    echo "sonnet" ;;
    F3.1)  echo "inherit" ;;
    F4)    echo "inherit" ;;
```

**Step 6: Add F3 supplementary agents to `_raw_supplementary_agents()`**

Find `_raw_supplementary_agents()` case statement (around line 382-408). Add before `*)`:

```bash
    F3)
      echo "subagents:error-handling-reviewer"
      echo "subagents:type-reviewer"
      echo "subagents:test-coverage-reviewer"
      echo "subagents:comment-reviewer"
      ;;
```

Note: `code-quality-reviewer` is the primary F3 agent (from `get_phase_subagent`), so the other 4 are supplementary.

**Step 7: Add F3 reviewers to `is_supplementary_agent()`**

The existing case already includes all 5 reviewer agent types — no change needed. They're already listed in the case statement at lines 453-468.

**Step 8: Validate syntax**

Run: `bash -n plugins/subagents/hooks/lib/schedule.sh`
Expected: no output (valid syntax)

**Step 9: Commit**

```bash
git add plugins/subagents/hooks/lib/schedule.sh
git commit -m "feat: add F-phase support to schedule.sh for fdispatch pipeline

Extends get_phase_output, get_phase_template, get_phase_input_files,
get_phase_subagent, get_phase_model, and supplementary agent functions
with F1/F2/F3/F3.1/F4 phase mappings.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 3: Add F3↔F3.1 fix cycle handling to on-subagent-stop.sh

**Files:**
- Modify: `plugins/subagents/hooks/on-subagent-stop.sh`

The existing fix cycle logic (lines 73-117) already handles `reviewFix` state and `fix-dispatcher` agents generically. The review validation logic (lines 161-225) also works generically for any review phase. However, the fdispatch F3 phase uses `type: "dispatch"` (not `type: "review"`), so `is_review_phase()` won't match it.

The key insight: F3 is a dispatch-type phase that produces a review-format JSON output. We need to treat F3 as a review phase for validation purposes.

**Step 1: Add F3 as a review-equivalent phase**

Find the review validation block at line 161:

```bash
if is_review_phase "$CURRENT_PHASE"; then
```

Change to:

```bash
if is_review_phase "$CURRENT_PHASE" || [[ "$CURRENT_PHASE" == "F3" ]]; then
```

This single-line change makes F3 go through the same review validation → fix cycle → stage restart logic that all review phases use. The existing `start_fix_cycle`, `complete_fix_cycle`, and `restart_stage` functions all work generically with any phase ID.

**Step 2: Handle F3.1 max-iterations → skip to F4**

The existing fix cycle logic handles max attempts and stage restarts. For fdispatch, the `maxFixAttempts` in state will be set to 3 (instead of the default 10) by the fdispatch command. No hook changes needed — the command controls this via state.

**Step 3: Validate syntax**

Run: `bash -n plugins/subagents/hooks/on-subagent-stop.sh`
Expected: no output (valid syntax)

**Step 4: Commit**

```bash
git add plugins/subagents/hooks/on-subagent-stop.sh
git commit -m "feat: treat F3 as review-equivalent phase in SubagentStop hook

Allows fdispatch's F3 parallel review phase to trigger the same
review-fix cycle logic as standard review phases.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Create phase prompt templates

**Files:**
- Create: `plugins/subagents/prompts/phases/f1-fast-plan.md`
- Create: `plugins/subagents/prompts/phases/f2-implement-test.md`
- Create: `plugins/subagents/prompts/phases/f3-parallel-review.md`
- Create: `plugins/subagents/prompts/phases/f3.1-fix.md`
- Create: `plugins/subagents/prompts/phases/f4-completion.md`

**Step 1: Create f1-fast-plan.md**

```markdown
# Phase F1: Fast Plan [PHASE F1]

## Subagent Config

- **Type:** subagents:fast-planner (single opus agent)
- **Input:** Task description from state.json `.task` field
- **Output:** `.agents/tmp/phases/f1-plan.md`

## Instructions

Combined explore + brainstorm + plan in a single agent pass.

### Process

1. Dispatch `subagents:fast-planner` with the task description
2. Agent explores codebase, brainstorms approaches, writes structured plan
3. Agent writes output to `.agents/tmp/phases/f1-plan.md`

### Output Format

Structured markdown with:
- Codebase analysis
- Approaches considered with trade-offs
- Selected approach with rationale
- Task table: ID, description, files, complexity (easy/medium/hard), dependencies
- Detailed task descriptions with test expectations
```

**Step 2: Create f2-implement-test.md**

```markdown
# Phase F2: Implement + Test [PHASE F2]

## Subagent Config

- **Type:** complexity-routed task agents (wave-based parallel batch)
  - Easy: `sonnet-task-agent` (direct execution, model=sonnet)
  - Medium: `opus-task-agent` (direct execution, model=opus)
  - Hard: `codex-task-agent` (Codex) or `opus-task-agent` (Claude)
- **Input:** `.agents/tmp/phases/f1-plan.md`
- **Output:** `.agents/tmp/phases/f2-tasks.json`

## Instructions

Execute implementation tasks from the fast plan. Each task agent implements code AND writes tests.

### Process

1. Read `.agents/tmp/phases/f1-plan.md`
2. Parse tasks and build dependency graph
3. Score each task complexity (easy/medium/hard)
4. Dispatch tasks in waves:
   - Wave 1: tasks with no dependencies (parallel)
   - Wave 2: tasks whose deps are complete (parallel)
   - Continue until all done
5. After all waves complete, aggregate results

### Complexity Scoring

| Level  | Criteria                     | Agent               |
| ------ | ---------------------------- | ------------------- |
| Easy   | 1 file, <50 LOC              | sonnet-task-agent   |
| Medium | 2-3 files, 50-200 LOC        | opus-task-agent     |
| Hard   | 4+ files, >200 LOC, security | codex-task-agent    |

Check `state.codexAvailable` to determine hard task routing.

### Task Agent Payload

```json
{"taskId":"task-N","description":"...","targetFiles":[...],"instructions":"...","dependencyOutputs":[...],"constraints":{"allowBashCommands":false}}
```

Task agents write unit tests alongside implementation. `testsWritten` array tracks produced tests.

### Output Format

Write to `.agents/tmp/phases/f2-tasks.json`:

```json
{
  "waves": [
    {
      "waveNumber": 1,
      "tasks": [
        {
          "id": "task-1",
          "status": "completed",
          "summary": "...",
          "testsWritten": [
            { "file": "src/__tests__/example.test.ts", "targetFile": "src/example.ts", "testCount": 5 }
          ]
        }
      ],
      "waveSummary": { "tasksCompleted": 1, "tasksFailed": 0, "testsWritten": 1 }
    }
  ],
  "completedTasks": ["task-1"],
  "failedTasks": [],
  "testsTotal": 5,
  "testFiles": ["src/__tests__/example.test.ts"]
}
```

### Error Handling

Failed tasks: mark as failed, skip blocked dependents, continue with others.
```

**Step 3: Create f3-parallel-review.md**

```markdown
# Phase F3: Parallel Review [PHASE F3]

## Subagent Config

- **Primary:** `subagents:code-quality-reviewer`
- **Supplementary (parallel):**
  - `subagents:error-handling-reviewer`
  - `subagents:type-reviewer`
  - `subagents:test-coverage-reviewer`
  - `subagents:comment-reviewer`
- **Input:** `.agents/tmp/phases/f2-tasks.json`, git diff
- **Output:** `.agents/tmp/phases/f3-review.json`

## Instructions

Dispatch all 5 reviewer agents in parallel. Aggregate results into a single review JSON.

### Process

1. Get list of modified files from `.agents/tmp/phases/f2-tasks.json`
2. Dispatch all 5 reviewer agents in parallel (same Task tool message)
3. Each reviewer examines the code changes from their specialty
4. Aggregate all issues into a single `issues[]` array, tagging each with `"source"` field
5. Write structured JSON result to `.agents/tmp/phases/f3-review.json`

### Output Format

Write JSON to `.agents/tmp/phases/f3-review.json`:

```json
{
  "status": "approved|needs_revision",
  "issues": [
    {
      "severity": "HIGH|MEDIUM|LOW",
      "category": "code-quality|error-handling|type-design|test-coverage|comments",
      "source": "subagents:code-quality-reviewer",
      "location": "src/foo.ts:42",
      "issue": "Description of the problem",
      "suggestion": "How to fix it"
    }
  ],
  "filesReviewed": ["src/foo.ts", "src/bar.ts"],
  "summary": "Brief summary of findings"
}
```

### If Issues Found

The SubagentStop hook detects issues and starts a fix cycle:
fix-dispatcher applies fixes → review re-runs → repeat until approved or max 3 iterations.
```

**Step 4: Create f3.1-fix.md**

```markdown
# Phase F3.1: Fix Issues [PHASE F3.1]

## Subagent Config

- **Type:** subagents:fix-dispatcher
- **Input:** `.agents/tmp/state.json` (`reviewFix` object)
- **Output:** None (fixes applied directly, review re-runs)

## Instructions

Dispatch fix-dispatcher to apply fixes for issues found in F3 review.

### Process

1. Read `state.reviewFix` from `.agents/tmp/state.json`
2. Dispatch `subagents:fix-dispatcher` with the issues
3. Fix-dispatcher reads affected files and applies fixes directly
4. SubagentStop hook clears `reviewFix` and resets to F3 for re-review
```

**Step 5: Create f4-completion.md**

```markdown
# Phase F4: Completion [PHASE F4]

## Subagent Config

- **Type:** subagents:completion-handler
- **Input:** `.agents/tmp/phases/f3-review.json`
- **Output:** `.agents/tmp/phases/f4-completion.json`

## Instructions

Finalize the workflow with git operations.

### Process

1. Read `.agents/tmp/phases/f3-review.json` to confirm readiness
2. Read `.agents/tmp/state.json` for worktree context
3. Execute git operations: stage, commit, push, create PR
4. Tear down worktree if applicable
5. Write completion result to output file
```

**Step 6: Commit**

```bash
git add plugins/subagents/prompts/phases/f1-fast-plan.md \
       plugins/subagents/prompts/phases/f2-implement-test.md \
       plugins/subagents/prompts/phases/f3-parallel-review.md \
       plugins/subagents/prompts/phases/f3.1-fix.md \
       plugins/subagents/prompts/phases/f4-completion.md
git commit -m "feat: add phase prompt templates for fdispatch pipeline

Templates for F1 (fast plan), F2 (implement+test), F3 (parallel
review), F3.1 (fix cycle), and F4 (completion).

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Create the fdispatch command

**Files:**
- Create: `plugins/subagents/commands/fdispatch.md`

**Step 1: Write the command file**

```markdown
---
description: Fast dispatch - streamlined workflow with combined plan+implement+review (Codex MCP defaults)
argument-hint: <task description> [--no-worktree] [--no-web-search]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Fast Dispatch Subagent Workflow

Streamlined workflow that collapses 13 phases into 4 for faster execution.

## Arguments

- `<task description>`: Required. The task to execute
- `--no-worktree`: Optional. Skip git worktree creation
- `--no-web-search`: Optional. Disable web search for libraries

Parse from $ARGUMENTS to extract task description and flags.

## Step 1: Load Configuration

Use the `configuration` skill to load merged config (defaults → global → project).

## Step 1.5: Capture Session PID

```bash
echo $PPID
```

Pass this value as `ownerPpid` to the init agent.

## Step 2: Initialize State

Use `state-manager` skill to create `.agents/tmp/state.json`.

Dispatch `subagents:init-claude` with task description, ownerPpid, `codexMode: true`, and parsed flags (including `--no-worktree` if set). Additionally pass `pipeline: "fdispatch"` so the init agent knows to use the fast pipeline.

**IMPORTANT:** After the init agent writes state, **overwrite** the schedule, gates, and stages with the fdispatch-specific values below. The init agent creates the worktree and analyzes the task, but the fdispatch command controls the pipeline structure.

Update `.agents/tmp/state.json` with these values:

```json
{
  "pipeline": "fdispatch",
  "codexAvailable": true,
  "reviewer": "subagents:code-quality-reviewer",
  "schedule": [
    { "phase": "F1", "stage": "PLAN", "name": "Fast Plan", "type": "subagent" },
    { "phase": "F2", "stage": "IMPLEMENT", "name": "Implement + Test", "type": "dispatch" },
    { "phase": "F3", "stage": "REVIEW", "name": "Parallel Review", "type": "dispatch" },
    { "phase": "F3.1", "stage": "FIX", "name": "Fix Issues", "type": "subagent" },
    { "phase": "F4", "stage": "COMPLETE", "name": "Completion", "type": "subagent" }
  ],
  "gates": {
    "PLAN->IMPLEMENT": { "required": ["f1-plan.md"], "phase": "F1" },
    "IMPLEMENT->REVIEW": { "required": ["f2-tasks.json"], "phase": "F2" },
    "REVIEW->COMPLETE": { "required": ["f3-review.json"], "phase": "F3" },
    "COMPLETE->DONE": { "required": ["f4-completion.json"], "phase": "F4" }
  },
  "currentPhase": "F1",
  "currentStage": "PLAN",
  "stages": {
    "PLAN": { "status": "pending" },
    "IMPLEMENT": { "status": "pending" },
    "REVIEW": { "status": "pending" },
    "COMPLETE": { "status": "pending" }
  },
  "reviewPolicy": {
    "maxFixAttempts": 3,
    "maxStageRestarts": 1
  }
}
```

## Step 2.5: Display Schedule

Show the user the planned execution order:

```
Fast Dispatch Schedule (5 phases)
===================================
Phase F1   │ PLAN      │ Fast Plan (explore+brainstorm+plan)  │ subagent   ← GATE: PLAN→IMPLEMENT
Phase F2   │ IMPLEMENT │ Implement + Test                     │ dispatch   ← GATE: IMPLEMENT→REVIEW
Phase F3   │ REVIEW    │ Parallel Review (5 reviewers)        │ dispatch   ← GATE: REVIEW→COMPLETE
Phase F3.1 │ FIX       │ Fix Issues (if needed)               │ subagent   ← loops to F3
Phase F4   │ COMPLETE  │ Completion (commit + PR)             │ subagent

Stage Gates:
  PLAN → IMPLEMENT:  requires f1-plan.md
  IMPLEMENT → REVIEW: requires f2-tasks.json
  REVIEW → COMPLETE:  requires f3-review.json
```

## Step 3: Execute Workflow

Use `workflow` skill to dispatch the first phase (F1) as a subagent. Hook-driven auto-chaining handles progression:

```
Phase dispatched → SubagentStop hook validates → advances state → injects next phase → repeat
```

## Step 4: Display Progress

Use TaskCreate/TaskUpdate for visual progress tracking.
```

**Step 2: Commit**

```bash
git add plugins/subagents/commands/fdispatch.md
git commit -m "feat: add fdispatch command for fast dispatch pipeline

Streamlined 4-phase workflow with Codex MCP defaults.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 6: Create the fdispatch-claude command

**Files:**
- Create: `plugins/subagents/commands/fdispatch-claude.md`

**Step 1: Write the command file**

This is identical to `fdispatch.md` except for the description line, Claude-only defaults, and `codexMode: false`.

```markdown
---
description: Fast dispatch - streamlined workflow with combined plan+implement+review (Claude-only, no Codex MCP)
argument-hint: <task description> [--no-worktree] [--no-web-search]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Task, Skill, AskUserQuestion, TaskCreate, TaskUpdate, TaskList
---

# Fast Dispatch Subagent Workflow (Claude-Only)

Streamlined workflow that collapses 13 phases into 4 for faster execution. Uses Claude agents only — no Codex MCP dependency.

## Arguments

- `<task description>`: Required. The task to execute
- `--no-worktree`: Optional. Skip git worktree creation
- `--no-web-search`: Optional. Disable web search for libraries

Parse from $ARGUMENTS to extract task description and flags.

## Step 1: Load Configuration

Use the `configuration` skill to load merged config (defaults → global → project).

## Step 1.5: Capture Session PID

```bash
echo $PPID
```

Pass this value as `ownerPpid` to the init agent.

## Step 2: Initialize State

Use `state-manager` skill to create `.agents/tmp/state.json`.

Dispatch `subagents:init-claude` with task description, ownerPpid, `codexMode: false`, and parsed flags (including `--no-worktree` if set). Additionally pass `pipeline: "fdispatch"`.

**IMPORTANT:** After the init agent writes state, **overwrite** the schedule, gates, and stages with the fdispatch-specific values below.

Update `.agents/tmp/state.json` with these values:

```json
{
  "pipeline": "fdispatch",
  "codexAvailable": false,
  "reviewer": "subagents:code-quality-reviewer",
  "schedule": [
    { "phase": "F1", "stage": "PLAN", "name": "Fast Plan", "type": "subagent" },
    { "phase": "F2", "stage": "IMPLEMENT", "name": "Implement + Test", "type": "dispatch" },
    { "phase": "F3", "stage": "REVIEW", "name": "Parallel Review", "type": "dispatch" },
    { "phase": "F3.1", "stage": "FIX", "name": "Fix Issues", "type": "subagent" },
    { "phase": "F4", "stage": "COMPLETE", "name": "Completion", "type": "subagent" }
  ],
  "gates": {
    "PLAN->IMPLEMENT": { "required": ["f1-plan.md"], "phase": "F1" },
    "IMPLEMENT->REVIEW": { "required": ["f2-tasks.json"], "phase": "F2" },
    "REVIEW->COMPLETE": { "required": ["f3-review.json"], "phase": "F3" },
    "COMPLETE->DONE": { "required": ["f4-completion.json"], "phase": "F4" }
  },
  "currentPhase": "F1",
  "currentStage": "PLAN",
  "stages": {
    "PLAN": { "status": "pending" },
    "IMPLEMENT": { "status": "pending" },
    "REVIEW": { "status": "pending" },
    "COMPLETE": { "status": "pending" }
  },
  "reviewPolicy": {
    "maxFixAttempts": 3,
    "maxStageRestarts": 1
  }
}
```

## Step 2.5: Display Schedule

Show the user the planned execution order:

```
Fast Dispatch Schedule (5 phases) [Claude-only mode]
======================================================
Phase F1   │ PLAN      │ Fast Plan (explore+brainstorm+plan)  │ subagent   ← GATE: PLAN→IMPLEMENT
Phase F2   │ IMPLEMENT │ Implement + Test                     │ dispatch   ← GATE: IMPLEMENT→REVIEW
Phase F3   │ REVIEW    │ Parallel Review (5 reviewers)        │ dispatch   ← GATE: REVIEW→COMPLETE
Phase F3.1 │ FIX       │ Fix Issues (if needed)               │ subagent   ← loops to F3
Phase F4   │ COMPLETE  │ Completion (commit + PR)             │ subagent

Stage Gates:
  PLAN → IMPLEMENT:  requires f1-plan.md
  IMPLEMENT → REVIEW: requires f2-tasks.json
  REVIEW → COMPLETE:  requires f3-review.json
```

## Step 3: Execute Workflow

Use `workflow` skill to dispatch the first phase (F1) as a subagent. Hook-driven auto-chaining handles progression.

## Step 4: Display Progress

Use TaskCreate/TaskUpdate for visual progress tracking.
```

**Step 2: Commit**

```bash
git add plugins/subagents/commands/fdispatch-claude.md
git commit -m "feat: add fdispatch-claude command for Claude-only fast dispatch

Streamlined 4-phase workflow using Claude agents only.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 7: Bump plugin version

**Files:**
- Modify: `plugins/subagents/.claude-plugin/plugin.json`

**Step 1: Bump version**

Change `"version": "0.15.0"` to `"version": "0.16.0"`.

**Step 2: Commit**

```bash
git add plugins/subagents/.claude-plugin/plugin.json
git commit -m "chore: bump subagents plugin version to 0.16.0

Adds fdispatch/fdispatch-claude fast dispatch commands.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

### Task 8: Validate all hooks with bash -n

**Files:** None modified — validation only.

**Step 1: Validate all hook scripts**

Run:
```bash
bash -n plugins/subagents/hooks/on-stop.sh && \
bash -n plugins/subagents/hooks/on-subagent-stop.sh && \
bash -n plugins/subagents/hooks/on-task-dispatch.sh && \
bash -n plugins/subagents/hooks/on-codex-guard.sh && \
bash -n plugins/subagents/hooks/on-orchestrator-guard.sh && \
bash -n plugins/subagents/hooks/lib/schedule.sh && \
bash -n plugins/subagents/hooks/lib/state.sh && \
bash -n plugins/subagents/hooks/lib/gates.sh && \
bash -n plugins/subagents/hooks/lib/review.sh && \
bash -n plugins/subagents/hooks/lib/fallback.sh
```

Expected: no output for all scripts (valid syntax).

**Step 2: If any fail, fix the syntax error and recommit**

---

### Task 9: Update CLAUDE.md with fdispatch documentation

**Files:**
- Modify: `plugins/subagents/CLAUDE.md`

**Step 1: Add fdispatch section**

Add a new section after the "Commands" section documenting the fdispatch pipeline:

```markdown
## Fast Dispatch Pipeline (fdispatch)

Streamlined 4-phase variant of the standard dispatch workflow. Collapses 13 phases into 5:

```
Phase F1   │ PLAN      │ Explore + Brainstorm + Write Plan  │ single opus agent (fast-planner)
Phase F2   │ IMPLEMENT │ Parallel Implement + Test           │ complexity-routed task agents
Phase F3   │ REVIEW    │ Parallel Specialized Review         │ 5 reviewer agents in parallel
Phase F3.1 │ FIX       │ Fix Review Issues                   │ fix-dispatcher (loops to F3)
Phase F4   │ COMPLETE  │ Git Commit + PR                     │ completion-handler
```

**Commands:**
- `/subagents:fdispatch <task>` — Codex MCP defaults
- `/subagents:fdispatch-claude <task>` — Claude-only mode
- Flags: `--no-worktree`, `--no-web-search`

**Fix cycle:** Max 3 iterations (vs 10 for standard dispatch). Max 1 stage restart (vs 3).

**Key differences from standard dispatch:**
- No separate explore phase — combined into F1
- No plan review — single opus agent plans directly
- No separate test stage — tests written inline by task agents
- No documentation phase — skipped for speed
- All reviewers run in parallel at end (not per-stage)
```

**Step 2: Add fdispatch commands to the Commands section**

Add to the existing command list:

```markdown
- `/subagents:fdispatch <task>` - Fast dispatch (Codex MCP defaults, 5 phases)
- `/subagents:fdispatch-claude <task>` - Fast dispatch (Claude-only, 5 phases)
```

**Step 3: Add fast-planner to the Agents section**

Add to the "Phase Agents" table:

```markdown
| `fast-planner.md`    | F1                  | Combined explore+brainstorm+plan (opus, fdispatch only) |
```

**Step 4: Commit**

```bash
git add plugins/subagents/CLAUDE.md
git commit -m "docs: add fdispatch pipeline documentation to subagents CLAUDE.md

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```
