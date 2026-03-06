# ants Plugin -- Agent Instructions

Ant-colony themed swarm workflow with dual-track parallel build and quality execution.

## Plugin Structure

```
plugins/ants/
├── .claude-plugin/plugin.json    # Plugin manifest (name, version)
├── agents/                        # Agent definitions (11 agents)
│   ├── architect.md               # Plan writer with wave assignments
│   ├── blueprint-reviewer.md      # Plan validator
│   ├── cartographer.md            # Deep architecture tracer
│   ├── drone.md                   # Commit + PR shipper
│   ├── explore-aggregator.md      # Merges forager/cartographer outputs
│   ├── forager.md                 # Breadth-first codebase scout
│   ├── guardian.md                # Test writer for quality track
│   ├── nurse.md                   # Documentation updater
│   ├── queen.md                   # Track sync + ship/loop verdict
│   ├── sentinel.md                # Sentinel code reviewer
│   └── worker.md                  # Task implementer (one per task)
├── commands/                      # Slash commands
│   └── swarm.md                   # /ants:swarm <task>
├── hooks/                         # Shell hooks (Ralph Loop driver)
│   ├── hooks.json                 # Hook event configuration
│   ├── on-stop.sh                 # Stop: prompt re-injection
│   ├── on-subagent-stop.sh        # SubagentStop: validate + advance
│   ├── on-task-gate.sh            # PreToolUse (Task): dispatch validation
│   ├── on-edit-gate.sh            # PreToolUse (Edit/Write): edit control
│   └── lib/
│       ├── state.sh               # Shared bash state helpers
│       └── swarm.sh               # Pipeline-specific phase routing
├── prompts/                       # Phase prompt templates
│   ├── A0-explore.md              # Colony exploration dispatch
│   └── A1-plan.md                 # Architect plan dispatch
├── skills/                        # Workflow documentation
│   ├── swarm/SKILL.md             # Swarm pipeline reference
│   └── workflow/SKILL.md          # Ralph Loop mechanics
├── CLAUDE.md                      # This file -- architecture docs
└── README.md                      # User-facing documentation
```

## Agent Roster

| # | Agent | Role | Model | Tools | Leaf? |
|---|-------|------|-------|-------|-------|
| 1 | forager | Breadth-first codebase scout | haiku | Read, Glob, Grep, Write | Yes |
| 2 | cartographer | Deep architecture tracer | sonnet | Read, Glob, Grep, Write | Yes |
| 3 | explore-aggregator | Merges explorer outputs into report | haiku | Read, Write, Glob | Yes |
| 4 | architect | Plans implementation with wave assignments | sonnet | Read, Glob, Grep, WebSearch | Yes |
| 5 | blueprint-reviewer | Validates plan completeness and wave correctness | sonnet | Read, Glob, Grep | Yes |
| 6 | worker | Implements a single task from the plan | inherit | Read, Grep, Glob, Edit, Write, Bash | Yes |
| 7 | sentinel | Sentinel reviewer for quality track | sonnet | Read, Glob, Grep, Bash | Yes |
| 8 | queen | Merges track results and renders ship/loop verdict | sonnet | Read, Glob, Grep | Yes |
| 9 | nurse | Updates documentation after implementation | sonnet | Read, Write, Edit, Glob, Grep | Yes |
| 10 | drone | Commits changes and opens PR | inherit | Read, Glob, Grep, Bash, Write | Yes |
| 11 | (orchestrator) | Ralph Loop driver (hooks, not an agent file) | -- | -- | -- |

All agents have `disallowedTools: [Task]` -- no agent can spawn subagents. The orchestrator (hooks) is the only entity that dispatches agents.

## Pipeline Phases (A0-A5)

```
EXPLORE ──> PLAN ──> BUILD ──> SYNC ──> SHIP
  A0        A1,A2     A3       A4       A5
                               |
                          verdict?
                         /        \
                      ship       loop ──> back to A1
```

| Phase | Stage | Agent(s) | Description |
|-------|-------|----------|-------------|
| A0 | EXPLORE | forager x2-4, cartographer x1, explore-aggregator x1 | Parallel codebase exploration |
| A1 | PLAN | architect x1 | Structured plan with wave assignments |
| A2 | PLAN | blueprint-reviewer x1 | Plan validation |
| A3 | BUILD | worker xN (per wave), guardian xN (per wave), sentinel xN (per wave) | Dual-track parallel execution |
| A4 | SYNC | queen x1 | Merge tracks, ship/loop verdict |
| A5 | SHIP | nurse x1, drone x1 | Documentation update + commit/PR |

## Dual-Track Build + Quality Design

Phase A3 is the core innovation. Two tracks run in coordinated waves:

**Build Track:** Workers implement tasks in waves according to the architect's plan. Wave 1 (foundation) runs first, then Wave 2 (dependent tasks) after a completion barrier.

**Quality Track:** Sentinel agents review each wave's output as it completes. They run sentinel reviews checking correctness, test coverage, integration risks, and acceptance criteria adherence.

**Wave synchronization:** Workers in the same wave run in parallel. After all workers in a wave complete, sentinels review that wave. Only after sentinel review completes does the next wave start.

This design catches issues per-wave rather than waiting until the end, enabling earlier feedback within a single loop iteration.

## Hook Architecture

Four hooks drive the workflow via the Ralph Loop pattern:

### on-stop.sh (Stop event)

- Reads `state.json` to determine current phase
- Generates phase-specific orchestrator prompt (~30-60 lines)
- Returns `{"decision":"block","reason":"<prompt>"}` to keep Claude working
- Allows exit only when status is `complete` or `blocked`

### on-subagent-stop.sh (SubagentStop event)

- Validates subagent output file exists and is valid
- Checks stage gates at boundaries
- Handles A4 queen verdict (ship -> A5, loop -> A1 with incremented counter)
- Handles A3 wave barriers (wave complete -> sentinel review -> next wave)
- Advances `currentPhase` in state
- Exits silently (no stdout) -- Stop hook handles prompt injection

### on-task-gate.sh (PreToolUse: Task)

- Validates that the dispatched `ants:*` agent matches the current phase
- Blocks dispatch of wrong agent types
- Prevents out-of-order phase execution

### on-edit-gate.sh (PreToolUse: Edit/Write)

- Allows file edits only in BUILD (A3) and SHIP (A5) stages
- Blocks edits during EXPLORE, PLAN, and SYNC stages
- Allows writes to `.agents/` path at all times (state and output files)

### hooks.json Configuration

```json
{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "on-stop.sh"}]}],
    "SubagentStop": [{"hooks": [{"type": "command", "command": "on-subagent-stop.sh"}]}],
    "PreToolUse": [
      {"matcher": "Task", "hooks": [{"type": "command", "command": "on-task-gate.sh"}]},
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "on-edit-gate.sh"}]}
    ]
  }
}
```

## State Management

State tracked in `.agents/tmp/state.json`. Shared library `hooks/lib/state.sh` provides:

- `check_ants_workflow()` -- plugin guard, session scoping, status check
- `read_state_field()` / `state_get()` -- read fields with optional required validation
- `update_state()` -- atomic state update with file locking (flock)
- `validate_json_file()` -- check file exists and contains valid JSON
- `require_int()` -- validate integer fields

Session scoping via `ownerPpid` + `sessionId` ensures hooks only fire for the session that owns the workflow.

### Output File Layout

```
.agents/tmp/
├── state.json                           # Workflow state
├── phases/
│   ├── A0-explore.forager.1.tmp         # Forager results
│   ├── A0-explore.forager.2.tmp
│   ├── A0-explore.cartographer.tmp      # Cartographer results
│   ├── A0-explore.md                    # Aggregated exploration
│   ├── loop-1/
│   │   ├── A1-plan.md                   # Architect's plan
│   │   ├── A2-review.json              # Blueprint review
│   │   ├── A3-build.json              # Worker results
│   │   ├── A3-quality.json            # Sentinel results
│   │   ├── A4-queen-verdict.json     # Queen verdict
│   │   ├── A5-docs.json              # Nurse documentation summary
│   │   └── A5-ship.json              # Drone commit/PR output
│   ├── loop-2/                        # If looped back
│   │   └── ...
```

## Code Style

- **Markdown:** YAML frontmatter, follow existing agent structure
- **Naming:** kebab-case for files (e.g., `blueprint-reviewer.md`, `explore-aggregator.md`)
- **Agent theme:** Ant colony roles (forager, cartographer, architect, worker, sentinel, queen, nurse, drone)
- **Shell hooks:** `set -euo pipefail`, use `local var; var="$(cmd)"` (not `local var="$(cmd)"`), source libs from `$SCRIPT_DIR/lib/`
- **Shell validation:** Run `bash -n <script>` after modifying hook shell scripts
- **Git commits:** Prefix with `feat|fix|docs|chore|ci`, include co-author line
- **Git excludes:** Never commit `.agents/**`, `*.tmp`, `*.log`

## Boundaries

### Always

- Update state.json after each phase completes
- Follow phase progression (A0 -> A1 -> A2 -> A3 -> A4 -> A5)
- Respect stage gates before advancing
- Validate output files before marking phases complete
- Use `disallowedTools: [Task]` on all leaf agents
- Block git commands in worker agents
- Bump plugin.json version on changes

### Ask First

- Skipping phases (A0 can be skipped, others require confirmation)
- Changing maxLoops mid-workflow
- Modifying state.json schema
- Adding new agents to the roster
- Changing wave synchronization strategy

### Never

- Skip A4 queen verdict -- always sync before shipping
- Ship when critical or warning issues remain unresolved
- Allow agents to spawn subagents (all are leaf agents)
- Commit secrets or credentials
- Modify files during EXPLORE, PLAN, or SYNC stages (enforced by edit gate)
- Proceed past maxLoops without user approval
