# Phase 1: Brainstorm [PHASE 1]

## Subagent Config

- **Type:** dispatch (Explore + general-purpose parallel agents)
- **Input:** task description (from `state.json .task`)
- **Output:** `.agents/tmp/iterate/phases/1-brainstorm.md`

## Instructions

Explore the problem space, generate ideas, and clarify requirements using parallel research agents.

### Process

1. Read the task description from the iteration state
2. **Launch parallel research subagents** to explore independent domains:
   - Research existing code patterns and architecture
   - Explore problem domain and requirements
   - Investigate test strategy and coverage requirements
   - Analyze similar implementations in codebase
   - Research external libraries/APIs needed
   - Explore edge cases and error scenarios
3. Aggregate findings from all parallel agents
4. Analyze patterns, existing code, and constraints
5. Determine 2-3 approaches with trade-offs
6. Select recommended approach with rationale
7. Document test strategy requirements:
   - What test frameworks/tools are available?
   - What testing patterns does the codebase use?
   - What edge cases need coverage?
8. Write decisions to output file

### Parallel Agent Dispatch

Identify independent research areas for the task and dispatch one subagent per domain. There is no limit on the number of parallel agents. Each agent should:

- Focus on a single research area
- Report findings in structured format
- Include relevant file paths and code snippets discovered

### Output Format

Write to `.agents/tmp/iterate/phases/1-brainstorm.md`:

```markdown
# Brainstorm Results

## Task
{task description}

## Research Findings

### Codebase Analysis
{findings from codebase exploration agents}

### Problem Domain
{requirements, constraints, domain knowledge}

### Existing Patterns
{relevant patterns found in codebase}

## Approaches Considered

### Approach 1: {name}
- **Description:** ...
- **Pros:** ...
- **Cons:** ...
- **Complexity:** easy/medium/hard

### Approach 2: {name}
- **Description:** ...
- **Pros:** ...
- **Cons:** ...
- **Complexity:** easy/medium/hard

### Approach 3: {name} (optional)
...

## Selected Approach
{chosen approach with rationale}

## Test Strategy Requirements
- **Frameworks:** {available test frameworks}
- **Patterns:** {existing test patterns in codebase}
- **Edge Cases:** {identified edge cases needing coverage}

## Implementation Areas
{list of distinct areas to plan in Phase 2}

## Design Decisions
{key decisions made and why}
```
