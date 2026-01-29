---
name: plan-dispatcher
description: Dispatch parallel Plan agents to create implementation plans
---

# Plan Dispatcher

Dispatch 1-10 parallel Plan agents to create detailed implementation plans.

## When to Use

Phase 1.2 of workflow, after brainstorming determines approach.

## Modes

- `parallel` (default): Multiple Plan agents, each handles an aspect
- `single`: One unified plan (for simpler tasks)

## Plan Area Identification

Based on brainstorm output, identify distinct plan areas:

- Database/schema changes
- API routes/controllers
- Frontend components
- Business logic
- Tests
- Configuration
- Documentation

## Dispatch Process

1. Read brainstorm output from `.agents/tmp/phases/1.1-brainstorm.md`
2. Identify plan areas → determine agent count (1-10)
3. Generate plan prompts (one per area)
4. Dispatch all Plan agents in parallel:

```
Task(
  description: "Plan: {area}",
  prompt: "Create detailed implementation plan for {area}. Context: {brainstorm summary}",
  subagent_type: "Plan",
  model: config.stages.PLAN.planning.model
)
```

5. Wait for all agents to complete
6. Merge results to `.agents/tmp/phases/1.2-plan.md`

## Output Format

Write merged plan to `.agents/tmp/phases/1.2-plan.md`:

```markdown
# Implementation Plan

## Overview

{merged summary}

## Tasks

### Task 1: {name}

- **Area:** {area}
- **Files:** {files to create/modify}
- **Dependencies:** {task dependencies}
- **Complexity:** easy|medium|hard

### Task 2: {name}

...

## Dependency Graph

{task dependency order for wave-based execution}
```

## Update State

After completion:

- Set `stages.PLAN.phases["1.2"].status: "completed"`
- Set `stages.PLAN.phases["1.2"].agentCount: {count}`
- Set `files.plan: ".agents/tmp/phases/1.2-plan.md"`

## Error Handling

If any Plan agent fails:

1. Record partial results from successful agents
2. Log failed areas
3. Ask user if they want to continue with partial plan or retry
