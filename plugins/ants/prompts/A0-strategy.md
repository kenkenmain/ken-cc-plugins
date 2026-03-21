# [PHASE A0 — SUB-PHASE] Strategy Evaluation

Dispatch the **strategist** agent after exploration completes to evaluate implementation approaches before the architect plans.

## Agent

- **strategist** (`ants:strategist`) x 1 — pre-plan approach evaluator

The strategist runs on the `sonnet` model in `plan` mode. It reads the exploration report and brainstorms 2-3 approaches with trade-off analysis.

## Dispatch Timing

The strategist runs as a **sub-phase within A0**, after the explore-aggregator writes `A0-explore.md` and before A0 is marked complete. This is NOT a separate phase — it uses marker files (`.strategist.dispatched` / `.strategist.done`) within the A0 dispatch flow.

## Strategist Dispatch Template

```
You are the colony's strategist. Evaluate implementation approaches before the architect plans.

Task: {{TASK}}

Read the exploration report at .agents/tmp/phases/A0-explore.md for codebase context.

{{PREVIOUS_LOOP_CONTEXT}}

Brainstorm 2-3 distinct implementation approaches. For each approach:
1. Name and description (2-4 sentences)
2. Pros and cons (3-5 each)
3. Key assumptions

Evaluate all approaches on 5 dimensions (1-5 scale):
- Complexity, Risk, Reversibility, Maintainability, Time-to-implement

Select the best approach with clear justification.

Output file: .agents/tmp/phases/A0-strategy.md

After writing A0-strategy.md, use SendMessage to notify the team.
Write the file FIRST, then send the message. Files are the source of truth.

SendMessage recipient: "team"
Message: "Strategy evaluation complete. Recommended approach: [Name]. Strategy at .agents/tmp/phases/A0-strategy.md"
```

## Output Path

- `.agents/tmp/phases/A0-strategy.md` — strategy analysis with approaches, trade-off matrix, and recommendation

## Gate

No hard gate. Strategy output is **supplementary, not required**. If the strategist fails or times out, A0 is marked complete without a strategy file, and the architect proceeds using only the exploration report. The architect already brainstorms approaches as part of its process — the strategist front-loads this work for higher quality.

## Input

The strategist reads:
- `.agents/tmp/phases/A0-explore.md` — the consolidated exploration report (required)
- Previous loop context (injected by dispatch prompt if loop > 1)

## Expected Output Structure

The strategist writes `A0-strategy.md` with:

```markdown
# Implementation Strategy

## Problem Analysis
[2-3 sentences: what needs to be built and key constraints]

## Approaches

### Approach 1: [Name]
**Description:** [2-4 sentences]
**Pros:** [bullet list]
**Cons:** [bullet list]
**Key assumption:** [what must be true]

### Approach 2: [Name]
[same structure]

### Approach 3: [Name] (if applicable)
[same structure]

## Trade-off Matrix

| Dimension | Approach 1 | Approach 2 | Approach 3 |
|-----------|-----------|-----------|-----------|
| Complexity | X/5 | X/5 | X/5 |
| Risk | X/5 | X/5 | X/5 |
| Reversibility | X/5 | X/5 | X/5 |
| Maintainability | X/5 | X/5 | X/5 |
| Time-to-implement | X/5 | X/5 | X/5 |
| **Total** | **XX/25** | **XX/25** | **XX/25** |

## Recommendation

**Selected approach:** [Name]
**Justification:** [3-5 sentences]
**Risks and mitigations:** [bullet list]
**Guidance for architect:** [bullet list]
```

## Next Phase

After the strategist completes (or times out), A0 is marked complete and the workflow advances to A1 (Architect Plan). The architect reads both `A0-explore.md` and `A0-strategy.md` (if present) as input.
