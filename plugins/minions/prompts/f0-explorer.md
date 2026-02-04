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
3. Each writes its findings to a dedicated output file using the Write tool
4. After all 4 complete, the orchestrator consolidates output files into a single context document
5. The consolidated context is passed to F1 (Scout) as supplementary input

## Prompt Template (per explorer)

```
You are {{EXPLORER_NAME}}. Explore the codebase to gather context for the upcoming task.

Task: {{TASK}}

Your specialization: {{SPECIALIZATION}}

Read the codebase and write a concise summary relevant to the task.
Focus only on what a planner would need to know.

Write your output to: .agents/tmp/phases/f0-explorer.{{NAME}}.tmp
```

### Explorer Specializations

| Agent | `{{EXPLORER_NAME}}` | `{{NAME}}` | `{{SPECIALIZATION}}` |
| --- | --- | --- | --- |
| explorer-files | explorer-files | files | Map the project structure. Identify key files, entry points, and directories relevant to the task. |
| explorer-architecture | explorer-architecture | architecture | Identify architectural patterns, module boundaries, dependency relationships, and layering relevant to the task. |
| explorer-tests | explorer-tests | tests | Survey the test landscape. Identify test frameworks, existing test files, coverage patterns, and testing conventions. |
| explorer-patterns | explorer-patterns | patterns | Identify code patterns, naming conventions, error handling idioms, and style conventions used in the codebase. |

## Output Paths

Each explorer writes its findings to a dedicated output file using the Write tool:

- `.agents/tmp/phases/f0-explorer.files.tmp`
- `.agents/tmp/phases/f0-explorer.architecture.tmp`
- `.agents/tmp/phases/f0-explorer.tests.tmp`
- `.agents/tmp/phases/f0-explorer.patterns.tmp`

## Consolidation

After all 4 complete, the orchestrator writes the consolidated output to:

`.agents/tmp/phases/f0-explorer-context.md`

```markdown
# Explorer Context

## File Structure
{content from .agents/tmp/phases/f0-explorer.files.tmp}

## Architecture
{content from .agents/tmp/phases/f0-explorer.architecture.tmp}

## Tests
{content from .agents/tmp/phases/f0-explorer.tests.tmp}

## Patterns
{content from .agents/tmp/phases/f0-explorer.patterns.tmp}
```

This file is passed to the F1 scout as additional context.

## Gate

No hard gate. Explorer output is **supplementary, not required**. If any explorer fails or times out, the workflow continues without that section. F1 (Scout) proceeds regardless.

Next phase: F1 (Scout)
