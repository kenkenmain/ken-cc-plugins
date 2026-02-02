---
description: Launch a multi-phase debugging workflow with parallel exploration, solution proposals, ranking, implementation, review, and documentation
argument-hint: <bug or task description>
allowed-tools: [Bash, Read, Write, Glob, Grep, Task, AskUserQuestion, TaskCreate, TaskUpdate, TaskList]
---

# Debug Workflow

Launch a structured debugging workflow that explores a bug, proposes multiple solutions in parallel, ranks them, implements the best one, reviews the fix, and updates documentation.

## Arguments

- `<bug or task description>`: Required. Description of the bug or issue to debug.

Parse from $ARGUMENTS to extract the task description.

## Pipeline Overview

```
Phase 1: Explore    → 3-5 parallel debug-explorer agents investigate the bug
Phase 2: Propose    → 3-5 parallel solution-proposer agents each propose a fix
Phase 3: Aggregate  → solution-aggregator ranks proposals and selects best
Phase 4: Implement  → debug-implementer applies the selected fix
Phase 5: Review     → debug-reviewer validates the implementation
Phase 6: Document   → debug-doc-updater updates affected documentation
```

All phase outputs are written to `.agents/tmp/debug/`.

## Step 1: Setup

Create the output directory and display the pipeline:

```bash
mkdir -p .agents/tmp/debug
```

Create a TaskCreate for the overall workflow with subject "Debug: {task}" and show the pipeline to the user:

```
Debug Workflow (6 phases)
=========================
Phase 1 │ EXPLORE   │ Parallel bug investigation    │ 3-5 agents
Phase 2 │ PROPOSE   │ Parallel solution proposals   │ 3-5 agents
Phase 3 │ AGGREGATE │ Rank and select best solution │ 1 agent
Phase 4 │ IMPLEMENT │ Apply the selected fix        │ 1 agent
Phase 5 │ REVIEW    │ Validate the implementation   │ 1 agent
Phase 6 │ DOCUMENT  │ Update affected documentation │ 1 agent
```

## Step 2: Phase 1 — Explore

Dispatch 3-5 parallel `subagents:debug-explorer` agents. Generate exploration queries based on the bug description. Each agent investigates a different angle:

- **Agent 1:** Search for the error/symptom in the codebase — find where it manifests
- **Agent 2:** Trace the execution path — follow the code flow around the suspected area
- **Agent 3:** Search for related changes — recent commits, similar patterns, test coverage
- **Additional agents** (if bug is complex): edge cases, dependency analysis, configuration

For each agent, include in the prompt:

```
[DEBUG EXPLORE]

Bug description: {task description}

Exploration query: {specific query for this agent}

Temp output file: .agents/tmp/debug/explore.debug-explorer.{n}.tmp
```

Dispatch all explore agents in parallel using multiple Task tool calls in a single message. Use `model: "sonnet"` for each.

After all agents complete, read all `.agents/tmp/debug/explore.debug-explorer.*.tmp` files and concatenate them into `.agents/tmp/debug/1-explore.md`:

```markdown
# Phase 1: Debug Exploration

## Bug Description
{task description}

{concatenated findings from all explorer agents}
```

Write this file using the Write tool.

## Step 3: Phase 2 — Propose Solutions

Read `.agents/tmp/debug/1-explore.md` to understand the findings.

Dispatch 3-5 parallel `subagents:solution-proposer` agents. Each agent proposes a different solution approach:

- **Agent 1:** Minimal fix — smallest change that addresses the root cause
- **Agent 2:** Comprehensive fix — addresses root cause plus related edge cases
- **Agent 3:** Defensive fix — adds validation, error handling, and safety checks
- **Additional agents** (if warranted): refactor approach, alternative algorithm, etc.

For each agent, include in the prompt:

```
[DEBUG PROPOSE]

Bug description: {task description}

Exploration findings:
{contents of 1-explore.md}

Approach: {specific angle for this agent, e.g., "propose a minimal fix"}

Temp output file: .agents/tmp/debug/propose.solution-proposer.{n}.tmp
```

Dispatch all propose agents in parallel. Use `model: "sonnet"` for each.

## Step 4: Phase 3 — Aggregate and Rank

Dispatch a single `subagents:solution-aggregator` agent. Include in the prompt:

```
[DEBUG AGGREGATE]

Bug description: {task description}

Read all solution proposals from .agents/tmp/debug/propose.solution-proposer.*.tmp

Write the ranked analysis to: .agents/tmp/debug/3-solutions.md
```

Use `model: "opus"` for the aggregator.

After the agent completes, read `.agents/tmp/debug/3-solutions.md` and display a summary to the user showing the ranked solutions. Use AskUserQuestion to confirm the recommended solution or let the user pick a different one.

## Step 5: Phase 4 — Implement

Dispatch a single `subagents:debug-implementer` agent. Include in the prompt:

```
[DEBUG IMPLEMENT]

Bug description: {task description}

Solution analysis (read this file): .agents/tmp/debug/3-solutions.md

Write implementation results to: .agents/tmp/debug/4-implementation.json
```

Use `model: "opus"` for the implementer.

After the agent completes, read `.agents/tmp/debug/4-implementation.json` and display a summary of changes.

## Step 6: Phase 5 — Review

Dispatch a single `subagents:debug-reviewer` agent. Include in the prompt:

```
[DEBUG REVIEW]

Bug description: {task description}

Solution analysis: .agents/tmp/debug/3-solutions.md
Implementation results: .agents/tmp/debug/4-implementation.json

Read the modified files listed in the implementation results and review them.

Write review results to: .agents/tmp/debug/5-review.json
```

Use the default model (inherit) for the reviewer.

After the agent completes, read `.agents/tmp/debug/5-review.json`.

- If `status: "approved"`: proceed to Phase 6
- If `status: "needs_revision"` with HIGH issues: display issues to user and ask whether to retry implementation or stop
- If `status: "needs_revision"` with only MEDIUM/LOW issues: proceed to Phase 6 with a note

## Step 7: Phase 6 — Document

Dispatch a single `subagents:debug-doc-updater` agent. Include in the prompt:

```
[DEBUG DOCUMENT]

Bug description: {task description}

Solution analysis: .agents/tmp/debug/3-solutions.md
Implementation results: .agents/tmp/debug/4-implementation.json

Write documentation update summary to: .agents/tmp/debug/6-docs.md
```

Use the default model (inherit) for the doc updater.

After the agent completes, read `.agents/tmp/debug/6-docs.md` and display the summary.

## Step 8: Complete

Display final summary:

```
Debug Workflow Complete
=======================
Bug: {task description}
Solution: {selected solution title}
Files Modified: {list from implementation}
Tests Written: {count from implementation}
Review: {approved/needs_revision}
Docs Updated: {list or "none needed"}
```

Mark the task as completed.
