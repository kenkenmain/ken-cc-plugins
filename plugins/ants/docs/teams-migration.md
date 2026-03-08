# Agent Teams — Architecture Reference

> **Status: IMPLEMENTED** — v0.3.0 uses Agent Teams delegate mode exclusively. This document is now an architecture reference.

## Overview

Ants v0.3 replaced the Ralph Loop pattern with Agent Teams delegate mode. The migration was completed as a full rewrite:

- **Ralph Loop removed** — Stop hook no longer re-injects prompts. SubagentStop is a no-op.
- **Agent Teams hooks** — TeammateIdle assigns tasks, TaskCompleted validates output.
- **Auto-enable** — The swarm command sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` automatically.
- **State schema v3** — `teamName` field added, `dispatchMode` and `agentTeamsAvailable` removed.

## Architecture

```
/ants:swarm "add auth module"
         ↓
swarm.md command:
  1. Auto-enable CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  2. Create team: Teammate({ operation: "spawnTeam", team_name: "ants-<slug>" })
  3. Create phase tasks via TaskCreate with dependency chains:
     A0 (no deps) → A1 → A2 → A3 → A4 → A5
  4. Spawn 3-5 teammates
  5. Lead enters delegate mode (coordination-only)
         ↓
TeammateIdle hook (on-teammate-idle.sh):
  - Teammate goes idle
  - Hook finds next ready task from state.json
  - Returns exit 2 with task prompt → keeps teammate working
         ↓
TaskCompleted hook (on-task-completed.sh):
  - Teammate marks task complete
  - Hook validates output (quality gate):
    - Output file exists + valid JSON
    - Stage gates met
    - Circuit breaker checks
  - Exit 0 = accept | Exit 2 = reject with feedback
  - On A1 complete: dynamically add A3 worker/sentinel/arbiter sub-tasks
  - On A4 verdict: handle ship (→A5) or loop (→A1 with new loop)
```

## Key Files

| File | Purpose |
|------|---------|
| `hooks/on-teammate-idle.sh` | TeammateIdle handler — task router |
| `hooks/on-task-completed.sh` | TaskCompleted handler — quality gate |
| `hooks/on-stop.sh` | Simplified — allows lead to stop freely |
| `hooks/on-subagent-stop.sh` | No-op (exit 0) |
| `hooks/lib/teams.sh` | Team creation, task assignment, prompt generation |
| `commands/swarm.md` | Team-native initialization flow |

## Removed Files (from v0.2)

| File | Reason |
|------|--------|
| `hooks/on-teams-stub.sh` | Replaced by real TeammateIdle/TaskCompleted handlers |
| `hooks/on-task-gate.sh` | Task tool dispatch no longer used — teammates are spawned via team API |
