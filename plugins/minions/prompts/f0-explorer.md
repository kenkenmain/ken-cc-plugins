# Phase F0: Pre-Scout Exploration

Dispatch **explorer** agents in parallel to gather codebase context before the scout plans.

## Agents

- **explorer-files** (`minions:explorer-files`) — file inventory: project structure, key files, entry points
- **explorer-architecture** (`minions:explorer-architecture`) — architecture: patterns, layers, dependencies, module boundaries
- **explorer-tests** (`minions:explorer-tests`) — test landscape: frameworks, coverage areas, test conventions
- **explorer-patterns** (`minions:explorer-patterns`) — code patterns: naming conventions, error handling, common idioms

All 4 run in parallel on the `haiku` model.

## Dispatch Timing

F0 runs during launch initialization, **before** F1 (Scout) is dispatched. The orchestrator kicks off all 4 explorers immediately on workflow start while other initialization proceeds.

## Process

1. Dispatch all 4 explorer agents simultaneously with the task description
2. Each agent reads the codebase using its specialization lens
3. Each returns its findings as structured markdown in its final response
4. The orchestrator captures each agent's output and consolidates into a single context document
5. The consolidated context is passed to F1 (Scout) as supplementary input

## Prompt Template (per explorer)

```
You are {{EXPLORER_NAME}}. Explore the codebase to gather context for the upcoming task.

Task: {{TASK}}

Your specialization: {{SPECIALIZATION}}

Read the codebase and return a concise summary relevant to the task.
Focus only on what a planner would need to know.
Return your findings as structured markdown in your final response.
```

### Explorer Specializations

| Agent | `{{EXPLORER_NAME}}` | `{{NAME}}` | `{{SPECIALIZATION}}` |
| --- | --- | --- | --- |
| explorer-files | explorer-files | files | Map the project structure. Identify key files, entry points, and directories relevant to the task. |
| explorer-architecture | explorer-architecture | architecture | Identify architectural patterns, module boundaries, dependency relationships, and layering relevant to the task. |
| explorer-tests | explorer-tests | tests | Survey the test landscape. Identify test frameworks, existing test files, coverage patterns, and testing conventions. |
| explorer-patterns | explorer-patterns | patterns | Identify code patterns, naming conventions, error handling idioms, and style conventions used in the codebase. |

## Output Capture

Each explorer returns its findings as text. The orchestrator captures the output from each Task tool response. Explorer agents do not write files (they have no Write or Bash tools).

## Consolidation

After all 4 complete, the orchestrator writes the consolidated output to:

`.agents/tmp/phases/f0-explorer-context.md`

```markdown
# Explorer Context

## File Structure
{output captured from explorer-files agent response}

## Architecture
{output captured from explorer-architecture agent response}

## Tests
{output captured from explorer-tests agent response}

## Patterns
{output captured from explorer-patterns agent response}
```

This file is passed to the F1 scout as additional context.

## Gate

No hard gate. Explorer output is **supplementary, not required**. If any explorer fails or times out, the workflow continues without that section. F1 (Scout) proceeds regardless.

Next phase: F1 (Scout)
