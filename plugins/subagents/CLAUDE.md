# Subagents Plugin - Agent Instructions

This plugin implements a hook-driven subagent architecture for Claude Code. Every workflow phase runs as an isolated subagent, with shell hooks enforcing progression, gates, and auto-chaining.

## Architecture Overview (v5 — Phase-Specific Prompts)

```
Main Conversation (Orchestrator Loop)
│
├── Stop hook generates PHASE-SPECIFIC orchestrator prompt (~40-70 lines)
│   └── Claude reads state → dispatches current phase as subagent (Task tool)
│
├── SubagentStop hook validates → advances state → exits silently
│   └── No stdout — pure side-effect (validate output, check gates, advance)
│   └── Codex timeout detection → retry tracking → Claude fallback
│
├── Stop hook fires again → generates next phase's prompt
│   └── Claude reads updated state → dispatches next phase
│
├── PreToolUse hook validates dispatch matches current phase
│
├── Session scoping: hooks only fire for the owning session ($PPID)
│
└── Phases communicate only via .agents/tmp/phases/ files
```

**Key Design (Ralph Pattern):** The Stop hook generates a **phase-specific orchestrator prompt** every iteration via `generate_phase_prompt()` in `schedule.sh`. This replaces the previous full 130-line `orchestrator-loop.md` injection, reducing token overhead by ~50%. Claude reads `.agents/tmp/state.json` to determine the current phase and dispatches it. No conversation memory required. State on disk determines behavior. The SubagentStop hook is a pure side-effect hook (validate, advance, exit silently).

### Session Scoping

Hooks use `$PPID`-based session detection to prevent cross-conversation interference. At workflow start, the dispatch command captures `$PPID` and stores it as `ownerPpid` in state.json. All hooks call `check_session_owner()` — if `$PPID` doesn't match, the hook exits 0 (allows, doesn't interfere). Backward compatible: missing `ownerPpid` skips the check.

### Git Worktree Isolation

By default, the workflow creates an isolated git worktree for code changes:

- **Worktree path:** `../<repo-name>--subagent` (sibling directory)
- **Branch:** `subagents/<slugified-task>`
- **State stays in original dir:** `.agents/tmp/` and hooks always live in the original project directory
- **Code changes in worktree:** All code reads, writes, edits, tests happen in the worktree

The orchestrator prompt includes a "Working Directory" section when `state.worktree` exists, directing phase agents to use the worktree for code and the original dir for state files. The completion handler tears down the worktree after committing and creating a PR.

Use `--no-worktree` to skip worktree creation and work directly in the project directory.

## Hooks

Three shell hooks enforce the workflow:

| Hook                  | Event        | Purpose                                                          |
| --------------------- | ------------ | ---------------------------------------------------------------- |
| `on-subagent-stop.sh` | SubagentStop | Validate output, check gates, advance state, Codex fallback      |
| `on-stop.sh`          | Stop         | Generate phase-specific prompt (Ralph-style loop driver)          |
| `on-task-dispatch.sh` | PreToolUse   | Validate Task dispatches match expected phase                    |

Hooks are registered in `hooks/hooks.json` and sourced from `hooks/lib/` (state.sh, gates.sh, schedule.sh, review.sh, fallback.sh).

### Ralph-Style Loop Mechanics

The Stop hook calls `generate_phase_prompt()` from `schedule.sh` to build a phase-specific prompt (~40-70 lines) and injects it as the `reason` in `{"decision":"block","reason":"<prompt>"}`. The prompt includes only the current phase's dispatch instructions, supplementary agents, and relevant rules. `prompts/orchestrator-loop.md` is kept as a reference document but is NOT injected at runtime. Claude reads `.agents/tmp/state.json` to determine the current phase, dispatches it as a subagent, and the cycle repeats.

## Workflow Stages

```
EXPLORE → PLAN → IMPLEMENT → TEST → FINAL
```

All 12 phases run as subagents. No inline phases.

### Phase Types

| Type       | Description                         | Examples                |
| ---------- | ----------------------------------- | ----------------------- |
| `dispatch` | Parallel batch (multiple subagents) | 0, 1.2, 2.1            |
| `subagent` | Single subagent                     | 3.1, 3.3, 4.1, 4.3     |
| `review`   | Review via state.reviewer agent     | 1.3, 2.3, 3.4, 3.5, 4.2 |

### EXPLORE Stage (Phase 0)

- Dispatches 1-10 parallel explorer agents based on task complexity
- **Supplementary:** `subagents:deep-explorer` for deep architecture tracing (always Claude — avoids Codex timeout risk on supplementary agents)
- **Supplementary:** `subagents:brainstormer` — runs after explorers to synthesize 2-3 implementation approaches
- Output: `.agents/tmp/phases/0-explore.md` + `.agents/tmp/phases/1.1-brainstorm.md`

### PLAN Stage (Phases 1.2-1.3)

- 1.2: Parallel planner agents + **`subagents:architecture-analyst`** for architecture blueprint
- 1.3: Plan review via state.reviewer (all reviews use `codex-xhigh` when Codex available)
- Input: both `0-explore.md` and `1.1-brainstorm.md` from EXPLORE
- Output: `.agents/tmp/phases/1.2-plan.md`

### IMPLEMENT Stage (Phases 2.1, 2.3)

- 2.1: Wave-based task execution via task-agent (includes post-implementation simplification)
- 2.3: Implementation review via state.reviewer + **supplementary parallel checks:**
  - `subagents:code-quality-reviewer` — code quality and conventions
  - `subagents:error-handling-reviewer` — error handling gaps
  - `subagents:type-reviewer` — type design quality
- Output: `.agents/tmp/phases/2.1-tasks.json`

### TEST Stage (Phases 3.1, 3.3-3.5)

- 3.1: **Run tests AND analyze failures** via state.testRunner agent (merged — produces both `3.1-test-results.json` and `3.2-analysis.md`)
- 3.3: **Develop Tests & CI** via test-developer agent (coverage loop — writes tests until `coverageThreshold` met, default 90%)
- 3.4: Test development review via state.reviewer
- 3.5: Test review via state.reviewer — **checks coverage threshold**; loops back to 3.3 if coverage not met

**Coverage Loop:** Phases 3.3 → 3.4 → 3.5 repeat until `coverage ≥ coverageThreshold` or `maxIterations` (20) reached. The SubagentStop hook manages the loop by resetting `currentPhase` to `"3.3"` when `3.5-test-review.json` reports `coverage.met: false`.

### Stage Restarts (Two-Tier Retry)

When review-fix cycles exhaust their fix attempts (`maxFixAttempts`, default: 10), the workflow automatically restarts the entire stage from its first phase instead of immediately blocking. This gives the workflow a clean slate — all phase outputs for the stage are deleted, fix counters are reset, and the orchestrator re-dispatches from the beginning of the stage.

```
Tier 1: 10 fix attempts per review phase (within one run of the stage)
Tier 2: 3 stage restarts (each restart resets fix counters to 0)
Total:  up to 3 x 10 = 30 fix attempts per review phase before blocking
```

Only after both tiers are exhausted does the workflow set `status: "blocked"`. Stage restarts are tracked at `stages[stage].stageRestarts` and logged in `restartHistory[]`. Configurable via `reviewPolicy.maxStageRestarts` (default: 3).

### FINAL Stage (Phases 4.1-4.3)

- 4.1: Documentation via doc-updater + **`subagents:claude-md-updater`** in parallel
- 4.2: Final review via state.reviewer + **supplementary parallel checks:**
  - `subagents:code-quality-reviewer` — final code quality sweep
  - `subagents:test-coverage-reviewer` — test coverage completeness
  - `subagents:comment-reviewer` — comment accuracy
- 4.3: Git commit, PR creation, worktree teardown via completion-handler

## Codex Availability: Optimistic Defaults + Runtime Fallback

State always initializes with `codexAvailable: true` and Codex reviewer agents configured. No pre-workflow Codex probe — if Codex MCP is unavailable, the first review phase timeout triggers automatic fallback to Claude agents via `fallback.sh`.

## Codex Timeout & Fallback

Three-layer defense against Codex MCP hangs:

### Layer 1: Prompt-Level Time Limit

All Codex agent prompts include "TIME LIMIT: Complete within 10 minutes." This is a soft hint — the model may not respect it.

### Layer 2: Background Dispatch + TaskOutput Timeout

For phases using Codex agents, the generated orchestrator prompt instructs:
1. Dispatch via Task with `run_in_background: true`
2. Poll with `TaskOutput(task_id, block=true, timeout=600000)` (10 min)
3. On timeout: `TaskStop(task_id)` + write `{"codexTimeout": true}` error JSON

### Layer 3: Retry Tracking + Auto Claude Fallback

`hooks/lib/fallback.sh` manages retry tracking and automatic fallback:
- SubagentStop hook detects `codexTimeout: true` or missing output
- Increments `dispatchRetries` counter per phase
- After `maxRetries` (default: 2): switches ALL Codex agents to Claude equivalents
- Records switch in `state.codexFallback` with timestamp and reason

```
Codex phase dispatch:
  Layer 1: Prompt says "complete within 10 min"
  Layer 2: Background dispatch with 10-min timeout
           → Success: proceed normally
           → Timeout: cancel + write {"codexTimeout": true}
  Layer 3: SubagentStop detects timeout marker
           → Retry 1: delete timeout output, re-dispatch Codex
           → Retry 2: switch to Claude agents, re-dispatch Claude
           → Claude succeeds: proceed normally
```

## Phase Prompt Templates

Each active phase has a prompt template in `prompts/phases/`:

```
prompts/phases/
├── 0-explore.md
├── 1.1-brainstorm.md         (still used by brainstormer supplementary agent)
├── 1.2-plan.md
├── 1.3-plan-review.md
├── 2.1-implement.md
├── 2.3-impl-review.md
├── 3.1-run-tests.md          (merged: produces both test results + analysis)
├── 3.2-analyze-failures.md   (reference only — no longer scheduled)
├── 3.3-develop-tests.md
├── 3.4-test-dev-review.md
├── 3.5-test-review.md
├── 4.1-documentation.md
├── 4.2-final-review.md
└── 4.3-completion.md
```

Templates include `[PHASE X.Y]` tags for PreToolUse hook validation.

## State Management

State file: `.agents/tmp/state.json`

Key state fields:

- `ownerPpid`: Session PID for session scoping (hooks only fire for owner session)
- `schedule`: Ordered array of all 12 phases to execute
- `gates`: Map of stage transitions to required output files
- `stages`: Per-stage status, phases, and restart counts
- `worktree`: (optional) `{ path, branch, createdAt }` — present when worktree isolation is active
- `codexTimeout`: `{ reviewPhases, testPhases, explorePhases, maxRetries }` — timeout config (ms)
- `codexFallback`: (optional) `{ switchedAt, reason }` — present after auto-fallback to Claude
- `coverageThreshold`: target test coverage percentage (default: 90)
- `coverageLoop`: (optional) tracks 3.3→3.5 iteration when coverage below threshold (max 20 iterations)
- `webSearch`: whether agents can search for libraries online (default: true, disable with `--no-web-search`)
- `reviewPolicy`: `{ minBlockSeverity, maxFixAttempts, maxStageRestarts }` — controls review-fix behavior
- `restartHistory`: (optional) audit trail of stage restart events `[{ stage, fromPhase, toPhase, restart, reason, at }]`

State updates are performed by hook scripts via `hooks/lib/state.sh` (atomic writes with jq).

All phase outputs: `.agents/tmp/phases/`

## Schedule & Stage Gates

All workflow phases are pre-scheduled at initialization. Stage transitions are enforced by hooks.

### Schedule (12 phases)

```
Phase 0   │ EXPLORE   │ Explore (+ Brainstorm)  │ dispatch  ← GATE: EXPLORE→PLAN
Phase 1.2 │ PLAN      │ Plan                    │ dispatch
Phase 1.3 │ PLAN      │ Plan Review             │ review    ← GATE: PLAN→IMPLEMENT
Phase 2.1 │ IMPLEMENT │ Implement (+ simplify)  │ dispatch
Phase 2.3 │ IMPLEMENT │ Implementation Review   │ review    ← GATE: IMPLEMENT→TEST
Phase 3.1 │ TEST      │ Run Tests & Analyze     │ subagent
Phase 3.3 │ TEST      │ Develop Tests           │ subagent
Phase 3.4 │ TEST      │ Test Dev Review         │ review
Phase 3.5 │ TEST      │ Test Review             │ review    ← GATE: TEST→FINAL
Phase 4.1 │ FINAL     │ Documentation           │ subagent
Phase 4.2 │ FINAL     │ Final Review            │ review    ← GATE: FINAL→COMPLETE
Phase 4.3 │ FINAL     │ Completion              │ subagent
```

### Gates

Gates are checked by `on-subagent-stop.sh` at stage boundaries:

| Gate            | Required Files                                  | Blocks Transition To |
| --------------- | ----------------------------------------------- | -------------------- |
| EXPLORE->PLAN   | `0-explore.md`, `1.1-brainstorm.md`             | PLAN                 |
| PLAN->IMPLEMENT | `1.2-plan.md`, `1.3-plan-review.json`           | IMPLEMENT            |
| IMPLEMENT->TEST | `2.1-tasks.json`, `2.3-impl-review.json`        | TEST                 |
| TEST->FINAL     | `3.1-test-results.json`, `3.3-test-dev.json`, `3.5-test-review.json` | FINAL     |
| FINAL->COMPLETE | `4.2-final-review.json`                         | Completion           |

## Model vs MCP Tool Namespaces

**These are SEPARATE namespaces. Never mix them.**

| Type      | Valid Values                                        | Usage                       |
| --------- | --------------------------------------------------- | --------------------------- |
| ModelId   | `sonnet-4.5`, `opus-4.5`, `haiku-4.5`, `inherit`    | Task tool `model` parameter |
| McpToolId | `codex-high`, `codex-xhigh`                         | Review phase `tool` field   |

## Review Model Selection

Review phases (1.3, 2.3, 3.4, 3.5, 4.2) use tiered model selection based on Codex availability:

| Codex Available | Primary Reviewer          | Supplementary Model | Rationale                                       |
| --------------- | ------------------------- | ------------------- | ----------------------------------------------- |
| Yes             | `codex-xhigh` (all reviews) | `sonnet`         | Codex handles deep reasoning; plugins need speed |
| No              | `subagents:claude-reviewer` | `opus`            | Plugins are primary review path; need thoroughness |

All Codex review phases use `codex-xhigh` — no distinction between phases.

## Complexity Scoring

Task complexity determines model selection during Phase 2.1:

| Level  | Model       | Criteria                                 |
| ------ | ----------- | ---------------------------------------- |
| Easy   | sonnet-4.5  | Single file, <50 LOC                     |
| Medium | opus-4.5    | 2-3 files, 50-200 LOC                    |
| Hard   | codex-xhigh | 4+ files, >200 LOC, security/concurrency |

## Supplementary Agents

Native agents that run **in parallel** with primary phase agents (all self-contained within subagents plugin):

| Agent                              | Replaces                                | Phases    |
| ---------------------------------- | --------------------------------------- | --------- |
| `subagents:deep-explorer`          | `feature-dev:code-explorer`             | 0         |
| `subagents:brainstormer`           | separate Phase 1.1                      | 0         |
| `subagents:architecture-analyst`   | `feature-dev:code-architect`            | 1.2       |
| `subagents:code-quality-reviewer`  | `pr-review-toolkit:code-reviewer`       | 2.3, 4.2  |
| `subagents:error-handling-reviewer` | `pr-review-toolkit:silent-failure-hunter` | 2.3     |
| `subagents:type-reviewer`          | `pr-review-toolkit:type-design-analyzer` | 2.3      |
| `subagents:test-coverage-reviewer` | `pr-review-toolkit:pr-test-analyzer`    | 4.2       |
| `subagents:comment-reviewer`       | `pr-review-toolkit:comment-analyzer`    | 4.2       |
| `subagents:claude-md-updater`      | `claude-md-management:revise-claude-md` | 4.1       |
| `subagents:fix-dispatcher`         | inline orchestrator logic               | review-fix |

All supplementary agents are always available — no availability checks needed.

**External dependency:** Only `superpowers` plugin remains external (required for `brainstorming` skill used by the brainstormer supplementary agent in Phase 0).

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

| Agent File             | Purpose                                                        |
| ---------------------- | -------------------------------------------------------------- |
| `init-claude.md`       | Workflow init with Claude reasoning, worktree creation, optimistic Codex defaults |

Flow: dispatch runs inline git+plugin checks → `init-claude` (always). Pre-flight checks are inline bash in the dispatch command. Codex reviewers are configured optimistically; `fallback.sh` handles runtime unavailability.

The init agent creates a git worktree (unless `--no-worktree`) and records `state.worktree` and `state.ownerPpid` in state.json.

### Phase Agents

Dispatched by the orchestrator loop during workflow execution:

| Agent File             | Phase(s)            | Purpose                                 |
| ---------------------- | ------------------- | --------------------------------------- |
| `explorer.md`          | 0                   | Codebase exploration (parallel batch)   |
| `deep-explorer.md`     | 0 (supplement)      | Deep architecture tracing               |
| `brainstormer.md`      | 0 (supplement)      | Implementation strategy analysis        |
| `planner.md`           | 1.2                 | Detailed planning (parallel batch)      |
| `architecture-analyst.md` | 1.2 (supplement) | Architecture blueprint                  |
| `codex-reviewer.md`    | 1.3, 2.3, 3.4, 3.5, 4.2 | Codex MCP review dispatch (when Codex available) |
| `claude-reviewer.md`   | 1.3, 2.3, 3.4, 3.5, 4.2 | Claude reasoning review (Codex fallback) |
| `fix-dispatcher.md`    | review-fix          | Reads review issues and applies fixes directly |
| `difficulty-estimator.md` | 2.1              | Task complexity scoring (Claude)        |
| `codex-difficulty-estimator.md` | 2.1        | Task complexity scoring (Codex MCP)     |
| `task-agent.md`        | 2.1                 | Task execution + simplification (wave-based parallel) |
| `code-quality-reviewer.md` | 2.3, 4.2        | Code quality and conventions (supplementary) |
| `error-handling-reviewer.md` | 2.3           | Silent failure hunting (supplementary)  |
| `type-reviewer.md`     | 2.3                 | Type design analysis (supplementary)    |
| `test-runner.md`       | 3.1                 | Lint, test, and failure analysis (Claude) |
| `codex-test-runner.md` | 3.1                 | Lint, test, and failure analysis (Codex MCP) |
| `failure-analyzer.md`  | (reference)         | Kept for reference — merged into test-runner |
| `codex-failure-analyzer.md` | (reference)    | Kept for reference — merged into codex-test-runner |
| `simplifier.md`        | (reference)         | Kept for reference — merged into task-agent |
| `test-developer.md`    | 3.3                 | Writes tests and CI until coverage threshold met |
| `doc-updater.md`       | 4.1                 | Documentation updates                   |
| `claude-md-updater.md` | 4.1 (supplement)    | CLAUDE.md updates                       |
| `test-coverage-reviewer.md` | 4.2 (supplement) | Test coverage analysis                |
| `comment-reviewer.md`  | 4.2 (supplement)    | Comment accuracy review                 |
| `completion-handler.md`| 4.3                 | Git commit, PR creation, worktree teardown |

### Hook Libraries

| Library File       | Purpose                                          |
| ------------------ | ------------------------------------------------ |
| `state.sh`         | State I/O, session scoping (`check_session_owner`) |
| `gates.sh`         | Stage gate validation                            |
| `schedule.sh`      | Phase advancement, `generate_phase_prompt()`     |
| `review.sh`        | Review validation, fix cycles, stage restarts    |
| `fallback.sh`      | Codex timeout detection, retry tracking, Claude fallback |
