# kenkenmain-plugins

Claude Code plugin marketplace for development workflows.

## Installation

```bash
# Add the marketplace
claude plugin marketplace add kenkenmain/kenkenmain-plugins

# Install plugins
claude plugin install superpowers-iterate@kenkenmain-plugins
```

## Available Plugins

### superpowers-iterate

Orchestrates an 8-phase iteration workflow for disciplined development:

| Phase | Name         | Purpose                                    |
| ----- | ------------ | ------------------------------------------ |
| 1     | Brainstorm   | Explore problem space, generate ideas      |
| 2     | Plan         | Create detailed implementation plan        |
| 3     | Implement    | TDD-style implementation with LSP support  |
| 4     | Review       | Code review (3 rounds)                     |
| 5     | Test         | Run lint and tests                         |
| 6     | Simplify     | Reduce code bloat with code-simplifier     |
| 7     | Final Review | High-reasoning Codex review (3 rounds)     |
| 8     | Codex        | Final validation with extra-high reasoning |

**Commands:**

- `/iterate <task>` - Start the 8-phase workflow
- `/iterate-status` - Check current iteration progress

**Prerequisites:**

- `superpowers` plugin (from superpowers-marketplace)
- `code-simplifier` plugin (from claude-plugins-official)
- Codex MCP servers (`@codex`, `@codex-high`, `@codex-xhigh`)

## License

MIT
