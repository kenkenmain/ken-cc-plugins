# Superpowers Iterate Plugin - Agent Instructions

## Commands

### Testing

```bash
make lint          # Lint check (not configured yet)
make test          # Run tests (not configured yet)
```

### Plugin Development

```bash
claude plugin install ./plugins/superpowers-iterate  # Install locally
claude plugin list                                    # List installed
```

### Iteration Workflow

```bash
/superpowers-iterate:iterate <task>                   # Full mode (Codex MCP)
/superpowers-iterate:iterate --lite <task>            # Lite mode (Claude only)
/superpowers-iterate:iterate --max-iterations 5 <task> # Limit iterations
/superpowers-iterate:iterate-status                   # Check progress
```

## Project Structure

```
ken-cc-plugins/
├── plugins/
│   └── superpowers-iterate/
│       ├── .claude-plugin/plugin.json    # Plugin manifest (name, version)
│       ├── commands/                      # Slash commands (iterate.md, iterate-status.md)
│       ├── skills/iteration-workflow/     # Main skill (SKILL.md)
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
Phase 3: Plan Review   -> mcp__codex__codex (validates plan before implementation)
Phase 4: Implement     -> superpowers:subagent-driven-development
Phase 5: Review        -> superpowers:requesting-code-review
Phase 6: Test          -> make lint && make test
Phase 7: Simplify      -> code-simplifier agent
Phase 8: Final Review  -> mcp__codex__codex (decision point - loop or proceed)
Phase 9: Codex Final   -> mcp__codex-high__codex (full mode only)
```

**Iteration Loop:** Phases 1-8 repeat until Phase 8 finds zero issues or max iterations reached.

## Model Configuration

| Phase | Activity     | Model     | MCP Tool                 | Rationale                            |
| ----- | ------------ | --------- | ------------------------ | ------------------------------------ |
| 1     | Brainstorm   | `sonnet`  | N/A                      | Cost-effective parallel exploration  |
| 2     | Plan         | `sonnet`  | N/A                      | Parallel plan creation               |
| 3     | Plan Review  | N/A       | `mcp__codex__codex`      | Medium reasoning for plan validation |
| 4     | Implement    | `inherit` | N/A                      | User controls quality                |
| 5     | Review       | `inherit` | N/A                      | Quick sanity check                   |
| 6     | Test         | N/A       | N/A                      | Bash commands                        |
| 7     | Simplify     | `inherit` | N/A                      | Code quality                         |
| 8     | Final Review | N/A       | `mcp__codex__codex`      | Medium reasoning for iteration       |
| 9     | Codex Final  | N/A       | `mcp__codex-high__codex` | High reasoning for final validation  |

## Code Style

### Markdown Files

- Use YAML frontmatter (---) for plugin metadata
- Follow existing command/skill/agent structure
- Include examples in `<example>` tags

### Naming

- Commands: kebab-case (e.g., `iterate-status.md`)
- Skills: kebab-case (e.g., `iteration-workflow`)
- Agents: kebab-case (e.g., `codex-reviewer.md`)

### Git Commits

- Prefix: `feat|fix|docs|chore|ci`
- Co-author: `Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>`
- Example: `feat: add Phase 3 Plan Review stage`

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

### Always Do

- Update `.agents/iteration-state.json` after each phase
- Follow phase progression (never skip)
- Fix HIGH severity issues before proceeding
- Validate plan before implementation (Phase 3)
- Bump `plugin.json` version on changes

### Ask First

- Skipping phases
- Changing iteration count mid-workflow
- Modifying state file schema

### Never Do

- Skip Phase 8 decision point without explicit user approval
- Proceed with HIGH severity issues
- Commit secrets or API keys
- Break backward compatibility without version bump
