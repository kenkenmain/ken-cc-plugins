# [PHASE A0] Colony Exploration

Dispatch **forager** and **cartographer** agents in parallel to gather codebase context before planning begins.

## Agents

- **forager** (`ants:forager`) x N — breadth-first codebase scouts, each assigned a focused query
- **cartographer** (`ants:cartographer`) x 1 — depth-first architecture tracer
- **explore-aggregator** (`ants:explore-aggregator`) x 1 — synthesizes forager + cartographer results into A0-explore.md

Foragers run on the `haiku` model. Cartographer and explore-aggregator run on `sonnet`. The explore-aggregator reads forager/cartographer temp files via task dependency chains (blockedBy) and synthesizes the final report, offloading orchestrator context overhead.

## Dispatch Timing

A0 runs at workflow start, **before** any planning phase. All foragers, the cartographer, and the explore-aggregator are dispatched simultaneously via task dependency chains. Foragers and cartographer write their results to temp files. The explore-aggregator task is blockedBy all foragers and the cartographer, so it starts only after all temp files are written.

## Process

1. **Determine forager queries** based on the task description (typically 2-4 foragers)
2. **Dispatch all foragers + cartographer + explore-aggregator via task dependency chains:**
   - Each forager gets a focused query (files, tests, patterns, dependencies, etc.)
   - The cartographer gets the full task for deep architecture tracing
   - The explore-aggregator is blockedBy all foragers + cartographer (starts only after all temp files are written)
3. Each explorer reads the codebase through its lens and writes findings to a dedicated temp file. After writing the temp file, its work is complete.
4. **Explore-aggregator reads** all forager + cartographer temp files and synthesizes into `.agents/tmp/phases/A0-explore.md`
5. **Explore-aggregator notifies** the team via SendMessage that exploration is complete
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

After writing your temp file, your work is complete. The explore-aggregator reads your
temp file via task dependency chains (blockedBy). No SendMessage is needed.
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

After writing your temp file, your work is complete. The explore-aggregator reads your
temp file via task dependency chains (blockedBy). No SendMessage is needed.
```

## Explore-Aggregator Dispatch Template

```
You are the explore-aggregator. Read findings from all forager and cartographer temp files
and synthesize them into the canonical exploration report.

Task: {{TASK}}

Expected source files (written by predecessor tasks via blockedBy dependency chain):
- .agents/tmp/phases/A0-explore.forager.{1..N}.tmp — forager results
- .agents/tmp/phases/A0-explore.cartographer.tmp — cartographer architecture trace

Use Glob to discover all forager files: .agents/tmp/phases/A0-explore.forager.*.tmp

Read all temp files, then synthesize into a unified report.

Output file: .agents/tmp/phases/A0-explore.md

After writing A0-explore.md, use SendMessage to notify the team that exploration is
complete. Write the file FIRST, then send the message. Files are the source of truth.

SendMessage recipient: "team"
Message: "A0 exploration complete. Report at .agents/tmp/phases/A0-explore.md"
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
