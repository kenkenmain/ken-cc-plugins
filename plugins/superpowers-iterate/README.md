# superpowers-iterate

Orchestrates the complete 8-phase development iteration workflow for Claude Code.

## Installation

### Option 1: Local Installation (from this repo)

```bash
# Add plugin from local path
claude plugin add /path/to/remote-server-setup/plugins/superpowers-iterate
```

### Option 2: Global Installation

Copy to your Claude plugins directory:

```bash
cp -r plugins/superpowers-iterate ~/.claude/plugins/local/
claude plugin add ~/.claude/plugins/local/superpowers-iterate
```

## Prerequisites

The following should be configured for full functionality:

- **Superpowers plugin** (required for phases 1-4)
  - `superpowers:brainstorming` - Phase 1
  - `superpowers:writing-plans` - Phase 2
  - `superpowers:executing-plans` - Phase 3 plan execution
  - `superpowers:subagent-driven-development` - Phase 3
  - `superpowers:requesting-code-review` - Phase 4
  - `superpowers:dispatching-parallel-agents` - Parallel subagent dispatch
  - `superpowers:test-driven-development` - TDD for implementation

- **code-simplifier plugin** @ claude-plugins-official (Phase 6)
  - `code-simplifier:code-simplifier` - Reduces code bloat
  - Install: `claude plugin install code-simplifier`

- **Codex MCP servers** (Phase 7 and 8)
  - `mcp__codex__codex` - Standard reasoning
  - `mcp__codex-high__codex` - High reasoning (Phase 7)
  - `mcp__codex-xhigh__codex` - Extra-high reasoning (Phase 8)

- **LSP plugins** @ claude-plugins-official (Phase 3 - Required)
  - Provides code intelligence: go-to-definition, find references, diagnostics
  - Subagents use LSP tools: `mcp__lsp__get_diagnostics`, `mcp__lsp__goto_definition`, etc.
  - Install per language used in your project:
    - `claude plugin install typescript-lsp` (JS/TS)
    - `claude plugin install pyright-lsp` (Python)
    - `claude plugin install gopls-lsp` (Go)
    - `claude plugin install rust-analyzer-lsp` (Rust)
    - `claude plugin install clangd-lsp` (C/C++)
    - `claude plugin install jdtls-lsp` (Java)
    - `claude plugin install kotlin-lsp` (Kotlin)

## Commands

### `/iterate <task-description>`

Start a new 8-phase iteration workflow:

```
/iterate Add user authentication with OAuth2
```

This will guide you through all 8 phases, tracking progress in `.agents/iteration-state.json`.

### `/iterate-status`

Check current iteration progress:

```
/iterate-status
```

Shows current phase, completed phases, and next steps.

## The 8 Phases

| Phase | Name         | Purpose                      | Integration                                 |
| ----- | ------------ | ---------------------------- | ------------------------------------------- |
| 1     | Brainstorm   | Explore problem space        | `brainstorming` + N parallel subagents      |
| 2     | Plan         | Create implementation plan   | `writing-plans` + N parallel subagents      |
| 3     | Implement    | TDD-style implementation     | `subagent-driven-development` + N subagents |
| 4     | Review       | Code review (3 rounds)       | `requesting-code-review`                    |
| 5     | Test         | make lint && make test       | Bash                                        |
| 6     | Simplify     | Reduce code bloat            | `code-simplifier:code-simplifier` plugin    |
| 7     | Final Review | Codex-high review (3 rounds) | `mcp__codex-high__codex`                    |
| 8     | Codex        | Final validation             | `mcp__codex-xhigh__codex`                   |

## State Management

Progress is tracked in `.agents/iteration-state.json`:

```json
{
  "version": 1,
  "task": "Add user authentication",
  "startedAt": "2026-01-20T12:00:00Z",
  "currentPhase": 3,
  "phases": {
    "1": { "status": "completed" },
    "2": { "status": "completed" },
    "3": { "status": "in_progress" },
    "4": { "status": "pending" },
    "5": { "status": "pending" },
    "6": { "status": "pending" },
    "7": { "status": "pending" },
    "8": { "status": "pending" }
  }
}
```

This allows:

- Resuming interrupted iterations
- Checking progress via `/iterate-status`
- Audit trail of completed phases

## Project Requirements

Your project should have:

- `make lint` target (or equivalent)
- `make test` target (or equivalent)
- `.agents/` directory (created automatically)

## Workflow Diagram

```
┌─────────────┐
│  /iterate   │
│   <task>    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 1.Brainstorm│──► superpowers:brainstorming
│             │    + N parallel sonnet subagents
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   2. Plan   │──► superpowers:writing-plans
│             │    + N parallel sonnet subagents
└──────┬──────┘
       │
       ▼
┌─────────────┐
│3. Implement │──► superpowers:subagent-driven-development
│             │    + N subagents (TDD)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  4. Review  │──► superpowers:requesting-code-review
│             │    (3 rounds)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   5. Test   │──► make lint && make test
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 6. Simplify │──► code-simplifier:code-simplifier
└──────┬──────┘
       │
       ▼
┌─────────────┐
│7.Final Revw │──► @codex-high MCP
│             │    (3 review rounds)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  8. Codex   │──► @codex-xhigh MCP
└──────┬──────┘
       │
       ▼
   ✓ Complete
```

## License

MIT

## Author

Kennard Ng <kennard.ng.pool.hua@gmail.com>
