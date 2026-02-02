# kenken

4-stage iterative development workflow for Claude Code.

**Stages:** PLAN -> IMPLEMENT -> TEST (optional) -> FINAL

## Installation

```bash
# From ken-cc-plugins marketplace
claude plugin marketplace add kenkenmain/ken-cc-plugins
claude plugin install kenken@ken-cc-plugins
```

## Quick Start

```bash
# Start iterative workflow
/kenken:iterate Add user authentication with OAuth2

# Check status
/kenken:iterate-status

# Resume interrupted workflow
/kenken:iterate-resume

# Configure settings
/kenken:iterate-configure
/kenken:iterate-configure --show
/kenken:iterate-configure --reset

# Set up a new GitHub repo with GitFlow
/kenken:gh-repo-setup my-new-repo

# Configure an existing repo
/kenken:gh-repo-setup --existing
```

## GitHub Repository Setup

The `gh-repo-setup` skill sets up GitHub repositories with best practices:

```bash
/kenken:gh-repo-setup [repo-name]
/kenken:gh-repo-setup --existing
```

**Features:**

- **GitFlow branching** - Creates main and develop branches
- **Branch protection** - Requires PR reviews, admins can bypass
- **Squash merge only** - Merge commit and rebase disabled
- **Auto-delete branches** - Branches deleted after merge
- **Issue templates** - Bug report and feature request templates
- **PR template** - Standardized pull request format
- **CI workflow** - Label-triggered GitHub Actions (add `ci` label to run)
- **Dependabot** - Weekly updates for github-actions

## The 4 Stages

### Stage 1: PLAN

| Phase | Name        | Description                         |
| ----- | ----------- | ----------------------------------- |
| 1.1   | Brainstorm  | Understand problem, design solution |
| 1.2   | Write Plan  | Create detailed implementation plan |
| 1.3   | Plan Review | Validate plan with Codex review     |

### Stage 2: IMPLEMENT

| Phase | Name             | Description                |
| ----- | ---------------- | -------------------------- |
| 2.1   | Implementation   | Execute plan task by task  |
| 2.2   | Code Simplify    | Reduce complexity          |
| 2.3   | Implement Review | Validate with Codex review |

### Stage 3: TEST (Optional)

| Phase | Name           | Description                 |
| ----- | -------------- | --------------------------- |
| 3.1   | Test Plan      | Plan test coverage          |
| 3.2   | Write Tests    | Implement tests             |
| 3.3   | Coverage Check | Verify coverage threshold   |
| 3.4   | Run Tests      | Execute and capture results |
| 3.5   | Test Review    | Validate test quality       |

Enable via config: `stages.test.enabled: true`

### Stage 4: FINAL

| Phase | Name               | Description                       |
| ----- | ------------------ | --------------------------------- |
| 4.1   | Codex Final        | Final validation (high reasoning) |
| 4.2   | Suggest Extensions | Propose next steps                |
| 4.3   | Completion         | Git workflow options              |

**Completion options:**

- **No git** - Just finish, no git operations
- **Commit only** - Commit to current branch (non-branch workflow)
- **Branch + PR** - Create feature branch and open PR (branch-based workflow)

## Configuration

```bash
# Interactive wizard
/kenken:iterate-configure

# Show current config
/kenken:iterate-configure --show

# Reset to defaults
/kenken:iterate-configure --reset
```

**Config files:**

- Global: `~/.claude/kenken-config.json`
- Project: `.claude/kenken-config.json`

Project config overrides global.

## Prerequisites

**Required plugins:**

- superpowers
- code-simplifier

**Required MCP servers (full mode):**

- codex (`mcp__codex-high__codex`)
- codex-high (`mcp__codex-xhigh__codex`)

## State Management

Progress tracked in `.agents/kenken-state.json`

## License

MIT

## Author

Kennard Ng <kennard.ng.pool.hua@gmail.com>
