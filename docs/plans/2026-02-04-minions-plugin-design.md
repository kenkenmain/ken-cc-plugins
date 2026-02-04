# Minions Plugin Design

## Overview

Standalone Claude Code plugin with a single command `/minions:launch` that runs a 4-phase development workflow with personality-driven agents and a loop-back mechanism for issue resolution.

**Philosophy:** Constraint is freedom. Agents have distinct personalities, enforce their own completeness, and the pipeline loops until the code is clean — or stops and reports after 10 attempts.

## Pipeline

```
F1 (scout) → F2 (builder) → F3 (critic || pedant || witness)
     ^                              |
     └──────── if any issues ───────┘
               (max 10 loops)

All clean → F4 (shipper)
Loop 10 hit → stop and report
```

- **F1-F3 loop:** Any issues from any F3 agent trigger a full loop back to F1. Scout re-plans based on the previous loop's F3 outputs.
- **F4 runs once:** Only after F3 produces a clean verdict.
- **Hard stop at loop 10:** Workflow stops with a report of remaining issues. Nothing gets committed.

## Agent Roster (6 agents)

All agents inherit model from the parent conversation (no `model` field in frontmatter unless specifically needed). Each agent has a per-agent prompt-based Stop hook that validates completeness before allowing it to finish.

### scout (F1)

- **Personality:** Curious, thorough. Maps everything before anyone moves.
- **Role:** Explore codebase, brainstorm approaches, write implementation plan with task table.
- **Tools:** Read, Glob, Grep, WebSearch (read-only — no Edit/Write/Bash)
- **Stop hook validates:** Plan has task table, acceptance criteria per task, file list.
- **Loop 2+:** Reads previous loop's F3 outputs (critic, pedant, witness) and re-plans to address issues.
- **Output:** `loop-N/f1-plan.md`

### builder (F2)

- **Personality:** Disciplined, scope-focused. Implements exactly what's asked, logs out-of-scope findings to SCOPE_NOTES.md.
- **Role:** Implement tasks from scout's plan. One builder per task, run in parallel.
- **Tools:** Read, Glob, Grep, Edit, Write, Bash (no Task — leaf agent)
- **Stop hook validates:** All acceptance criteria met, tests pass, lint clean, output JSON valid.
- **Bash restrictions:** Git commands blocked by PreToolUse hook in frontmatter.
- **Output:** `loop-N/f2-tasks.json` (aggregated from per-builder outputs)

### critic (F3a)

- **Personality:** Skeptical, finds what others miss. Focused on things that break.
- **Role:** Static analysis — bugs, logic errors, security vulnerabilities, missing error handling.
- **Tools:** Read, Glob, Grep, Bash (read-only — no Edit/Write)
- **Stop hook validates:** All files reviewed, issues have severity + evidence, output JSON valid.
- **Runs in parallel** with pedant and witness.
- **Output:** `loop-N/f3-critic.json`

### pedant (F3b)

- **Personality:** Exacting, cares about craft. Focused on things that rot.
- **Role:** Code quality — naming, style, unnecessary complexity, test coverage gaps, comment accuracy.
- **Tools:** Read, Glob, Grep, Bash (read-only — no Edit/Write)
- **Stop hook validates:** All files reviewed, quality issues documented, output JSON valid.
- **Runs in parallel** with critic and witness.
- **Output:** `loop-N/f3-pedant.json`

### witness (F3c)

- **Personality:** "I'll believe it when I see it." Observes, doesn't trust assertions.
- **Role:** Runtime verification — runs the code, curls endpoints, captures output, observes behavior. Inspired by claudikins-kernel's catastrophiser.
- **Tools:** Read, Glob, Grep, Bash, WebFetch (no Edit/Write — observe only)
- **Stop hook validates:** Code was actually run, evidence captured (output, screenshots, responses), output JSON valid.
- **Runs in parallel** with critic and pedant.
- **Output:** `loop-N/f3-witness.json`

### shipper (F4)

- **Personality:** Gets things across the finish line. Clean commits, thorough docs.
- **Role:** Update documentation, create git commit, open PR.
- **Tools:** Read, Glob, Grep, Edit, Write, Bash
- **Stop hook validates:** Docs updated, commit created, PR opened.
- **Only runs when F3 verdict is clean.**
- **Output:** `loop-N/f4-ship.json`

## Plugin Structure

```
plugins/minions/
├── .claude-plugin/
│   └── plugin.json              # { "name": "minions", "version": "0.1.0" }
├── commands/
│   └── launch.md               # /minions:launch — the only command
├── agents/
│   ├── scout.md                # F1: explore + brainstorm + plan
│   ├── builder.md              # F2: implement tasks (parallel)
│   ├── critic.md               # F3a: correctness review
│   ├── pedant.md               # F3b: quality review
│   ├── witness.md              # F3c: runtime verification
│   └── shipper.md              # F4: docs + commit + PR
├── hooks/
│   ├── hooks.json              # Hook registration
│   ├── on-stop.sh              # Loop driver (Ralph-style prompt generation)
│   ├── on-subagent-stop.sh     # Validate output, advance state, check verdict
│   └── on-task-gate.sh         # Block out-of-order Task dispatches
└── prompts/
    ├── f1-scout.md             # Scout phase prompt template
    ├── f2-builder.md           # Builder phase prompt template
    ├── f3-review.md            # F3 dispatch prompt (critic || pedant || witness)
    └── f4-shipper.md           # Shipper phase prompt template
```

No skills, no configuration command, no debug workflow, no preflight. Single command, 6 agents, 3 hooks.

## State Management

State file: `.agents/tmp/state.json`

```json
{
  "version": 1,
  "plugin": "minions",
  "status": "in_progress",
  "task": "the user's task description",
  "startedAt": "ISO timestamp",
  "updatedAt": "ISO timestamp",
  "currentPhase": "F1",
  "loop": 1,
  "maxLoops": 10,
  "ownerPpid": "12345",
  "schedule": [
    { "phase": "F1", "name": "Scout", "type": "subagent" },
    { "phase": "F2", "name": "Build", "type": "dispatch" },
    { "phase": "F3", "name": "Review", "type": "dispatch" },
    { "phase": "F4", "name": "Ship", "type": "subagent" }
  ],
  "loops": [
    {
      "loop": 1,
      "startedAt": "ISO timestamp",
      "f1": { "status": "complete" },
      "f2": { "status": "complete" },
      "f3": {
        "status": "complete",
        "critic": { "issues": 2 },
        "pedant": { "issues": 1 },
        "witness": { "status": "FAIL", "issues": 1 }
      },
      "verdict": "issues_found",
      "totalIssues": 4
    }
  ],
  "files": [],
  "failure": null
}
```

### Phase Outputs

Stored in `.agents/tmp/phases/` with loop prefix:

```
loop-1/f1-plan.md
loop-1/f2-tasks.json
loop-1/f3-critic.json
loop-1/f3-pedant.json
loop-1/f3-witness.json
loop-2/f1-plan.md          ← scout re-plans based on loop-1 issues
loop-2/f2-tasks.json
loop-2/f3-critic.json
loop-2/f3-pedant.json
loop-2/f3-witness.json
...
```

## Gate Enforcement (3 layers)

### Layer 1: Per-Agent Stop Hooks (prompt-type, in frontmatter)

Each agent has a prompt-type Stop hook that validates completeness. The agent cannot finish until the hook returns `{ok: true}`. Modeled after claudikins-kernel's babyclaude pattern.

### Layer 2: SubagentStop Hook (on-subagent-stop.sh)

Fires when any agent finishes. Validates:
- Output file exists at expected path
- Output is valid JSON/markdown
- Advances `currentPhase` in state.json
- For F3: aggregates verdict from critic + pedant + witness
  - If `verdict == "clean"` → advance to F4
  - If `verdict == "issues_found"` → increment loop counter
    - If `loop <= maxLoops` → reset currentPhase to F1
    - If `loop > maxLoops` → set status to "stopped", report issues

### Layer 3: PreToolUse Hook (on-task-gate.sh)

Fires before any Task dispatch. Blocks if:
- The dispatched agent doesn't match the current phase
- Required output from previous phase is missing

## Hook Design

### hooks.json

```json
{
  "description": "Minions workflow enforcement hooks",
  "hooks": {
    "Stop": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/on-stop.sh",
          "timeout": 10
        }]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/on-subagent-stop.sh",
          "timeout": 15
        }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Task",
        "hooks": [{
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/on-task-gate.sh",
          "timeout": 5
        }]
      }
    ]
  }
}
```

### on-stop.sh (Loop Driver)

Ralph-style Stop hook. Reads state.json, generates a phase-specific prompt, and injects it as `{"decision":"block","reason":"<prompt>"}` to drive the orchestrator loop.

### on-subagent-stop.sh (Validator + Advancer)

- Validates output file exists and is well-formed
- Updates state.json with phase results
- For F3: waits for all 3 agents (critic, pedant, witness) to complete before rendering verdict
- Handles loop-back logic (increment loop, reset to F1 or advance to F4)

### on-task-gate.sh (Order Enforcer)

- Reads `currentPhase` from state.json
- Maps dispatched agent type to expected phase
- Blocks if mismatch
- Blocks if previous phase output file missing

## Key Design Decisions

1. **Inherit model by default** — no `model` field in agent frontmatter. User controls model via their session.
2. **Full loop back to F1** — not in-phase fix cycles. Scout re-plans, builder re-implements, reviewers re-verify.
3. **3 parallel F3 agents** — critic (correctness), pedant (quality), witness (runtime). All must pass.
4. **Per-agent Stop hooks** — prompt-based validation prevents incomplete work from passing through.
5. **Scope discipline** — builder logs out-of-scope findings to SCOPE_NOTES.md, never fixes them.
6. **10 loop max, hard stop** — no proceeding with known issues.
7. **Standalone** — no dependency on subagents plugin. Own agents, hooks, prompts.
8. **Minimal surface area** — 1 command, 6 agents, 3 hooks, 4 prompts. No config, no debug, no preflight.
