# Superpowers Iterate Plugin - Agent Instructions

## Commands

```bash
# Iteration Workflow
/superpowers-iterate:iterate <task>                    # Full mode (Codex MCP)
/superpowers-iterate:iterate --lite <task>             # Lite mode (Claude only)
/superpowers-iterate:iterate --max-iterations 5 <task> # Limit iterations
/superpowers-iterate:iterate-status                    # Check progress
/superpowers-iterate:configure                         # Configure models per phase
/superpowers-iterate:configure --show                  # Show current config
/superpowers-iterate:configure --reset                 # Reset to defaults

# Plugin Development
claude plugin install ./plugins/superpowers-iterate    # Install locally
claude plugin list                                     # List installed
```

## Project Structure

```
ken-cc-plugins/
├── plugins/
│   └── superpowers-iterate/
│       ├── .claude-plugin/plugin.json    # Plugin manifest (name, version)
│       ├── commands/                      # Slash commands (iterate.md, iterate-status.md)
│       ├── skills/iteration-workflow/     # Main skill (SKILL.md)
│       ├── skills/configuration/          # Config management (SKILL.md)
│       └── agents/                        # Agent definitions (codex-reviewer.md)
├── docs/plans/                            # Design docs and implementation plans
├── .agents/                               # Runtime state (iteration-state.json)
├── .github/workflows/                     # CI validation
├── AGENTS.md                              # This file - agent instructions
├── CLAUDE.md                              # Symlink to AGENTS.md
└── README.md                              # User-facing documentation
```

## Workflow Architecture

This plugin orchestrates a 9-phase development iteration:

```
Phase 1: Brainstorm    -> superpowers:brainstorming + parallel agents
Phase 2: Plan          -> superpowers:writing-plans + parallel agents
Phase 3: Plan Review   -> mcp__codex__codex (default, configurable via /configure)
Phase 4: Implement     -> superpowers:subagent-driven-development
Phase 5: Review        -> superpowers:requesting-code-review
Phase 6: Test          -> make lint && make test
Phase 7: Simplify      -> code-simplifier agent
Phase 8: Final Review  -> mcp__codex__codex (default, configurable via /configure)
Phase 9: Codex Final   -> mcp__codex-high__codex (full mode only)
```

**Iteration Loop:** Phases 1-8 repeat until Phase 8 finds zero issues or max iterations reached.

## Model Configuration

| Phase | Activity     | Model     | MCP Tool                 | Rationale                            |
| ----- | ------------ | --------- | ------------------------ | ------------------------------------ |
| 1     | Brainstorm   | `inherit` | N/A                      | User controls via /configure         |
| 2     | Plan         | `inherit` | N/A                      | User controls via /configure         |
| 3     | Plan Review  | N/A       | `mcp__codex__codex`      | Medium reasoning for plan validation |
| 4     | Implement    | `inherit` | N/A                      | User controls quality                |
| 5     | Review       | `inherit` | N/A                      | Quick sanity check                   |
| 6     | Test         | N/A       | N/A                      | Bash commands                        |
| 7     | Simplify     | `inherit` | N/A                      | Code quality                         |
| 8     | Final Review | N/A       | `mcp__codex__codex`      | Medium reasoning for iteration       |
| 9     | Codex Final  | N/A       | `mcp__codex-high__codex` | High reasoning for final validation  |

## Configuration

Configure models per phase via `/superpowers-iterate:configure` or edit JSON directly:

**Global:** `~/.claude/iterate-config.json`
**Project:** `.claude/iterate-config.local.json`

Project overrides global. See `plugins/superpowers-iterate/skills/configuration/SKILL.md` for schema.

## Code Style

- **Markdown:** Use YAML frontmatter, follow existing command/skill/agent structure
- **Naming:** kebab-case for commands, skills, agents (e.g., `iterate-status.md`)
- **Git Commits:** Prefix with `feat|fix|docs|chore|ci`, include co-author line

## State Management

State tracked in `.agents/iteration-state.json`:

```json
{
  "version": 3,
  "task": "<description>",
  "mode": "full",
  "maxIterations": 10,
  "currentIteration": 1,
  "currentPhase": 1,
  "startedAt": "ISO timestamp",
  "iterations": [
    {
      "iteration": 1,
      "startedAt": "ISO timestamp",
      "phases": {
        "1": { "status": "..." },
        "2": { "status": "..." },
        "3": { "status": "...", "planReviewIssues": [] },
        "4": { "status": "..." },
        "5": { "status": "..." },
        "6": { "status": "..." },
        "7": { "status": "..." },
        "8": { "status": "..." }
      },
      "phase8Issues": []
    }
  ],
  "phase9": { "status": "pending" }
}
```

## Boundaries

**Always:** Update state after each phase, follow phase progression, fix HIGH severity issues, validate plan before implementation, bump plugin.json version on changes

**Ask First:** Skipping phases, changing iteration count mid-workflow, modifying state file schema

**Never:** Skip Phase 8 decision point without approval, proceed with HIGH severity issues, commit secrets
