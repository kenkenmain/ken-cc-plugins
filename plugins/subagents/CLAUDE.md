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

The workflow can optionally create an isolated git worktree for code changes when `--worktree` is passed:

- **Worktree path:** `../<repo-name>--subagent` (sibling directory)
- **Branch:** `subagents/<slugified-task>`
- **State stays in original dir:** `.agents/tmp/` and hooks always live in the original project directory
- **Code changes in worktree:** All code reads, writes, edits, tests happen in the worktree

The orchestrator prompt includes a "Working Directory" section when `state.worktree` exists, directing phase agents to use the worktree for code and the original dir for state files. The completion handler tears down the worktree after committing and creating a PR.

Use `--worktree` to enable worktree creation. Without it, all work happens directly in the project directory.

## Hooks

Six shell hooks enforce the workflow:

| Hook                      | Event              | Purpose                                                          |
| ------------------------- | ------------------ | ---------------------------------------------------------------- |
| `on-fdispatch-init.sh`    | UserPromptSubmit   | Pre-initialize fdispatch state in shell before Claude processes command |
| `on-subagent-stop.sh`     | SubagentStop       | Validate output, check gates, advance state, Codex fallback      |
| `on-stop.sh`              | Stop               | Generate phase-specific prompt (Ralph-style loop driver)          |
| `on-task-dispatch.sh`     | PreToolUse         | Validate Task dispatches match expected phase + enforce background dispatch for Codex agents |
| `on-codex-guard.sh`       | PreToolUse         | Block direct Codex MCP calls, force background dispatch          |
| `on-orchestrator-guard.sh`| PreToolUse         | Block direct Edit/Write to code files, force subagent dispatch   |

Hooks are registered in `hooks/hooks.json` and sourced from `hooks/lib/` (state.sh, gates.sh, schedule.sh, review.sh, fallback.sh).

### Ralph-Style Loop Mechanics

The Stop hook calls `generate_phase_prompt()` from `schedule.sh` to build a phase-specific prompt (~40-70 lines) and injects it as the `reason` in `{"decision":"block","reason":"<prompt>"}`. The prompt includes only the current phase's dispatch instructions, supplementary agents, and relevant rules. `prompts/orchestrator-loop.md` is kept as a reference document but is NOT injected at runtime. Claude reads `.agents/tmp/state.json` to determine the current phase, dispatches it as a subagent, and the cycle repeats.

## Workflow Stages

```
EXPLORE → PLAN → IMPLEMENT → TEST → FINAL
```

Phase count depends on pipeline profile: minimal (5), standard (13), thorough (15). All phases run as subagents.

### Phase Types

| Type       | Description                         | Examples                |
| ---------- | ----------------------------------- | ----------------------- |
| `dispatch` | Parallel batch (multiple subagents) | 0, 1.2, 2.1            |
| `subagent` | Single subagent                     | 3.1, 3.3, 4.1, 4.3     |
| `review`   | Review via state.reviewer agent     | 1.3, 2.3, 3.4, 3.5, 4.2 |

### EXPLORE Stage (Phase 0)

- Dispatches 1-10 parallel explorer agents based on task complexity
- **Supplementary:** `subagents:deep-explorer` for deep architecture tracing
- **Aggregator:** `state.exploreAggregator` (Codex: `codex-explore-aggregator`, Claude: `explore-aggregator`)
- Primary agents write to per-agent `.tmp` files; aggregator merges into final output
- Output: `.agents/tmp/phases/0-explore.md`

### PLAN Stage (Phases 1.1-1.3)

- 1.1: Standalone brainstormer subagent — reads finalized `0-explore.md` and synthesizes 2-3 implementation approaches
- 1.2: Parallel planner agents + **`subagents:architecture-analyst`** for architecture blueprint
- **Aggregator:** `state.planAggregator` (Codex: `codex-plan-aggregator`, Claude: `plan-aggregator`)
- 1.3: Plan review via state.reviewer (all reviews use `codex-high` when Codex available)
- Input: both `0-explore.md` and `1.1-brainstorm.md`
- Output: `.agents/tmp/phases/1.1-brainstorm.md`, `.agents/tmp/phases/1.2-plan.md`

### IMPLEMENT Stage (Phases 2.1, 2.3)

- 2.1: Wave-based task execution via complexity-routed task agents (includes **test writing** + post-implementation simplification)
  - Easy tasks → `sonnet-task-agent` (direct execution, model=sonnet)
  - Medium tasks → `opus-task-agent` (direct execution, model=opus)
  - Hard tasks → `codex-task-agent` (Codex mode) or `opus-task-agent` (Claude mode, when `codexAvailable: false`)
  - Task agents write unit tests alongside code (hybrid approach) — `testsWritten` array in output
  - Tests follow project conventions (search-before-write pattern for framework/convention discovery)
  - Skip conditions: config-only, generated code, docs-only, test-file-only changes
- 2.3: Implementation review via state.reviewer + **supplementary parallel checks:**
  - `subagents:code-quality-reviewer` — code quality and conventions
  - `subagents:error-handling-reviewer` — error handling gaps
  - `subagents:type-reviewer` — type design quality
  - Review criteria includes **test quality** (section 5 in `high-stakes/implementation.md`)
- Output: `.agents/tmp/phases/2.1-tasks.json` (includes per-task `testsWritten`, aggregate `testsTotal`/`testFiles`)

### TEST Stage (Phases 3.1, 3.3-3.5)

- 3.1: **Run tests AND analyze failures** via state.testDeveloper agent (merged — produces both `3.1-test-results.json` and `3.2-analysis.md`)
- 3.3: **Develop Tests & CI** via state.testDeveloper agent (**gap-filler** — reads `2.1-tasks.json` for existing `testsWritten`, then fills remaining coverage gaps until `coverageThreshold` met, default 90%)
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

Only after both tiers are exhausted does the workflow set `status: "blocked"`. Stage restarts are tracked at `stages[stage].restartCount` and logged in `restartHistory[]`. Configurable via `reviewPolicy.maxStageRestarts` (default: 3).

### FINAL Stage (Phases 4.1-4.3)

- 4.1: Documentation via state.docUpdater + **`subagents:claude-md-updater`** in parallel
- 4.2: Final review via state.reviewer + **supplementary parallel checks:**
  - `subagents:code-quality-reviewer` — final code quality sweep
  - `subagents:test-coverage-reviewer` — test coverage completeness
  - `subagents:comment-reviewer` — comment accuracy
- 4.3: Git commit, PR creation, worktree teardown via completion-handler + **`subagents:retrospective-analyst`** (supplementary) for workflow learnings

## Codex Availability: Dispatch Mode Determines Defaults

- **`dispatch` (Codex mode):** State initializes with `codexAvailable: true` and Codex agents configured. No pre-workflow Codex probe — if Codex MCP is unavailable, the first review phase timeout triggers automatic fallback to Claude agents via `fallback.sh`.
- **`dispatch-claude` (Claude mode):** State initializes with `codexAvailable: false` and Claude agents configured. No Codex MCP dependency, no fallback needed.

## Codex Timeout & Fallback

Four-layer defense against Codex MCP hangs:

### Layer 0: Hook-Enforced Background Dispatch (Mechanical Guard)

PreToolUse hooks (`on-codex-guard.sh` + `on-task-dispatch.sh`) mechanically block:
- Direct `mcp__codex-high__codex` calls during active workflow
- Codex agent Task dispatches without `run_in_background: true`

This is the **only layer that doesn't depend on Claude following prompt instructions**. It forces all Codex MCP usage through background-dispatched Task agents, making Layer 2 timeout mechanically enforceable.

### Layer 1: Prompt-Level Time Limit

All Codex agent prompts include "TIME LIMIT: Complete within 10 minutes." This is a soft hint — the model may not respect it.

### Layer 2: Background Dispatch + Phase-Aware TaskOutput Timeout

For phases using Codex agents, the generated orchestrator prompt instructs:
1. Dispatch via Task with `run_in_background: true` (enforced by Layer 0 hooks)
2. Poll with `TaskOutput(task_id, block=true, timeout=<phase_timeout>)`
3. On timeout: `TaskStop(task_id)` + write `{"codexTimeout": true}` error JSON

**Phase-aware timeouts** (via `get_phase_timeout()` in `schedule.sh`):

| Phase Type     | Timeout      | Rationale                                |
| -------------- | ------------ | ---------------------------------------- |
| Review         | 5 min        | Reviews should be fast; fall back quickly |
| Final Review   | 10-15 min    | Scales by code size: <500 LOC → 10 min, ≥500 LOC → 15 min |
| Implementation | 30 min       | Codex coding needs time; don't kill active work |
| Test           | 10 min       | Medium complexity                        |
| Default        | 5 min        | Safe fallback                            |

Final review timeout is determined by `_git_loc_changed()` which checks `git diff` against the merge base. Override with `state.codexTimeout.finalReviewPhases` (ms) to set a fixed value.

### Layer 3: Retry Tracking + Auto Claude Fallback

`hooks/lib/fallback.sh` manages retry tracking and automatic fallback:
- SubagentStop hook detects `codexTimeout: true` or missing output
- Increments `dispatchRetries` counter per phase
- After `maxRetries` (default: 2): switches ALL Codex agents to Claude equivalents
- Records switch in `state.codexFallback` with timestamp and reason

```
Codex phase dispatch:
  Layer 0: Hook blocks direct MCP calls + non-background dispatches
  Layer 1: Prompt says "complete within 10 min"
  Layer 2: Background dispatch with phase-aware timeout (5-30 min)
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
├── 1.1-brainstorm.md
├── 1.2-plan.md
├── 1.3-plan-review.md
├── 2.1-implement.md
├── 2.3-impl-review.md
├── 3.1-run-tests.md          (merged: produces both test results + analysis)
├── 3.3-develop-tests.md
├── 3.4-test-dev-review.md
├── 3.5-test-review.md
├── 4.1-documentation.md
├── 4.2-final-review.md
└── 4.3-completion.md
```

Templates include `[PHASE X.Y]` tags for PreToolUse hook validation.

## Per-Agent Temp File Convention

Dispatch phases (0, 1.2) use per-agent temp files to avoid orchestrator context bloat. Each parallel agent writes its output to a unique temp file, and an aggregator agent reads all temp files to produce the final phase output.

### Naming Pattern

`{phase_output_basename}.{agent-name}.{n}.tmp`

Where:
- `{phase_output_basename}` is the phase output file without extension (e.g., `0-explore`, `1.2-plan`)
- `{agent-name}` is the agent type without `subagents:` prefix (e.g., `explorer`, `planner`, `deep-explorer`, `architecture-analyst`)
- `{n}` is a 1-based index for parallel batch agents; omitted for single-instance agents
- All temp files live in `.agents/tmp/phases/`

### Examples

**Phase 0 (Explore):**
```
.agents/tmp/phases/0-explore.explorer.1.tmp     (explorer agent 1)
.agents/tmp/phases/0-explore.explorer.2.tmp     (explorer agent 2)
.agents/tmp/phases/0-explore.explorer.3.tmp     (explorer agent 3)
.agents/tmp/phases/0-explore.deep-explorer.tmp  (single deep-explorer, no index)
```

**Phase 1.2 (Plan):**
```
.agents/tmp/phases/1.2-plan.planner.1.tmp              (planner agent 1 — area 1)
.agents/tmp/phases/1.2-plan.planner.2.tmp              (planner agent 2 — area 2)
.agents/tmp/phases/1.2-plan.architecture-analyst.tmp   (single architecture-analyst, no index)
```

### Cleanup

Temp files are NOT deleted by aggregators. They are cleaned up when:
- A new workflow starts (`init-claude` creates a fresh `.agents/tmp/phases/` directory)
- The user runs `/subagents:teardown`

## State Management

State file: `.agents/tmp/state.json`

Key state fields:

- `ownerPpid`: Session PID for session scoping (hooks only fire for owner session)
- `pipelineProfile`: Selected profile (`minimal`, `standard`, `thorough`)
- `supplementaryPolicy`: `"on-issues"` (default) or `"always"` — controls dynamic supplementary dispatch
- `supplementaryRun`: (optional) map of phase IDs where supplementary agents were triggered (e.g., `{"2.3": true}`)
- `schedule`: Ordered array of phases to execute (5-15 depending on profile)
- `gates`: Map of stage transitions to required output files
- `stages`: Per-stage status, phases, and restart counts
- `worktree`: (optional) `{ path, branch, createdAt }` — present when worktree isolation is active
- `codexTimeout`: `{ reviewPhases, finalReviewPhases, implementPhases, testPhases, explorePhases, maxRetries }` — timeout config (ms)
- `codexFallback`: (optional) `{ switchedAt, reason }` — present after auto-fallback to Claude
- `coverageThreshold`: target test coverage percentage (default: 90)
- `coverageLoop`: (optional) tracks 3.3→3.5 iteration when coverage below threshold (max 20 iterations)
- `webSearch`: whether agents can search for libraries online (default: true, disable with `--no-web-search`)
- `exploreAggregator`: Agent type for explore aggregation (Codex: `subagents:codex-explore-aggregator`, Claude: `subagents:explore-aggregator`)
- `planAggregator`: Agent type for plan aggregation (Codex: `subagents:codex-plan-aggregator`, Claude: `subagents:plan-aggregator`)
- `reviewPolicy`: `{ minBlockSeverity, maxFixAttempts, maxStageRestarts }` — controls review-fix behavior
- `restartHistory`: (optional) audit trail of stage restart events `[{ stage, fromPhase, toPhase, restart, reason, at }]`

State updates are performed by hook scripts via `hooks/lib/state.sh` (atomic writes with jq).

All phase outputs: `.agents/tmp/phases/`

## Schedule & Stage Gates

All workflow phases are pre-scheduled at initialization. Stage transitions are enforced by hooks.

### Pipeline Profiles

Profile is selected by the init agent based on task complexity (or `--profile` override):

| Profile    | Phases | Stages                                    | When Used                              |
| ---------- | ------ | ----------------------------------------- | -------------------------------------- |
| `minimal`  | 5      | EXPLORE, IMPLEMENT, FINAL                 | Simple: typo, rename, config, single file |
| `standard` | 13     | EXPLORE, PLAN, IMPLEMENT, TEST, FINAL     | Medium: feature, bugfix, 2-5 files     |
| `thorough` | 15     | EXPLORE, PLAN, IMPLEMENT, TEST, FINAL     | Complex: architecture, security, 6+ files |

`thorough` adds Phase 2.2 (Simplify) and Phase 3.2 (Analyze Failures) over `standard`.

Config: `pipeline.defaultProfile` in `subagents-config.json`, or `--profile` CLI flag.

### Schedule (standard profile, 13 phases)

```
Phase 0   │ EXPLORE   │ Explore                 │ dispatch  ← GATE: EXPLORE→PLAN
Phase 1.1 │ PLAN      │ Brainstorm              │ subagent
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
| EXPLORE->PLAN   | `0-explore.md`                                  | PLAN                 |
| PLAN->IMPLEMENT | `1.1-brainstorm.md`, `1.2-plan.md`, `1.3-plan-review.json` | IMPLEMENT |
| IMPLEMENT->TEST | `2.1-tasks.json`, `2.3-impl-review.json`        | TEST                 |
| TEST->FINAL     | `3.1-test-results.json`, `3.3-test-dev.json`, `3.5-test-review.json` | FINAL     |
| FINAL->COMPLETE | `4.2-final-review.json`                         | Completion           |

## Model vs MCP Tool Namespaces

**These are SEPARATE namespaces. Never mix them.**

| Type      | Valid Values                                        | Usage                       |
| --------- | --------------------------------------------------- | --------------------------- |
| ModelId   | `sonnet`, `opus`, `haiku`, `inherit`                | Task tool `model` parameter (aliases for sonnet-4.5, opus-4.5, haiku-4.5) |
| McpToolId | `codex-high`                                        | Review phase `tool` field   |

## Review Model Selection

Review phases (1.3, 2.3, 3.4, 3.5, 4.2) use tiered model selection based on Codex availability:

| Codex Available | Primary Reviewer          | Supplementary Model | Rationale                                       |
| --------------- | ------------------------- | ------------------- | ----------------------------------------------- |
| Yes             | `codex-high` (all reviews)  | `sonnet`         | Codex handles review; plugins need speed |
| No              | `subagents:claude-reviewer` | `opus`            | Plugins are primary review path; need thoroughness |

All Codex review phases use `codex-high` — no distinction between phases.

## Complexity Scoring

Task complexity determines agent selection during Phase 2.1:

| Level  | Agent (Codex mode)  | Agent (Claude mode) | Criteria                                 |
| ------ | ------------------- | ------------------- | ---------------------------------------- |
| Easy   | sonnet-task-agent   | sonnet-task-agent   | Single file, <50 LOC                     |
| Medium | opus-task-agent     | opus-task-agent     | 2-3 files, 50-200 LOC                    |
| Hard   | codex-task-agent    | opus-task-agent     | 4+ files, >200 LOC, security/concurrency |

## Supplementary Agents

Native agents that run **in parallel** with primary phase agents (all self-contained within subagents plugin):

| Agent                              | Replaces                                | Phases    |
| ---------------------------------- | --------------------------------------- | --------- |
| `subagents:deep-explorer`          | `feature-dev:code-explorer`             | 0         |
| `subagents:architecture-analyst`   | `feature-dev:code-architect`            | 1.2       |
| `subagents:code-quality-reviewer`  | `pr-review-toolkit:code-reviewer`       | 2.3, 4.2  |
| `subagents:error-handling-reviewer` | `pr-review-toolkit:silent-failure-hunter` | 2.3     |
| `subagents:type-reviewer`          | `pr-review-toolkit:type-design-analyzer` | 2.3      |
| `subagents:test-coverage-reviewer` | `pr-review-toolkit:pr-test-analyzer`    | 4.2       |
| `subagents:comment-reviewer`       | `pr-review-toolkit:comment-analyzer`    | 4.2       |
| `subagents:claude-md-updater`      | `claude-md-management:revise-claude-md` | 4.1       |
| `subagents:fix-dispatcher`         | inline orchestrator logic               | review-fix |
| `subagents:retrospective-analyst`  | (new — no external equivalent)          | 4.3        |

All supplementary agents are always available — no availability checks needed.

### Dynamic Supplementary Dispatch

Controlled by `supplementaryPolicy` (default: `"on-issues"`):

| Policy      | Behavior                                                                 |
| ----------- | ------------------------------------------------------------------------ |
| `on-issues` | For review phases: dispatch primary only first. If approved → skip supplementary (saves tokens). If issues found → re-dispatch with supplementary included. Non-review phases always dispatch supplementary. |
| `always`    | Dispatch primary + supplementary together for all phases (original behavior). |

State tracking: `supplementaryRun["{phase}"] = true` is set by SubagentStop when primary finds issues. `get_supplementary_agents()` checks this flag to decide whether to include supplementary agents. Cleared on stage restart.

### Parallel Fix Dispatch

When review-fix cycles find issues across multiple files, fix-dispatchers run in parallel:

```
Review finds 4 issues: auth.ts (2), db.ts (1), api.ts (1)
  → Group 1: auth.ts (sequential within group)
  → Group 2: db.ts
  → Group 3: api.ts
  → 3 parallel fix-dispatchers
```

`group_issues_by_file()` in `review.sh` groups blocking issues by file path. `start_fix_cycle()` stores groups in `state.reviewFix.groups[]` with `pendingGroups` counter. SubagentStop decrements `pendingGroups` on each fix-dispatcher completion, only clearing the fix cycle when all groups finish.

### Aggregator Agents

Aggregator agents run as a second step in dispatch phases, reading per-agent temp files and producing the final phase output:

| Agent                              | Codex Variant                        | Phase | Purpose                                  |
| ---------------------------------- | ------------------------------------ | ----- | ---------------------------------------- |
| `subagents:explore-aggregator`     | `subagents:codex-explore-aggregator` | 0     | Merge explorer + deep-explorer temp files |
| `subagents:plan-aggregator`        | `subagents:codex-plan-aggregator`    | 1.2   | Merge planner + architecture-analyst temp files, renumber tasks |

Routing is determined by state fields (`exploreAggregator`, `planAggregator`), set by `init-claude` based on dispatch mode. Fallback switches Codex variants to Claude variants via `fallback.sh`.

### Temp File Lifecycle

Per-agent `.tmp` files in `.agents/tmp/phases/` persist through the workflow run for debugging and reference. Cleanup occurs when `init-claude` starts a new workflow (creates fresh `.agents/tmp/phases/` directory) or when the user runs `/subagents:teardown`.

**External dependency:** Only `superpowers` plugin remains external (required for `brainstorming` skill used by the brainstormer agent in Phase 1.1).

## Commands

- `/subagents:init <task>` - Create worktree + start workflow (main entry point, persists across restarts)
- `/subagents:teardown` - Commit, push to GitHub, create PR, remove worktree
- `/subagents:preflight` - Run pre-flight checks and environment setup
- `/subagents:dispatch <task>` - Start workflow (Codex MCP defaults)
- `/subagents:dispatch-claude <task>` - Start workflow (Claude-only, no Codex MCP)
- `/subagents:stop` - Stop gracefully with checkpoint
- `/subagents:resume` - Resume from checkpoint
- `/subagents:status` - Show progress
- `/subagents:configure` - Configure settings
- `/subagents:debug <task>` - Multi-phase debugging workflow with parallel exploration and solution ranking
- `/subagents:fdispatch <task>` - Fast dispatch (Codex MCP defaults, 4 phases)
- `/subagents:fdispatch-claude <task>` - Fast dispatch (Claude-only, 4 phases)

## Fast Dispatch Pipeline (fdispatch)

Streamlined 4-phase variant of the standard dispatch workflow. Collapses 13 phases into 4:

```
Phase F1   │ PLAN      │ Explore + Brainstorm + Write Plan  │ single opus agent (fast-planner)
Phase F2   │ IMPLEMENT │ Parallel Implement + Test           │ opus-task-agent for all tasks
Phase F3   │ REVIEW    │ Parallel Specialized Review         │ 5 Codex or Claude reviewers in parallel
           │           │ (fix cycle runs within F3 if needed)│
Phase F4   │ COMPLETE  │ Git Commit + PR                     │ completion-handler
```

**Commands:**
- `/subagents:fdispatch <task>` — Codex MCP defaults
- `/subagents:fdispatch-claude <task>` — Claude-only mode
- Flags: `--worktree`, `--no-web-search`

**Fix cycle:** Max 3 iterations (vs 10 for standard dispatch). Max 1 stage restart (vs 3).

**Initialization:** fdispatch does **not** use `subagents:init-claude`. State is initialized inline by the fdispatch command itself (directory creation, worktree setup, state.json write). This avoids dispatching an opus-level agent for work fdispatch immediately overwrites. The state contains no named agent routing fields (`reviewer`, `failureAnalyzer`, etc.) — F-phases route agents via `codexAvailable` in `schedule.sh`.

**Key differences from standard dispatch:**
- No init-claude agent — state initialized inline
- No separate explore phase — combined into F1
- No plan review — single opus agent plans directly
- No separate test stage — tests written inline by task agents
- No documentation phase — skipped for speed
- All reviewers run in parallel at end (not per-stage)
- No named agent routing fields — uses `codexAvailable` for Codex/Claude selection

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
| `init-claude.md`       | Workflow init with Claude reasoning, worktree creation, Codex/Claude defaults (standard dispatch only) |

Flow: dispatch/dispatch-claude → `init-claude` → orchestrator loop. Pre-flight checks available via `/subagents:preflight` command. For `dispatch` (Codex mode), agents are configured optimistically; `fallback.sh` handles runtime unavailability. For `dispatch-claude`, Claude agents are configured directly.

**Note:** fdispatch/fdispatch-claude do NOT use `init-claude`. They initialize state inline (directory creation, worktree, state.json) to avoid an unnecessary opus-level dispatch.

The init agent creates a git worktree (only if `--worktree` is set) and records `state.worktree` and `state.ownerPpid` in state.json.

### Phase Agents

Dispatched by the orchestrator loop during workflow execution:

| Agent File             | Phase(s)            | Purpose                                 |
| ---------------------- | ------------------- | --------------------------------------- |
| `explorer.md`          | 0                   | Codebase exploration (parallel batch)   |
| `deep-explorer.md`     | 0 (supplement)      | Deep architecture tracing               |
| `explore-aggregator.md`     | 0 (aggregator)      | Aggregates explorer temp files into final report (Claude) |
| `codex-explore-aggregator.md` | 0 (aggregator)    | Thin Codex MCP wrapper for explore aggregation |
| `brainstormer.md`      | 1.1                 | Implementation strategy analysis        |
| `fast-planner.md`      | F1                  | Combined explore+brainstorm+plan (opus, fdispatch only) |
| `planner.md`           | 1.2                 | Detailed planning (parallel batch)      |
| `architecture-analyst.md` | 1.2 (supplement) | Architecture blueprint                  |
| `plan-aggregator.md`        | 1.2 (aggregator)    | Aggregates planner temp files into unified plan (Claude) |
| `codex-plan-aggregator.md`  | 1.2 (aggregator)    | Thin Codex MCP wrapper for plan aggregation |
| `codex-reviewer.md`    | 1.3, 2.3, 3.4, 3.5, 4.2 | Codex MCP review dispatch (when Codex available) |
| `claude-reviewer.md`   | 1.3, 2.3, 3.4, 3.5, 4.2 | Claude reasoning review (Codex fallback) |
| `fix-dispatcher.md`    | review-fix          | Reads review issues and applies fixes directly |
| `difficulty-estimator.md` | 2.1              | Task complexity scoring (Claude)        |
| `codex-difficulty-estimator.md` | 2.1        | Task complexity scoring (Codex MCP)     |
| `sonnet-task-agent.md` | 2.1 (easy)          | Direct task execution (model=sonnet) — wave-based parallel |
| `opus-task-agent.md`   | 2.1 (medium)        | Direct task execution (model=opus) — wave-based parallel |
| `codex-task-agent.md`  | 2.1 (hard)          | Codex-high MCP task wrapper — wave-based parallel |
| `code-quality-reviewer.md` | 2.3, 4.2        | Code quality and conventions (supplementary) |
| `error-handling-reviewer.md` | 2.3           | Silent failure hunting (supplementary)  |
| `type-reviewer.md`     | 2.3                 | Type design analysis (supplementary)    |
| `test-runner.md`       | (reference)         | Kept for reference — merged into test-developer |
| `codex-test-runner.md` | (reference)         | Kept for reference — merged into codex-test-developer |
| `failure-analyzer.md`  | (reference)         | Kept for reference — merged into test-developer |
| `codex-failure-analyzer.md` | (reference)    | Kept for reference — merged into codex-test-developer |
| `simplifier.md`        | (reference)         | Kept for reference — merged into task agents |
| `test-developer.md`    | 3.1, 3.3            | Run tests, analyze failures, write tests until coverage met (Claude) |
| `codex-test-developer.md` | 3.1, 3.3         | Thin codex-high MCP wrapper for test execution and development |
| `doc-updater.md`       | 4.1                 | Documentation updates (Claude)          |
| `codex-doc-updater.md` | 4.1                 | Thin codex-high MCP wrapper for documentation |
| `claude-md-updater.md` | 4.1 (supplement)    | CLAUDE.md updates                       |
| `test-coverage-reviewer.md` | 4.2 (supplement) | Test coverage analysis                |
| `comment-reviewer.md`  | 4.2 (supplement)    | Comment accuracy review                 |
| `codex-code-quality-reviewer.md` | F3 (Codex primary) | Thin Codex MCP wrapper for code quality review |
| `codex-error-handling-reviewer.md` | F3 (Codex supplement) | Thin Codex MCP wrapper for error handling review |
| `codex-type-reviewer.md` | F3 (Codex supplement) | Thin Codex MCP wrapper for type design review |
| `codex-test-coverage-reviewer.md` | F3 (Codex supplement) | Thin Codex MCP wrapper for test coverage review |
| `codex-comment-reviewer.md` | F3 (Codex supplement) | Thin Codex MCP wrapper for comment review |
| `completion-handler.md`| 4.3                 | Git commit, PR creation, worktree teardown |
| `retrospective-analyst.md` | 4.3 (supplement) | Workflow metrics analysis, CLAUDE.md learnings |

### Debug Workflow Agents

Dispatched by the `/subagents:debug` command for multi-phase debugging:

| Agent File              | Phase           | Purpose                                      |
| ----------------------- | --------------- | -------------------------------------------- |
| `debug-explorer.md`     | 1 (parallel)    | Codebase exploration focused on bug context  |
| `solution-proposer.md`  | 2 (parallel)    | Proposes a specific fix approach             |
| `solution-aggregator.md`| 3               | Aggregates and ranks proposals               |
| `debug-implementer.md`  | 4               | Implements the selected solution             |
| `debug-reviewer.md`     | 5               | Reviews fix for correctness and risk         |
| `debug-doc-updater.md`  | 6               | Updates documentation after fix              |

### Hook Libraries

| Library File       | Purpose                                          |
| ------------------ | ------------------------------------------------ |
| `state.sh`         | State I/O, session scoping (`check_session_owner`) |
| `gates.sh`         | Stage gate validation                            |
| `schedule.sh`      | Phase advancement, `generate_phase_prompt()`     |
| `review.sh`        | Review validation, fix cycles, stage restarts    |
| `fallback.sh`      | Codex timeout detection, retry tracking, Claude fallback |

## Subagent Development Guidelines

Based on the official Claude Code subagent API (https://code.claude.com/docs/en/sub-agents).

### File Format

Agent definitions are Markdown files with YAML frontmatter. The frontmatter configures metadata; the body becomes the system prompt.

```markdown
---
name: my-agent
description: "When Claude should delegate to this agent"
tools: [Read, Glob, Grep]
model: sonnet
---

System prompt content here. This is ALL the agent receives —
not the full Claude Code system prompt.
```

### Frontmatter Fields

| Field             | Required | Description                                                     |
| ----------------- | -------- | --------------------------------------------------------------- |
| `name`            | Yes      | Unique identifier, lowercase with hyphens                       |
| `description`     | Yes      | When Claude should delegate — write clearly so Claude routes correctly |
| `tools`           | No       | Allowlist of tools. Inherits all tools if omitted               |
| `disallowedTools` | No       | Denylist — removed from inherited or specified tools            |
| `model`           | No       | `sonnet`, `opus`, `haiku`, or `inherit` (default: `inherit`)   |
| `permissionMode`  | No       | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan` |
| `skills`          | No       | Skills injected fully into agent context at startup             |
| `hooks`           | No       | Lifecycle hooks scoped to this agent                            |
| `color`           | No       | Background color for UI identification                          |

### Critical Constraints

- **No nesting:** Subagents cannot spawn other subagents. If a workflow needs nested delegation, chain agents from the main conversation or use skills.
- **Isolated context:** Agents receive only their system prompt + basic environment info (working directory). They do NOT receive the full Claude Code system prompt or the parent conversation's context.
- **Skills must be explicit:** Agents don't inherit skills from the parent. List them in `skills:` frontmatter to inject the full skill content.
- **Tool restrictions matter:** Use `tools` (allowlist) or `disallowedTools` (denylist) to enforce capabilities. Read-only agents should specify `tools: [Read, Glob, Grep]` and explicitly exclude `Write`, `Edit`, `Task`.
- **`disallowedTools: [Task]`** prevents agents from spawning further subagents — use this for leaf agents like `sonnet-task-agent.md`.

### Description Best Practices

Claude uses the `description` field to decide when to delegate. Write it to:
- State the agent's specialty clearly
- Include "Use proactively" if the agent should be invoked without explicit user request
- Describe trigger conditions (e.g., "after code changes", "when encountering errors")
- Avoid generic descriptions — Claude needs specificity to route correctly

### Model Selection

| Model     | When to use                                                   |
| --------- | ------------------------------------------------------------- |
| `haiku`   | Fast read-only exploration, low-latency search, cost control  |
| `sonnet`  | Balanced capability — analysis, code review, moderate tasks   |
| `opus`    | Complex reasoning, thorough review, multi-file implementation |
| `inherit` | Same model as parent conversation (default)                   |

### System Prompt Structure (Convention)

This plugin follows a consistent agent prompt structure:

```markdown
# Agent Name

You are a [role]. Your job is to [primary responsibility].

## Your Role
- **Bullet points** describing what the agent does

## Process
1. Step-by-step numbered workflow

## Output Format
Description of expected output structure (JSON schema, markdown, etc.)

## Guidelines / Constraints
- Specific rules and boundaries
```

### Agent Scopes

| Location                     | Scope                   | Priority    |
| ---------------------------- | ----------------------- | ----------- |
| `--agents` CLI flag          | Current session only    | 1 (highest) |
| `.claude/agents/`            | Current project         | 2           |
| `~/.claude/agents/`          | All user projects       | 3           |
| Plugin `agents/` directory   | Where plugin is enabled | 4 (lowest)  |

Plugin agents (this plugin's `agents/` dir) have lowest priority. User or project agents with the same name will override them.

## Hook Development Guidelines

Based on the official Claude Code hooks API (https://code.claude.com/docs/en/hooks).

### Hook Types

| Type      | Description                                          | Key Fields         |
| --------- | ---------------------------------------------------- | ------------------ |
| `command` | Shell script execution — receives JSON on stdin      | `command`, `async` |
| `prompt`  | Single-turn LLM evaluation — returns `{ok, reason}`  | `prompt`, `model`  |
| `agent`   | Multi-turn subagent with tool access (Read, Grep, Glob) | `prompt`, `model` |

### Hook Events

| Event                | When it fires                          | Can block? | Matcher input        |
| -------------------- | -------------------------------------- | ---------- | -------------------- |
| `SessionStart`       | Session begins or resumes              | No         | `startup`, `resume`, `clear`, `compact` |
| `UserPromptSubmit`   | User submits a prompt                  | Yes        | (none)               |
| `PreToolUse`         | Before tool call executes              | Yes        | Tool name            |
| `PermissionRequest`  | Permission dialog about to show        | Yes        | Tool name            |
| `PostToolUse`        | After tool call succeeds               | No         | Tool name            |
| `PostToolUseFailure` | After tool call fails                  | No         | Tool name            |
| `Notification`       | Claude Code sends notification         | No         | Notification type    |
| `SubagentStart`      | Subagent is spawned                    | No         | Agent type name      |
| `SubagentStop`       | Subagent finishes                      | Yes        | Agent type name      |
| `Stop`               | Claude finishes responding             | Yes        | (none)               |
| `PreCompact`         | Before context compaction              | No         | `manual`, `auto`     |
| `SessionEnd`         | Session terminates                     | No         | Exit reason          |

### Exit Codes

| Code  | Meaning                                                                |
| ----- | ---------------------------------------------------------------------- |
| `0`   | Success — stdout parsed for JSON output (`decision`, `reason`, etc.)   |
| `2`   | Blocking error — stderr fed to Claude as error, action blocked         |
| Other | Non-blocking error — stderr shown in verbose mode, execution continues |

### Plugin Hook Configuration (`hooks/hooks.json`)

```json
{
  "description": "Human-readable description",
  "hooks": {
    "EventName": [
      {
        "matcher": "regex pattern",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/script.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- Use `${CLAUDE_PLUGIN_ROOT}` for plugin-relative paths
- Use `"$CLAUDE_PROJECT_DIR"` for project-relative paths (quote for spaces)
- Matchers are regex: `Edit|Write` matches either, `mcp__.*` matches all MCP tools
- Omit matcher or use `"*"` to match all occurrences

### JSON Input (stdin)

All hooks receive common fields plus event-specific fields:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/dir",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": { "command": "npm test" }
}
```

### JSON Output (stdout)

On exit 0, hooks can print JSON to stdout:

| Field            | Description                                                  |
| ---------------- | ------------------------------------------------------------ |
| `decision`       | `"block"` prevents the action (PreToolUse, Stop, SubagentStop) |
| `reason`         | Explanation — shown to Claude when blocking                  |
| `continue`       | `false` stops Claude entirely (takes precedence over `decision`) |
| `stopReason`     | Message shown to user when `continue: false`                 |
| `suppressOutput` | `true` hides stdout from verbose mode                        |
| `systemMessage`  | Warning shown to user                                        |

Event-specific fields go in `hookSpecificOutput`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "explanation",
    "additionalContext": "context for Claude",
    "updatedInput": { "field": "modified value" }
  }
}
```

### Shell Script Conventions (This Plugin)

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

# 1. Read JSON input from stdin
INPUT="$(cat)"

# 2. Check workflow active + session scoping
if ! is_workflow_active; then exit 0; fi
if ! check_session_owner; then exit 0; fi

# 3. Plugin guard (only act on subagents workflows)
STATE_PLUGIN="$(state_get '.plugin // empty')"
if [[ -n "$STATE_PLUGIN" && "$STATE_PLUGIN" != "subagents" ]]; then
  exit 0
fi

# 4. Extract fields with jq
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // ""')"

# 5. Output decision as JSON (or exit 0 silently to allow)
jq -n --arg reason "Explanation" \
  '{"decision":"block","reason":$reason}'
```

### Key Patterns

- **Session scoping:** Always call `check_session_owner()` to prevent cross-conversation interference
- **Plugin guard:** Check `state.plugin == "subagents"` to avoid interfering with other plugins' workflows
- **Workflow check:** `is_workflow_active` returns false when no workflow is running — exit 0 to allow normal operation
- **Silent allow:** Exit 0 with no output to allow without interference
- **Blocking:** Exit 0 with `{"decision":"block","reason":"..."}` to block with guidance to Claude
- **Error blocking:** Exit 2 with stderr message for hard blocks without JSON
- **Atomic state writes:** Use `hooks/lib/state.sh` helpers with jq for state updates — write to tmp then move
- **Validate with `bash -n`:** Always run `bash -n <script>` after modifying hook shell scripts
- **Variable declarations:** Use `local var; var="$(cmd)"` not `local var="$(cmd)"` (avoids masking exit codes with `set -e`)
