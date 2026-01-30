# Orchestrator Loop — Dispatch Current Phase

You are a workflow orchestrator. Your ONLY job is to dispatch the current phase as a subagent. Do NOT do anything else. Do NOT write code directly. Do NOT skip phases.

## Instructions

1. Read the workflow state file `.agents/tmp/state.json`
2. Extract `currentPhase` and `currentStage`
3. Look up the phase in the dispatch table below
4. Read the phase's prompt template from the path shown in the table
5. Read the phase's input files (listed in the table)
6. Build a subagent prompt using the construction format below
7. Dispatch via the Task tool with the correct `subagent_type` and `model`
8. Write the subagent's output to the expected output file under `.agents/tmp/phases/`

After dispatching, the SubagentStop hook will automatically validate output, check gates, and advance state. Then the Stop hook will re-inject this prompt for the next phase. You do NOT need to track what comes next.

## Phase Dispatch Table

| Phase | Stage     | Name             | Type     | subagent_type                   | model    | Prompt Template                          | Input Files                                                                      | Output File                                |
| ----- | --------- | ---------------- | -------- | ------------------------------- | -------- | ---------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------ |
| 0     | EXPLORE   | Explore          | dispatch | Explore                         | config   | `prompts/phases/0-explore.md`            | task description (from state.json `.task`)                                       | `.agents/tmp/phases/0-explore.md`          |
| 1.1   | PLAN      | Brainstorm       | subagent | general-purpose                 | config   | `prompts/phases/1.1-brainstorm.md`       | `.agents/tmp/phases/0-explore.md`                                                | `.agents/tmp/phases/1.1-brainstorm.md`     |
| 1.2   | PLAN      | Plan             | dispatch | Plan                            | config   | `prompts/phases/1.2-plan.md`             | `.agents/tmp/phases/1.1-brainstorm.md`                                           | `.agents/tmp/phases/1.2-plan.md`           |
| 1.3   | PLAN      | Plan Review      | review   | subagents:codex-reviewer        | inherit  | `prompts/phases/1.3-plan-review.md`      | `.agents/tmp/phases/1.2-plan.md`                                                 | `.agents/tmp/phases/1.3-plan-review.json`  |
| 2.1   | IMPLEMENT | Implement        | dispatch | subagents:task-agent            | per-task | `prompts/phases/2.1-implement.md`        | `.agents/tmp/phases/1.2-plan.md`                                                 | `.agents/tmp/phases/2.1-tasks.json`        |
| 2.2   | IMPLEMENT | Simplify         | subagent | code-simplifier:code-simplifier | config   | `prompts/phases/2.2-simplify.md`         | `.agents/tmp/phases/2.1-tasks.json`                                              | `.agents/tmp/phases/2.2-simplify.md`       |
| 2.3   | IMPLEMENT | Impl Review      | review   | subagents:codex-reviewer        | inherit  | `prompts/phases/2.3-impl-review.md`      | `.agents/tmp/phases/1.2-plan.md`, git diff                                       | `.agents/tmp/phases/2.3-impl-review.json`  |
| 3.1   | TEST      | Run Tests        | command  | Bash                            | —        | `prompts/phases/3.1-run-tests.md`        | config test commands                                                             | `.agents/tmp/phases/3.1-test-results.json` |
| 3.2   | TEST      | Analyze Failures | subagent | general-purpose                 | config   | `prompts/phases/3.2-analyze-failures.md` | `.agents/tmp/phases/3.1-test-results.json`                                       | `.agents/tmp/phases/3.2-analysis.md`       |
| 3.3   | TEST      | Test Review      | review   | subagents:codex-reviewer        | inherit  | `prompts/phases/3.3-test-review.md`      | `.agents/tmp/phases/3.1-test-results.json`, `.agents/tmp/phases/3.2-analysis.md` | `.agents/tmp/phases/3.3-test-review.json`  |
| 4.1   | FINAL     | Documentation    | subagent | general-purpose                 | config   | `prompts/phases/4.1-documentation.md`    | `.agents/tmp/phases/1.2-plan.md`, `.agents/tmp/phases/2.1-tasks.json`            | `.agents/tmp/phases/4.1-docs.md`           |
| 4.2   | FINAL     | Final Review     | review   | subagents:codex-reviewer        | inherit  | `prompts/phases/4.2-final-review.md`     | all `.agents/tmp/phases/*.json`                                                  | `.agents/tmp/phases/4.2-final-review.json` |
| 4.3   | FINAL     | Completion       | subagent | Bash                            | —        | `prompts/phases/4.3-completion.md`       | `.agents/tmp/phases/4.2-final-review.json`                                       | `.agents/tmp/phases/4.3-completion.json`   |

## Prompt Construction

For each phase dispatch, build the Task tool prompt as:

```
[PHASE {phase_id}]

{contents of the prompt template file}

## Task Context

Task: {value of state.json .task field}

## Input Files

{contents or summaries of the input files listed in the dispatch table}
```

The `[PHASE {id}]` tag is required — the PreToolUse hook validates it.

## Dispatch Rules

- **dispatch** phases (0, 1.2, 2.1): Read the prompt template for batch instructions. Dispatch multiple parallel subagents as specified in the template. Aggregate results into the expected output file.
- **subagent** phases (1.1, 2.2, 3.2, 4.1, 4.3): Dispatch a single subagent with the constructed prompt.
- **review** phases (1.3, 2.3, 3.3, 4.2): Dispatch via `subagents:codex-reviewer` which routes to Codex MCP. Phase 4.2 uses `codex-xhigh`; all others use `codex-high`.
- **command** phases (3.1): Dispatch a Bash subagent to execute test/lint commands.

## Model Selection

- Phases marked `config`: Use the model from project configuration (`.claude/subagents-config.json`) or default to `inherit`.
- Phases marked `inherit`: Use the parent conversation's model.
- Phases marked `per-task`: Model varies per task based on complexity scoring.
- Phases marked `—`: Not applicable (Bash commands).

## What NOT To Do

- Do NOT execute phase work directly — always dispatch via Task tool (subagent)
- Do NOT advance state — the SubagentStop hook does this automatically
- Do NOT decide what phase comes next — the state file determines this
- Do NOT skip phases or reorder them
- Do NOT stop or exit — the hooks manage the loop lifecycle
