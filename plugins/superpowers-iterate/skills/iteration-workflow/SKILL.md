---
name: iteration-workflow
description: Use when orchestrating a complete 9-phase development iteration. Activated by /superpowers-iterate:iterate command or when user asks to follow the iteration workflow.
---

# 9-Phase Iteration Workflow Skill

## When to Use

This skill activates when:

- User invokes `/superpowers-iterate:iterate <task>`
- User asks to "follow the iteration workflow"
- User mentions "superpowers iteration" or "9-phase workflow"

**Announce:** "I'm using the iteration-workflow skill to orchestrate this task through all 9 mandatory phases."

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

## Modes

| Mode           | Phase 3 Tool        | Phase 8 Tool                         | Phase 9                  | Requires                      |
| -------------- | ------------------- | ------------------------------------ | ------------------------ | ----------------------------- |
| Full (default) | `mcp__codex__codex` | `mcp__codex__codex`                  | `mcp__codex-high__codex` | Codex MCP servers             |
| Lite (--lite)  | Claude code-review  | `superpowers:requesting-code-review` | Skipped                  | superpowers + code-simplifier |

## Model Configuration

| Phase | Activity     | Model     | MCP Tool                 | Rationale                           |
| ----- | ------------ | --------- | ------------------------ | ----------------------------------- |
| 1     | Brainstorm   | `sonnet`  | N/A                      | Cost-effective parallel exploration |
| 2     | Plan         | `sonnet`  | N/A                      | Parallel plan creation              |
| 3     | Plan Review  | N/A       | `mcp__codex__codex`      | Medium reasoning for plan validation|
| 4     | Implement    | `inherit` | N/A                      | User controls quality               |
| 5     | Review       | `inherit` | N/A                      | Quick sanity check                  |
| 6     | Test         | N/A       | N/A                      | Bash commands                       |
| 7     | Simplify     | `inherit` | N/A                      | Code quality                        |
| 8     | Final Review | N/A       | `mcp__codex__codex`      | Medium reasoning for iteration      |
| 9     | Codex Final  | N/A       | `mcp__codex-high__codex` | High reasoning for final validation |

Parallel agents (dispatched via `superpowers:dispatching-parallel-agents`) use `model: sonnet`.
Single-task agents (code-reviewer, code-simplifier) inherit the parent model.

## State Management

**State file:** `.agents/iteration-state.json`

Initialize at start:

```json
{
  "version": 3,
  "task": "<task description>",
  "mode": "full",
  "maxIterations": 10,
  "currentIteration": 1,
  "currentPhase": 1,
  "startedAt": "<ISO timestamp>",
  "iterations": [
    {
      "iteration": 1,
      "startedAt": "<timestamp>",
      "phases": {
        "1": { "status": "in_progress", "startedAt": "<timestamp>" },
        "2": { "status": "pending" },
        "3": { "status": "pending", "planReviewIssues": [] },
        "4": { "status": "pending" },
        "5": { "status": "pending" },
        "6": { "status": "pending" },
        "7": { "status": "pending" },
        "8": { "status": "pending" }
      },
      "phase8Issues": []
    }
  ],
  "phase9": { "status": "pending" }
}
```

Update state after each phase transition. When starting a new iteration, add a new entry to `iterations` array.

## Phase 1: Brainstorm

**Purpose:** Explore problem space, generate ideas, clarify requirements

**Required Skill:** `superpowers:brainstorming` + `superpowers:dispatching-parallel-agents`

**Actions:**

1. Mark Phase 1 as `in_progress` in state file
2. Use TodoWrite to track brainstorming tasks
3. **Launch parallel subagents as needed** using `superpowers:dispatching-parallel-agents`:
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
2. **Launch parallel subagents as needed** to create plan components:
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

## Phase 4: Implement

**Purpose:** TDD-style implementation following the plan

**Required Skill:** `superpowers:subagent-driven-development` + `superpowers:test-driven-development`

**Required Plugins:** LSP plugins for code intelligence

**Actions:**

1. Mark Phase 4 as `in_progress`
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

**Transition:** Mark Phase 4 complete, advance to Phase 5

## Phase 5: Review (1 Round)

**Purpose:** Quick code review sanity check before Phase 8's thorough review

**Required Skill:** `superpowers:requesting-code-review`

**Actions:**

1. Mark Phase 5 as `in_progress`
2. Get git SHAs for the changes:
   ```bash
   BASE_SHA=$(git merge-base HEAD main)
   HEAD_SHA=$(git rev-parse HEAD)
   ```
3. Dispatch code-reviewer subagent per `superpowers:requesting-code-review`
4. Provide:
   - WHAT_WAS_IMPLEMENTED: Description of changes
   - PLAN_OR_REQUIREMENTS: Reference to plan file
   - BASE_SHA and HEAD_SHA
5. Categorize issues:
   - **Critical:** Must fix immediately
   - **Important:** Fix now
   - **Minor:** Note for Phase 8
6. Fix Critical and Important issues
7. Re-run tests after fixes
8. Document findings in state

**Exit criteria:**

- 1 review round completed
- No Critical issues remaining
- Important issues addressed

**Transition:** Mark Phase 5 complete, advance to Phase 6

## Phase 6: Test

**Purpose:** Run lint and test suites

**Actions:**

1. Mark Phase 6 as `in_progress`
2. Run: `make lint`
   - If fails: Fix issues, re-run until pass
3. Run: `make test`
   - If fails: Fix issues, re-run until pass
4. Record results in state

**Exit criteria:**

- `make lint` passes
- `make test` passes

**Transition:** Mark Phase 6 complete, advance to Phase 7

## Phase 7: Code Simplifier

**Purpose:** Reduce code bloat using code-simplifier plugin

**Required Plugin:** `code-simplifier:code-simplifier` (from claude-plugins-official)

**Actions:**

1. Mark Phase 7 as `in_progress`
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

**Transition:** Mark Phase 7 complete, advance to Phase 8

## Phase 8: Final Review (Decision Point)

**Purpose:** Thorough review that determines whether to loop back to Phase 1 or proceed to completion.

**Required Tool:**

- Full mode: `mcp__codex__codex`
- Lite mode: `superpowers:requesting-code-review`

**Actions:**

1. Mark Phase 8 as `in_progress`
2. Check current iteration count against `maxIterations`
3. Run review based on mode:

### Full Mode (mcp\_\_codex\_\_codex)

Invoke `mcp__codex__codex` with review prompt:

```
Iteration {N}/{max} final review for merge readiness. Run these commands first:
1. make lint
2. make test

Focus on:
- Documentation accuracy
- Edge cases and error handling
- Test coverage completeness
- Code quality and maintainability
- Merge readiness

Report findings with severity (HIGH/MEDIUM/LOW) and file:line references.
If you find NO issues, explicitly state: "No issues found."
```

### Lite Mode (superpowers:requesting-code-review)

Dispatch code-reviewer subagent per `superpowers:requesting-code-review`:

- WHAT_WAS_IMPLEMENTED: Full description of all changes
- PLAN_OR_REQUIREMENTS: Reference to plan file
- BASE_SHA and HEAD_SHA from git

4. **Evaluate review results:**

   **If ZERO issues found:**
   - Announce: "Iteration {N} review found no issues. Proceeding to completion."
   - Store `phase8Issues: []` in state
   - **Full mode:** Proceed to Phase 9
   - **Lite mode:** Skip to Completion

   **If ANY issues found (HIGH, MEDIUM, or LOW):**
   - Announce: "Iteration {N} found {count} issues. Fixing and starting new iteration."
   - Fix ALL issues
   - Re-run `make lint && make test`
   - Store issues in `phase8Issues` array in state
   - **If currentIteration < maxIterations:**
     - Increment `currentIteration`
     - Add new iteration entry to state
     - **Loop back to Phase 1**
   - **If currentIteration >= maxIterations:**
     - Announce: "Reached max iterations ({max}). Proceeding with {count} unresolved issues noted."
     - **Full mode:** Proceed to Phase 9
     - **Lite mode:** Skip to Completion

**Exit criteria:**

- Review completed
- Either: zero issues found, OR all issues fixed and looping, OR max iterations reached

**Transition:**

- Zero issues OR max iterations → Phase 9 (full) or Completion (lite)
- Issues found AND iterations remaining → Phase 1 (new iteration)

## Phase 9: Codex-High Final Validation (Full Mode Only)

**Purpose:** Final validation with OpenAI Codex high reasoning

**Required Tool:** `mcp__codex-high__codex`

**Note:** This phase is skipped in lite mode.

**Actions:**

1. Mark Phase 9 as `in_progress`
2. Invoke `mcp__codex-high__codex` with final validation prompt:

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
4. Re-run Codex-high if significant changes made

**Exit criteria:**

- Codex-high review completed
- No HIGH severity issues remaining

**Transition:** Mark Phase 9 complete, proceed to Completion

## Completion

After Phase 8 (lite mode) or Phase 9 (full mode):

1. Update state file to show workflow complete
2. Announce: "Iteration workflow complete after {N} iteration(s)!"
3. Summarize:
   - Total iterations run
   - Issues found and fixed per iteration
   - Final state (clean or with noted issues)
4. Suggest next steps (commit, create PR, etc.)
5. Optionally use `superpowers:finishing-a-development-branch` for merge prep

## Resuming Interrupted Iterations

If iteration was interrupted:

1. Read `.agents/iteration-state.json`
2. Identify:
   - `currentIteration`: Which iteration we're on
   - `currentPhase`: Which phase within that iteration
   - `mode`: Full or lite
3. Announce: "Resuming iteration {N} at Phase {P}: <phase-name>"
4. Continue from where stopped

## Red Flags - STOP

**Never:**

- Skip phases (all 8 phases per iteration are mandatory)
- Advance without meeting exit criteria
- Ignore issues from Phase 8 review (must fix or note if at max iterations)
- Skip test runs
- Skip TDD (write tests after implementation)
- Dispatch parallel implementation subagents (conflicts)
- Exceed maxIterations without proceeding to completion

**If blocked:**

- Record blocker in state file notes
- Ask user for guidance
- Do not proceed until resolved
