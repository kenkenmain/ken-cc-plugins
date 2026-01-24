# Review Mini-Loops Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add configurable mini-loop behavior to review phases (3, 5, 6, 8) with severity thresholds, retry limits, and parallel fix support.

**Architecture:** Update configuration skill to support new review settings (onFailure, failOnSeverity, maxRetries, onMaxRetries, parallelFixes) with merge logic for reviewDefaults. Update iteration-workflow skill to implement mini-loop logic at each review phase. Update configure command to expose these settings interactively. Bump state schema to v4 and config schema to v2.

**Tech Stack:** Markdown (Claude plugins), JSON (config/state files)

**Test Strategy:** Manual testing via `/superpowers-iterate:configure --show` and running iterations with different configs.

---

## Task 1: Update Configuration Skill - Default Config

**Files:**

- Modify: `plugins/superpowers-iterate/skills/configuration/SKILL.md:17-34`

**Step 1: Update default configuration JSON**

Replace lines 17-34 with new v2 config including reviewDefaults and per-phase review settings:

````markdown
## Default Configuration

```json
{
    "version": 2,
    "reviewDefaults": {
        "failOnSeverity": "LOW",
        "maxRetries": 10,
        "onMaxRetries": "stop",
        "parallelFixes": true
    },
    "phases": {
        "1": {
            "model": "inherit",
            "parallel": true,
            "parallelModel": "inherit"
        },
        "2": {
            "model": "inherit",
            "parallel": true,
            "parallelModel": "inherit"
        },
        "3": { "tool": "mcp__codex__codex", "onFailure": "restart" },
        "4": { "model": "inherit", "parallel": false },
        "5": { "model": "inherit", "onFailure": "mini-loop" },
        "6": { "model": null, "onFailure": "restart" },
        "7": { "model": "inherit", "parallel": false },
        "8": { "tool": "mcp__codex__codex", "onFailure": "restart" },
        "9": { "tool": "mcp__codex-high__codex" }
    }
}
```

**Note:** Review phases (3, 5, 8) inherit `failOnSeverity`, `maxRetries`, `onMaxRetries`, and `parallelFixes` from `reviewDefaults`. Phase 6 (Test) only inherits `maxRetries` and `onMaxRetries` (no severity filtering for test failures). Only `onFailure` and phase-specific settings (like `tool` or `model`) are specified per-phase.

````

**Step 2: Verify change is syntactically correct**

Read the file and confirm JSON block is valid.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/configuration/SKILL.md
git commit -m "feat(config): add reviewDefaults and per-phase review settings to v2 config"
````
````

---

## Task 2: Update Configuration Skill - Merge Logic for reviewDefaults

**Files:**

- Modify: `plugins/superpowers-iterate/skills/configuration/SKILL.md:45-56`

**Step 1: Update merge logic section**

Replace lines 45-56 to include reviewDefaults merge:

```markdown
## Merge Logic (Per-Phase Deep Merge)

Each phase's config is merged individually. For review phases (3, 5, 6, 8), the merge order is:

1. Start with `reviewDefaults` (provides base values for review settings)
2. Apply default phase-specific settings (only `onFailure` and `tool`/`model`)
3. Apply global config `reviewDefaults` (overrides default reviewDefaults)
4. Apply global config phase-specific settings
5. Apply project config `reviewDefaults` (overrides global reviewDefaults)
6. Apply project config phase-specific settings (highest priority)

**Example:**
```

reviewDefaults (default): { "maxRetries": 10 }
phases.3 (default): { "onFailure": "restart" }
reviewDefaults (global): { "maxRetries": 5 }
phases.3 (project): { "onFailure": "mini-loop" }
Result phases.3: { "onFailure": "mini-loop", "maxRetries": 5, "failOnSeverity": "LOW", ... }

```

The key insight: `reviewDefaults` provides inherited defaults that can be overridden at any level.

To "unset" a value back to default: delete the key from config file.
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/configuration/SKILL.md
git commit -m "feat(config): add merge logic for reviewDefaults inheritance"
```

---

## Task 3: Update Configuration Skill - Validation Rules

**Files:**

- Modify: `plugins/superpowers-iterate/skills/configuration/SKILL.md:66-74`

**Step 1: Update validation rules table**

Replace lines 66-74 with expanded validation rules:

```markdown
## Validation Rules

| Phase     | Key            | Valid Values                                                   |
| --------- | -------------- | -------------------------------------------------------------- |
| 1,2,4,5,7 | model          | `inherit`, `sonnet`, `opus`, `haiku`                           |
| 1,2       | parallel       | `true`, `false`                                                |
| 3,8       | tool           | `mcp__codex__codex`, `mcp__codex-high__codex`, `claude-review` |
| 3,5,6,8   | onFailure      | `mini-loop`, `restart`, `proceed`, `stop`                      |
| 3,5,8     | failOnSeverity | `LOW`, `MEDIUM`, `HIGH`, `NONE`                                |
| 3,5,6,8   | maxRetries     | positive integer or `null` (unlimited)                         |
| 3,5,6,8   | onMaxRetries   | `stop`, `ask`, `restart`, `proceed`                            |
| 3,5,8     | parallelFixes  | `true`, `false`                                                |
| 6         | model          | `null` only (bash phase, not configurable)                     |
| 9         | tool           | `mcp__codex-high__codex` only (not configurable)               |

**`onMaxRetries` behaviors:**

- `stop`: Halt workflow, report what failed (default)
- `ask`: Prompt user to decide next action
- `restart`: Go back to Phase 1, start new iteration
- `proceed`: Continue to next phase with issues noted
```

**Step 2: Verify change**

Read file and confirm table is properly formatted.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/configuration/SKILL.md
git commit -m "feat(config): add validation rules for review settings with onMaxRetries docs"
```

---

## Task 4: Update Configure Command - Show Flag Output

**Files:**

- Modify: `plugins/superpowers-iterate/commands/configure.md:22-44`

**Step 1: Update --show output format**

Replace lines 22-44 with expanded output showing review settings (fix tool name formatting):

The replacement text for lines 22-44 should be:

```
## Step 2: Handle --show Flag

If `--show` in arguments, display current merged config:

    Current Configuration (merged from defaults + global + project):

    Phase 1 (Brainstorm):   model=inherit, parallel=true, parallelModel=inherit
    Phase 2 (Plan):         model=inherit, parallel=true, parallelModel=inherit
    Phase 3 (Plan Review):  tool=codex, onFailure=restart, failOnSeverity=LOW, maxRetries=10
    Phase 4 (Implement):    model=inherit
    Phase 5 (Review):       model=inherit, onFailure=mini-loop, failOnSeverity=LOW, maxRetries=10
    Phase 6 (Test):         onFailure=restart, maxRetries=10
    Phase 7 (Simplify):     model=inherit
    Phase 8 (Final Review): tool=codex, onFailure=restart, failOnSeverity=LOW, maxRetries=10
    Phase 9 (Codex Final):  tool=codex-high (not configurable)

    Review Defaults:
    - failOnSeverity: LOW (any issue fails)
    - maxRetries: 10
    - onMaxRetries: stop
    - parallelFixes: true

    Config files:
    - Global: ~/.claude/iterate-config.json [exists/not found]
    - Project: .claude/iterate-config.local.json [exists/not found]

Exit after showing.
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/commands/configure.md
git commit -m "feat(configure): update --show output to display review settings"
```

---

## Task 5: Update Configure Command - Phase Selection

**Files:**

- Modify: `plugins/superpowers-iterate/commands/configure.md:62-87`

**Step 1: Update phase selection options**

Replace lines 62-87 with updated options showing review settings:

```markdown
## Step 4: Interactive Configuration

Show current config (as in --show), then ask what to configure.

Use AskUserQuestion with multiSelect:

- question: "Which phases do you want to configure?"
- header: "Phases"
- multiSelect: true
- options (show current values in labels):
    - label: "Phase 1: Brainstorm (model=inherit, parallel=true)"
      description: "Configure model and parallel agents"
    - label: "Phase 2: Plan (model=inherit, parallel=true)"
      description: "Configure model and parallel agents"
    - label: "Phase 3: Plan Review (tool=codex, onFailure=restart)"
      description: "Configure review tool and failure behavior"
    - label: "Phase 4: Implement (model=inherit)"
      description: "Configure model"
    - label: "Phase 5: Review (onFailure=mini-loop)"
      description: "Configure failure behavior and retries"
    - label: "Phase 6: Test (onFailure=restart)"
      description: "Configure failure behavior"
    - label: "Phase 7: Simplify (model=inherit)"
      description: "Configure model"
    - label: "Phase 8: Final Review (tool=codex, onFailure=restart)"
      description: "Configure review tool and failure behavior"

Note: Phase 9 (Codex Final) is fixed to `mcp__codex-high__codex`.
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/commands/configure.md
git commit -m "feat(configure): update phase selection to include review phases"
```

---

## Task 6: Update Configure Command - Review Phase Questions

**Files:**

- Modify: `plugins/superpowers-iterate/commands/configure.md:89-115`

**Step 1: Add review phase configuration questions**

Replace lines 89-115 with expanded questions including all review settings:

```markdown
## Step 5: Configure Each Selected Phase

For each selected phase, ask appropriate questions:

### For Phases 1, 2 (Parallel phases)

Ask three questions:

1. **Model:** inherit (recommended), sonnet, opus, or haiku
2. **Parallel agents:** Yes (recommended) or No
3. **Parallel model** (if parallel=Yes): inherit, sonnet, opus, or haiku

### For Phase 3 (Plan Review)

Ask six questions:

1. **Tool:** codex (recommended), codex-high, or claude-review
2. **On failure:** Restart iteration (recommended), Mini-loop, Proceed, or Stop
3. **Fail on severity:** LOW (any issue, recommended), MEDIUM, HIGH, or NONE
4. **Max retries:** 10 (default), 5, 3, No limit, or Custom
5. **On max retries:** Stop (recommended), Ask me, Restart iteration, or Proceed
6. **Parallel fixes:** Yes (recommended) or No

### For Phase 5 (Code Review)

Ask six questions:

1. **Model:** inherit (recommended), sonnet, opus, or haiku
2. **On failure:** Mini-loop (recommended), Restart iteration, Proceed, or Stop
3. **Fail on severity:** LOW (any issue, recommended), MEDIUM, HIGH, or NONE
4. **Max retries:** 10 (default), 5, 3, No limit, or Custom
5. **On max retries:** Stop (recommended), Ask me, Restart iteration, or Proceed
6. **Parallel fixes:** Yes (recommended) or No

### For Phase 6 (Test)

Ask three questions:

1. **On failure:** Restart iteration (recommended), Mini-loop, Proceed, or Stop
2. **Max retries:** 10 (default), 5, 3, No limit, or Custom
3. **On max retries:** Stop (recommended), Ask me, Restart iteration, or Proceed

### For Phase 8 (Final Review)

Ask six questions:

1. **Tool:** codex (recommended), codex-high, or claude-review
2. **On failure:** Restart iteration (recommended), Mini-loop, Proceed, or Stop
3. **Fail on severity:** LOW (any issue, recommended), MEDIUM, HIGH, or NONE
4. **Max retries:** 10 (default), 5, 3, No limit, or Custom
5. **On max retries:** Stop (recommended), Ask me, Restart iteration, or Proceed
6. **Parallel fixes:** Yes (recommended) or No

### For Phases 4, 7 (Sequential phases)

Ask which model: inherit (recommended), sonnet, opus, or haiku

**Tool name mapping when saving:**

| UI Label      | Config Value             |
| ------------- | ------------------------ |
| codex         | `mcp__codex__codex`      |
| codex-high    | `mcp__codex-high__codex` |
| claude-review | `claude-review`          |
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/commands/configure.md
git commit -m "feat(configure): add all review phase configuration questions including onMaxRetries and parallelFixes"
```

---

## Task 7: Update Iteration Workflow - State Management

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md:30-34`

**Step 1: Update state management section**

Replace lines 30-34:

```markdown
## State Management

**State file:** `.agents/iteration-state.json`

Initialize at start with version 4 schema. Update state after each phase transition. See AGENTS.md for full schema.

**Review phase state fields:**

- `retryCount`: Number of mini-loop retries within the phase
- `lastIssues`: Array of issues from most recent review (severity, message, location)
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat(workflow): update state management for v4 schema with retry tracking"
```

---

## Task 8: Update Iteration Workflow - Phase 3 Config Options

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md:145-160`

**Step 1: Add config options to Phase 3 header**

After the "Required Tool" section (around line 155), add config options section:

```markdown
**Config options:**

- `onFailure`: `restart` (default), `mini-loop`, `proceed`, `stop`
- `failOnSeverity`: `LOW` (default), `MEDIUM`, `HIGH`, `NONE`
- `maxRetries`: `10` (default)
- `onMaxRetries`: `stop` (default), `ask`, `restart`, `proceed`
- `parallelFixes`: `true` (default)
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat(workflow): add config options to Phase 3 Plan Review"
```

---

## Task 9: Update Iteration Workflow - Phase 3 Actions

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md:156-206`

**Step 1: Rewrite Phase 3 actions with mini-loop logic**

Replace the Actions section of Phase 3:

```markdown
**Actions:**

1. Mark Phase 3 as `in_progress` in state file
2. Initialize `retryCount: 0` and `lastIssues: []` in phase state
3. Run review based on configured tool (Codex or Claude)
4. Parse issues and filter by `failOnSeverity` threshold
5. **Evaluate review results:**

    **If no issues at or above threshold:**
    - Announce: "Plan review passed. Proceeding to implementation."
    - Mark Phase 3 complete, advance to Phase 4

    **If issues found at or above threshold:**
    - Store issues in `lastIssues`
    - Check `onFailure` config:

    **onFailure = "restart":**
    - Announce: "Plan review found {count} issues. Restarting iteration."
    - Increment `currentIteration`, reset to Phase 1
    - If at `maxIterations`, proceed with issues noted

    **onFailure = "mini-loop":**
    - Check `retryCount` against `maxRetries`
    - If `retryCount >= maxRetries`: execute `onMaxRetries` behavior (stop/ask/restart/proceed)
    - Plan fixes for each issue (create fix plan per issue)
    - Execute fixes (parallel if `parallelFixes=true`, ask user if stuck)
    - Increment `retryCount`
    - Loop back to step 3 (re-run review)

    **onFailure = "proceed":**
    - Announce: "Plan review found {count} issues. Proceeding anyway (issues noted)."
    - Mark Phase 3 complete, advance to Phase 4

    **onFailure = "stop":**
    - Announce: "Plan review found {count} issues. Stopping workflow."
    - Halt workflow

**Exit criteria:**

- Review passed (no issues at threshold), OR
- `onFailure` behavior triggered

**Transition:** Mark Phase 3 complete, advance to Phase 4
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat(workflow): implement mini-loop logic for Phase 3 Plan Review"
```

---

## Task 10: Update Iteration Workflow - Phase 5 Config Options

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md:267-275`

**Step 1: Add config options to Phase 5 header**

After the "Required Skill" section, add:

```markdown
**Config options:**

- `onFailure`: `mini-loop` (default), `restart`, `proceed`, `stop`
- `failOnSeverity`: `LOW` (default), `MEDIUM`, `HIGH`, `NONE`
- `maxRetries`: `10` (default)
- `onMaxRetries`: `stop` (default), `ask`, `restart`, `proceed`
- `parallelFixes`: `true` (default)
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat(workflow): add config options to Phase 5 Code Review"
```

---

## Task 11: Update Iteration Workflow - Phase 5 Actions

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md:273-300`

**Step 1: Rewrite Phase 5 actions with mini-loop logic**

Replace the Actions section of Phase 5:

The replacement text for Phase 5 Actions section:

```
**Actions:**

1. Mark Phase 5 as `in_progress`
2. Initialize `retryCount: 0` and `lastIssues: []` in phase state
3. Get git SHAs: `BASE_SHA=$(git merge-base HEAD main)` and `HEAD_SHA=$(git rev-parse HEAD)`
4. Dispatch code-reviewer subagent per `superpowers:requesting-code-review`
5. Parse issues and filter by `failOnSeverity` threshold
6. **Evaluate review results:**

   **If no issues at or above threshold:**
   - Announce: "Code review passed. Proceeding to tests."
   - Mark Phase 5 complete, advance to Phase 6

   **If issues found at or above threshold:**
   - Store issues in `lastIssues`
   - Check `onFailure` config:

   **onFailure = "mini-loop":**
   - Check `retryCount` against `maxRetries`
   - If `retryCount >= maxRetries`: execute `onMaxRetries` behavior
   - Plan fixes for each issue
   - Execute fixes (parallel if `parallelFixes=true`, ask user if stuck)
   - Run `make lint && make test` after fixes
   - Increment `retryCount`
   - Loop back to step 4 (re-run review)

   **onFailure = "restart":**
   - Announce: "Code review found {count} issues. Restarting iteration."
   - Increment `currentIteration`, reset to Phase 1

   **onFailure = "proceed":**
   - Announce: "Code review found {count} issues. Proceeding anyway."
   - Mark Phase 5 complete, advance to Phase 6

   **onFailure = "stop":**
   - Announce: "Code review found {count} issues. Stopping workflow."
   - Halt workflow

**Exit criteria:**

- Review passed, OR
- `onFailure` behavior triggered

**Transition:** Mark Phase 5 complete, advance to Phase 6
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat(workflow): implement mini-loop logic for Phase 5 Code Review"
```

---

## Task 12: Update Iteration Workflow - Phase 6 with onFailure

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md:302-320`

**Step 1: Rewrite Phase 6 with onFailure config**

Replace Phase 6 section:

```markdown
## Phase 6: Test

**Purpose:** Run lint and test suites

**Config options:**

- `onFailure`: `restart` (default), `mini-loop`, `proceed`, `stop`
- `maxRetries`: `10` (default)
- `onMaxRetries`: `stop` (default), `ask`, `restart`, `proceed`

**Actions:**

1. Mark Phase 6 as `in_progress`
2. Initialize `retryCount: 0` in phase state
3. Run: `make lint`
4. Run: `make test`
5. **Evaluate test results:**

    **If all tests pass:**
    - Announce: "All tests passed."
    - Mark Phase 6 complete, advance to Phase 7

    **If tests fail:**
    - Check `onFailure` config:

    **onFailure = "restart":**
    - Announce: "Tests failed. Restarting iteration."
    - Increment `currentIteration`, reset to Phase 1
    - If at `maxIterations`, proceed with failures noted

    **onFailure = "mini-loop":**
    - Check `retryCount` against `maxRetries`
    - If `retryCount >= maxRetries`: execute `onMaxRetries` behavior
    - Plan fixes for failing tests
    - Execute fixes (ask user if stuck)
    - Increment `retryCount`
    - Loop back to step 3 (re-run tests)

    **onFailure = "proceed":**
    - Announce: "Tests failed. Proceeding anyway (failures noted)."
    - Mark Phase 6 complete, advance to Phase 7

    **onFailure = "stop":**
    - Announce: "Tests failed. Stopping workflow."
    - Halt workflow

**Exit criteria:**

- Tests pass, OR
- `onFailure` behavior triggered

**Transition:** Mark Phase 6 complete, advance to Phase 7
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat(workflow): add onFailure config to Phase 6 Test"
```

---

## Task 13: Update Iteration Workflow - Phase 8 Config Options

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md:351-365`

**Step 1: Add config options to Phase 8 header**

After the "Required Tool" section, add:

```markdown
**Config options:**

- `onFailure`: `restart` (default), `mini-loop`, `proceed`, `stop`
- `failOnSeverity`: `LOW` (default), `MEDIUM`, `HIGH`, `NONE`
- `maxRetries`: `10` (default)
- `onMaxRetries`: `stop` (default), `ask`, `restart`, `proceed`
- `parallelFixes`: `true` (default)
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat(workflow): add config options to Phase 8 Final Review"
```

---

## Task 14: Update Iteration Workflow - Phase 8 Actions

**Files:**

- Modify: `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md:362-426`

**Step 1: Rewrite Phase 8 actions with mini-loop logic**

Replace the Actions section of Phase 8:

```markdown
**Actions:**

1. Mark Phase 8 as `in_progress`
2. Initialize `retryCount: 0` and `lastIssues: []` in phase state
3. Check current iteration count against `maxIterations`
4. Run review based on configured tool (Codex or Claude)
5. Parse issues and filter by `failOnSeverity` threshold
6. **Evaluate review results:**

    **If no issues at or above threshold:**
    - Announce: "Iteration {N} final review passed. Proceeding to completion."
    - Store `lastIssues: []` in state
    - **Full mode:** Proceed to Phase 9
    - **Lite mode:** Skip to Completion

    **If issues found at or above threshold:**
    - Store issues in `lastIssues`
    - Check `onFailure` config:

    **onFailure = "restart":**
    - Announce: "Final review found {count} issues. Restarting iteration."
    - Fix ALL issues before restarting
    - Re-run `make lint && make test`
    - **If currentIteration < maxIterations:**
        - Increment `currentIteration`
        - Add new iteration entry to state
        - **Loop back to Phase 1**
    - **If currentIteration >= maxIterations:**
        - Announce: "Reached max iterations ({max}). Proceeding with {count} issues noted."
        - **Full mode:** Proceed to Phase 9
        - **Lite mode:** Skip to Completion

    **onFailure = "mini-loop":**
    - Check `retryCount` against `maxRetries`
    - If `retryCount >= maxRetries`: execute `onMaxRetries` behavior
    - Plan fixes for each issue
    - Execute fixes (parallel if `parallelFixes=true`, ask user if stuck)
    - Re-run `make lint && make test`
    - Increment `retryCount`
    - Loop back to step 4 (re-run review)

    **onFailure = "proceed":**
    - Announce: "Final review found {count} issues. Proceeding anyway."
    - **Full mode:** Proceed to Phase 9
    - **Lite mode:** Skip to Completion

    **onFailure = "stop":**
    - Announce: "Final review found {count} issues. Stopping workflow."
    - Halt workflow

**Exit criteria:**

- Review passed, OR
- `onFailure` behavior triggered

**Transition:**

- Pass or proceed → Phase 9 (full) or Completion (lite)
- Restart → Phase 1 (new iteration)
- Stop → Halt workflow
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md
git commit -m "feat(workflow): implement configurable mini-loop logic for Phase 8 Final Review"
```

---

## Task 15: Update AGENTS.md - State Schema

**Files:**

- Modify: `AGENTS.md:86-118`

**Step 1: Update state schema to v4**

Replace lines 86-118 with:

````markdown
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
````

**Issue format in `lastIssues`:**

```json
{
    "severity": "HIGH|MEDIUM|LOW",
    "message": "description",
    "location": "file:line"
}
```

````

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: update state schema to v4 with retry tracking"
````

---

## Task 16: Update AGENTS.md - Config Documentation

**Files:**

- Modify: `AGENTS.md:57-78`

**Step 1: Update model configuration table**

Replace lines 57-78 with:

```markdown
## Model Configuration

| Phase | Activity     | Model     | MCP Tool                 | onFailure | Rationale                           |
| ----- | ------------ | --------- | ------------------------ | --------- | ----------------------------------- |
| 1     | Brainstorm   | `inherit` | N/A                      | N/A       | User controls via /configure        |
| 2     | Plan         | `inherit` | N/A                      | N/A       | User controls via /configure        |
| 3     | Plan Review  | N/A       | `mcp__codex__codex`      | restart   | Restart iteration on plan issues    |
| 4     | Implement    | `inherit` | N/A                      | N/A       | User controls quality               |
| 5     | Review       | `inherit` | N/A                      | mini-loop | Fix issues within phase             |
| 6     | Test         | N/A       | N/A                      | restart   | Restart iteration on test failures  |
| 7     | Simplify     | `inherit` | N/A                      | N/A       | Code quality                        |
| 8     | Final Review | N/A       | `mcp__codex__codex`      | restart   | Restart iteration on final issues   |
| 9     | Codex Final  | N/A       | `mcp__codex-high__codex` | N/A       | High reasoning for final validation |

## Review Phase Configuration

Review phases (3, 5, 6, 8) support these config options:

| Option         | Values                                    | Default |
| -------------- | ----------------------------------------- | ------- |
| onFailure      | `mini-loop`, `restart`, `proceed`, `stop` | varies  |
| failOnSeverity | `LOW`, `MEDIUM`, `HIGH`, `NONE`           | `LOW`   |
| maxRetries     | positive integer or `null`                | `10`    |
| onMaxRetries   | `stop`, `ask`, `restart`, `proceed`       | `stop`  |
| parallelFixes  | `true`, `false`                           | `true`  |

**`onMaxRetries` behaviors:**

- `stop`: Halt workflow, report what failed (default)
- `ask`: Prompt user to decide next action
- `restart`: Go back to Phase 1, start new iteration
- `proceed`: Continue to next phase with issues noted
```

**Step 2: Verify change**

Read file and confirm formatting.

**Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "docs: add review phase configuration documentation with onMaxRetries"
```

---

## Task 17: Bump Plugin Version

**Files:**

- Modify: `plugins/superpowers-iterate/.claude-plugin/plugin.json:3`

**Step 1: Bump version to 2.0.0**

Change line 3 from `"version": "1.5.0"` to `"version": "2.0.0"`:

```json
{
  "name": "superpowers-iterate",
  "version": "2.0.0",
  ...
}
```

**Step 2: Verify change**

Read file and confirm version updated.

**Step 3: Commit**

```bash
git add plugins/superpowers-iterate/.claude-plugin/plugin.json
git commit -m "chore: bump version to 2.0.0 for review mini-loops feature"
```

---

## Summary

**Total Tasks:** 17

**Files Modified:**

- `plugins/superpowers-iterate/skills/configuration/SKILL.md` (Tasks 1-3)
- `plugins/superpowers-iterate/commands/configure.md` (Tasks 4-6)
- `plugins/superpowers-iterate/skills/iteration-workflow/SKILL.md` (Tasks 7-14)
- `AGENTS.md` (Tasks 15-16)
- `plugins/superpowers-iterate/.claude-plugin/plugin.json` (Task 17)

**Version Changes:**

- Config schema: v1 → v2
- State schema: v3 → v4
- Plugin version: 1.5.0 → 2.0.0

**Issues Fixed from Plan Review:**

1. Added merge logic for `reviewDefaults` (Task 2)
2. Added `onMaxRetries` behavior documentation (Task 3)
3. Split large phase rewrites into config + actions tasks (Tasks 8-14)
4. Added all missing configure questions including `parallelFixes` and `onMaxRetries` (Task 6)
5. Fixed tool name formatting in --show output (Task 4)
