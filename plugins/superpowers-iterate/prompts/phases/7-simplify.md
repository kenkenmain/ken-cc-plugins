# Phase 7: Simplify [PHASE 7]

## Subagent Config

- **Type:** subagent (code-simplifier:code-simplifier)
- **Input:** `.agents/tmp/iterate/phases/4-tasks.json`
- **Output:** `.agents/tmp/iterate/phases/7-simplify.md`

## Instructions

Review implemented code for simplification opportunities using the code-simplifier agent.

### Process

1. Read `.agents/tmp/iterate/phases/4-tasks.json` to get list of modified files
2. Dispatch `code-simplifier:code-simplifier` agent via Task tool:
   ```
   Task(
     description: "Simplify modified code from this iteration",
     prompt: "Review and simplify code modified in this iteration. Focus on clarity and maintainability while preserving functionality.",
     subagent_type: "code-simplifier:code-simplifier"
   )
   ```
3. Review each modified file for:
   - Unnecessary complexity
   - Duplicate code
   - Over-engineering
   - Dead code or unused imports
   - Missing simplifications
   - Overly verbose patterns that can be condensed
4. Apply appropriate simplifications directly
5. Re-run `make lint && make test` to verify no breakage
6. Write summary to output file

### Simplification Criteria

| Check                    | Action                                         |
| ------------------------ | ---------------------------------------------- |
| Duplicate code           | Extract shared function/module                 |
| Over-engineered patterns | Replace with simpler alternative               |
| Dead code                | Remove                                         |
| Verbose conditionals     | Simplify with early returns or ternaries       |
| Unused imports           | Remove                                         |
| Complex nesting          | Flatten with guard clauses                     |

### Output Format

Write to `.agents/tmp/iterate/phases/7-simplify.md`:

```markdown
# Simplification Report

## Files Reviewed
- {count} files from Phase 4 implementation

## Changes Made
- **{file path}**: {description of simplification}
- **{file path}**: {description of simplification}

## No Changes Needed
- **{file path}**: already clean

## Tests After Simplification
- Lint: PASS/FAIL
- Tests: PASS/FAIL

## Summary
{brief summary of simplification pass}
```
