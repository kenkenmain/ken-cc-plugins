# AGENTS.md and Workflow Improvements Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add AGENTS.md file, symlink CLAUDE.md, add Plan Review phase with codex-medium, and enhance model configuration.

**Architecture:** Create cross-platform AGENTS.md at repository root, add Phase 3 (Plan Review) between Plan and Implement, expand model configuration documentation.

**Tech Stack:** Markdown, YAML frontmatter, JSON state schema, Bash symlinks

**Test Strategy:** Validate markdown syntax, verify symlink, check JSON validity, CI validation

---

## Task 1: Create AGENTS.md file

**File:** `AGENTS.md` (repository root)

**Content:**
```markdown
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

| Phase | Activity | Model | MCP Tool | Rationale |
|-------|----------|-------|----------|-----------|
| 1 | Brainstorm | `sonnet` | N/A | Cost-effective parallel exploration |
| 2 | Plan | `sonnet` | N/A | Parallel plan creation |
| 3 | Plan Review | N/A | `mcp__codex__codex` | Medium reasoning for plan validation |
| 4 | Implement | `inherit` | N/A | User controls quality |
| 5 | Review | `inherit` | N/A | Quick sanity check |
| 6 | Test | N/A | N/A | Bash commands |
| 7 | Simplify | `inherit` | N/A | Code quality |
| 8 | Final Review | N/A | `mcp__codex__codex` | Medium reasoning for iteration decision |
| 9 | Codex Final | N/A | `mcp__codex-high__codex` | High reasoning for final validation |

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
  "currentIteration": 1,
  "currentPhase": 1,
  "phases": {
    "1": { "status": "..." },
    "2": { "status": "..." },
    "3": { "status": "...", "planReviewIssues": [] },
    ...
  }
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
```

**Acceptance criteria:**
- File created at repository root
- Contains all required sections
- Markdown syntax valid

---

## Task 2: Create CLAUDE.md symlink

**Command:**
```bash
ln -sf AGENTS.md CLAUDE.md
```

**Acceptance criteria:**
- CLAUDE.md is a symlink to AGENTS.md
- `ls -la CLAUDE.md` shows symlink
- `cat CLAUDE.md` shows AGENTS.md content

---

## Task 3: Update SKILL.md - Add Phase 3 (Plan Review)

**File:** `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md`

**Changes:**

### 3a: Update title and phase list

Change "8-Phase" to "9-Phase" and add Phase 3:

```markdown
# 9-Phase Iteration Workflow Skill

## The 9 Phases

```
Phase 1: Brainstorm    -> superpowers:brainstorming + N parallel subagents
Phase 2: Plan          -> superpowers:writing-plans + N parallel subagents
Phase 3: Plan Review   -> mcp__codex__codex (validates plan before implementation)
Phase 4: Implement     -> superpowers:subagent-driven-development + N subagents
Phase 5: Review        -> superpowers:requesting-code-review (1 round)
Phase 6: Test          -> make lint && make test
Phase 7: Simplify      -> code-simplifier agent
Phase 8: Final Review  -> Decision point (see below)
Phase 9: Codex         -> Final validation (full mode only)
```
```

### 3b: Update iteration loop diagram

```markdown
## Iteration Loop

Phases 1-8 repeat until Phase 8 finds **zero issues** or `--max-iterations` is reached.
Phase 9 runs once at the end (full mode only).

```
Iteration 1: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8
             Phase 8 finds issues? -> Fix -> Start Iteration 2
Iteration 2: Phase 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8
             Phase 8 finds zero issues? -> Proceed to Phase 9
Phase 9: Final validation (once)
```
```

### 3c: Add new Phase 3: Plan Review section

Insert after Phase 2, before current Phase 3 (which becomes Phase 4):

```markdown
## Phase 3: Plan Review

**Purpose:** Validate plan quality before implementation begins

**Required Tool:**
- Full mode: `mcp__codex__codex`
- Lite mode: `superpowers:requesting-code-review`

**Actions:**

1. Mark Phase 3 as `in_progress` in state file
2. Run review based on mode:

### Full Mode (mcp\_\_codex\_\_codex)

Invoke `mcp__codex__codex` with plan review prompt:

```
Review the implementation plan at docs/plans/YYYY-MM-DD-<feature-name>.md

Validate:
- Task granularity (each task should be 2-5 minutes of work)
- TDD steps included for each task
- File paths are specific and accurate
- Plan follows DRY, YAGNI principles
- Test strategy is comprehensive
- Dependencies and task order are correct
- Edge cases are covered

Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
If you find NO issues, explicitly state: "Plan looks good to proceed."
```

### Lite Mode (superpowers:requesting-code-review)

Dispatch code-reviewer subagent to review the plan document.

3. **Evaluate review results:**

   **If ZERO issues found:**
   - Announce: "Plan review passed. Proceeding to implementation."
   - Proceed to Phase 4

   **If HIGH/MEDIUM issues found:**
   - Fix plan issues
   - Re-run plan review
   - Do not proceed until plan is clean

   **If only LOW issues found:**
   - Note them for awareness
   - Proceed to Phase 4

**Exit criteria:**
- Plan review completed
- No HIGH or MEDIUM severity issues in plan
- Plan ready for implementation

**Transition:** Mark Phase 3 complete, advance to Phase 4
```

### 3d: Renumber remaining phases (3->4, 4->5, etc.)

Update all phase references:
- Old Phase 3 (Implement) -> Phase 4
- Old Phase 4 (Review) -> Phase 5
- Old Phase 5 (Test) -> Phase 6
- Old Phase 6 (Simplify) -> Phase 7
- Old Phase 7 (Final Review) -> Phase 8
- Old Phase 8 (Codex Final) -> Phase 9

### 3e: Update state schema in documentation

Change version to 3 and add phase 3 with planReviewIssues:

```json
{
  "version": 3,
  "phases": {
    "1": { "status": "..." },
    "2": { "status": "..." },
    "3": { "status": "...", "planReviewIssues": [] },
    "4": { "status": "..." },
    ...
    "8": { "status": "..." }
  },
  "phase9": { "status": "pending" }
}
```

**Acceptance criteria:**
- SKILL.md shows 9 phases
- Phase 3 (Plan Review) is documented
- All phase numbers updated
- State schema shows version 3

---

## Task 4: Update iterate.md command

**File:** `plugins/superpowers-iterate/commands/iterate.md`

**Changes:**
- Update phase table to show 9 phases
- Add Phase 3 (Plan Review)
- Update state schema example to version 3

**Acceptance criteria:**
- Command documentation shows 9 phases
- State schema example is version 3

---

## Task 5: Update README.md (plugin)

**File:** `plugins/superpowers-iterate/README.md`

**Changes:**
- Update phase count from 8 to 9
- Add Phase 3 (Plan Review) to phase list
- Update any phase number references

**Acceptance criteria:**
- README shows 9-phase workflow
- Phase 3 (Plan Review) documented

---

## Task 6: Update root README.md

**File:** `README.md`

**Changes:**
- Update phase count if mentioned
- Reference AGENTS.md and CLAUDE.md

**Acceptance criteria:**
- Root README is consistent with plugin changes

---

## Task 7: Bump plugin version

**File:** `plugins/superpowers-iterate/.claude-plugin/plugin.json`

**Change:** `"version": "1.3.0"` -> `"version": "1.4.0"`

**Acceptance criteria:**
- Version is 1.4.0
- JSON is valid

---

## Task 8: Commit and create PR

**Commands:**
```bash
git add AGENTS.md CLAUDE.md plugins/ README.md docs/
git commit -m "feat: add AGENTS.md, Phase 3 Plan Review, and 9-phase workflow"
git push -u origin feature/agents-md-and-workflow-improvements
gh pr create --title "..." --body "..."
```

**Acceptance criteria:**
- All changes committed
- PR created with summary
