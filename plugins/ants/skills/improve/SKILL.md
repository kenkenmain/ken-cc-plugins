---
name: improve
description: Iterative self-improvement pipeline -- review-fix loop with adversarial sentinels until all issues (info severity and above) are resolved or max iterations reached
---

# Improve Pipeline

Stateless iterative review-fix pipeline. Dispatches specialist sentinels (correctness, security, perf) in parallel, consolidates via review-arbiter, dispatches review-fixer to apply targeted fixes, then re-reviews. Loops until arbiter returns "clean" verdict (zero issues) or max iterations (5) reached. No state.json, no hooks, no Agent Teams -- follows the same stateless direct-dispatch model as the debug pipeline.

## Key Architecture

- **Stateless:** No `.agents/tmp/state.json` is created or read during improve
- **Direct dispatch:** The improve command spawns agents via Agent tool, reads their output files, and proceeds
- **No hooks:** Because no ants state.json exists, `check_ants_workflow()` in every hook returns false (exits 0 immediately), so all hooks pass through without interfering
- **Self-contained:** All output files live under `.agents/tmp/improve/`
- **Iterative:** Loops up to 5 iterations with early termination on clean verdict

## Pipeline

```
Phase I0  | REVIEW      | Adversarial Review     | 3x parallel sentinels + review-arbiter
Phase I1  | FIX         | Targeted Repair        | 1x review-fixer
[loop back to I0 if issues remain, up to 5 iterations]
Phase I2  | REPORT      | Summary                | Orchestrator displays results
```

### Pipeline Diagram

```
Iteration 1:
    I0 Review (3x parallel sentinels)
       / | \
correctness security perf
       \ | /
    review-arbiter (consolidate)
       |
    verdict?
     /      \
  clean    issues_found
    |         |
  I2 Report  I1 Fix (review-fixer)
              |
            [loop -> I0 Review, iteration 2]

...repeat up to 5 iterations...

I2 Report (summary of all iterations)
```

## Phase Details

### Phase I0: Adversarial Review (REVIEW)

Three specialist sentinels dispatched in parallel: `ants:sentinel-correctness`, `ants:sentinel-security`, `ants:sentinel-perf`. Each reviews all project files relevant to the task description.

After all three complete, `ants:review-arbiter` consolidates findings by cross-referencing, deduplicating, and resolving conflicts across all three sentinel reports. The arbiter reports all issues by default -- no severity threshold override is needed, as the arbiter naturally captures all severities including info.

- **Sentinel output:** `.agents/tmp/improve/iter-{N}/I0-review.sentinel-correctness.json`, `.agents/tmp/improve/iter-{N}/I0-review.sentinel-security.json`, `.agents/tmp/improve/iter-{N}/I0-review.sentinel-perf.json`
- **Arbiter output:** `.agents/tmp/improve/iter-{N}/I0-quality.json`
- **Verdict:** `clean` (zero issues) terminates loop; `issues_found` (any severity) triggers I1

### Phase I1: Targeted Repair (FIX)

Single `ants:review-fixer` agent reads issues from `.agents/tmp/improve/iter-{N}/I0-quality.json`. The dispatch prompt overrides the fixer's default state.json input -- since the improve pipeline is stateless, there is no state file. Instead, the fixer is pointed directly to the arbiter's quality file.

Fixer processes issues in severity order: critical first, then warning, then info. ALL severities are fixed (info and above) -- this is the key differentiator from the swarm pipeline.

- **Output:** `.agents/tmp/improve/iter-{N}/I1-fix.json`
- **After fix completes:** Loop back to I0 for re-review

### Phase I2: Summary Report (REPORT)

No agent dispatched -- the orchestrator reads all iteration outputs and displays a summary. Shows: iteration count, issues found per iteration, issues fixed per iteration, final verdict. Displayed directly to the user.

## Severity Policy

- Fix ALL issues: critical, warning, AND info
- This distinguishes improve from swarm (which only blocks on critical/warning)
- The improve pipeline is explicitly for thoroughness
- No configurable threshold -- always fixes everything

## Iteration Control

- **Max iterations:** 5 (hardcoded in command, not configurable)
- **Early termination:** Arbiter returns `clean` verdict (zero issues at any severity)
- **No circuit breaker:** Stateless pipeline uses simple iteration counter
- If 5 iterations cannot resolve all issues, the remaining issues likely need human judgment

## Phase-Agent Mapping

| Phase | Agent | Model | Reused | Count | Execution |
|-------|-------|-------|--------|-------|-----------|
| I0 | `ants:sentinel-correctness` | sonnet | Yes | 1 | Parallel |
| I0 | `ants:sentinel-security` | sonnet | Yes | 1 | Parallel |
| I0 | `ants:sentinel-perf` | sonnet | Yes | 1 | Parallel |
| I0 | `ants:review-arbiter` | sonnet | Yes | 1 | Sequential (after sentinels) |
| I1 | `ants:review-fixer` | inherit | Yes | 1 | Single |

**Total:** 5 reused agents, 0 new agents

## Output File Layout

All output files live under `.agents/tmp/improve/` with per-iteration subdirectories:

| Phase | File | Format | Description |
|-------|------|--------|-------------|
| I0 sentinel | `.agents/tmp/improve/iter-{N}/I0-review.sentinel-correctness.json` | JSON | Correctness findings |
| I0 sentinel | `.agents/tmp/improve/iter-{N}/I0-review.sentinel-security.json` | JSON | Security findings |
| I0 sentinel | `.agents/tmp/improve/iter-{N}/I0-review.sentinel-perf.json` | JSON | Performance findings |
| I0 arbiter | `.agents/tmp/improve/iter-{N}/I0-quality.json` | JSON | Consolidated verdict |
| I1 fixer | `.agents/tmp/improve/iter-{N}/I1-fix.json` | JSON | Fix report |

## Orchestration Model

The improve pipeline uses **stateless direct dispatch** -- the same model as the debug pipeline, fundamentally different from the swarm pipeline's hook-driven Agent Teams orchestration.

- **No state.json** -- iteration progress is tracked in the command's conversation context, not `.agents/tmp/state.json`. Because no state file exists, all ants hooks (`check_ants_workflow()`) exit 0 immediately as no-ops.
- **Direct dispatch** -- the command spawns agents via Agent tool, reads their output files, evaluates verdicts, and loops. No hooks, no Agent Teams.
- **Review-fixer edits freely** -- the edit gate imposes no restrictions since there is no active swarm state.
