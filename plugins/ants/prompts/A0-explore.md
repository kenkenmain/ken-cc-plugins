# [PHASE A0] Colony Exploration

Dispatch **forager** and **cartographer** agents in parallel to gather codebase context before planning begins.

## Agents

- **forager** (`ants:forager`) x N — breadth-first codebase scouts, each assigned a focused query
- **cartographer** (`ants:cartographer`) x 1 — depth-first architecture tracer
- **explore-aggregator** (`ants:explore-aggregator`) x 1 — synthesizes forager + cartographer results into A0-explore.md

Foragers run on the `haiku` model. Cartographer and explore-aggregator run on `sonnet`. The explore-aggregator receives forager/cartographer results via SendMessage and synthesizes the final report, offloading queen context overhead.

## Dispatch Timing

A0 runs at workflow start, **before** any planning phase. The queen dispatches all foragers, the cartographer, and the explore-aggregator simultaneously. Foragers and cartographer send their results to the explore-aggregator (not the queen). The queen waits only for the explore-aggregator's confirmation.

## Process

1. **Determine forager queries** based on the task description (typically 2-4 foragers)
2. **Dispatch all foragers + cartographer + explore-aggregator in parallel:**
   - Each forager gets a focused query (files, tests, patterns, dependencies, etc.)
   - Foragers send their results to the explore-aggregator (recipient: "explore-aggregator")
   - The cartographer gets the full task for deep architecture tracing
   - Cartographer sends results to the explore-aggregator (recipient: "explore-aggregator")
   - The explore-aggregator waits for results from all foragers + cartographer
3. Each explorer reads the codebase through its lens and writes findings to a temp file and sends via SendMessage to explore-aggregator
4. **Explore-aggregator synthesizes** all results into `.agents/tmp/phases/A0-explore.md`
5. **Explore-aggregator confirms** to queen via SendMessage (recipient: "queen")
6. The consolidated report is passed to the next phase as supplementary context

## Forager Dispatch Template

For each forager (1 through N):

```
You are the colony's forager. Scout the codebase to gather intelligence for the upcoming task.

Task: {{TASK}}

Your assigned query: {{QUERY}}

Read the codebase and write a concise summary relevant to the task.
Focus only on what a planner would need to know.

Temp output file: .agents/tmp/phases/A0-explore.forager.{{N}}.tmp

After writing the temp file, send your findings to the explore-aggregator via SendMessage
(recipient: "explore-aggregator") with a summary of your findings.
```

### Suggested Forager Queries

| Forager | `{{QUERY}}` |
| --- | --- |
| forager.1 | Map the project structure. Identify key files, entry points, and directories relevant to the task. |
| forager.2 | Survey the test landscape. Identify test frameworks, existing test files, coverage patterns, and testing conventions. |
| forager.3 | Identify code patterns, naming conventions, error handling idioms, and style conventions used in the codebase. |
| forager.4 | Find existing implementations related to the task. Look for utilities, helpers, and patterns that could be reused. |

Adjust the number of foragers based on task complexity: 2 for simple tasks, 4 for complex ones.

## Cartographer Dispatch Template

```
You are the colony's cartographer. Map the deep architecture of this codebase for the upcoming task.

Task: {{TASK}}

Trace execution paths, dependency graphs, and architectural layers.
Focus on how components connect and where the task will need to integrate.

Temp output file: .agents/tmp/phases/A0-explore.cartographer.tmp

After writing the temp file, send your architecture trace to the explore-aggregator via SendMessage
(recipient: "explore-aggregator") with a summary of your findings.
```

## Explore-Aggregator Dispatch Template

```
You are the explore-aggregator. Receive findings from all foragers and the cartographer
and synthesize them into the canonical exploration report.

Task: {{TASK}}

Expected sources:
- forager ×{{N}} — each will send their findings via SendMessage
- cartographer ×1 — will send their architecture trace via SendMessage

Wait for all results, then synthesize into a unified report.

Output file: .agents/tmp/phases/A0-explore.md

After writing the report, confirm to the queen via SendMessage (recipient: "queen")
with {status: "complete", outputPath: ".agents/tmp/phases/A0-explore.md", summary: "..."}
```

## Output Paths

Each agent writes its findings to a dedicated temp file:

- `.agents/tmp/phases/A0-explore.forager.1.tmp`
- `.agents/tmp/phases/A0-explore.forager.2.tmp`
- `.agents/tmp/phases/A0-explore.forager.3.tmp`
- `.agents/tmp/phases/A0-explore.forager.4.tmp`
- `.agents/tmp/phases/A0-explore.cartographer.tmp`

Final merged report:

- `.agents/tmp/phases/A0-explore.md`

## Gate

No hard gate. Explorer output is **supplementary, not required**. If any forager fails or times out, the workflow continues without that section's intelligence. The next phase proceeds regardless — the colony adapts.

## Next Phase

Proceed to the planning phase with the consolidated exploration context from `.agents/tmp/phases/A0-explore.md`.
