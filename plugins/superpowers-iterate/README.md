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

- **Full (default):** Uses Codex MCP for reviews (Phases 3, 8, 9)
- **Lite (`--lite`):** Uses Claude reviews, skips Phase 9

## Prerequisites

- **superpowers plugin** - brainstorming, writing-plans, subagent-driven-development, requesting-code-review
- **code-simplifier plugin** - Phase 7
- **LSP plugins** (optional) - typescript-lsp, pyright-lsp, gopls-lsp
- **Codex MCP servers** (full mode only) - `mcp__codex__codex`, `mcp__codex-high__codex`

## The 9 Phases

| Phase | Name         | Integration                          |
| ----- | ------------ | ------------------------------------ |
| 1     | Brainstorm   | brainstorming + parallel subagents   |
| 2     | Plan         | writing-plans + parallel subagents   |
| 3     | Plan Review  | Codex (full) or Claude review (lite) |
| 4     | Implement    | subagent-driven-development + LSP    |
| 5     | Review       | requesting-code-review (1 round)     |
| 6     | Test         | make lint && make test               |
| 7     | Simplify     | code-simplifier                      |
| 8     | Final Review | Codex (full) or Claude review (lite) |
| 9     | Codex Final  | mcp\_\_codex-high (full mode only)   |

**Iteration Loop:** Phases 1-8 repeat until Phase 8 finds zero issues or max iterations reached.

## State Management

Progress tracked in `.agents/iteration-state.json`. See [AGENTS.md](../../AGENTS.md) for schema details.

## Project Requirements

- `make lint` and `make test` targets
- `.agents/` directory (created automatically)

## License

MIT

## Author

Kennard Ng <kennard.ng.pool.hua@gmail.com>
