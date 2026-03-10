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
#   teams_send_message()           — Convenience wrapper for SendMessage patterns
#   teams_create_phase_tasks()     — Creates a single queen pipeline task
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
# teams_send_message
# ---------------------------------------------------------------------------
# Convenience wrapper for the SendMessage tool pattern used by hooks.
# Generates JSON output that hooks can emit on stdout (exit 0) to instruct
# the orchestrator to deliver a message to a teammate via SendMessage.
#
# This wraps the add_message() state helper with a structured JSON envelope
# that hooks can use for cross-phase communication without manually
# constructing the JSON.
#
# Arguments:
#   $1 — sender agent name (e.g., "queen", "architect")
#   $2 — recipient agent name (e.g., "worker", "sentinel-correctness")
#   $3 — message content (plain text, max 500 chars recommended)
#
# Usage:
#   teams_send_message "queen" "architect" "Fix auth module in next loop"
#
# Side effects:
#   - Appends message to state.json via add_message()
#   - Outputs JSON envelope to stdout for hook consumers
# ---------------------------------------------------------------------------
teams_send_message() {
  local from="${1:?teams_send_message requires from}"
  local to="${2:?teams_send_message requires to}"
  local content="${3:?teams_send_message requires content}"

  # Persist the message in state.json for cross-phase retrieval
  if ! add_message "$from" "$to" "$content"; then
    echo "ERROR: Failed to persist message" >&2
    return 1
  fi

  # Emit structured JSON for hook consumers
  jq -n \
    --arg from "$from" \
    --arg to "$to" \
    --arg content "$content" \
    '{
      "sendMessage": {
        "from": $from,
        "to": $to,
        "content": $content
      }
    }'
}

# ---------------------------------------------------------------------------
# teams_create_phase_tasks
# ---------------------------------------------------------------------------
# LEGACY: This function creates a 'queen-pipeline' TaskCreate entry for the
# Agent Teams delegate mode. In the current orchestrator-driven swarm/pswarm
# path (v0.5+), there is NO corresponding TaskCompleted handler for the
# queen-pipeline task -- the orchestrator dispatches agents directly via the
# Agent tool and drives phase transitions itself, bypassing TaskCreate
# entirely. This function is only valid in Agent Teams delegate mode where
# the queen agent processes task completions via TeammateIdle/TaskCompleted
# hooks. Kept for potential Agent Teams reactivation.
# ---------------------------------------------------------------------------
# Creates a SINGLE queen pipeline task for the orchestrator. The queen drives
# all phases (A0 through A5) internally via SendMessage, rather than creating
# a 6-task chain with blockedBy dependencies.
#
# Single-task model rationale:
#   The queen is the sole pipeline orchestrator. She uses SendMessage to
#   coordinate teammates through phases sequentially. This eliminates the
#   need for external dependency chains (blockedBy) since the queen manages
#   phase ordering internally. The hooks (TeammateIdle, TaskCompleted) still
#   validate outputs and advance state, but the task graph is flat: one task,
#   one owner, all phases driven by SendMessage.
#
# The orchestrator reads this JSON and calls TaskCreate for the single entry.
#
# Usage:
#   local tasks_json
#   tasks_json="$(teams_create_phase_tasks)"
#   echo "$tasks_json" | jq '.[0]'
# ---------------------------------------------------------------------------
teams_create_phase_tasks() {
  local task
  task="$(state_get '.task' --required)"

  jq -n --arg task "$task" '[
    {
      "phaseId": "queen-pipeline",
      "subject": "Queen Pipeline: Full A0-A5 execution",
      "description": ("Drive all phases (A0 Explore, A1 Plan, A2 Review, A3 Build, A4 Sync, A5 Ship) for task: " + $task + ". Use SendMessage to coordinate teammates through each phase. Read state.json for current phase and loop. Write phase outputs to .agents/tmp/phases/."),
      "activeForm": "Driving colony pipeline",
      "blockedBy": []
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
  local subtasks_output
  subtasks_output=$(jq '
    # Collect all worker task IDs
    [.[].id] as $worker_ids |
    ["sentinel-correctness", "sentinel-security", "sentinel-perf", "sentinel-style"] as $sentinel_names |

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
        elif $name == "sentinel-perf" then "N+1 queries, blocking I/O, complexity"
        else "code style, readability, maintainability" end)),
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

    # Simplifier task — depends on ALL worker tasks (parallel with sentinels)
    [{
      phaseId: "A3-simplifier",
      subject: "A3 Simplifier: Code cleanup",
      description: "Apply targeted code cleanup to worker outputs — dead code removal, complexity reduction, over-engineering cleanup without behavioral changes.",
      activeForm: "Simplifying code",
      agentType: "ants:simplifier",
      blockedBy: [$worker_ids[] | "A3-worker-" + .]
    }] +

    # Arbiter task — depends on ALL sentinel tasks, guardian, and simplifier
    [{
      phaseId: "A3-arbiter",
      subject: "A3 Arbiter: Consolidate reviews",
      description: "Cross-reference and deduplicate sentinel findings into unified A3-quality.json",
      activeForm: "Consolidating reviews",
      agentType: "ants:review-arbiter",
      blockedBy: ["A3-sentinel-correctness", "A3-sentinel-security", "A3-sentinel-perf", "A3-sentinel-style", "A3-guardian", "A3-simplifier"]
    }]
  ' "$tasks_file" 2>/dev/null)

  if [[ -z "$subtasks_output" ]]; then
    teams_log "ERROR: jq failed to produce subtask descriptors from $tasks_file"
    return 1
  fi

  # Validate output is a non-empty JSON array
  if ! printf '%s' "$subtasks_output" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    teams_log "ERROR: subtask output is not a non-empty JSON array"
    return 1
  fi

  printf '%s\n' "$subtasks_output"
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

  # Batch-read task, loop, webSearch, and worktreePath in a single jq pass
  local batch_fields
  if ! batch_fields="$(jq -r '[(.task // ""), (.loop // 1 | tostring), (.webSearch // false | tostring), (.worktreePath // "")] | join("\t")' "$STATE_FILE" 2>/dev/null)"; then
    echo "ERROR: Failed to read fields from state.json" >&2
    return 1
  fi
  if [[ "$batch_fields" != *$'\t'* ]]; then
    echo "ERROR: Unexpected jq output format from state.json (no tab delimiter)" >&2
    return 1
  fi
  local task loop web_search worktree_path_raw
  IFS=$'\t' read -r task loop web_search worktree_path_raw <<< "$batch_fields"
  if [[ -z "$task" ]]; then
    echo "ERROR: state.json missing required field: .task" >&2
    return 1
  fi
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
      local known_agents='["architect","blueprint-reviewer","bug-scout","cartographer","drone","explore-aggregator","fix-worker","forager","guardian","nurse","queen","review-arbiter","review-fixer","sentinel-correctness","sentinel-perf","sentinel-security","sentinel-style","simplifier","solution-aggregator","solution-proposer","worker"]'
      formatted_messages="$(printf '%s' "$messages_json" | jq -r --argjson allowed "$known_agents" '.[] | "- From \(if .from and (.from | IN($allowed[])) then .from else "unknown" end) (loop \(.loop // 0)): \(.content // "" | tostring | gsub("[\\u0000-\\u001f]"; "") | sub("^#+"; "") | .[0:500])"' 2>/dev/null || { echo "WARNING: Failed to format messages for phase agent" >&2; echo "(Message formatting failed — check .agents/tmp/state.json .messages array directly)"; })"
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
    worktree_path="${worktree_path_raw:-}"
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

## Teammate Communication

Use SendMessage to communicate with other agents in the team. SendMessage
enables cross-phase coordination — send status updates, request input, or
relay findings to teammates working on related phases. Messages are persisted
in state.json and delivered when the recipient's phase activates.

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
      if [[ "$web_search" == "true" ]]; then
        printf '\n%s\n' 'Web search is enabled — use WebSearch to research library ecosystems, discover relevant external APIs, and gather external context for the task.'
      fi
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
      if [[ "$web_search" == "true" ]]; then
        printf '\n%s\n' 'Web search is enabled — use WebSearch to research libraries, frameworks, and external APIs when evaluating implementation approaches.'
      fi
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
