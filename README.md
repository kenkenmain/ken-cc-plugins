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

9-phase iterative development workflow. Phases 1-8 loop until Phase 8 finds zero issues.

```bash
/superpowers-iterate:iterate <task>         # Full mode (requires Codex MCP)
/superpowers-iterate:iterate --lite <task>  # Lite mode (no Codex required)
/superpowers-iterate:iterate-status         # Check progress
```

**Phases:** Brainstorm -> Plan -> Plan Review -> Implement -> Review -> Test -> Simplify -> Final Review -> Codex Final

**Prerequisites:** superpowers plugin, code-simplifier plugin, Codex MCP (full mode only)

See [AGENTS.md](AGENTS.md) for workflow architecture, modes, and state management details.

## License

MIT
