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

### subagents

Hook-driven subagent architecture with parallel debugging. 15-phase workflow with gate enforcement.

```bash
/subagents:dispatch <task>                          # Full workflow
/subagents:dispatch <task> --no-worktree            # Without git worktree isolation
/subagents:debug <bug description>                  # Parallel solution search
/subagents:debug --solutions 5 <bug description>    # Search 5 solutions
/subagents:status                                   # Check progress
```

**Stages:** Explore -> Plan -> Implement -> Test -> Final

**Debug Mode:** Dispatches multiple agents to search for different solutions to a bug in parallel, ranks them, and lets you choose.

See [plugins/subagents/README.md](plugins/subagents/README.md) for full documentation.

## License

MIT
