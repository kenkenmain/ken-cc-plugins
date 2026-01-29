---
name: complexity-scorer
description: Classify task complexity (easy/medium/hard) and assign appropriate model for execution
---

# Complexity Scorer

Analyze a task and classify its complexity to determine the appropriate model for execution.

## When to Use

Invoked by phase-executor before dispatching each task agent (dynamically at execution time).

## Input

Task context: description, target files, dependencies, instructions.

## Scoring Criteria

### Easy → sonnet

Single file, <50 LOC, no external dependencies, pure logic, no security/concurrency.

**Keywords:** utility, helper, constant, rename, simple, basic, update, tweak

**Examples:** utility function, constant update, variable rename, type annotations, typo fix

### Medium → opus

2-3 files, 50-200 LOC, internal dependencies, I/O operations, basic error handling.

**Keywords:** service, endpoint, handler, component, feature, integrate

**Examples:** API endpoint, service method, database query, form validation, UI component

### Hard → opus + codex-xhigh review

4+ files, >200 LOC, external dependencies, cross-layer logic, security/concurrency concerns, complex state.

**Keywords:** auth, security, payment, distributed, async, concurrent, migration, integration, system

**Examples:** authentication, payment integration, distributed cache, database migration, real-time sync

## Output

Return classification result:

```json
{
  "taskId": "task-1",
  "complexity": "easy" | "medium" | "hard",
  "model": "sonnet" | "opus",
  "needsCodexReview": false | true,
  "reasoning": "Brief explanation of classification"
}
```

**Note:** `needsCodexReview: true` only for hard tasks.

## Algorithm

Parse description → estimate scope → check keywords → evaluate dependencies → check concerns → classify → select model → return result with reasoning.

## Configuration Override

Respects config overrides for model assignments per complexity level.

## Edge Cases

- **Ambiguous:** Prefer higher complexity
- **Refactoring:** Large multi-file refactors = hard
- **Tests:** Match complexity of code tested
- **Documentation:** Easy unless system is complex
