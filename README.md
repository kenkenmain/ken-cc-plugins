# ken-cc-plugins

Claude Code plugin marketplace for development workflows.

## Installation

```bash
# Add the marketplace
claude plugin marketplace add kenkenmain/ken-cc-plugins

# Install plugins
claude plugin install superpowers-iterate@ken-cc-plugins
```

## Available Plugins

### superpowers-iterate

Orchestrates an iterative 8-phase development workflow. Phases 1-7 loop until the code passes review with zero issues.

**Commands:**

```bash
/superpowers-iterate:iterate <task>                        # Full mode (requires Codex MCP)
/superpowers-iterate:iterate --lite <task>                 # Lite mode (no Codex required)
/superpowers-iterate:iterate --max-iterations 5 <task>     # Limit iterations
/superpowers-iterate:iterate-status                        # Check progress
```

**Modes:**

| Mode           | Phase 7            | Phase 8         | Requires                |
| -------------- | ------------------ | --------------- | ----------------------- |
| Full (default) | Codex-high MCP     | Codex-xhigh MCP | Codex MCP servers       |
| Lite (--lite)  | Claude code review | Skipped         | Only superpowers plugin |

**The Iteration Loop:**

```
Iteration 1: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7
             Phase 7 finds issues? -> Fix -> Iteration 2
Iteration 2: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7
             Phase 7 finds zero issues? -> Phase 8 -> Done
```

**Phases:**

| Phase | Name         | Purpose                                   |
| ----- | ------------ | ----------------------------------------- |
| 1     | Brainstorm   | Explore problem space, generate ideas     |
| 2     | Plan         | Create detailed implementation plan       |
| 3     | Implement    | TDD-style implementation with LSP support |
| 4     | Review       | Quick sanity check (1 round)              |
| 5     | Test         | Run lint and tests                        |
| 6     | Simplify     | Reduce code bloat with code-simplifier    |
| 7     | Final Review | Decision point - loop or proceed          |
| 8     | Codex        | Final validation (full mode only)         |

**Prerequisites:**

- `superpowers` plugin (from superpowers-marketplace)
- `code-simplifier` plugin (from claude-plugins-official)
- Codex MCP servers - only for full mode (`@codex-high`, `@codex-xhigh`)

## License

MIT
