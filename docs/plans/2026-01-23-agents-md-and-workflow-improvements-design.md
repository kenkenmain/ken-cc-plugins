# Design: AGENTS.md and Workflow Improvements

## Problem Statement

The plugin needs:
1. AGENTS.md file for cross-platform AI agent compatibility
2. CLAUDE.md symlinked to AGENTS.md for Claude Code support
3. CI version checks verification
4. A plan review stage after brainstorm and plan phases (using codex-medium)
5. Configurable model settings for workflow phases

## Requirements Analysis

### 1. AGENTS.md File

AGENTS.md is an emerging standard for AI agent instructions (stewarded by Agentic AI Foundation). Key sections:
- Commands (testing, plugin development, git workflow)
- Project Structure
- Code Style & Conventions
- Plugin Architecture
- Testing & Validation
- Boundaries (always do, ask first, never do)

### 2. CLAUDE.md Symlink

- CLAUDE.md is Claude Code's native configuration format
- Symlink to AGENTS.md ensures single source of truth
- Both files will have same content

### 3. CI Version Checks Status

Current CI has:
- Semver format validation
- Version bump detection (WARNING only, not blocking)

Gaps identified:
- Version bump check is non-blocking (should fail PR)
- No validation of required fields (name, description, author, license)
- No version progression check (new > old)

### 4. Plan Review Stage

Insert new Phase 2.5 between Plan and Implement:
- Purpose: Validate plan quality before expensive implementation
- Tool: `mcp__codex__codex` (standard/medium reasoning)
- Review criteria: task granularity, TDD steps, file paths, edge cases

### 5. Model Configuration

Implement configurable model settings:
- Parallel agents: `model: sonnet` (cost-effective)
- Single-task agents: `model: inherit` (respects user choice)
- Review phases: Configurable MCP reasoning levels

## Design Decisions

### Phase Structure Change

Current 8 phases become 9 phases:

```
Phase 1: Brainstorm   -> superpowers:brainstorming + N parallel subagents
Phase 2: Plan         -> superpowers:writing-plans + N parallel subagents
Phase 3: Plan Review  -> mcp__codex__codex (NEW)
Phase 4: Implement    -> superpowers:subagent-driven-development
Phase 5: Review       -> superpowers:requesting-code-review (1 round)
Phase 6: Test         -> make lint && make test
Phase 7: Simplify     -> code-simplifier agent
Phase 8: Final Review -> mcp__codex__codex - decision point
Phase 9: Codex        -> mcp__codex-high__codex final validation
```

### Model Configuration Table

| Phase | Activity | Model Setting | MCP Tool | Reasoning |
|-------|----------|---------------|----------|-----------|
| 1 | Brainstorm | `sonnet` | N/A | Parallel exploration |
| 2 | Plan | `sonnet` | N/A | Parallel planning |
| 3 | Plan Review | N/A | `mcp__codex__codex` | Medium reasoning for plan validation |
| 4 | Implement | `inherit` | N/A | User controls quality |
| 5 | Review | `inherit` | N/A | Quick sanity check |
| 6 | Test | N/A | N/A | Bash commands |
| 7 | Simplify | `inherit` | N/A | Code quality |
| 8 | Final Review | N/A | `mcp__codex__codex` | Medium for iteration |
| 9 | Codex Final | N/A | `mcp__codex-high__codex` | High for final |

### State File Schema Update

```json
{
  "version": 3,
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
  "phase9": { "status": "..." }
}
```

## Files to Create/Modify

1. **Create AGENTS.md** - Root level agent instructions
2. **Create CLAUDE.md** - Symlink to AGENTS.md
3. **Modify SKILL.md** - Add Phase 3 (Plan Review), renumber phases 3-8 to 4-9
4. **Modify iterate.md** - Update phase table
5. **Modify README.md** - Update phase documentation
6. **Modify plugin.json** - Bump version to 1.4.0

## Test Strategy

1. Validate AGENTS.md content
2. Verify CLAUDE.md symlink works
3. Test updated 9-phase workflow
4. Verify state file schema handles new phase
5. CI validation passes
