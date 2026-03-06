# Agent Teams Migration Guide

This guide explains how to enable the Claude Code Agent Teams API in ants once the API stabilizes. All v0.2 interfaces are designed for a minimal dispatch-layer swap — the orchestration logic, state machine, and hook architecture remain unchanged.

---

## Prerequisites

Before activating Teams mode:

1. **Environment variable** — The Agent Teams API is gated behind a feature flag:
   ```bash
   export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
   ```
   Verify it is visible inside Claude Code sessions before proceeding.

2. **Terminal with split-pane support** — Teams spawns agents as visible peer sessions. You need one of:
   - **tmux** — `tmux new-session -s ants` and split panes with `Ctrl-b %` / `Ctrl-b "`
   - **iTerm2** — Shell Integration enabled; panes appear automatically when agents spawn

3. **ants v0.2+** — The dispatch abstraction (`lib/teams.sh`, `generate_swarm_prompt()` in `lib/swarm.sh`) and hook stubs (`on-teams-stub.sh`) must already be present. Check:
   ```bash
   ls plugins/ants/hooks/lib/teams.sh
   ls plugins/ants/hooks/on-teams-stub.sh
   ```

---

## What Changes

### Dispatch layer only

The only code that changes is how agents are launched. Everything else — the state machine, phase gates, wave barriers, loop-back logic, output file layout — stays identical.

| Layer | Before (subagent) | After (teams) |
|---|---|---|
| Worker launch | `Task(subagent_type=worker, ...)` | `TeammateTool(spawn, agent=worker, ...)` |
| Waiting for result | SubagentStop hook fires on completion | TaskCompleted hook fires with result payload |
| Idle worker reassignment | Stop hook re-injects orchestrator prompt | TeammateIdle hook assigns next ready task |
| Output collection | Worker writes to `.agents/tmp/phases/...` | Mailbox message + same file write |
| State advancement | SubagentStop updates state.json | TaskCompleted updates state.json |
| Edit ownership | on-edit-gate.sh checks file_owner in taskPool | Same — file_owner field is Teams-compatible |

Workers write output files to `.agents/tmp/phases/` in both modes. Mailbox messages carry a summary and status; the canonical output remains on disk.

---

## Concept Mapping

| Ants v0.2 (subagent mode) | Agent Teams equivalent | Notes |
|---|---|---|
| `Task` tool dispatch | `TeammateTool` spawn | Same agent definitions, different launcher |
| File-based output to `.agents/tmp/phases/` | Mailbox message + file output | File output is retained; mailbox adds async notification |
| Wave barrier (all workers done before sentinel) | Task dependency unblocking | Declare worker task IDs as dependencies of sentinel task |
| Stop hook prompt injection | TeammateIdle auto-assignment | Idle orchestrator picks up next queued task |
| SubagentStop validation + state advance | TaskCompleted quality gate | Same validation logic, different trigger event |
| on-edit-gate.sh `file_owner` in taskPool | Exclusive file ownership per teammate | Teams enforces this natively; gate becomes advisory |
| `dispatchMode: "subagent"` in state.json | `dispatchMode: "teams"` in state.json | Switched by `teams_detect()` at swarm init |
| `generate_swarm_prompt()` returns Task prompt | Returns TeammateTool call spec | Branching already in `lib/swarm.sh` |
| `on-teams-stub.sh` exits 0 (no-op) | `on-teams-stub.sh` runs real handler | Remove early-exit guard once API is stable |

---

## Step-by-Step Activation

### Step 1 — Set the environment variable

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

Add to your shell profile if you want it persistent. `lib/teams.sh::teams_detect()` reads this variable; it is also checked during swarm init to set `state.agentTeamsAvailable` and `state.dispatchMode`.

### Step 2 — Update `lib/teams.sh` dispatch mode

Open `plugins/ants/hooks/lib/teams.sh`. The `teams_get_dispatch_mode()` function currently returns `"subagent"` unconditionally as a safe default. Change the teams branch to return `"teams"`:

```bash
teams_get_dispatch_mode() {
  if teams_detect; then
    echo "teams"   # was: echo "subagent" (placeholder)
  else
    echo "subagent"
  fi
}
```

### Step 3 — Implement the Teams dispatch adapter in `lib/swarm.sh`

`generate_swarm_prompt()` already branches on `dispatchMode`. The `"teams"` branch currently logs a warning and falls back to subagent. Replace the placeholder with a real TeammateTool call spec:

```bash
# In generate_swarm_prompt():
"teams")
  # Return TeammateTool spawn spec instead of Task prompt
  build_teammate_spawn_spec "$agent_type" "$description" "$task_descriptor"
  ;;
```

Implement `build_teammate_spawn_spec()` to produce the JSON structure expected by TeammateTool. Use `build_task_descriptor()` output as the task payload.

### Step 4 — Enable TeammateIdle and TaskCompleted hooks in `hooks.json`

The hooks are already registered in `hooks.json` pointing to `on-teams-stub.sh`. The stub currently exits 0 when Teams is not available. Once the API is active, add the real handler logic.

In `hooks/hooks.json`, the entries look like:
```json
"TeammateIdle": [
  {
    "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/on-teams-stub.sh" }]
  }
],
"TaskCompleted": [
  {
    "hooks": [{ "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/on-teams-stub.sh" }]
  }
]
```

In `on-teams-stub.sh`, remove or conditionalize the early-exit guard:
```bash
# Remove this block once Teams API is stable:
# if ! detect_teams_available; then
#   exit 0
# fi
```

Then add handlers for each event type (read `HOOK_EVENT` from stdin JSON):
- `TeammateIdle` — call `generate_swarm_prompt()` for the next ready task and assign it
- `TaskCompleted` — call the same validation logic currently in `on-subagent-stop.sh`

### Step 5 — Configure delegate mode for the orchestrator

With Teams, the orchestrator can run in **delegate mode** — it receives tasks from the shared task list rather than Stop hook re-injection. In `swarm.md`, when `dispatchMode == "teams"`:

1. Skip the Stop hook prompt injection path.
2. Initialize the orchestrator teammate with `delegate: true`.
3. The orchestrator's first task is the initial phase prompt; subsequent tasks come from TeammateIdle assignments.

This removes the Stop hook loop entirely in Teams mode. The SubagentStop/TaskCompleted hook takes over all state advancement.

---

## Rollback Procedure

If Teams mode causes issues, revert immediately with no data loss:

1. **Unset the env var:**
   ```bash
   unset CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
   ```

2. **Reset dispatch mode in state.json** (if a workflow is in progress):
   ```bash
   jq '.dispatchMode = "subagent" | .agentTeamsAvailable = false' \
     .agents/tmp/state.json > /tmp/state-rollback.json \
     && mv /tmp/state-rollback.json .agents/tmp/state.json
   ```

3. **Restart the workflow** — the Stop hook will re-inject the correct orchestrator prompt for the current phase. All output files written so far are intact.

`teams_detect()` is called on every dispatch. As soon as the env var is unset, new dispatches fall back to `Task` tool automatically. No hook changes are required.

---

## Known Limitations (Experimental)

As of ants v0.2, the Agent Teams API carries these limitations:

- **Experimental — no stability guarantee.** The API may change or be removed. Do not use in production workflows until it is marked stable.
- **No session resumption.** If a Claude Code session is interrupted while teammates are running, the team cannot be resumed in a new session. Use `/ants:swarm` only for tasks that can complete in one session. Subagent mode (`dispatchMode: "subagent"`) supports resume via state.json.
- **One team per session.** Claude Code supports a single active team per session. Running multiple concurrent ants workflows in the same session is not supported in Teams mode. Subagent mode allows multiple parallel workflows via `ownerPpid`/`sessionId` scoping.
- **Split-pane visibility requires tmux or iTerm2.** In standard terminal environments, teammate panes may not be visible, making it harder to follow progress. The `.agents/tmp/teams.log` written by `teams_log()` is the fallback for status.
- **Mailbox message ordering is not guaranteed.** Handlers in `on-teams-stub.sh` must treat `TaskCompleted` messages as idempotent and re-validate against state.json rather than trusting message order.

---

## What Does Not Change

These components are identical in both dispatch modes and require no migration work:

- `lib/state.sh` — atomic state updates, session scoping, JSON validation
- `lib/dag.sh` — phase-level status tracking (pending/in_progress/complete)
- `lib/circuit-breaker.sh` — fix attempt tracking, stage restart logic
- `lib/task-pool.sh` — task claiming, file ownership, completion tracking
- All agent definitions (`agents/*.md`) — agent prompts are dispatch-mode agnostic
- All phase output files — layout under `.agents/tmp/phases/` is unchanged
- `on-task-gate.sh` — phase-order validation runs on PreToolUse regardless of dispatch mode
- `on-edit-gate.sh` — file ownership enforcement is unchanged
- Loop-back logic in `on-subagent-stop.sh` / `on-stop.sh` — same conditions, same state transitions
