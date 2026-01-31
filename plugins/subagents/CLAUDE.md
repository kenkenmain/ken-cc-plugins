# Subagents Plugin - Agent Instructions

This plugin implements a hook-driven subagent architecture for Claude Code. Every workflow phase runs as an isolated subagent, with shell hooks enforcing progression, gates, and auto-chaining.

## Architecture Overview (v4 — Ralph-Style Loop)

```
Main Conversation (Orchestrator Loop)
│
├── Stop hook injects FULL orchestrator prompt (prompts/orchestrator-loop.md)
│   └── Claude reads state → dispatches current phase as subagent (Task tool)
│
├── SubagentStop hook validates → advances state → exits silently
│   └── No stdout — pure side-effect (validate output, check gates, advance)
│
├── Stop hook fires again → re-injects same orchestrator prompt
│   └── Claude reads updated state → dispatches next phase
│
├── PreToolUse hook validates dispatch matches current phase
│
└── Phases communicate only via .agents/tmp/phases/ files
```

**Key Design (Ralph Pattern):** The Stop hook re-injects the **complete orchestrator prompt** every iteration — not a hint. Claude reads `.agents/tmp/state.json` to determine the current phase and dispatches it. No conversation memory required. State on disk determines behavior. The SubagentStop hook is a pure side-effect hook (validate, advance, exit silently).

## Hooks

Three shell hooks enforce the workflow:

| Hook                  | Event        | Purpose                                                          |
| --------------------- | ------------ | ---------------------------------------------------------------- |
| `on-subagent-stop.sh` | SubagentStop | Validate output, check gates, advance state (silent — no stdout) |
| `on-stop.sh`          | Stop         | Re-inject full orchestrator prompt (Ralph-style loop driver)     |
| `on-task-dispatch.sh` | PreToolUse   | Validate Task dispatches match expected phase                    |

Hooks are registered in `hooks/hooks.json` and sourced from `hooks/lib/` (state.sh, gates.sh, schedule.sh).

### Ralph-Style Loop Mechanics

The Stop hook reads `prompts/orchestrator-loop.md` and injects it as the `reason` in `{"decision":"block","reason":"<prompt>"}`. This is the same complete prompt every time. Claude reads `.agents/tmp/state.json` to determine the current phase, dispatches it as a subagent, and the cycle repeats. The SubagentStop hook handles state advancement silently (no stdout output).

## Workflow Stages

```
EXPLORE → PLAN → IMPLEMENT → TEST → FINAL
```

All 13 phases run as subagents. No inline phases.

### Phase Types

| Type       | Description                         | Examples                      |
| ---------- | ----------------------------------- | ----------------------------- |
| `dispatch` | Parallel batch (multiple subagents) | 0, 1.2, 2.1                  |
| `subagent` | Single subagent                     | 1.1, 2.2, 3.1, 3.2, 4.1, 4.3 |
| `review`   | Codex MCP review via codex-reviewer | 1.3, 2.3, 3.3, 4.2           |

### EXPLORE Stage (Phase 0)

- Dispatches 1-10 parallel explorer agents based on task complexity
- Output: `.agents/tmp/phases/0-explore.md`

### PLAN Stage (Phases 1.1-1.3)

- 1.1: Brainstorm via brainstormer agent
- 1.2: Parallel planner agents for detailed planning
- 1.3: Codex MCP review of plan via codex-reviewer agent
- Output: `.agents/tmp/phases/1.2-plan.md`

### IMPLEMENT Stage (Phases 2.1-2.3)

- 2.1: Wave-based task execution via task-agent
- 2.2: Code simplification via simplifier agent
- 2.3: Codex MCP implementation review via codex-reviewer agent
- Output: `.agents/tmp/phases/2.1-tasks.json`

### TEST Stage (Phases 3.1-3.3)

- 3.1: Run lint and test commands via test-runner agent
- 3.2: Analyze failures via failure-analyzer agent
- 3.3: Codex MCP test review via codex-reviewer agent

### FINAL Stage (Phases 4.1-4.3)

- 4.1: Documentation updates via doc-updater agent
- 4.2: Final Codex MCP review via codex-reviewer agent (codex-xhigh)
- 4.3: Git branch and PR creation via completion-handler agent

## Phase Prompt Templates

Each phase has a prompt template in `prompts/phases/`:

```
prompts/phases/
├── 0-explore.md
├── 1.1-brainstorm.md
├── 1.2-plan.md
├── 1.3-plan-review.md
├── 2.1-implement.md
├── 2.2-simplify.md
├── 2.3-impl-review.md
├── 3.1-run-tests.md
├── 3.2-analyze-failures.md
├── 3.3-test-review.md
├── 4.1-documentation.md
├── 4.2-final-review.md
└── 4.3-completion.md
```

Templates include `[PHASE X.Y]` tags for PreToolUse hook validation.

## State Management

State file: `.agents/tmp/state.json`

Key state fields:

- `schedule`: Ordered array of all phases to execute
- `gates`: Map of stage transitions to required output files
- `stages`: Per-stage status, phases, and restart counts

State updates are performed by hook scripts via `hooks/lib/state.sh` (atomic writes with jq).

All phase outputs: `.agents/tmp/phases/`

## Schedule & Stage Gates

All workflow phases are pre-scheduled at initialization. Stage transitions are enforced by hooks.

### Schedule

The `schedule` array in state lists every phase in execution order. Each entry has:

- `phase`: identifier (e.g., `"1.3"`)
- `stage`: parent stage (`EXPLORE`, `PLAN`, `IMPLEMENT`, `TEST`, `FINAL`)
- `name`: human-readable label
- `type`: execution type (`dispatch`, `subagent`, `review`)

### Gates

Gates are checked by `on-subagent-stop.sh` at stage boundaries:

| Gate            | Required Files                                  | Blocks Transition To |
| --------------- | ----------------------------------------------- | -------------------- |
| EXPLORE->PLAN   | `0-explore.md`                                  | PLAN                 |
| PLAN->IMPLEMENT | `1.2-plan.md`, `1.3-plan-review.json`           | IMPLEMENT            |
| IMPLEMENT->TEST | `2.1-tasks.json`, `2.3-impl-review.json`        | TEST                 |
| TEST->FINAL     | `3.1-test-results.json`, `3.3-test-review.json` | FINAL                |
| FINAL->COMPLETE | `4.2-final-review.json`                         | Completion           |

## Model vs MCP Tool Namespaces

**These are SEPARATE namespaces. Never mix them.**

| Type      | Valid Values                                        | Usage                       |
| --------- | --------------------------------------------------- | --------------------------- |
| ModelId   | `sonnet-4.5`, `opus-4.5`, `haiku-4.5`, `inherit`    | Task tool `model` parameter |
| McpToolId | `codex-high`, `codex-xhigh`                         | Review phase `tool` field   |

## Complexity Scoring

Task complexity determines model selection during Phase 2.1:

| Level  | Model       | Criteria                                 |
| ------ | ----------- | ---------------------------------------- |
| Easy   | sonnet-4.5  | Single file, <50 LOC                     |
| Medium | opus-4.5    | 2-3 files, 50-200 LOC                    |
| Hard   | codex-xhigh | 4+ files, >200 LOC, security/concurrency |

## Commands

- `/subagents:dispatch <task>` - Start workflow
- `/subagents:stop` - Stop gracefully with checkpoint
- `/subagents:resume` - Resume from checkpoint
- `/subagents:status` - Show progress
- `/subagents:configure` - Configure settings

## Skills

- `workflow` - Thin orchestrator loop (dispatches phases, hooks handle enforcement)
- `state-manager` - State schema documentation and recovery procedures
- `configuration` - Config loading and merging

## Agents

All agents are custom subagent definitions in `agents/`. Each agent's `.md` file contains YAML frontmatter (name, description, tools) and a system prompt with role, process, output format, and constraints.

### Pre-Workflow Agents

Dispatched by the dispatch command before the orchestrator loop starts:

| Agent File             | Purpose                                              |
| ---------------------- | ---------------------------------------------------- |
| `env-check.md`         | Probes Codex MCP availability (sonnet)               |
| `init-codex.md`        | Workflow init with Codex task analysis                |
| `init-claude.md`       | Workflow init with Claude reasoning (Codex fallback)  |

Flow: `env-check` → if codex available → `init-codex`, else → `init-claude`

### Phase Agents

Dispatched by the orchestrator loop during workflow execution:

| Agent File             | Phase(s)            | Purpose                                 |
| ---------------------- | ------------------- | --------------------------------------- |
| `explorer.md`          | 0                   | Codebase exploration (parallel batch)   |
| `brainstormer.md`      | 1.1                 | Implementation strategy analysis        |
| `planner.md`           | 1.2                 | Detailed planning (parallel batch)      |
| `codex-reviewer.md`    | 1.3, 2.3, 3.3, 4.2 | Codex MCP review dispatch               |
| `task-agent.md`        | 2.1                 | Task execution (wave-based parallel)    |
| `simplifier.md`        | 2.2                 | Code simplification                     |
| `test-runner.md`       | 3.1                 | Lint and test execution                 |
| `failure-analyzer.md`  | 3.2                 | Test failure analysis and fixes         |
| `doc-updater.md`       | 4.1                 | Documentation updates                   |
| `completion-handler.md`| 4.3                 | Git branch, commit, and PR creation     |
