---
name: iteration-workflow
description: Use when orchestrating a complete 8-phase development iteration. Activated by /iterate command or when user asks to follow the iteration workflow.
---

# 8-Phase Iteration Workflow Skill

## When to Use

This skill activates when:

- User invokes `/iterate <task>`
- User asks to "follow the iteration workflow"
- User mentions "superpowers iteration" or "8-phase workflow"

**Announce:** "I'm using the iteration-workflow skill to orchestrate this task through all 8 mandatory phases."

## The 8 Phases

```
Phase 1: Brainstorm  -> superpowers:brainstorming + N parallel subagents
Phase 2: Plan        -> superpowers:writing-plans + N parallel subagents
Phase 3: Implement   -> superpowers:subagent-driven-development + N subagents
Phase 4: Review      -> superpowers:requesting-code-review (3 rounds)
Phase 5: Test        -> make lint && make test
Phase 6: Simplify    -> code-simplifier agent
Phase 7: Final Review -> @codex-high MCP review (3 rounds)
Phase 8: Codex       -> @codex-xhigh MCP final validation
```

## State Management

**State file:** `.agents/iteration-state.json`

Initialize at start:

```json
{
  "version": 1,
  "task": "<task description>",
  "startedAt": "<ISO timestamp>",
  "currentPhase": 1,
  "phases": {
    "1": { "status": "in_progress", "startedAt": "<timestamp>" },
    "2": { "status": "pending" },
    "3": { "status": "pending" },
    "4": { "status": "pending" },
    "5": { "status": "pending" },
    "6": { "status": "pending" },
    "7": { "status": "pending" },
    "8": { "status": "pending" }
  }
}
```

Update state after each phase transition.

## Phase 1: Brainstorm

**Purpose:** Explore problem space, generate ideas, clarify requirements

**Required Skill:** `superpowers:brainstorming` + `superpowers:dispatching-parallel-agents`

**Actions:**

1. Mark Phase 1 as `in_progress` in state file
2. Use TodoWrite to track brainstorming tasks
3. **Launch as many parallel sonnet subagents as needed** using `superpowers:dispatching-parallel-agents`:
   - Identify independent research areas for the task
   - Dispatch one subagent per independent domain (no limit)
   - Example domains:
     - Research existing code patterns and architecture
     - Explore problem domain and requirements
     - Investigate test strategy and coverage requirements
     - Analyze similar implementations in codebase
     - Research external libraries/APIs needed
     - Explore edge cases and error scenarios
4. Follow `superpowers:brainstorming` process:
   - Ask questions one at a time to refine the idea
   - Propose 2-3 different approaches with trade-offs
   - Present design in 200-300 word sections, validating each
5. Document test strategy requirements during brainstorming:
   - What test frameworks/tools are available?
   - What testing patterns does the codebase use?
   - What edge cases need coverage?
6. Save design to `docs/plans/YYYY-MM-DD-<topic>-design.md`

**Exit criteria:**

- Problem is well understood
- Approach is agreed upon
- Design decisions documented
- Test strategy requirements identified

**Transition:** Mark Phase 1 complete, advance to Phase 2

## Phase 2: Plan

**Purpose:** Create detailed implementation plan with bite-sized tasks including tests

**Required Skill:** `superpowers:writing-plans` + `superpowers:dispatching-parallel-agents`

**Actions:**

1. Mark Phase 2 as `in_progress`
2. **Launch as many parallel sonnet subagents as needed** to create plan components:
   - Identify independent planning areas based on brainstorm output
   - Dispatch one subagent per independent component (no limit)
   - Example planning areas:
     - Plan core implementation tasks
     - Plan test coverage (TDD approach)
     - Plan integration points and edge cases
     - Plan documentation updates
     - Plan migration/upgrade paths
     - Plan performance considerations
3. Follow `superpowers:writing-plans` format:
   - Each task is 2-5 minutes of work
   - Include exact file paths
   - Include complete code in plan
   - Follow DRY, YAGNI, TDD principles
4. **Each task MUST include test steps:**
   - Step 1: Write failing test
   - Step 2: Run test to verify it fails
   - Step 3: Write minimal implementation
   - Step 4: Run test to verify it passes
   - Step 5: Commit
5. Save plan to `docs/plans/YYYY-MM-DD-<feature-name>.md`
6. Document the plan using TodoWrite

**Plan header must include:**

```markdown
# [Feature Name] Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Test Strategy:** [Testing approach and frameworks]

---
```

**Exit criteria:**

- Implementation plan created with TDD steps
- All tasks have clear acceptance criteria
- Test strategy defined for each task
- Plan follows superpowers:writing-plans format

**Transition:** Mark Phase 2 complete, advance to Phase 3

## Phase 3: Implement

**Purpose:** TDD-style implementation following the plan

**Required Skill:** `superpowers:subagent-driven-development` + `superpowers:test-driven-development`

**Required Plugins:** LSP plugins for code intelligence

**Actions:**

1. Mark Phase 3 as `in_progress`
2. Follow `superpowers:subagent-driven-development` process:
   - Read plan, extract all tasks, create TodoWrite
   - **Launch as many subagents as needed** for implementation:
     - One implementer subagent per task (sequential to avoid conflicts)
     - Multiple reviewer subagents can run in parallel
   - For each task:
     a. Dispatch implementer subagent with full task text AND LSP context:
        ```
        You have access to LSP (Language Server Protocol) tools:
        - mcp__lsp__get_diagnostics: Get errors/warnings for a file
        - mcp__lsp__get_hover: Get type info and documentation at position
        - mcp__lsp__goto_definition: Jump to symbol definition
        - mcp__lsp__find_references: Find all references to a symbol
        - mcp__lsp__get_completions: Get code completions at position

        Use LSP tools to:
        - Check for errors before committing
        - Understand existing code via hover/go-to-definition
        - Find all usages before refactoring
        ```
     b. Answer any questions from subagent
     c. Subagent follows `superpowers:test-driven-development`:
        - Write failing test first
        - Run to verify it fails
        - Write minimal code to pass
        - Run to verify it passes
        - Use `mcp__lsp__get_diagnostics` to check for errors
        - Self-review and commit
     d. Dispatch spec reviewer subagent
     e. Dispatch code quality reviewer subagent (can use LSP diagnostics)
     f. Mark task complete in TodoWrite
3. Run `make lint && make test` to verify all tests pass
4. Commit after tests pass

**Note:** Implementation subagents run sequentially (to avoid file conflicts), but reviewer subagents can run in parallel.

**Exit criteria:**

- All tasks from plan implemented
- Tests written for new functionality (TDD)
- `make lint && make test` pass
- Code committed

**Transition:** Mark Phase 3 complete, advance to Phase 4

## Phase 4: Review (3 Rounds)

**Purpose:** Code review with 3 mandatory rounds

**Required Skill:** `superpowers:requesting-code-review`

**Actions:**

1. Mark Phase 4 as `in_progress`
2. Get git SHAs for the changes:
   ```bash
   BASE_SHA=$(git merge-base HEAD main)
   HEAD_SHA=$(git rev-parse HEAD)
   ```
3. For round in [1, 2, 3]:
   a. Dispatch code-reviewer subagent per `superpowers:requesting-code-review`
   b. Provide:
   - WHAT_WAS_IMPLEMENTED: Description of changes
   - PLAN_OR_REQUIREMENTS: Reference to plan file
   - BASE_SHA and HEAD_SHA
     c. Categorize issues:
   - **Critical:** Must fix immediately
   - **Important:** Fix before next round
   - **Minor:** Note for later
     d. Fix Critical and Important issues
     e. Re-run tests after fixes
4. Document findings in state

**Exit criteria:**

- 3 review rounds completed
- No Critical issues remaining
- Important issues addressed

**Transition:** Mark Phase 4 complete, advance to Phase 5

## Phase 5: Test

**Purpose:** Run lint and test suites

**Actions:**

1. Mark Phase 5 as `in_progress`
2. Run: `make lint`
   - If fails: Fix issues, re-run until pass
3. Run: `make test`
   - If fails: Fix issues, re-run until pass
4. Record results in state

**Exit criteria:**

- `make lint` passes
- `make test` passes

**Transition:** Mark Phase 5 complete, advance to Phase 6

## Phase 6: Code Simplifier

**Purpose:** Reduce code bloat using code-simplifier plugin

**Required Plugin:** `code-simplifier:code-simplifier` (from claude-plugins-official)

**Actions:**

1. Mark Phase 6 as `in_progress`
2. Launch code-simplifier agent using Task tool:
   ```
   Task(
     description: "Simplify modified code",
     prompt: "Review and simplify code modified in this iteration. Focus on clarity and maintainability while preserving functionality.",
     subagent_type: "code-simplifier:code-simplifier"
   )
   ```
3. Review suggestions
4. Apply appropriate simplifications
5. Re-run tests to verify no breakage

**Exit criteria:**

- Code simplifier has reviewed changes
- Appropriate simplifications applied
- Tests still pass

**Transition:** Mark Phase 6 complete, advance to Phase 7

## Phase 7: Codex-High Final Review (3 Rounds)

**Purpose:** Final review focused on merge readiness using Codex high reasoning

**Required Tool:** `mcp__codex-high__codex`

**Actions:**

1. Mark Phase 7 as `in_progress`
2. For round in [1, 2, 3]:
   a. Invoke `mcp__codex-high__codex` with review prompt:

   ```
   Review round {N}/3 for merge readiness. Run these commands first:
   1. make lint
   2. make test

   Focus on:
   - Documentation accuracy
   - Edge cases and error handling
   - Test coverage completeness
   - Code quality and maintainability
   - Merge readiness

   Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
   ```

   b. Categorize Codex findings:
   - **HIGH:** Must fix immediately
   - **MEDIUM:** Fix before next round
   - **LOW:** Note for later
     c. Fix HIGH and MEDIUM issues
     d. Re-run tests after fixes

3. Document findings in state

**Exit criteria:**

- 3 Codex review rounds completed
- No HIGH severity issues remaining
- Code is merge-ready
- Documentation is accurate
- Test coverage is complete

**Transition:** Mark Phase 7 complete, advance to Phase 8

## Phase 8: Codex-XHigh Final Validation

**Purpose:** Final validation with OpenAI Codex extra-high reasoning

**Required Tool:** `mcp__codex-xhigh__codex`

**Actions:**

1. Mark Phase 8 as `in_progress`
2. Invoke `mcp__codex-xhigh__codex` with final validation prompt:

   ```
   Final validation review. Run these commands first:
   1. make lint
   2. make test

   This is the FINAL check before merge. Be thorough.

   Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
   Focus on:
   - Correctness and logic errors
   - Idempotency of operations
   - Documentation accuracy
   - Test coverage gaps
   - Security concerns
   - Edge cases missed in earlier reviews
   ```

3. Address any HIGH severity issues
4. Re-run Codex-xhigh if significant changes made

**Exit criteria:**

- Codex-xhigh review completed
- No HIGH severity issues remaining

**Transition:** Mark Phase 8 complete

## Completion

After Phase 8:

1. Update state file to show all phases complete
2. Announce: "Iteration workflow complete!"
3. Summarize accomplishments
4. Suggest next steps (commit, create PR, etc.)
5. Optionally use `superpowers:finishing-a-development-branch` for merge prep

## Resuming Interrupted Iterations

If iteration was interrupted:

1. Read `.agents/iteration-state.json`
2. Identify current phase from `currentPhase` field
3. Announce: "Resuming iteration at Phase N: <phase-name>"
4. Continue from where stopped

## Red Flags - STOP

**Never:**

- Skip phases (all 8 are mandatory)
- Advance without meeting exit criteria
- Ignore Critical issues from reviews
- Skip test runs
- Skip TDD (write tests after implementation)
- Dispatch parallel implementation subagents (conflicts)

**If blocked:**

- Record blocker in state file notes
- Ask user for guidance
- Do not proceed until resolved
