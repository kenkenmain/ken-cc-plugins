#!/usr/bin/env bash
# teams.sh — Agent Teams dispatch layer for ants hooks.
# Source this from hook scripts after state.sh and swarm.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/swarm.sh"
#   source "$SCRIPT_DIR/lib/teams.sh"
#
# =============================================================================
# Purpose
# =============================================================================
#
# Ants v0.3 uses Agent Teams as the sole dispatch mechanism. Teammates
# self-claim tasks from a shared task list with dependency chains.
# TeammateIdle hooks assign work, TaskCompleted hooks enforce quality gates.
#
# Key functions:
#   teams_create_phase_tasks()     — Creates TaskCreate entries for A0-A5
#   teams_add_a3_subtasks()        — Dynamically adds worker/sentinel/arbiter tasks
#   teams_get_next_ready_task()    — Finds next dispatchable phase from state
#   teams_build_teammate_prompt()  — Generates execution prompt for a teammate
#   teams_assign_idle_teammate()   — Builds exit-2 JSON for TeammateIdle
#   teams_reject_completion()      — Builds exit-2 JSON for TaskCompleted rejection
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# teams_log
# ---------------------------------------------------------------------------
teams_log() {
  local message="${1:?teams_log requires a message}"
  echo "[TEAMS] ${message}" >&2
}

# ---------------------------------------------------------------------------
# teams_create_phase_tasks
# ---------------------------------------------------------------------------
# Outputs JSON array of phase task descriptors for the orchestrator to create
# via TaskCreate. Each entry includes subject, description, and blockedBy
# for dependency chains: A0 → A1 → A2 → A3 → A4 → A5.
#
# The orchestrator reads this JSON and calls TaskCreate for each entry.
#
# Usage:
#   local tasks_json
#   tasks_json="$(teams_create_phase_tasks)"
#   echo "$tasks_json" | jq '.[0]'
# ---------------------------------------------------------------------------
teams_create_phase_tasks() {
  local task
  task="$(state_get '.task' --required)"

  # Note: descriptions reference loop-1 as initial hints. On loop-back,
  # teams_build_teammate_prompt() provides the correct loop-N path dynamically.
  jq -n --arg task "$task" '[
    {
      "phaseId": "A0",
      "subject": "A0: Colony Exploration",
      "description": ("Explore the codebase for task: " + $task + ". Dispatch forager and cartographer agents. Write output to .agents/tmp/phases/A0-explore.md"),
      "activeForm": "Exploring codebase",
      "blockedBy": []
    },
    {
      "phaseId": "A1",
      "subject": "A1: Architect Plan",
      "description": ("Create implementation plan for: " + $task + ". Read A0-explore.md. Write plan to .agents/tmp/phases/loop-1/A1-plan.md and task descriptors to A1-tasks.json"),
      "activeForm": "Planning implementation",
      "blockedBy": ["A0"]
    },
    {
      "phaseId": "A2",
      "subject": "A2: Blueprint Review",
      "description": "Review the architect plan for completeness, feasibility, and dependency correctness. Write review JSON to .agents/tmp/phases/loop-1/A2-review.json",
      "activeForm": "Reviewing plan",
      "blockedBy": ["A1"]
    },
    {
      "phaseId": "A3",
      "subject": "A3: Dual-Track Build",
      "description": "Execute the build: workers implement tasks from the pool, sentinels review, arbiter consolidates. Write output to .agents/tmp/phases/loop-1/A3-build.json and A3-quality.json",
      "activeForm": "Building implementation",
      "blockedBy": ["A2"]
    },
    {
      "phaseId": "A4",
      "subject": "A4: Queen Synchronization",
      "description": "Synchronize build and quality track results. Render clean/issues_found verdict. Write to .agents/tmp/phases/loop-1/A4-queen-verdict.json",
      "activeForm": "Reviewing verdict",
      "blockedBy": ["A3"]
    },
    {
      "phaseId": "A5",
      "subject": "A5: Ship",
      "description": "Update documentation, create git commit, and open PR. Write output to .agents/tmp/phases/loop-1/A5-ship.json",
      "activeForm": "Shipping implementation",
      "blockedBy": ["A4"]
    }
  ]'
}

# ---------------------------------------------------------------------------
# teams_add_a3_subtasks
# ---------------------------------------------------------------------------
# Reads A1-tasks.json (architect's task descriptors) and outputs JSON array
# of sub-task descriptors for A3 workers, sentinels, and arbiter.
#
# Dependency structure:
#   - Worker tasks: inter-task deps from architect + all depend on A2
#   - Sentinel tasks: depend on ALL worker tasks
#   - Arbiter task: depends on ALL sentinel tasks
#   - Guardian task: depends on ALL worker tasks (parallel with sentinels)
#
# Arguments:
#   $1 — path to A1-tasks.json
#
# Usage:
#   local subtasks
#   subtasks="$(teams_add_a3_subtasks ".agents/tmp/phases/loop-1/A1-tasks.json")"
# ---------------------------------------------------------------------------
teams_add_a3_subtasks() {
  local tasks_file="${1:?teams_add_a3_subtasks requires tasks_json path}"

  if [[ ! -f "$tasks_file" ]]; then
    teams_log "ERROR: A1-tasks.json not found at $tasks_file"
    return 1
  fi

  # Validate A1-tasks.json is a JSON array before checking task IDs
  if ! jq -e 'type == "array"' "$tasks_file" >/dev/null 2>&1; then
    teams_log "ERROR: A1-tasks.json is not a JSON array"
    return 1
  fi

  # Validate task IDs match safe pattern (alphanumeric, hyphens, underscores only)
  local invalid_ids
  invalid_ids=$(jq -r '[.[].id | select(test("^[A-Za-z0-9_-]+$") | not)] | join(", ")' "$tasks_file" 2>/dev/null || echo "")
  if [[ -n "$invalid_ids" ]]; then
    teams_log "ERROR: Invalid task IDs in A1-tasks.json: ${invalid_ids}. IDs must match ^[A-Za-z0-9_-]+$"
    return 1
  fi

  # Read architect's tasks and build sub-task descriptors
  jq '
    # Collect all worker task IDs
    [.[].id] as $worker_ids |
    ["sentinel-correctness", "sentinel-security", "sentinel-perf"] as $sentinel_names |

    # Worker tasks — each depends on its declared dependencies (prefixed with A3-)
    [.[] | {
      phaseId: ("A3-worker-" + .id),
      subject: ("A3 Worker: " + .description),
      description: ("Implement task " + .id + ": " + .description + "\nFiles: " + (.files_owned // [] | join(", ")) + "\nAcceptance criteria: " + (.acceptance_criteria // "See plan")),
      activeForm: ("Building " + .id),
      agentType: "ants:worker",
      blockedBy: (["A2"] + [.dependencies // [] | .[] | "A3-worker-" + .])
    }] +

    # Sentinel tasks — each depends on ALL worker tasks
    [$sentinel_names[] | . as $name | {
      phaseId: ("A3-" + $name),
      subject: ("A3 Sentinel: " + $name),
      description: ("Review implementation for " + (if $name == "sentinel-correctness" then "bugs, logic errors, and error handling"
        elif $name == "sentinel-security" then "OWASP top 10, injection, secrets, access control"
        else "N+1 queries, blocking I/O, complexity" end)),
      activeForm: ("Reviewing " + $name),
      agentType: ("ants:" + $name),
      blockedBy: [$worker_ids[] | "A3-worker-" + .]
    }] +

    # Guardian task — depends on ALL worker tasks (parallel with sentinels)
    [{
      phaseId: "A3-guardian",
      subject: "A3 Guardian: Write tests",
      description: "Write tests for the implemented code. Cover happy path, edge cases, and error paths.",
      activeForm: "Writing tests",
      agentType: "ants:guardian",
      blockedBy: [$worker_ids[] | "A3-worker-" + .]
    }] +

    # Arbiter task — depends on ALL sentinel tasks
    [{
      phaseId: "A3-arbiter",
      subject: "A3 Arbiter: Consolidate reviews",
      description: "Cross-reference and deduplicate sentinel findings into unified A3-quality.json",
      activeForm: "Consolidating reviews",
      agentType: "ants:review-arbiter",
      blockedBy: ["A3-sentinel-correctness", "A3-sentinel-security", "A3-sentinel-perf"]
    }]
  ' "$tasks_file"
}

# ---------------------------------------------------------------------------
# teams_get_next_ready_task
# ---------------------------------------------------------------------------
# Reads state.json to find the next phase that should be dispatched.
# Returns the phase ID (e.g., "A0", "A1", "A3") or empty if no tasks ready.
#
# Logic:
#   - Check currentPhase from state
#   - If phase is DONE/STOPPED/BLOCKED → return empty
#   - Otherwise return currentPhase (it's ready to execute)
#
# Usage:
#   local next
#   next="$(teams_get_next_ready_task)"
#   if [[ -n "$next" ]]; then ...
# ---------------------------------------------------------------------------
teams_get_next_ready_task() {
  local current_phase
  current_phase="$(state_get '.currentPhase' --required)"

  local status
  status="$(state_get '.status' --required)"

  case "$status" in
    complete|blocked|stopped)
      echo ""
      return 0
      ;;
  esac

  case "$current_phase" in
    DONE|STOPPED|BLOCKED)
      echo ""
      return 0
      ;;
    *)
      echo "$current_phase"
      return 0
      ;;
  esac
}

# ---------------------------------------------------------------------------
# teams_build_teammate_prompt
# ---------------------------------------------------------------------------
# Generates a direct execution prompt for a teammate. Unlike the old
# generate_swarm_prompt() which told the orchestrator to dispatch subagents,
# this produces a prompt for the teammate to execute the work directly.
#
# Arguments:
#   $1 — phase ID (A0, A1, A2, A3, A4, A5)
#
# Usage:
#   local prompt
#   prompt="$(teams_build_teammate_prompt "A1")"
# ---------------------------------------------------------------------------
teams_build_teammate_prompt() {
  local phase="${1:?teams_build_teammate_prompt requires a phase ID}"

  # Batch-read task and loop in a single jq pass to avoid multiple lock/fork cycles
  local task_and_loop
  if ! task_and_loop="$(jq -r '"\(.task // "")\t\(.loop // 1)"' "$STATE_FILE" 2>/dev/null)"; then
    echo "ERROR: Failed to read task and loop from state.json" >&2
    return 1
  fi
  # Validate output contains a tab delimiter (guards against jq producing unexpected output)
  if [[ "$task_and_loop" != *$'\t'* ]]; then
    echo "ERROR: Unexpected jq output format from state.json (no tab delimiter)" >&2
    return 1
  fi
  local task
  task="$(printf '%s' "$task_and_loop" | cut -f1)"
  if [[ -z "$task" ]]; then
    echo "ERROR: state.json missing required field: .task" >&2
    return 1
  fi
  local loop
  loop="$(printf '%s' "$task_and_loop" | cut -f2)"
  loop=$(require_int "$loop" "loop")

  local phases_dir
  if [[ "$phase" == "A0" ]]; then
    phases_dir=".agents/tmp/phases"
  else
    phases_dir=".agents/tmp/phases/loop-${loop}"
  fi

  local output_file
  output_file="$(get_phase_output "$phase")"
  local input_files
  input_files="$(get_phase_input "$phase")"
  input_files="${input_files//\{LOOP\}/${loop}}"

  # Loop context for A1 when re-planning
  local prev_context=""
  if [[ "$phase" == "A1" && "$loop" -gt 1 ]]; then
    local prev=$((loop - 1))
    prev_context="IMPORTANT: This is loop ${loop}. Read the previous loop's queen verdict:
- .agents/tmp/phases/loop-${prev}/A4-queen-verdict.json

Plan targeted fixes for the issues found. Do NOT re-plan the entire feature."
  fi

  # Message injection: retrieve messages targeted at this phase's agent
  local phase_agent=""
  case "$phase" in
    A0) phase_agent="forager" ;;
    A1) phase_agent="architect" ;;
    A2) phase_agent="blueprint-reviewer" ;;
    A3) phase_agent="worker" ;;
    A4) phase_agent="queen" ;;
    A5) phase_agent="drone" ;;
  esac

  local messages_context=""
  if [[ -n "$phase_agent" ]]; then
    local messages_json
    messages_json="$(get_messages_for "$phase_agent")"
    if [[ -n "$messages_json" && "$messages_json" != "[]" ]]; then
      local formatted_messages
      formatted_messages="$(printf '%s' "$messages_json" | jq -r '.[] | "- From \(.from) (loop \(.loop)): \(.content)"' 2>/dev/null || { echo "WARNING: Failed to format messages for phase agent" >&2; echo ""; })"
      if [[ -n "$formatted_messages" ]]; then
        messages_context="## Messages from Previous Phases
${formatted_messages}"
      fi
    fi
  fi

  # Worktree context for A5 (shipping phase)
  local worktree_context=""
  if [[ "$phase" == "A5" ]]; then
    local worktree_path
    worktree_path="$(state_get '.worktreePath // empty')"
    if [[ -n "$worktree_path" ]]; then
      worktree_context="IMPORTANT: This workflow uses a git worktree at: ${worktree_path}
All git operations must be performed within the worktree directory."
    fi
  fi

  cat <<PROMPT
## Ants Colony — Phase ${phase} — Loop ${loop}

Task: ${task}
${prev_context:+
${prev_context}
}${messages_context:+
${messages_context}
}${worktree_context:+
${worktree_context}
}
Input files:
${input_files}

Output: ${phases_dir}/${output_file}

Create the directory first: mkdir -p ${phases_dir}

PROMPT

  case "$phase" in
    A0)
      cat <<'RULES'
Explore the codebase to understand the project structure, existing patterns,
and relevant code. Write a comprehensive exploration report to the output file.

Use Read, Glob, and Grep tools to explore. Cover:
- Project structure and key directories
- Relevant existing implementations
- Test patterns and conventions
- Architecture and dependencies
RULES
      ;;
    A1)
      cat <<'RULES'
Read the exploration output and create a detailed implementation plan.
Break the work into discrete tasks with:
- Task ID, description, files to modify
- Dependencies between tasks
- Acceptance criteria for each task

Write the plan as markdown to the output file.
Also write task descriptors as JSON to A1-tasks.json in the same directory.
RULES
      ;;
    A2)
      cat <<'RULES'
Review the plan for completeness, feasibility, and dependency correctness.
Write a JSON review to the output file:
{
  "status": "approved|needs_revision",
  "issues": [...],
  "summary": "..."
}
RULES
      ;;
    A3)
      cat <<RULES
Implement the tasks from the plan. Read A1-tasks.json for task descriptors.
Build the implementation, write tests, then write output JSON:
{
  "tasks": [...each task result...],
  "files_changed": [...deduplicated list...],
  "all_complete": true
}

After implementation, review the code for correctness, security, and performance.
Write quality review to: ${phases_dir}/A3-quality.json
RULES
      ;;
    A4)
      cat <<RULES
Read the build output and quality review. Cross-reference issues against
the implementation. Render a verdict:
{
  "verdict": "clean|issues_found",
  "issues": [...],
  "total_issues": N,
  "recommendation": "clean|loop"
}

If "clean": workflow advances to shipping.
If "issues_found": workflow loops back to planning with targeted fixes.
RULES
      ;;
    A5)
      cat <<RULES
Ship the completed work:
1. Update documentation (README, CLAUDE.md if relevant)
2. Create a git commit with conventional commit message
3. Push branch and open a PR

Write output JSON:
{
  "commit_sha": "...",
  "pr_url": "...",
  "docs_updated": true|false,
  "summary": "..."
}
RULES
      ;;
  esac
}

# ---------------------------------------------------------------------------
# teams_assign_idle_teammate
# ---------------------------------------------------------------------------
# Builds the stderr message for a TeammateIdle hook that keeps the teammate
# working. The hook should write this to stderr and exit 2.
#
# Arguments:
#   $1 — task prompt to assign
#
# Usage:
#   teams_assign_idle_teammate "$prompt"
#   # then: exit 2
# ---------------------------------------------------------------------------
teams_assign_idle_teammate() {
  local prompt="${1:?teams_assign_idle_teammate requires a prompt}"
  printf '%s\n' "$prompt" >&2
}

# ---------------------------------------------------------------------------
# teams_reject_completion
# ---------------------------------------------------------------------------
# Builds the stderr message for a TaskCompleted hook that rejects completion.
# The hook should write this to stderr and exit 2.
#
# Arguments:
#   $1 — reason for rejection
#
# Usage:
#   teams_reject_completion "Output file missing"
#   # then: exit 2
# ---------------------------------------------------------------------------
teams_reject_completion() {
  local reason="${1:?teams_reject_completion requires a reason}"
  echo "Task completion rejected: ${reason}" >&2
}
