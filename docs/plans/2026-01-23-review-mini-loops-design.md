# Review Mini-Loops Design

**Date:** 2026-01-23

**Goal:** Add configurable mini-loop behavior to review phases so each review stage can fix issues and re-review until clean, with configurable failure thresholds and behaviors.

## Configuration Schema (Version 2)

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
        "3": {
            "tool": "mcp__codex__codex",
            "onFailure": "restart",
            "failOnSeverity": "LOW",
            "maxRetries": 10,
            "parallelFixes": true
        },
        "4": { "model": "inherit", "parallel": false },
        "5": {
            "model": "inherit",
            "onFailure": "mini-loop",
            "failOnSeverity": "LOW",
            "maxRetries": 10,
            "parallelFixes": true
        },
        "6": {
            "model": null,
            "onFailure": "restart",
            "maxRetries": 10
        },
        "7": { "model": "inherit", "parallel": false },
        "8": {
            "tool": "mcp__codex__codex",
            "onFailure": "restart",
            "failOnSeverity": "LOW",
            "maxRetries": 10,
            "parallelFixes": true
        },
        "9": { "tool": "mcp__codex-high__codex" }
    }
}
```

## Config Field Definitions

### `onFailure`

What happens when review finds issues at or above the severity threshold.

| Value         | Behavior                                       |
| ------------- | ---------------------------------------------- |
| `"mini-loop"` | Fix issues within phase, re-review until clean |
| `"restart"`   | Go back to Phase 1, start new iteration        |
| `"proceed"`   | Note issues, continue to next phase            |
| `"stop"`      | Halt workflow entirely                         |

### `failOnSeverity`

Minimum severity that triggers failure. Threshold-based (includes all severities at or above).

| Value      | Fails on                      |
| ---------- | ----------------------------- |
| `"LOW"`    | HIGH, MEDIUM, LOW (any issue) |
| `"MEDIUM"` | HIGH, MEDIUM                  |
| `"HIGH"`   | HIGH only                     |
| `"NONE"`   | Never fails                   |

### `maxRetries`

Maximum retry attempts for mini-loop. Default: 10.

### `onMaxRetries`

What happens when maxRetries is exceeded.

| Value       | Behavior                                |
| ----------- | --------------------------------------- |
| `"stop"`    | Halt workflow, report failure (default) |
| `"ask"`     | Prompt user to decide                   |
| `"restart"` | Go back to Phase 1                      |
| `"proceed"` | Continue with issues noted              |

### `parallelFixes`

Enable parallel agents for fixing independent issues. Default: true.

## Phase Defaults

| Phase | Name         | onFailure | failOnSeverity | maxRetries |
| ----- | ------------ | --------- | -------------- | ---------- |
| 3     | Plan Review  | restart   | LOW            | 10         |
| 5     | Code Review  | mini-loop | LOW            | 10         |
| 6     | Test         | restart   | N/A            | 10         |
| 8     | Final Review | restart   | LOW            | 10         |

## State Schema (Version 4)

```json
{
    "version": 4,
    "task": "<description>",
    "mode": "full",
    "maxIterations": 10,
    "currentIteration": 1,
    "currentPhase": 3,
    "startedAt": "ISO timestamp",
    "iterations": [
        {
            "iteration": 1,
            "startedAt": "ISO timestamp",
            "phases": {
                "1": { "status": "completed" },
                "2": { "status": "completed" },
                "3": {
                    "status": "in_progress",
                    "retryCount": 2,
                    "lastIssues": [
                        {
                            "severity": "MEDIUM",
                            "message": "...",
                            "location": "file:line"
                        }
                    ]
                },
                "4": { "status": "pending" },
                "5": {
                    "status": "pending",
                    "retryCount": 0,
                    "lastIssues": []
                },
                "6": { "status": "pending", "retryCount": 0 },
                "7": { "status": "pending" },
                "8": {
                    "status": "pending",
                    "retryCount": 0,
                    "lastIssues": []
                }
            }
        }
    ],
    "phase9": { "status": "pending" }
}
```

## Mini-Loop Flow

```
1. Run review (Codex or Claude)
           ↓
2. Parse issues by severity
           ↓
3. Filter by failOnSeverity threshold
           ↓
   ┌───────┴───────┐
   │ No failing    │
   │ issues?       │→ PASS: Continue to next phase
   └───────────────┘
           ↓
   ┌───────┴───────┐
   │ Check         │
   │ onFailure     │
   └───────┬───────┘
     ↓     ↓     ↓     ↓
 restart mini  proceed stop
     ↓   loop    ↓      ↓
  Phase   ↓    Next   Halt
    1     ↓    phase  workflow
           ↓
4. Check maxRetries
   → If exceeded: trigger onMaxRetries
           ↓
5. Plan fixes for each issue
   → Create fix plan per issue
   → Group independent fixes
           ↓
6. Execute fixes
   → Parallel if parallelFixes=true
   → Ask user if stuck
           ↓
7. Increment retryCount, update lastIssues
           ↓
8. Loop back to step 1 (re-review)
```

## Files to Modify

| File                                 | Changes                                              |
| ------------------------------------ | ---------------------------------------------------- |
| `skills/configuration/SKILL.md`      | Add new config fields, validation, merge logic       |
| `skills/iteration-workflow/SKILL.md` | Add mini-loop flow to phases 3, 5, 6, 8              |
| `commands/configure.md`              | Add interactive questions for review settings        |
| `AGENTS.md`                          | Update state schema, config docs, phase descriptions |
| `.claude-plugin/plugin.json`         | Bump version                                         |

## Interactive Configure Updates

New questions for review phases:

```
1. "What should happen when issues are found?"
   - Restart iteration (go back to Phase 1)
   - Mini-loop (fix and re-review within phase)
   - Proceed (note issues, continue anyway)
   - Stop (halt workflow)

2. "Minimum severity that causes failure?"
   - LOW (any issue fails) [default]
   - MEDIUM (MEDIUM and HIGH fail)
   - HIGH (only HIGH fails)
   - NONE (never fail)

3. "Enable parallel agents for fixing issues?"
   - Yes (recommended)
   - No

4. "Retry limit for mini-loop?"
   - 10 retries (default)
   - 5 retries
   - 3 retries
   - No limit
   - Custom

5. "What happens when retry limit is reached?"
   - Stop workflow (default)
   - Ask me what to do
   - Restart iteration
   - Proceed with issues noted
```
