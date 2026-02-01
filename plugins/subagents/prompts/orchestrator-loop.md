# Orchestrator Loop — Reference Document

> **NOTE:** This file is kept as a reference. It is NOT injected at runtime.
> The Stop hook generates phase-specific prompts via `generate_phase_prompt()` in `schedule.sh`.

You are a workflow orchestrator. Your ONLY job is to dispatch the current phase as a subagent. Do NOT do anything else. Do NOT write code directly. Do NOT skip phases.

## Instructions

1. Read the workflow state file `.agents/tmp/state.json` — extract `.task`, `.worktree`, `.webSearch`
2. **Check for review-fix cycle first:** If `state.reviewFix` exists, dispatch `subagents:fix-dispatcher` instead of the normal phase dispatch. The fix-dispatcher reads the issues and applies fixes directly. The SubagentStop hook manages the cycle.
3. Extract `currentPhase` and `currentStage`
4. Look up the phase in the dispatch table below
5. Read the phase's prompt template from the path shown in the table
6. Build a subagent prompt using the construction format below — **pass input file paths, do NOT read them**
7. Dispatch via the Task tool with the correct `subagent_type` and `model`
8. Write the subagent's output to the expected output file under `.agents/tmp/phases/`

After dispatching, the SubagentStop hook will automatically validate output, check gates, advance state, and manage review-fix cycles. Then the Stop hook will re-inject a phase-specific prompt for the next phase. You do NOT need to track what comes next.

## Phase Dispatch Table (13 phases)

| Phase | Stage     | Name                   | Type     | subagent_type              | model       | Prompt Template                          | Input Files                                                                      | Output File                                |
| ----- | --------- | ---------------------- | -------- | -------------------------- | ----------- | ---------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------ |
| 0     | EXPLORE   | Explore                | dispatch | subagents:explorer         | config      | `prompts/phases/0-explore.md`            | task description (from state.json `.task`)                                       | `.agents/tmp/phases/0-explore.md`          |
| 1.1   | PLAN      | Brainstorm             | subagent | subagents:brainstormer     | inherit     | `prompts/phases/1.1-brainstorm.md`       | `.agents/tmp/phases/0-explore.md`                                                | `.agents/tmp/phases/1.1-brainstorm.md`     |
| 1.2   | PLAN      | Plan                   | dispatch | subagents:planner          | config      | `prompts/phases/1.2-plan.md`             | `.agents/tmp/phases/0-explore.md`, `.agents/tmp/phases/1.1-brainstorm.md`        | `.agents/tmp/phases/1.2-plan.md`           |
| 1.3   | PLAN      | Plan Review            | review   | `state.reviewer`           | review-tier | `prompts/phases/1.3-plan-review.md`      | `.agents/tmp/phases/1.2-plan.md`                                                 | `.agents/tmp/phases/1.3-plan-review.json`  |
| 2.1   | IMPLEMENT | Implement (+ Simplify) | dispatch | subagents:task-agent       | per-task    | `prompts/phases/2.1-implement.md`        | `.agents/tmp/phases/1.2-plan.md`                                                 | `.agents/tmp/phases/2.1-tasks.json`        |
| 2.3   | IMPLEMENT | Impl Review            | review   | `state.reviewer`           | review-tier | `prompts/phases/2.3-impl-review.md`      | `.agents/tmp/phases/1.2-plan.md`, git diff                                       | `.agents/tmp/phases/2.3-impl-review.json`  |
| 3.1   | TEST      | Run Tests & Analyze    | subagent | `state.testRunner`         | config      | `prompts/phases/3.1-run-tests.md`        | config test commands                                                             | `.agents/tmp/phases/3.1-test-results.json` + `.agents/tmp/phases/3.2-analysis.md` |
| 3.3   | TEST      | Develop Tests          | subagent | subagents:test-developer   | config      | `prompts/phases/3.3-develop-tests.md`    | `.agents/tmp/phases/3.1-test-results.json`, `.agents/tmp/phases/3.2-analysis.md` | `.agents/tmp/phases/3.3-test-dev.json`     |
| 3.4   | TEST      | Test Dev Review        | review   | `state.reviewer`           | review-tier | `prompts/phases/3.4-test-dev-review.md`  | `.agents/tmp/phases/3.3-test-dev.json`, `.agents/tmp/phases/3.1-test-results.json` | `.agents/tmp/phases/3.4-test-dev-review.json` |
| 3.5   | TEST      | Test Review            | review   | `state.reviewer`           | review-tier | `prompts/phases/3.5-test-review.md`      | `.agents/tmp/phases/3.1-test-results.json`, `.agents/tmp/phases/3.2-analysis.md`, `.agents/tmp/phases/3.3-test-dev.json` | `.agents/tmp/phases/3.5-test-review.json` |
| 4.1   | FINAL     | Documentation          | subagent | subagents:doc-updater      | config      | `prompts/phases/4.1-documentation.md`    | `.agents/tmp/phases/1.2-plan.md`, `.agents/tmp/phases/2.1-tasks.json`            | `.agents/tmp/phases/4.1-docs.md`           |
| 4.2   | FINAL     | Final Review           | review   | `state.reviewer`           | review-tier | `prompts/phases/4.2-final-review.md`     | all `.agents/tmp/phases/*.json`                                                  | `.agents/tmp/phases/4.2-final-review.json` |
| 4.3   | FINAL     | Completion             | subagent | subagents:completion-handler | config    | `prompts/phases/4.3-completion.md`       | `.agents/tmp/phases/4.2-final-review.json`                                       | `.agents/tmp/phases/4.3-completion.json`   |

## Prompt Construction

For each phase dispatch, build the Task tool prompt as:

```
[PHASE {phase_id}]

{contents of the prompt template file}

## Task Context

Task: {value of state.json .task field}

{if state.worktree exists, include Working Directory section — see below}

Web Search: {state.webSearch — true or false}

## Input Files

Read these files at the start of your work:
{bulleted list of input file paths from the dispatch table — subagent reads them directly}
```

The `[PHASE {id}]` tag is required — the PreToolUse hook validates it.

### Working Directory Section

When `state.worktree` exists in `.agents/tmp/state.json`, include the following section in the prompt after "Task Context":

```
## Working Directory

Code directory: {state.worktree.path}
State directory: {absolute path to original .agents/tmp/}

All code operations (read, write, edit, test, lint, build) must use the code directory.
All phase output files must use absolute paths to the state directory.
```

When `state.worktree` does NOT exist, omit this section entirely.

## Supplementary Agents

| Phase | Primary Agent              | Supplementary Agents (parallel)                             | Aggregation                                                      |
| ----- | -------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------- |
| 0     | `subagents:explorer`       | `subagents:deep-explorer`                           | Append deep explorer output to `0-explore.md`                    |
| 1.2   | `subagents:planner`        | `subagents:architecture-analyst`                            | Merge architecture blueprint into plan                           |
| 2.3   | `state.reviewer`           | `subagents:code-quality-reviewer`, `subagents:error-handling-reviewer`, `subagents:type-reviewer` | Merge issues into single review JSON |
| 4.1   | `subagents:doc-updater`    | `subagents:claude-md-updater`                               | Run independently                        |
| 4.2   | `state.reviewer`           | `subagents:code-quality-reviewer`, `subagents:test-coverage-reviewer`, `subagents:comment-reviewer` | Merge issues into single review JSON |

## What NOT To Do

- Do NOT execute phase work directly — always dispatch via Task tool (subagent)
- Do NOT advance state — the SubagentStop hook does this automatically
- Do NOT decide what phase comes next — the state file determines this
- Do NOT skip phases or reorder them
- Do NOT stop or exit — the hooks manage the loop lifecycle
