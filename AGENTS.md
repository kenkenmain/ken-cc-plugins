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

| Phase | Activity     | Tool / Model             | onFailure | Notes                        |
| ----- | ------------ | ------------------------ | --------- | ---------------------------- |
| 1     | Brainstorm   | `inherit`                | N/A       | Parallel agents configurable |
| 2     | Plan         | `inherit`                | N/A       | Parallel agents configurable |
| 3     | Plan Review  | `mcp__codex__codex`      | restart   | Configurable via /configure  |
| 4     | Implement    | `inherit`                | N/A       | Sequential subagents         |
| 5     | Review       | `inherit`                | mini-loop | Fix issues within phase      |
| 6     | Test         | Bash (`make lint/test`)  | restart   | No model needed              |
| 7     | Simplify     | `inherit`                | N/A       | code-simplifier agent        |
| 8     | Final Review | `mcp__codex__codex`      | restart   | Configurable via /configure  |
| 9     | Codex Final  | `mcp__codex-high__codex` | N/A       | Full mode only               |

## Review Phase Configuration

Review phases (3, 5, 8) support these config options:

| Option         | Values                                    | Default |
| -------------- | ----------------------------------------- | ------- |
| onFailure      | `mini-loop`, `restart`, `proceed`, `stop` | varies  |
| failOnSeverity | `LOW`, `MEDIUM`, `HIGH`, `NONE`           | `LOW`   |
| maxRetries     | positive integer or `null`                | `10`    |
| onMaxRetries   | `stop`, `ask`, `restart`, `proceed`       | `stop`  |
| parallelFixes  | `true`, `false`                           | `true`  |

Phase 6 (Test) only supports `onFailure`, `maxRetries`, and `onMaxRetries` (no severity filtering - tests are pass/fail).

**`onMaxRetries` behaviors:**

- `stop`: Halt workflow, report what failed (default)
- `ask`: Prompt user to decide next action
- `restart`: Go back to Phase 1, start new iteration
- `proceed`: Continue to next phase with issues noted

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
  "version": 4,
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
        "3": {
          "status": "...",
          "retryCount": 0,
          "lastIssues": []
        },
        "4": { "status": "..." },
        "5": {
          "status": "...",
          "retryCount": 0,
          "lastIssues": []
        },
        "6": {
          "status": "...",
          "retryCount": 0
        },
        "7": { "status": "..." },
        "8": {
          "status": "...",
          "retryCount": 0,
          "lastIssues": []
        }
      }
    }
  ],
  "phase9": { "status": "pending" }
}
```

**Issue format in `lastIssues`:**

```json
{
  "severity": "HIGH|MEDIUM|LOW",
  "message": "description",
  "location": "file:line"
}
```

## Boundaries

**Always:** Update state after each phase, follow phase progression, fix HIGH severity issues, validate plan before implementation, bump plugin.json version on changes

**Ask First:** Skipping phases, changing iteration count mid-workflow, modifying state file schema

**Never:** Skip Phase 8 decision point without approval, proceed with HIGH severity issues, commit secrets, include `docs/plans/` in PRs (plans are local working documents)
