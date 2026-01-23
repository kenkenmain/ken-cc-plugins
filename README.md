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

Orchestrates an iterative 9-phase development workflow. Phases 1-8 loop until the code passes review with zero issues.

See [AGENTS.md](AGENTS.md) for detailed agent instructions and workflow architecture.

**Commands:**

```bash
/superpowers-iterate:iterate <task>                        # Full mode (requires Codex MCP)
/superpowers-iterate:iterate --lite <task>                 # Lite mode (no Codex required)
/superpowers-iterate:iterate --max-iterations 5 <task>     # Limit iterations
/superpowers-iterate:iterate-status                        # Check progress
```

**Modes:**

| Mode           | Phase 3 Tool        | Phase 8 Tool                         | Phase 9                  | Requires                      |
| -------------- | ------------------- | ------------------------------------ | ------------------------ | ----------------------------- |
| Full (default) | `mcp__codex__codex` | `mcp__codex__codex`                  | `mcp__codex-high__codex` | Codex MCP servers             |
| Lite (--lite)  | Claude code-review  | `superpowers:requesting-code-review` | Skipped                  | superpowers + code-simplifier |

**The Iteration Loop:**

```
Iteration 1: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8
             Phase 8 finds issues? -> Fix -> Iteration 2
Iteration 2: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8
             Phase 8 finds zero issues? -> Phase 9 (full) or Done (lite)
Phase 9: Final validation (full mode only)
```

**Phases:**

| Phase | Name         | Purpose                                   |
| ----- | ------------ | ----------------------------------------- |
| 1     | Brainstorm   | Explore problem space, generate ideas     |
| 2     | Plan         | Create detailed implementation plan       |
| 3     | Plan Review  | Validate plan before implementation       |
| 4     | Implement    | TDD-style implementation with LSP support |
| 5     | Review       | Quick sanity check (1 round)              |
| 6     | Test         | Run lint and tests                        |
| 7     | Simplify     | Reduce code bloat with code-simplifier    |
| 8     | Final Review | Decision point - loop or proceed          |
| 9     | Codex        | Final validation (full mode only)         |

**Prerequisites:**

- `superpowers` plugin (from superpowers-marketplace)
- `code-simplifier` plugin (from claude-plugins-official)
- Codex MCP servers - only for full mode (`mcp__codex__codex`, `mcp__codex-high__codex`)

## License

MIT
