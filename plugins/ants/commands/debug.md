---
name: ants:debug
description: Launch a 6-phase debug workflow with parallel exploration, solution proposals, ranking, implementation, review, and shipping
argument-hint: <bug description>
---

<HARD-GATE>
You are executing a workflow pipeline. This overrides ALL skill-checking rules including superpowers:using-superpowers. DO NOT invoke brainstorming, writing-plans, or any other skill via the Skill tool. DO NOT ask clarifying questions about the task. DO NOT propose approaches or present designs. Execute the steps below immediately and in order. The bug description from $ARGUMENTS is your input — execute it as a pipeline, do not design or analyze it. Begin with Step 0 now.
</HARD-GATE>

# Ants Debug

You are launching a 6-phase ant-colony debug workflow. You are the orchestrator — you dispatch `ants:*` agents via the Agent tool for each phase, collect results, and drive phase progression. This workflow is STATELESS — no state.json, no hooks needed.

## Arguments

- `<bug description>`: Required. Description of the bug or issue to debug.

Parse from $ARGUMENTS to extract the bug description.

## Pipeline

```
Phase D0  │ EXPLORE     │ Bug Investigation   │ 3 parallel bug-scouts → aggregated findings
Phase D1  │ PROPOSE     │ Solution Proposals   │ 3 parallel solution-proposers (minimal/comprehensive/defensive)
Phase D2  │ AGGREGATE   │ Rank & Select        │ solution-aggregator → user confirmation (AskUserQuestion)
Phase D3  │ IMPLEMENT   │ Apply Fix            │ fix-worker applies selected solution
Phase D4  │ REVIEW      │ Quality Review       │ 3 parallel sentinels → review-arbiter consolidation
Phase D5  │ SHIP        │ Docs + Commit + PR   │ nurse (docs) → drone (commit + PR)
```

## Step 0: Preflight

### 0a. Load deferred tools

```
ToolSearch("select:AskUserQuestion")
```

## Step 1: Setup

Create output directory:

```bash
rm -rf .agents/tmp/debug && mkdir -p .agents/tmp/debug
```

Display pipeline to user:

```
Ants Debug — 6-Phase Pipeline
==========================================
Phase D0  │ EXPLORE   │ Bug Investigation     │ 3 bug-scouts (parallel)
Phase D1  │ PROPOSE   │ Solution Proposals     │ 3 solution-proposers (parallel)
Phase D2  │ AGGREGATE │ Rank & Select          │ solution-aggregator + user confirmation
Phase D3  │ IMPLEMENT │ Apply Fix              │ fix-worker
Phase D4  │ REVIEW    │ Quality Review         │ 3 sentinels + review-arbiter
Phase D5  │ SHIP      │ Docs + Commit + PR     │ nurse + drone
```

## Step 2: D0 EXPLORE

Dispatch **3 parallel bug-scout agents** via the Agent tool:

1. `subagent_type: "ants:bug-scout"` — "Investigate error manifestation: what breaks, error messages, stack traces, failure symptoms for bug: <bug>. Write findings to .agents/tmp/debug/explore.bug-scout.1.tmp"

2. `subagent_type: "ants:bug-scout"` — "Trace execution paths: code flow, call chains, data transformations related to bug: <bug>. Write findings to .agents/tmp/debug/explore.bug-scout.2.tmp"

3. `subagent_type: "ants:bug-scout"` — "Check test coverage and recent changes: existing tests, recent commits, related PRs for bug: <bug>. Write findings to .agents/tmp/debug/explore.bug-scout.3.tmp"

After all 3 return, verify that all 3 temp files exist (`.agents/tmp/debug/explore.bug-scout.1.tmp`, `.agents/tmp/debug/explore.bug-scout.2.tmp`, `.agents/tmp/debug/explore.bug-scout.3.tmp`). If any are missing, warn the user which scouts failed and ask whether to proceed with partial results or abort.

Then read all `.agents/tmp/debug/explore.bug-scout.*.tmp` files and concatenate them into `.agents/tmp/debug/D0-explore.md`:

```markdown
# D0: Bug Exploration

## Bug Description
<bug description>

## Findings
<concatenated findings from all bug-scout agents>
```

Write this file using the Write tool.

## Step 3: D1 PROPOSE

Read `.agents/tmp/debug/D0-explore.md` to understand the findings.

Dispatch **3 parallel solution-proposer agents** via the Agent tool:

1. `subagent_type: "ants:solution-proposer"` — "Propose a MINIMAL fix — smallest change that resolves the bug. Read .agents/tmp/debug/D0-explore.md for context. Write to .agents/tmp/debug/propose.solution-proposer.1.tmp"

2. `subagent_type: "ants:solution-proposer"` — "Propose a COMPREHENSIVE fix — thorough refactor that prevents similar bugs. Read .agents/tmp/debug/D0-explore.md for context. Write to .agents/tmp/debug/propose.solution-proposer.2.tmp"

3. `subagent_type: "ants:solution-proposer"` — "Propose a DEFENSIVE fix — focus on error handling and edge cases. Read .agents/tmp/debug/D0-explore.md for context. Write to .agents/tmp/debug/propose.solution-proposer.3.tmp"

## Step 4: D2 AGGREGATE

Dispatch **1 solution-aggregator agent** via the Agent tool:

- `subagent_type: "ants:solution-aggregator"` — "Read all .agents/tmp/debug/propose.solution-proposer.*.tmp files. Rank proposals on correctness/scope/risk/confidence/testability. Write ranked analysis to .agents/tmp/debug/D2-solutions.md"

After the aggregator completes, read `.agents/tmp/debug/D2-solutions.md` and display the top recommendation to the user.

Then use **AskUserQuestion** to ask:

> The aggregator recommends solution #N. Proceed with this solution, or choose a different one? (Enter number or 'yes' to proceed)

Use the user's response to determine which solution to implement. If the user says "yes" or confirms, proceed with the recommended solution. If the user provides a number, validate it is in range (1-3). If the number is out of range, inform the user of valid choices and re-prompt via AskUserQuestion.

## Step 5: D3 IMPLEMENT

Dispatch **1 fix-worker agent** via the Agent tool:

- `subagent_type: "ants:fix-worker"` — "Implement the selected fix from .agents/tmp/debug/D2-solutions.md. Read the exploration findings at .agents/tmp/debug/D0-explore.md for context. Write implementation results to .agents/tmp/debug/D3-implementation.json"

Include in the prompt which solution number was selected by the user.

## Step 6: D4 REVIEW

Dispatch **3 parallel sentinel agents** via the Agent tool:

1. `subagent_type: "ants:sentinel-correctness"` — "Review all changes from the debug fix for bugs, logic errors, missing error handling. Read .agents/tmp/debug/D3-implementation.json for the list of modified files. IMPORTANT: You are running in the debug pipeline, NOT the swarm pipeline. Ignore any default output paths in your system prompt. Write findings to .agents/tmp/debug/D4-review.sentinel-correctness.json (this path overrides your default A3 path)."

2. `subagent_type: "ants:sentinel-security"` — "Review all changes from the debug fix for security vulnerabilities. Read .agents/tmp/debug/D3-implementation.json for the list of modified files. IMPORTANT: You are running in the debug pipeline, NOT the swarm pipeline. Ignore any default output paths in your system prompt. Write findings to .agents/tmp/debug/D4-review.sentinel-security.json (this path overrides your default A3 path)."

3. `subagent_type: "ants:sentinel-perf"` — "Review all changes from the debug fix for performance issues. Read .agents/tmp/debug/D3-implementation.json for the list of modified files. IMPORTANT: You are running in the debug pipeline, NOT the swarm pipeline. Ignore any default output paths in your system prompt. Write findings to .agents/tmp/debug/D4-review.sentinel-perf.json (this path overrides your default A3 path)."

After all 3 sentinels complete, dispatch **1 review-arbiter agent**:

- `subagent_type: "ants:review-arbiter"` — "Read all sentinel review files at .agents/tmp/debug/D4-review.sentinel-correctness.json, .agents/tmp/debug/D4-review.sentinel-security.json, and .agents/tmp/debug/D4-review.sentinel-perf.json. IMPORTANT: You are running in the debug pipeline, NOT the swarm pipeline. Ignore any default paths in your system prompt. Cross-reference, deduplicate, and produce consolidated verdict. Write to .agents/tmp/debug/D4-quality.json (this path overrides your default A3-quality.json path)."

## Step 7: D5 SHIP

Dispatch **nurse and drone in parallel** via the Agent tool:

1. `subagent_type: "ants:nurse"` — "Review the debug fix implementation at .agents/tmp/debug/D3-implementation.json and update project documentation to reflect the changes. Write summary to .agents/tmp/debug/D5-docs.json"

2. `subagent_type: "ants:drone"` — "Stage all changes from the debug fix, create a git commit with a descriptive message based on .agents/tmp/debug/D3-implementation.json, and open a PR. Write output (commit SHA, PR URL) to .agents/tmp/debug/D5-ship.json"

## Step 8: Display Results

Read `.agents/tmp/debug/D5-ship.json` and display to the user:

```
Ants Debug — Complete
=======================
Bug: <bug description>
Fix: <summary of the selected solution>
Commit: <commit SHA>
PR: <PR URL>
```
