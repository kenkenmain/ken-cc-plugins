# Minions Plugin -- Agent Instructions

Personality-driven multi-pipeline workflow with four pipelines: launch (4-phase), superlaunch (15-phase), cursor (Cursor-inspired), and review (review-fix iteration).

## Plugin Structure

```
plugins/minions/
├── .claude-plugin/plugin.json    # Plugin manifest (name, version)
├── agents/                        # Agent definitions (38 agents)
│   ├── architecture-analyst.md    # Architecture pattern analyzer (superlaunch S2)
│   ├── brainstormer.md            # Implementation approach evaluator (superlaunch S1)
│   ├── builder.md                 # Task implementer for launch F2
│   ├── claude-md-updater.md       # CLAUDE.md learnings updater (superlaunch S12)
│   ├── claude-reviewer.md         # Claude reasoning reviewer (standalone)
│   ├── critic.md                  # Correctness reviewer (launch F3, review R1)
│   ├── cursor-builder.md          # Per-task committer for cursor C2/C2.5
│   ├── deep-explorer.md           # Deep architecture tracer (superlaunch S0)
│   ├── doc-updater.md             # Documentation updater (superlaunch S12)
│   ├── explore-aggregator.md      # Merges explorer outputs (superlaunch S0)
│   ├── explorer.md                # Parallel codebase explorer (superlaunch S0)
│   ├── explorer-architecture.md   # Architecture explorer (pre-F1/C1)
│   ├── explorer-files.md          # File structure explorer (pre-F1/C1)
│   ├── explorer-patterns.md       # Coding patterns explorer (pre-F1/C1)
│   ├── explorer-tests.md          # Test conventions explorer (pre-F1/C1)
│   ├── failure-analyzer.md        # Test failure root cause analyzer (superlaunch S8)
│   ├── final-reviewer.md          # Comprehensive final reviewer (superlaunch S13)
│   ├── impl-reviewer.md           # Implementation code reviewer (superlaunch S6)
│   ├── judge.md                   # Continuation judge for cursor C3
│   ├── judgement-agent.md         # Holistic judgment reviewer (launch F3, superlaunch supplementary)
│   ├── pedant.md                  # Quality/style reviewer (launch F3, review R1)
│   ├── plan-aggregator.md         # Merges planner outputs (superlaunch S2)
│   ├── plan-reviewer.md           # Plan completeness reviewer (superlaunch S3)
│   ├── planner.md                 # Implementation plan writer (superlaunch S2)
│   ├── retrospective-analyst.md   # Workflow metrics analyzer (superlaunch S14)
│   ├── review-fixer.md            # Targeted fix agent for review R2
│   ├── scout.md                   # Planning agent for launch F1
│   ├── security-reviewer.md       # Deep security reviewer (launch F3, review R1)
│   ├── shipper.md                 # Commit + PR agent (launch F4, cursor C4, superlaunch S14)
│   ├── silent-failure-hunter.md   # Error handling reviewer (launch F3, review R1)
│   ├── simplifier.md              # Code simplification agent (superlaunch S5)
│   ├── sub-scout.md               # Domain-specific parallel planner (cursor C1)
│   ├── task-agent.md              # Per-task implementer (superlaunch S4)
│   ├── test-developer.md          # Test writer (superlaunch S7/S9)
│   ├── test-dev-reviewer.md       # Test code reviewer (superlaunch S10)
│   ├── test-reviewer.md           # Test coverage reviewer (superlaunch S11)
│   ├── type-reviewer.md           # Type design quality reviewer (superlaunch S6)
│   └── witness.md                 # Runtime verification agent (launch F3, review R1)
├── commands/                      # Slash commands
│   ├── launch.md                  # /minions:launch <task>
│   ├── superlaunch.md             # /minions:superlaunch <task>
│   ├── cursor.md                  # /minions:cursor <task>
│   └── review.md                  # /minions:review <task>
├── hooks/                         # Shell hooks (Ralph-style loop driver)
│   ├── hooks.json                 # Hook event configuration (4 event types)
│   ├── on-launch-init.sh          # UserPromptSubmit: stale state detection
│   ├── on-stop.sh                 # Stop: pipeline router + launch prompt generator
│   ├── on-stop-superlaunch.sh     # Stop: superlaunch prompt generator
│   ├── on-stop-cursor.sh          # Stop: cursor prompt generator + verdict processing
│   ├── on-stop-review.sh          # Stop: review prompt generator + verdict processing
│   ├── on-subagent-stop.sh        # SubagentStop: pipeline router + launch validation
│   ├── on-subagent-stop-superlaunch.sh  # SubagentStop: superlaunch phase advancement
│   ├── on-subagent-stop-cursor.sh       # SubagentStop: cursor verdict handling
│   ├── on-subagent-stop-review.sh       # SubagentStop: review verdict aggregation
│   ├── on-task-gate.sh            # PreToolUse (Task): pipeline router + launch dispatch gate
│   ├── on-task-gate-superlaunch.sh      # PreToolUse (Task): superlaunch dispatch gate
│   ├── on-task-gate-cursor.sh           # PreToolUse (Task): cursor dispatch gate
│   ├── on-task-gate-review.sh           # PreToolUse (Task): review dispatch gate
│   ├── on-edit-gate.sh            # PreToolUse (Edit/Write): pipeline router + launch edit gate
│   ├── on-edit-gate-superlaunch.sh      # PreToolUse (Edit/Write): superlaunch edit gate
│   ├── on-edit-gate-cursor.sh           # PreToolUse (Edit/Write): cursor edit gate
│   ├── on-edit-gate-review.sh           # PreToolUse (Edit/Write): review edit gate
│   └── lib/
│       ├── state.sh               # Core state helpers (check, get, update, validate, lock)
│       ├── superlaunch.sh         # Superlaunch phase routing, prompts, gates, supplementary agents
│       └── cursor.sh              # Cursor agent-phase mapping and prompt generation
├── prompts/                       # Phase prompt templates
│   ├── f0-explorer.md             # Pre-F1 explorer dispatch
│   ├── f1-scout.md                # F1 scout dispatch
│   ├── f2-builder.md              # F2 builder dispatch
│   ├── f3-review.md               # F3 review dispatch
│   ├── f4-shipper.md              # F4 shipper dispatch
│   ├── cursor/
│   │   ├── c1-plan.md             # C1 sub-scout dispatch
│   │   ├── c2-build.md            # C2 cursor-builder dispatch
│   │   ├── c2.5-fix.md            # C2.5 fix-builder dispatch
│   │   └── c3-judge.md            # C3 judge dispatch
│   ├── high-stakes/
│   │   ├── final-review.md        # High-stakes final review template
│   │   ├── implementation.md      # High-stakes implementation template
│   │   ├── plan-review.md         # High-stakes plan review template
│   │   └── test-review.md         # High-stakes test review template
│   └── superlaunch/
│       ├── S0-explore.md          # S0 explore dispatch
│       ├── S1-brainstorm.md       # S1 brainstorm dispatch
│       ├── S2-plan.md             # S2 plan dispatch
│       ├── S3-plan-review.md      # S3 plan review dispatch
│       ├── S4-implement.md        # S4 implement dispatch
│       ├── S5-simplify.md         # S5 simplify dispatch
│       ├── S6-impl-review.md      # S6 implementation review dispatch
│       ├── S7-run-tests.md        # S7 test run dispatch
│       ├── S8-analyze.md          # S8 failure analysis dispatch
│       ├── S9-develop-tests.md    # S9 test development dispatch
│       ├── S10-test-dev-review.md # S10 test dev review dispatch
│       ├── S11-test-review.md     # S11 test review dispatch
│       ├── S12-documentation.md   # S12 documentation dispatch
│       ├── S13-final-review.md    # S13 final review dispatch
│       └── S14-completion.md      # S14 completion dispatch
├── skills/                        # Workflow documentation
│   ├── workflow/SKILL.md          # Ralph-style orchestration reference
│   ├── superlaunch/SKILL.md       # Superlaunch pipeline reference
│   └── review/SKILL.md            # Review pipeline reference
└── CLAUDE.md                      # This file -- architecture docs
```

## Agent Roster

| # | Agent | Role | Model | Tools | Leaf? |
|---|-------|------|-------|-------|-------|
| 1 | architecture-analyst | Codebase patterns and architecture blueprint | inherit | Read, Write, Glob, Grep | Yes |
| 2 | brainstormer | Implementation approach evaluator | inherit | Read, Write | Yes |
| 3 | builder | Task implementer for launch F2 | inherit | Read, Grep, Glob, Edit, Write, Bash | Yes |
| 4 | claude-md-updater | CLAUDE.md learnings updater | sonnet | Read, Write, Edit, Glob, Grep | Yes |
| 5 | claude-reviewer | Claude reasoning reviewer (standalone) | inherit | Read, Glob, Grep | Yes |
| 6 | critic | Correctness reviewer (bugs, logic, security) | inherit | Read, Glob, Grep, Bash | Yes |
| 7 | cursor-builder | Per-task committer for cursor C2/C2.5 | inherit | Read, Grep, Glob, Edit, Write, Bash | Yes |
| 8 | deep-explorer | Deep architecture tracer | haiku | Read, Glob, Grep, Write | Yes |
| 9 | doc-updater | Documentation updater | sonnet | Read, Write, Edit, Glob, Grep | Yes |
| 10 | explore-aggregator | Merges parallel explorer outputs | haiku | Read, Write, Glob | Yes |
| 11 | explorer | Parallel codebase explorer (1-10 agents) | haiku | Read, Glob, Grep, Write | Yes |
| 12 | explorer-architecture | Fast architecture explorer (pre-F1/C1) | haiku | Read, Write, Glob, Grep | Yes |
| 13 | explorer-files | Fast file structure explorer (pre-F1/C1) | haiku | Read, Write, Glob, Grep | Yes |
| 14 | explorer-patterns | Fast coding patterns explorer (pre-F1/C1) | haiku | Read, Write, Glob, Grep | Yes |
| 15 | explorer-tests | Fast test conventions explorer (pre-F1/C1) | haiku | Read, Write, Glob, Grep | Yes |
| 16 | failure-analyzer | Test failure root cause analyzer | inherit | Read, Write, Edit, Glob, Grep | Yes |
| 17 | final-reviewer | Comprehensive final reviewer | inherit | Read, Glob, Grep | Yes |
| 18 | impl-reviewer | Implementation code reviewer | inherit | Read, Glob, Grep | Yes |
| 19 | judge | Continuation judge (approve/fix/replan) | inherit | Read, Glob, Grep, Bash | Yes |
| 20 | judgement-agent | Holistic judgment reviewer | sonnet | Read, Glob, Grep, Bash | Yes |
| 21 | pedant | Quality/style reviewer | inherit | Read, Glob, Grep, Bash | Yes |
| 22 | plan-aggregator | Merges parallel planner outputs | haiku | Read, Write, Glob | Yes |
| 23 | plan-reviewer | Plan completeness reviewer | inherit | Read, Glob, Grep | Yes |
| 24 | planner | Implementation plan writer (parallel batch) | inherit | Read, Write, Glob, Grep | Yes |
| 25 | retrospective-analyst | Workflow metrics and learnings | inherit | Read, Write, Edit, Glob, Grep | Yes |
| 26 | review-fixer | Targeted fix agent for review R2 | inherit | Read, Write, Edit, Glob, Grep, Bash | Yes |
| 27 | scout | Planning agent for launch F1 | sonnet | Read, Glob, Grep, WebSearch | Yes |
| 28 | security-reviewer | Deep security reviewer (OWASP, injection) | inherit | Read, Glob, Grep, Bash | Yes |
| 29 | shipper | Commit + PR agent | sonnet | Read, Glob, Grep, Edit, Write, Bash | Yes |
| 30 | silent-failure-hunter | Error handling reviewer | inherit | Read, Glob, Grep, Bash | Yes |
| 31 | simplifier | Code simplification agent | inherit | Read, Write, Edit, Glob, Grep | Yes |
| 32 | sub-scout | Domain-specific parallel planner | sonnet | Read, Glob, Grep, WebSearch | Yes |
| 33 | task-agent | Per-task implementer (superlaunch S4) | inherit | Read, Write, Edit, Bash, Glob, Grep, WebSearch | Yes |
| 34 | test-developer | Test writer and CI config | inherit | Read, Write, Edit, Bash, Glob, Grep, WebSearch | Yes |
| 35 | test-dev-reviewer | Test code quality reviewer | inherit | Read, Glob, Grep | Yes |
| 36 | test-reviewer | Test coverage reviewer | inherit | Read, Glob, Grep | Yes |
| 37 | type-reviewer | Type design quality reviewer | sonnet | Read, Glob, Grep | Yes |
| 38 | witness | Runtime verification agent | inherit | Read, Glob, Grep, Bash, WebFetch | Yes |

All agents have `disallowedTools: [Task]` -- no agent can spawn subagents. The orchestrator (hooks) manages phase progression via the Ralph Loop pattern.

**Read-only reviewers:** Agents in rows 6, 17, 18-21, 23, 28, 30, 35-37 have `disallowedTools: [Edit, Write, Task]` -- reviewers must never modify source files. The judge (row 19) and witness (row 38) have `permissionMode: plan` and `permissionMode: default` respectively.

### Pipeline Agent Usage

| Agent | launch | cursor | superlaunch | review |
|-------|--------|--------|-------------|--------|
| explorer-files/architecture/tests/patterns | Pre-F1 | Pre-C1 | -- | -- |
| explorer, deep-explorer, explore-aggregator | -- | -- | S0 | -- |
| scout | F1 | -- | -- | -- |
| sub-scout | -- | C1 | -- | -- |
| brainstormer | -- | -- | S1 | -- |
| planner, architecture-analyst, plan-aggregator | -- | -- | S2 | -- |
| plan-reviewer | -- | -- | S3 | -- |
| builder | F2 | -- | -- | -- |
| cursor-builder | -- | C2, C2.5 | -- | -- |
| task-agent | -- | -- | S4 | -- |
| simplifier | -- | -- | S5 | -- |
| impl-reviewer | -- | -- | S6 | -- |
| critic, pedant, witness, security-reviewer, silent-failure-hunter | F3 | -- | -- | R1 |
| judgement-agent | F3 | -- | S3, S6, S10, S11, S13 | -- |
| judge | -- | C3 | -- | -- |
| review-fixer | -- | -- | -- | R2 |
| test-developer, failure-analyzer | -- | -- | S7-S9 | -- |
| test-dev-reviewer, test-reviewer | -- | -- | S10, S11 | -- |
| doc-updater, claude-md-updater | -- | -- | S12 | -- |
| final-reviewer, retrospective-analyst | -- | -- | S13, S14 | -- |
| shipper | F4 | C4 | S14 | -- |

## Four Pipelines

### Launch (4-phase)

```
Explorers (4x haiku, parallel) --> F1 (scout) --> F2 (builders) --> F3 (6 reviewers, parallel)
                                     ^                                    |
                                     +---------- if issues ---------------+
                                                 (max 10 loops)

All clean --> F4 (shipper)
```

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| Pre-F1 | EXPLORE | explorer-files, explorer-architecture, explorer-tests, explorer-patterns (4x parallel haiku) | Pre-scout codebase context |
| F1 | SCOUT | scout x1 | Explore + plan with task table |
| F2 | BUILD | builder xN (per task, parallel) | Implement all tasks from plan |
| F3 | REVIEW | critic, pedant, witness, security-reviewer, silent-failure-hunter, judgement-agent (6x parallel) | Parallel personality-driven review |
| F4 | SHIP | shipper x1 | Documentation + commit + PR |

Command: `/minions:launch <task>`

### Cursor (Cursor-inspired)

```
Explorers (4x haiku) --> C1 (sub-scouts) --> C2 (cursor-builders) --> C3 (judge)
                              ^                                         |
                              |              +-- approve --> C4 (ship)
                              +-- replan ----+
                                             +-- fix --> C2.5 (fix-builders) --> C3
                                                         ^                       |
                                                         +--- fix (max 5) ------+
```

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| Pre-C1 | EXPLORE | explorer-files, explorer-architecture, explorer-tests, explorer-patterns (4x parallel haiku) | Pre-plan codebase context |
| C1 | PLAN | sub-scout x2-3 (parallel, per domain) | Domain-specific parallel planning |
| C2 | BUILD | cursor-builder xN (per task, parallel commits) | Implement with per-task git commits |
| C3 | JUDGE | judge x1 | Single verdict: approve/fix/replan |
| C2.5 | FIX | cursor-builder xN (per fix group) | Targeted fix patches |
| C4 | SHIP | shipper x1 | Squash-merge + PR |

Command: `/minions:cursor <task>`

### Superlaunch (15-phase)

```
EXPLORE --> PLAN --> IMPLEMENT --> TEST --> FINAL --> COMPLETE
  S0       S1-S3     S4-S6       S7-S11    S12-S14
```

| Phase | Stage | Agent(s) | Type | Description |
|-------|-------|----------|------|-------------|
| S0 | EXPLORE | explorer + deep-explorer + explore-aggregator | dispatch | Parallel codebase exploration |
| S1 | PLAN | brainstormer | subagent | Implementation approach analysis |
| S2 | PLAN | planner + architecture-analyst + plan-aggregator | dispatch | Parallel planning + aggregation |
| S3 | PLAN | plan-reviewer + judgement-agent | review | Plan validation |
| S4 | IMPLEMENT | task-agent xN (parallel batch) | dispatch | Per-task implementation |
| S5 | IMPLEMENT | simplifier | subagent | Code simplification pass |
| S6 | IMPLEMENT | impl-reviewer + critic + judgement-agent + silent-failure-hunter + type-reviewer | review | Implementation review |
| S7 | TEST | test-developer | subagent | Run tests |
| S8 | TEST | failure-analyzer | subagent | Analyze test failures |
| S9 | TEST | test-developer | subagent | Develop additional tests |
| S10 | TEST | test-dev-reviewer + judgement-agent | review | Test code review |
| S11 | TEST | test-reviewer + judgement-agent | review | Test coverage review (coverage loop) |
| S12 | FINAL | doc-updater + claude-md-updater | subagent | Documentation update |
| S13 | FINAL | final-reviewer + judgement-agent + pedant + security-reviewer + silent-failure-hunter | review | Final review |
| S14 | FINAL | shipper + retrospective-analyst | subagent | Commit + PR + learnings |

Command: `/minions:superlaunch <task>`

**Stage gates:** EXPLORE->PLAN (S0-explore.md), PLAN->IMPLEMENT (S1-brainstorm.md, S2-plan.md, S3-plan-review.json), IMPLEMENT->TEST (S4-tasks.json, S6-impl-review.json), TEST->FINAL (S7-test-results.json, S9-test-dev.json, S11-test-review.json), FINAL->COMPLETE (S13-final-review.json).

**Review-fix cycles:** Review phases (S3, S6, S10, S11, S13) support two-tier retry: 10 fix attempts per review phase (tier 1) and 3 stage restarts per stage (tier 2). Total: up to 30 fix attempts per review phase before blocking.

**Coverage loop:** Phases S9->S10->S11 repeat until `coverage >= coverageThreshold` (default 90%) or 20 iterations reached.

### Review (review-fix iteration)

```
R1 (5x reviewers, parallel) --> R2 (review-fixer)
        ^                            |
        +---- next iteration --------+
               (max 5 iterations)

R1 clean (0 issues) --> DONE
Iteration 5 with issues --> STOPPED
```

| Phase | Agent(s) | Description |
|-------|----------|-------------|
| R1 | critic, pedant, witness, security-reviewer, silent-failure-hunter (5x parallel) | Parallel review |
| R2 | review-fixer x1 | Fix ALL issues (critical, warning, info) |

Command: `/minions:review <task>`

## Hook Architecture

All pipelines share the same hook entry points. Each entry-point hook checks `state.pipeline` and delegates to the pipeline-specific handler via `exec`.

### hooks.json Configuration

```json
{
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type":"command","command":"on-launch-init.sh","timeout":5}]}],
    "Stop": [{"hooks": [{"type":"command","command":"on-stop.sh","timeout":10}]}],
    "SubagentStop": [{"hooks": [{"type":"command","command":"on-subagent-stop.sh","timeout":15}]}],
    "PreToolUse": [
      {"matcher":"Task","hooks": [{"type":"command","command":"on-task-gate.sh","timeout":5}]},
      {"matcher":"Edit|Write","hooks": [{"type":"command","command":"on-edit-gate.sh","timeout":5}]}
    ]
  }
}
```

### on-launch-init.sh (UserPromptSubmit)

- Detects existing workflow state when launching `/minions:launch`, `/minions:superlaunch`, or `/minions:review`
- Validates state.json is valid JSON and belongs to the minions plugin
- Checks if ownerPpid process is still alive (active session detection)
- Injects resume/clean prompts for stale or active workflows
- Non-blocking: uses `additionalContext` to inform Claude, never blocks the prompt

### on-stop.sh (Stop -- launch pipeline router)

- Checks workflow active and delegates to pipeline-specific handler:
  - `pipeline == "cursor"` -> `on-stop-cursor.sh`
  - `pipeline == "superlaunch"` -> `on-stop-superlaunch.sh`
  - `pipeline == "review"` -> `on-stop-review.sh`
- **Launch pipeline:** Generates phase-specific orchestrator prompts (F1/F2/F3/F4)
- Includes recovery logic: if output files exist but SubagentStop did not fire, advances state (F2->F3, F3->F4/loop)
- F3 verdict processing: cross-validates `overall_verdict` against `total_issues` (fail-safe: forces `issues_found` if `clean` with >0 issues)
- Loop-back: increments loop counter, creates new loop entry in state, re-generates F1 prompt
- Max loops: transitions to STOPPED status
- Terminal states (DONE/STOPPED): allows stop (exit 0 silent)

### on-stop-superlaunch.sh (Stop -- superlaunch)

- Calls `generate_sl_prompt()` from `lib/superlaunch.sh` for schedule-driven prompt generation
- Terminal states (DONE/STOPPED/COMPLETE): allows stop
- Minimal logic -- all complexity lives in `superlaunch.sh`

### on-stop-cursor.sh (Stop -- cursor)

- Includes recovery logic for C2->C3 and C2.5->C3 transitions
- C3 verdict processing: reads `c3-judge.json`, cross-validates approve with critical/warning issues
- Three-way verdict: approve->C4, fix->C2.5 (increment fixCycle), replan->C1 (increment loop)
- Fix cycle exhaustion: forces replan after maxFixCycles (default 5)
- Max replans: transitions to STOPPED
- Calls `generate_cursor_prompt()` from `lib/cursor.sh` for prompt generation

### on-stop-review.sh (Stop -- review)

- R1 verdict recovery: processes `r1-verdict.json` if SubagentStop did not fire
- R2 recovery: advances to next iteration R1 if `r2-fix-summary.md` exists
- R1 prompt: dispatches 5 parallel reviewers with iteration context
- R2 prompt: dispatches review-fixer with issue count from r1-verdict.json
- Clean verdict: transitions directly to DONE (no R2 needed)
- Max iterations: transitions to STOPPED

### on-subagent-stop.sh (SubagentStop -- launch pipeline router)

- Reads agent type from stdin JSON (`agent_name` field)
- Delegates to pipeline-specific handler via env var + exec:
  - `CURSOR_AGENT_TYPE` -> `on-subagent-stop-cursor.sh`
  - `SL_AGENT_TYPE` -> `on-subagent-stop-superlaunch.sh`
  - `REVIEW_AGENT_TYPE` -> `on-subagent-stop-review.sh`
- **Launch pipeline:** Phase-specific validation:
  - F1 (scout): validates `f1-plan.md` exists, advances to F2
  - F2 (builder): validates `f2-tasks.json` schema (`tasks`, `files_changed`, `all_complete`), advances to F3 with mkdir lock
  - F3 (6 reviewers): waits for all 6 output files, validates JSON, aggregates verdicts into `f3-verdict.json`, advances to F4 or loops back with mkdir lock
  - F4 (shipper): validates `f4-ship.json` schema (`commit_sha`, `docs_updated`), marks workflow DONE
- Concurrent safety: mkdir-based locks with stale lock detection (60s timeout) prevent duplicate state advancement

### on-subagent-stop-superlaunch.sh (SubagentStop -- superlaunch)

- Skips supplementary agents (they do not drive phase advancement)
- Aggregator agents: validates output file, checks stage gates at boundaries, advances state
- Primary agents: validates output, checks for aggregator phases (defers to aggregator if present)
- Review phases: handles verdict processing (approved, needs_revision, needs_coverage, blocked)
- Two-tier retry: fix attempts (tier 1, maxFixAttempts=10) -> stage restarts (tier 2, maxStageRestarts=3)
- Coverage loop: S11 `needs_coverage` verdict loops back to S9 (up to 20 iterations)
- Phase locking: mkdir-based with stale lock detection (120s timeout)
- Clears `reviewFix` state after successful fix cycle completion

### on-subagent-stop-cursor.sh (SubagentStop -- cursor)

- sub-scout: waits for `c1-plan.md` (orchestrator writes after aggregation), advances C1->C2
- cursor-builder in C2: waits for `c2-tasks.json`, advances C2->C3 with lock
- cursor-builder in C2.5: waits for `c2.5-fixes.json`, advances C2.5->C3 with lock
- judge: validates `c3-judge.json`, cross-validates approve verdict, handles fix/replan
- shipper: validates `c4-ship.json`, marks workflow DONE

### on-subagent-stop-review.sh (SubagentStop -- review)

- R1 reviewers (5 agents): waits for all 5 output files, validates JSON, aggregates into `r1-verdict.json`
- Clean verdict: marks workflow complete (DONE)
- Issues + under max iterations: advances to R2
- Issues + at max: transitions to STOPPED
- review-fixer: validates `r2-fix-summary.md`, increments iteration, creates next iteration directory, resets to R1

### on-task-gate.sh (PreToolUse: Task -- launch pipeline router)

- Validates dispatched agent matches current phase
- Delegates to pipeline-specific handler for non-launch pipelines
- **Launch pipeline:** Maps agents to expected phases (scout->F1, builder->F2, reviewers->F3, shipper->F4)
- Prerequisite checks: f1-plan.md for F2, f2-tasks.json for F3, f3-verdict.json with clean verdict for F4
- Explorer agents (pre-F1): always allowed (exit 0)
- Non-minions agents: silently allowed

### on-edit-gate.sh (PreToolUse: Edit/Write -- launch pipeline router)

- Blocks source file edits outside allowed phases
- Always allows writes to `.agents/` path (workflow output files)
- Always allows writes to paths outside the project directory
- Delegates to pipeline-specific handler for non-launch pipelines
- **Launch pipeline:** allows edits in F2 (build) and F4 (ship) only
- **Superlaunch:** allows edits in IMPLEMENT, TEST, and FINAL stages
- **Cursor:** allows edits in C2, C2.5, and C4
- **Review:** allows edits in R2 only
- Fail-closed: blocks if `file_path` is empty or missing

## State Management

State tracked in `.agents/tmp/state.json`. Shared libraries in `hooks/lib/`:

### state.sh (core)

- `check_workflow_active()` -- plugin guard (`plugin == "minions"`), session scoping (`ownerPpid`, `sessionId`), status check
- `state_get()` -- read fields with optional `--required` validation
- `update_state()` -- atomic state update with file locking (flock with mkdir fallback on macOS)
- `validate_json_file()` -- check file exists and contains valid JSON
- `require_int()` -- validate integer fields
- `lock_dir_mtime_epoch()` -- cross-platform directory mtime (Linux `stat -c %Y` with macOS `stat -f %m` fallback)

### superlaunch.sh (superlaunch routing)

- `get_sl_next_phase()` -- next phase from schedule
- `get_sl_phase_output()` / `get_sl_phase_input()` -- expected output/input filenames
- `get_sl_phase_agent()` -- primary agent for phase (review phases use dedicated reviewers)
- `get_sl_supplementary()` -- supplementary agents (respects `supplementaryPolicy`)
- `sl_phase_has_aggregator()` / `get_sl_phase_aggregator()` -- aggregator support (S0, S2)
- `is_sl_supplementary_agent()` / `is_sl_aggregator_agent()` -- agent type classification
- `validate_sl_gate()` -- check gate requirements at stage boundaries
- `generate_sl_prompt()` -- build orchestrator prompt from phase metadata (~40-70 lines)
- `get_sl_editable_stages()` -- returns `"IMPLEMENT TEST FINAL"`
- `get_sl_agent_phases()` / `is_sl_agent_allowed()` -- agent-to-phase mapping for dispatch/stop gates
- `get_sl_task_progress_instruction()` -- TaskUpdate instructions for stage transitions
- `get_sl_fix_cycle_task_instruction()` -- fix-cycle sub-task creation
- `get_sl_stage_restart_task_instruction()` -- stage-restart sub-task creation
- `get_sl_coverage_loop_task_instruction()` -- coverage-loop sub-task creation

### cursor.sh (cursor routing)

- `get_cursor_agent_phases()` -- maps agent to allowed phases (sub-scout->C1, cursor-builder->C2/C2.5, judge->C3, shipper->C4, explorers->PRE)
- `is_cursor_agent_allowed()` -- check if agent can run in current phase
- `generate_cursor_prompt()` -- build orchestrator prompt for each cursor phase (C1/C2/C2.5/C3/C4)

Session scoping via `ownerPpid` + `sessionId` ensures hooks only fire for the session that owns the workflow.

## State Schema

### Launch Pipeline

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "launch",
  "status": "in_progress|stopped|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID>",
  "currentPhase": "F1|F2|F3|F4|DONE|STOPPED",
  "loop": 1,
  "maxLoops": 10,
  "branch": "<feature branch name>",
  "startedAt": "ISO timestamp",
  "updatedAt": "ISO timestamp",
  "schedule": [
    {"phase": "F1", "name": "Scout", "type": "subagent"},
    {"phase": "F2", "name": "Build", "type": "dispatch"},
    {"phase": "F3", "name": "Review", "type": "dispatch"},
    {"phase": "F4", "name": "Ship", "type": "subagent"}
  ],
  "loops": [
    {
      "loop": 1,
      "startedAt": "ISO timestamp",
      "f1": {"status": "pending|complete"},
      "f2": {"status": "pending|complete"},
      "f3": {"status": "pending|complete", "verdict": "clean|issues_found"}
    }
  ],
  "files": [],
  "failure": null
}
```

### Cursor Pipeline

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "cursor",
  "status": "in_progress|stopped|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID>",
  "currentPhase": "C1|C2|C2.5|C3|C4|DONE|STOPPED",
  "loop": 1,
  "maxLoops": 3,
  "fixCycle": 0,
  "maxFixCycles": 5,
  "branch": "<feature branch name>",
  "startedAt": "ISO timestamp",
  "updatedAt": "ISO timestamp",
  "schedule": [
    {"phase": "C1", "name": "Plan", "type": "dispatch"},
    {"phase": "C2", "name": "Build", "type": "dispatch"},
    {"phase": "C3", "name": "Judge", "type": "subagent"},
    {"phase": "C4", "name": "Ship", "type": "subagent"}
  ],
  "loops": [
    {
      "loop": 1,
      "startedAt": "ISO timestamp",
      "c1": {"status": "pending|complete"},
      "c2": {"status": "pending|complete"},
      "c3": {"status": "pending|complete", "verdict": "approve|fix|replan"}
    }
  ],
  "files": [],
  "failure": null
}
```

### Superlaunch Pipeline

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "superlaunch",
  "status": "in_progress|blocked|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID>",
  "currentPhase": "S0|S1|...|S14|DONE|STOPPED",
  "currentStage": "EXPLORE|PLAN|IMPLEMENT|TEST|FINAL",
  "codexAvailable": false,
  "testDeveloper": "minions:test-developer",
  "failureAnalyzer": "minions:failure-analyzer",
  "docUpdater": "minions:doc-updater",
  "branch": "<feature branch name>",
  "startedAt": "ISO timestamp",
  "updatedAt": "ISO timestamp",
  "schedule": [
    {"phase":"S0","stage":"EXPLORE","name":"Explore","type":"dispatch"},
    {"phase":"S1","stage":"PLAN","name":"Brainstorm","type":"subagent"},
    {"phase":"S2","stage":"PLAN","name":"Plan","type":"dispatch"},
    {"phase":"S3","stage":"PLAN","name":"Plan Review","type":"review"},
    {"phase":"S4","stage":"IMPLEMENT","name":"Implement","type":"dispatch"},
    {"phase":"S5","stage":"IMPLEMENT","name":"Simplify","type":"subagent"},
    {"phase":"S6","stage":"IMPLEMENT","name":"Impl Review","type":"review"},
    {"phase":"S7","stage":"TEST","name":"Run Tests","type":"subagent"},
    {"phase":"S8","stage":"TEST","name":"Analyze","type":"subagent"},
    {"phase":"S9","stage":"TEST","name":"Develop Tests","type":"subagent"},
    {"phase":"S10","stage":"TEST","name":"Test Dev Review","type":"review"},
    {"phase":"S11","stage":"TEST","name":"Test Review","type":"review"},
    {"phase":"S12","stage":"FINAL","name":"Documentation","type":"subagent"},
    {"phase":"S13","stage":"FINAL","name":"Final Review","type":"review"},
    {"phase":"S14","stage":"FINAL","name":"Completion","type":"subagent"}
  ],
  "gates": {
    "EXPLORE->PLAN": {"required":["S0-explore.md"]},
    "PLAN->IMPLEMENT": {"required":["S1-brainstorm.md","S2-plan.md","S3-plan-review.json"]},
    "IMPLEMENT->TEST": {"required":["S4-tasks.json","S6-impl-review.json"]},
    "TEST->FINAL": {"required":["S7-test-results.json","S9-test-dev.json","S11-test-review.json"]},
    "FINAL->COMPLETE": {"required":["S13-final-review.json"]}
  },
  "stages": {
    "EXPLORE": {"status":"pending","phases":["S0"],"restartCount":0},
    "PLAN": {"status":"pending","phases":["S1","S2","S3"],"restartCount":0},
    "IMPLEMENT": {"status":"pending","phases":["S4","S5","S6"],"restartCount":0},
    "TEST": {"status":"pending","phases":["S7","S8","S9","S10","S11"],"restartCount":0},
    "FINAL": {"status":"pending","phases":["S12","S13","S14"],"restartCount":0}
  },
  "reviewPolicy": {"maxFixAttempts": 10, "maxStageRestarts": 3},
  "supplementaryPolicy": "on-issues",
  "coverageThreshold": 90,
  "webSearch": true,
  "fixAttempts": {},
  "coverageLoop": {"iteration": 0},
  "reviewFix": null,
  "supplementaryRun": {},
  "failure": null
}
```

### Review Pipeline

```json
{
  "version": 1,
  "plugin": "minions",
  "pipeline": "review",
  "status": "in_progress|stopped|complete",
  "task": "<task description>",
  "ownerPpid": "<process ID>",
  "sessionId": "<session ID>",
  "currentPhase": "R1|R2|DONE|STOPPED",
  "iteration": 1,
  "maxIterations": 5,
  "startedAt": "ISO timestamp",
  "updatedAt": "ISO timestamp",
  "schedule": [
    {"phase": "R1", "name": "Review", "type": "dispatch"},
    {"phase": "R2", "name": "Fix", "type": "subagent"}
  ],
  "iterations": [
    {
      "iteration": 1,
      "startedAt": "ISO timestamp",
      "r1": {"status": "pending|complete", "verdict": "clean|issues_found"},
      "r2": {"status": "pending|complete"},
      "verdict": null
    }
  ],
  "files": [],
  "failure": null
}
```

### Output File Layout

```
.agents/tmp/
├── state.json                              # Workflow state
├── phases/
│   ├── f0-explorer.files.tmp               # Explorer output (launch/cursor)
│   ├── f0-explorer.architecture.tmp
│   ├── f0-explorer.tests.tmp
│   ├── f0-explorer.patterns.tmp
│   ├── f0-explorer-context.md              # Aggregated explorer context
│   ├── loop-1/                             # Launch/cursor loop directory
│   │   ├── f1-plan.md                      # Scout plan (launch)
│   │   ├── f2-tasks.json                   # Builder results (launch)
│   │   ├── f3-critic.json                  # Critic review (launch)
│   │   ├── f3-pedant.json                  # Pedant review (launch)
│   │   ├── f3-witness.json                 # Witness review (launch)
│   │   ├── f3-security-reviewer.json       # Security review (launch)
│   │   ├── f3-silent-failure-hunter.json   # Silent failure review (launch)
│   │   ├── f3-judgement-agent.json         # Judgement review (launch)
│   │   ├── f3-verdict.json                 # Aggregated verdict (launch)
│   │   ├── f4-ship.json                    # Shipper output (launch)
│   │   ├── c1-sub-scout.*.md               # Sub-scout plans (cursor)
│   │   ├── c1-plan.md                      # Merged plan (cursor)
│   │   ├── c2-tasks.json                   # Builder results (cursor)
│   │   ├── c2.5-fixes.json                 # Fix results (cursor)
│   │   ├── c3-judge.json                   # Judge verdict (cursor)
│   │   └── c4-ship.json                    # Shipper output (cursor)
│   ├── S0-explore.md                       # Superlaunch explore output
│   ├── S1-brainstorm.md
│   ├── S2-plan.md
│   ├── S3-plan-review.json
│   ├── S4-tasks.json
│   ├── S5-simplify.md
│   ├── S6-impl-review.json
│   ├── S7-test-results.json
│   ├── S8-analysis.md
│   ├── S9-test-dev.json
│   ├── S10-test-dev-review.json
│   ├── S11-test-review.json
│   ├── S12-docs.md
│   ├── S13-final-review.json
│   ├── S14-completion.json
│   ├── review-1/                           # Review pipeline iteration directory
│   │   ├── r1-critic.json
│   │   ├── r1-pedant.json
│   │   ├── r1-witness.json
│   │   ├── r1-security-reviewer.json
│   │   ├── r1-silent-failure-hunter.json
│   │   ├── r1-verdict.json
│   │   └── r2-fix-summary.md
│   └── review-2/
│       └── ...
```

## Verdict Field Contracts

Different pipelines use different verdict field names because they serve distinct purposes:

| Pipeline | File(s) | Field | Values | Semantics |
|----------|---------|-------|--------|-----------|
| launch | `f3-verdict.json` | `overall_verdict` | `"clean"` / `"issues_found"` | Review verdict -- did reviewers find problems? |
| review | `r1-verdict.json` | `overall_verdict` | `"clean"` / `"issues_found"` | Review verdict -- same semantics as launch F3 |
| cursor | `c2-tasks.json`, `c2.5-fixes.json` | `all_complete` | `true` / `false` | Task-completion flag -- did all builders finish? |

**Why the fields differ:** `overall_verdict` is a review outcome (clean vs issues found) used by launch F3 and review R1 where parallel reviewers aggregate their findings. `all_complete` is a build-completion flag used by cursor C2/C2.5 where parallel cursor-builders report whether all tasks were implemented. The cursor pipeline defers its review verdict to the judge agent in C3 (`c3-judge.json`), which uses a three-way `verdict` field (`approve`/`fix`/`replan`).

Cross-validation rules:
- `overall_verdict: "clean"` is force-corrected to `"issues_found"` if `total_issues > 0` (fail-safe in `on-stop.sh` and `on-stop-review.sh`)
- `all_complete: true` is validated against individual task statuses in `on-subagent-stop-cursor.sh`

## Code Style

- **Markdown:** YAML frontmatter, follow existing agent structure
- **Naming:** kebab-case for files (e.g., `silent-failure-hunter.md`, `explore-aggregator.md`)
- **Agent theme:** Personality-driven roles (critic, pedant, witness, judge, scout, builder, shipper)
- **Shell hooks:** `set -euo pipefail`, use `local var; var="$(cmd)"` (not `local var="$(cmd)"`), source libs from `$SCRIPT_DIR/lib/`
- **Shell validation:** Run `bash -n <script>` after modifying hook shell scripts
- **Pipeline delegation:** Entry-point hooks check `state.pipeline` and `exec` to pipeline-specific scripts
- **Concurrent safety:** mkdir-based locks with stale lock detection for parallel agent advancement
- **Fail-safe verdicts:** Cross-validate `verdict` against issue counts; force `issues_found` if `clean` with >0 issues
- **Git commits:** Prefix with `feat|fix|docs|chore|ci`, include co-author line
- **Git excludes:** Never commit `.agents/**`, `*.tmp`, `*.log`

## Boundaries

### Always

- Update state.json after each phase completes
- Follow phase progression within each pipeline
- Respect stage gates before advancing (superlaunch)
- Validate output files before marking phases complete
- Use `disallowedTools: [Task]` on all leaf agents
- Cross-validate verdicts against issue counts (fail-safe)
- Use mkdir-based locks for concurrent phase advancement
- Bump plugin.json version on changes
- Check loop/iteration limits before looping back

### Ask First

- Skipping phases or stages
- Changing maxLoops/maxIterations mid-workflow
- Modifying state.json schema
- Adding new agents to the roster
- Adding a new pipeline type
- Changing review-fix retry limits

### Never

- Skip verdict validation -- always cross-validate counts vs declared verdict
- Ship when issues remain unresolved
- Allow agents to spawn subagents (all are leaf agents)
- Commit secrets or credentials
- Modify source files during non-build phases (enforced by edit gate)
- Proceed past maxLoops/maxIterations without user approval
- Advance state without validating output files exist and are well-formed
