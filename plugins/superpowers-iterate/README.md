# superpowers-iterate

Orchestrates an iterative 8-phase development workflow for Claude Code. Phases 1-7 loop until Phase 7 finds zero issues or `--max-iterations` is reached.

## Installation

```bash
# From ken-cc-plugins marketplace
claude plugin marketplace add kenkenmain/ken-cc-plugins
claude plugin install superpowers-iterate@ken-cc-plugins
```

## Commands

### `/superpowers-iterate:iterate [options] <task-description>`

Start the iterative workflow:

```bash
/superpowers-iterate:iterate Add user authentication with OAuth2           # Full mode
/superpowers-iterate:iterate --lite Add user authentication with OAuth2    # Lite mode (no Codex)
/superpowers-iterate:iterate --max-iterations 5 Add user authentication    # Limit iterations
/superpowers-iterate:iterate --lite --max-iterations 3 Fix login bug       # Combined
```

**Options:**

- `--lite`: Use lite mode (no Codex MCP required)
- `--max-iterations N`: Maximum iterations before stopping (default: 10)

### `/superpowers-iterate:iterate-status`

Check current iteration progress:

```
/superpowers-iterate:iterate-status
```

Shows current iteration, phase, completed phases, and issues found.

## Modes

| Mode           | Phase 7                              | Phase 8                  | Requires                |
| -------------- | ------------------------------------ | ------------------------ | ----------------------- |
| Full (default) | `mcp__codex-high__codex`             | `mcp__codex-high__codex` | Codex MCP servers       |
| Lite (--lite)  | `superpowers:requesting-code-review` | Skipped                  | Only superpowers plugin |

## The Iteration Loop

```
Iteration 1: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7
             Phase 7 finds issues? -> Fix -> Start Iteration 2
Iteration 2: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7
             Phase 7 finds zero issues? -> Phase 8 (full) or Done (lite)
Phase 8: Final validation (full mode only)
```

## Prerequisites

**Required for all modes:**

- **Superpowers plugin** (phases 1-4, 7 lite mode)
  - `superpowers:brainstorming` - Phase 1
  - `superpowers:writing-plans` - Phase 2
  - `superpowers:subagent-driven-development` - Phase 3
  - `superpowers:requesting-code-review` - Phase 4, Phase 7 (lite)
  - `superpowers:dispatching-parallel-agents` - Parallel subagent dispatch
  - `superpowers:test-driven-development` - TDD for implementation

- **code-simplifier plugin** @ claude-plugins-official (Phase 6)
  - Install: `claude plugin install code-simplifier`

- **LSP plugins** @ claude-plugins-official (Phase 3)
  - Install per language: `typescript-lsp`, `pyright-lsp`, `gopls-lsp`, etc.

**Required for full mode only:**

- **Codex MCP servers** (Phase 7 and 8)
  - `mcp__codex-high__codex` - Phase 7 review
  - `mcp__codex-high__codex` - Phase 8 final validation

## The 8 Phases

| Phase | Name         | Purpose                           | Integration                               |
| ----- | ------------ | --------------------------------- | ----------------------------------------- |
| 1     | Brainstorm   | Explore problem space             | `brainstorming` + N parallel subagents    |
| 2     | Plan         | Create implementation plan        | `writing-plans` + N parallel subagents    |
| 3     | Implement    | TDD-style implementation          | `subagent-driven-development` + LSP       |
| 4     | Review       | Quick sanity check (1 round)      | `requesting-code-review`                  |
| 5     | Test         | make lint && make test            | Bash                                      |
| 6     | Simplify     | Reduce code bloat                 | `code-simplifier:code-simplifier`         |
| 7     | Final Review | Decision point - loop or proceed  | Codex-high (full) or Claude review (lite) |
| 8     | Codex        | Final validation (full mode only) | `mcp__codex-high__codex`                  |

## State Management

Progress is tracked in `.agents/iteration-state.json`:

```json
{
  "version": 2,
  "task": "Add user authentication",
  "mode": "full",
  "maxIterations": 10,
  "currentIteration": 2,
  "currentPhase": 3,
  "startedAt": "2026-01-21T12:00:00Z",
  "iterations": [
    {
      "iteration": 1,
      "phases": { "1": {"status": "completed"}, ... },
      "phase7Issues": ["Issue 1", "Issue 2"]
    },
    {
      "iteration": 2,
      "phases": { "1": {"status": "completed"}, "2": {"status": "completed"}, "3": {"status": "in_progress"}, ... },
      "phase7Issues": []
    }
  ],
  "phase8": { "status": "pending" }
}
```

This allows:

- Resuming interrupted iterations
- Checking progress via `/superpowers-iterate:iterate-status`
- Audit trail of issues found per iteration

## Workflow Diagram

```
┌─────────────┐
│  /superpowers-iterate:iterate   │
│   <task>    │
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────────────┐
│           ITERATION LOOP                 │
│  ┌─────────────┐                         │
│  │ 1.Brainstorm│──► brainstorming        │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │   2. Plan   │──► writing-plans        │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │3. Implement │──► subagent-driven-dev  │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │  4. Review  │──► code review (1 round)│
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │   5. Test   │──► make lint && test    │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │ 6. Simplify │──► code-simplifier      │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐     Issues found?       │
│  │7.Final Revw │──────────────┐          │
│  └──────┬──────┘              │          │
│         │ No issues           │ Yes      │
│         │                     ▼          │
│         │              Fix issues        │
│         │                     │          │
│         │                     ▼          │
│         │              Loop to Phase 1 ──┘
└─────────┼────────────────────────────────┘
          │
          ▼ (Full mode only)
   ┌─────────────┐
   │  8. Codex   │──► @codex-high
   └──────┬──────┘
          │
          ▼
      ✓ Complete
```

## Project Requirements

Your project should have:

- `make lint` target (or equivalent)
- `make test` target (or equivalent)
- `.agents/` directory (created automatically)

## License

MIT

## Author

Kennard Ng <kennard.ng.pool.hua@gmail.com>
