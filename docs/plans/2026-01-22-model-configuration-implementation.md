# Model Configuration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Update superpowers-iterate plugin to use `sonnet` alias for parallel agents and `inherit` for non-parallel agents.

**Architecture:** Change hardcoded model IDs to use model aliases. Parallel agents use `sonnet` for cost-effective work, non-parallel agents use `inherit` to respect user's `/model` choice.

**Tech Stack:** YAML frontmatter in markdown files

**Test Strategy:** Validate YAML syntax and plugin.json version bump

---

## Task 1: Update codex-reviewer agent model

**File:** `plugins/superpowers-iterate/agents/codex-reviewer.md`

**Change:** Line 11, change `model: claude-sonnet-4-20250514` to `model: inherit`

**Rationale:** This is a single-task agent (not parallel), should respect user's `/model` choice.

**Before:**

```yaml
model: claude-sonnet-4-20250514
```

**After:**

```yaml
model: inherit
```

**Acceptance criteria:**

- YAML frontmatter is valid
- Model is set to `inherit`

---

## Task 2: Update SKILL.md to clarify model configuration

**File:** `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md`

**Changes:**

### 2a: Add Model Configuration section after "## Modes"

Add a new section explaining the model strategy:

```markdown
## Model Configuration

| Agent Type                              | Model Setting    | Rationale                                        |
| --------------------------------------- | ---------------- | ------------------------------------------------ |
| Parallel agents (research, exploration) | `model: sonnet`  | Latest Sonnet for cost-effective parallel work   |
| Non-parallel agents (single tasks)      | `model: inherit` | Respects user's `/model` choice (e.g., Opus 4.5) |

When dispatching agents via `superpowers:dispatching-parallel-agents`, specify `model: sonnet` in the Task tool call.
When dispatching single-task agents (code-reviewer, code-simplifier), use `model: inherit` or omit to inherit parent model.
```

### 2b: Update Phase 1 parallel agent guidance (line 98)

Change "Launch as many parallel sonnet subagents" to clarify model parameter:

**Before:**

```markdown
3. **Launch as many parallel sonnet subagents as needed** using `superpowers:dispatching-parallel-agents`:
```

**After:**

```markdown
3. **Launch as many parallel subagents as needed** (with `model: sonnet`) using `superpowers:dispatching-parallel-agents`:
```

### 2c: Update Phase 2 parallel agent guidance (line 136)

**Before:**

```markdown
2. **Launch as many parallel sonnet subagents as needed** to create plan components:
```

**After:**

```markdown
2. **Launch as many parallel subagents as needed** (with `model: sonnet`) to create plan components:
```

**Acceptance criteria:**

- New Model Configuration section is clear
- Phase 1 and 2 guidance updated

---

## Task 3: Bump plugin version

**File:** `plugins/superpowers-iterate/.claude-plugin/plugin.json`

**Change:** Bump version from `1.2.0` to `1.3.0`

**Rationale:** This is a minor feature change (model configuration clarification).

**Before:**

```json
"version": "1.2.0",
```

**After:**

```json
"version": "1.3.0",
```

**Acceptance criteria:**

- Version follows semver
- plugin.json is valid JSON

---

## Task 4: Create feature branch and commit

**Commands:**

```bash
git checkout -b feature/model-configuration-update
git add -A
git commit -m "feat: use sonnet alias for parallel agents, inherit for single-task agents"
```

**Acceptance criteria:**

- Branch created from main
- Changes committed
