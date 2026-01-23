# superpowers-iterate

Orchestrates an iterative 9-phase development workflow for Claude Code. Phases 1-8 loop until Phase 8 finds zero issues or `--max-iterations` is reached.

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

| Mode           | Phase 3 Tool        | Phase 8 Tool                         | Phase 9                  | Requires                      |
| -------------- | ------------------- | ------------------------------------ | ------------------------ | ----------------------------- |
| Full (default) | `mcp__codex__codex` | `mcp__codex__codex`                  | `mcp__codex-high__codex` | Codex MCP servers             |
| Lite (--lite)  | Claude code-review  | `superpowers:requesting-code-review` | Skipped                  | superpowers + code-simplifier |

## The Iteration Loop

```
Iteration 1: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8
             Phase 8 finds issues? -> Fix -> Start Iteration 2
Iteration 2: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8
             Phase 8 finds zero issues? -> Phase 9 (full) or Done (lite)
Phase 9: Final validation (full mode only)
```

## Prerequisites

**Required for all modes:**

- **Superpowers plugin** (phases 1-2, 4-5, 8 lite mode)
  - `superpowers:brainstorming` - Phase 1
  - `superpowers:writing-plans` - Phase 2
  - `superpowers:subagent-driven-development` - Phase 4
  - `superpowers:requesting-code-review` - Phase 5, Phase 8 (lite)
  - `superpowers:dispatching-parallel-agents` - Parallel subagent dispatch
  - `superpowers:test-driven-development` - TDD for implementation

- **code-simplifier plugin** @ claude-plugins-official (Phase 7)
  - Install: `claude plugin install code-simplifier`

- **LSP plugins** @ claude-plugins-official (Phase 4)
  - Install per language: `typescript-lsp`, `pyright-lsp`, `gopls-lsp`, etc.

**Required for full mode only:**

- **Codex MCP servers** (Phase 3, 8, and 9)
  - `mcp__codex__codex` - Phase 3 plan review (medium reasoning)
  - `mcp__codex__codex` - Phase 8 final review (medium reasoning)
  - `mcp__codex-high__codex` - Phase 9 final validation (high reasoning)

## The 9 Phases

| Phase | Name         | Purpose                           | Integration                            |
| ----- | ------------ | --------------------------------- | -------------------------------------- |
| 1     | Brainstorm   | Explore problem space             | `brainstorming` + N parallel subagents |
| 2     | Plan         | Create implementation plan        | `writing-plans` + N parallel subagents |
| 3     | Plan Review  | Validate plan before implement    | `mcp__codex__codex` (medium)           |
| 4     | Implement    | TDD-style implementation          | `subagent-driven-development` + LSP    |
| 5     | Review       | Quick sanity check (1 round)      | `requesting-code-review`               |
| 6     | Test         | make lint && make test            | Bash                                   |
| 7     | Simplify     | Reduce code bloat                 | `code-simplifier:code-simplifier`      |
| 8     | Final Review | Decision point - loop or proceed  | Codex (full) or Claude review (lite)   |
| 9     | Codex        | Final validation (full mode only) | `mcp__codex-high__codex`               |

## State Management

Progress is tracked in `.agents/iteration-state.json`:

```json
{
  "version": 3,
  "task": "Add user authentication",
  "mode": "full",
  "maxIterations": 10,
  "currentIteration": 2,
  "currentPhase": 4,
  "startedAt": "2026-01-21T12:00:00Z",
  "iterations": [
    {
      "iteration": 1,
      "phases": { "1": {"status": "completed"}, "2": {"status": "completed"}, "3": {"status": "completed", "planReviewIssues": []}, ... },
      "phase8Issues": ["Issue 1", "Issue 2"]
    },
    {
      "iteration": 2,
      "phases": { "1": {"status": "completed"}, "2": {"status": "completed"}, "3": {"status": "completed"}, "4": {"status": "in_progress"}, ... },
      "phase8Issues": []
    }
  ],
  "phase9": { "status": "pending" }
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
│  │3. Plan Revw │──► mcp__codex__codex    │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │4. Implement │──► subagent-driven-dev  │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │  5. Review  │──► code review (1 round)│
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │   6. Test   │──► make lint && test    │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐                         │
│  │ 7. Simplify │──► code-simplifier      │
│  └──────┬──────┘                         │
│         ▼                                │
│  ┌─────────────┐     Issues found?       │
│  │8.Final Revw │──────────────┐          │
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
   │  9. Codex   │──► mcp__codex-high
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
