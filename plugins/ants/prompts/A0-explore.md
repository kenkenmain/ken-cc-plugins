# [PHASE A0] Colony Exploration

Dispatch **forager** and **cartographer** agents in parallel to gather codebase context before planning begins.

## Agents

- **forager** (`ants:forager`) x N -- breadth-first codebase scouts, each assigned a focused query
- **cartographer** (`ants:cartographer`) x 1 -- depth-first architecture tracer
- **explore-aggregator** (`ants:explore-aggregator`) x 1 -- synthesizes forager + cartographer results into A0-explore.md

Foragers run on the `haiku` model. Cartographer and explore-aggregator run on `sonnet`. The explore-aggregator reads forager/cartographer temp files (guaranteed to exist via task dependency chains) and synthesizes the final report, offloading queen context overhead.

## Coordination Model (v0.6 -- File-Based + blockedBy)

A0 uses **file-based coordination** with task dependency chains (blockedBy fields in TaskCreate). No inter-agent messaging is needed.

1. **Foragers** write their results to individual temp files: `.agents/tmp/phases/A0-explore.forager.N.tmp`
2. **Cartographer** writes its architecture trace to: `.agents/tmp/phases/A0-explore.cartographer.tmp`
3. **Explore-aggregator** task is created with `blockedBy` referencing all forager task IDs and the cartographer task ID. This ensures the explore-aggregator does not start until all predecessor tasks have completed and their temp files exist.
4. **Explore-aggregator** reads all temp files (using Glob to discover `.agents/tmp/phases/A0-explore.forager.*.tmp`) and writes the consolidated report to: `.agents/tmp/phases/A0-explore.md`
5. The **TaskCompleted hook** validates the explore-aggregator's output (A0-explore.md exists) and advances `currentPhase` to A1.

No confirmation messages are needed -- task completion is detected by the TaskCompleted hook, which validates output files and advances workflow state.

## Dispatch Timing

A0 runs at workflow start, **before** any planning phase. The command creates all A0 tasks (foragers, cartographer, explore-aggregator) as part of the initial task graph with appropriate blockedBy chains. The TeammateIdle hook assigns ready tasks to idle teammates. The command waits for the TaskCompleted hook to advance the phase to A1.

## Process

1. **Determine forager queries** based on the task description (typically 2-4 foragers)
2. **Create task graph with blockedBy dependencies:**
   - Each forager task has no A0-internal dependencies (they run in parallel)
   - The cartographer task has no A0-internal dependencies (runs in parallel with foragers)
   - The explore-aggregator task is blockedBy all forager tasks + cartographer task
3. Each explorer reads the codebase through its lens and writes findings to its assigned temp file
4. **Explore-aggregator reads all temp files** and synthesizes them into `.agents/tmp/phases/A0-explore.md`
5. **TaskCompleted hook validates** A0-explore.md exists and advances currentPhase to A1
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

Write your structured findings to the temp file. Your work is complete when the temp file
is written. The TaskCompleted hook validates your output and advances the workflow.
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

Write your architecture trace to the temp file. Your work is complete when the temp file
is written. The TaskCompleted hook validates your output and advances the workflow.
```

## Explore-Aggregator Dispatch Template

```
You are the explore-aggregator. Read findings from all forager and cartographer temp files
and synthesize them into the canonical exploration report.

Task: {{TASK}}

Input files (guaranteed to exist via task dependency chain):
- .agents/tmp/phases/A0-explore.forager.*.tmp (use Glob to discover all forager files)
- .agents/tmp/phases/A0-explore.cartographer.tmp

Read all temp files, then synthesize into a unified report.

Output file: .agents/tmp/phases/A0-explore.md

Your work is complete when A0-explore.md is written. The TaskCompleted hook validates
this file and advances the workflow. No separate confirmation message is needed.
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

No hard gate. Explorer output is **supplementary, not required**. If any forager fails or times out, the workflow continues without that section's intelligence. The next phase proceeds regardless -- the colony adapts.

## Next Phase

Proceed to the planning phase with the consolidated exploration context from `.agents/tmp/phases/A0-explore.md`.
