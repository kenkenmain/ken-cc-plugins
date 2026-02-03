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

### subagents

Hook-driven subagent architecture for complex task execution with parallel agents and file-based state.

```bash
claude plugin install subagents@ken-cc-plugins

# Standard workflow (13 phases)
/subagents:dispatch <task>           # Codex MCP defaults
/subagents:dispatch-claude <task>    # Claude-only mode
/subagents:init <task>               # With git worktree isolation

# Fast workflow (4 phases)
/subagents:fdispatch <task>          # Fast dispatch (Codex MCP)
/subagents:fdispatch-claude <task>   # Fast dispatch (Claude-only)

# Debug workflow (6 phases)
/subagents:debug <task>              # Multi-phase debugging

# Management
/subagents:status                    # Check progress
/subagents:stop                      # Stop workflow gracefully
/subagents:resume                    # Resume from checkpoint
/subagents:teardown                  # Commit, push, create PR
/subagents:configure                 # Configure settings
```

**Pipelines:** Standard (Explore -> Plan -> Implement -> Test -> Final) | Fast (Plan -> Implement -> Review -> Complete) | Debug (Explore -> Propose -> Aggregate -> Implement -> Review -> Document)

**Features:** Complexity-routed task agents, hybrid test-alongside-code, Codex/Claude dispatch modes, pipeline profiles (minimal/standard/thorough), fast dispatch (4-phase variant), multi-phase debug workflow

See [plugins/subagents/README.md](plugins/subagents/README.md) for full documentation.

### superpowers-iterate

9-phase iterative development workflow. Phases 1-8 loop until Phase 8 finds zero issues.

```bash
claude plugin install superpowers-iterate@ken-cc-plugins

/superpowers-iterate:iterate <task>         # Full mode (requires Codex MCP)
/superpowers-iterate:iterate --lite <task>  # Lite mode (no Codex required)
/superpowers-iterate:iterate-status         # Check progress
```

**Phases:** Brainstorm -> Plan -> Plan Review -> Implement -> Review -> Test -> Simplify -> Final Review -> Codex Final

**Prerequisites:** superpowers plugin, code-simplifier plugin, Codex MCP (full mode only)

See [AGENTS.md](AGENTS.md) for workflow architecture, modes, and state management details.

### kenken

4-stage development workflow.

```bash
claude plugin install kenken@ken-cc-plugins

/kenken:iterate <task>             # Start iterative workflow
/kenken:iterate-status             # Check progress
/kenken:iterate-resume             # Resume interrupted workflow
/kenken:iterate-configure          # Configure settings
/kenken:gh-repo-setup [repo-name]  # Set up GitHub repo with GitFlow
```

See [plugins/kenken/README.md](plugins/kenken/README.md) for full documentation.

## License

MIT
