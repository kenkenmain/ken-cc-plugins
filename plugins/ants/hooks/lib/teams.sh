#!/usr/bin/env bash
# teams.sh — Agent Teams dispatch layer for ants v0.6 hooks.
# Source this from hook scripts after state.sh, swarm.sh, and task-pool.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/swarm.sh"
#   source "$SCRIPT_DIR/lib/task-pool.sh"
#   source "$SCRIPT_DIR/lib/teams.sh"
#
# =============================================================================
# Purpose
# =============================================================================
#
# Ants v0.6 uses Agent Teams delegate mode. Commands create teams with
# dependency-chain task graphs, spawn teammates, then enter a monitoring
# loop. TeammateIdle hooks route ready tasks to idle teammates.
# TaskCompleted hooks validate output, advance state, and set signal flags
# for the command's monitoring loop. SendMessage is a live coordination
# overlay -- agents write files first, then message teammates.
#
# Key functions:
#   teams_log()                      — Log with [TEAMS] prefix to stderr
#   teams_create_phase_tasks()       — Creates full A0-A5 dependency chain
#   teams_add_a3_subtasks()          — Dynamically adds worker/sentinel/arbiter tasks
#   teams_create_sswarm_tasks()      — Creates sswarm task graph (competing agents)
#   teams_create_verdict_tasks()     — Creates A5 nurse + drone tasks
#   teams_create_pswarm_run_tasks()  — Wrapper for pswarm run-boundary task graphs
#   teams_get_a3_task_prompt()       — Worker-specific prompt from task pool
#   teams_build_teammate_prompt()    — Generates execution prompt for a teammate
#   teams_assign_idle_teammate()     — Builds exit-2 JSON for TeammateIdle
#   teams_reject_completion()        — Builds exit-2 JSON for TaskCompleted rejection
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
# Creates the full A0 -> A1 -> A2 -> A3 -> A4 -> A5 dependency chain for
# Agent Teams delegate mode. Each phase is a separate task with blockedBy
# dependencies on the previous phase. A3 and A4 are placeholder tasks --
# A3 workers are created dynamically after A1 completes, and A4 verdict
# is evaluated inline by the TaskCompleted hook.
#
# Output: JSON array of 6 phase task objects printed to stdout.
#
# Usage:
#   local tasks_json
#   tasks_json="$(teams_create_phase_tasks)"
# ---------------------------------------------------------------------------
teams_create_phase_tasks() {
  local task
  task="$(state_get '.task' --required)"

  jq -n --arg task "$task" '[
    {
      "phaseId": "A0",
      "subject": "A0: Colony Exploration",
      "description": ("Explore the codebase to understand project structure, existing patterns, and relevant code for task: " + $task),
      "activeForm": "Exploring codebase",
      "blockedBy": []
    },
    {
      "phaseId": "A1",
      "subject": "A1: Architect Plan",
      "description": ("Read the exploration output and create a detailed implementation plan with task assignments for: " + $task),
      "activeForm": "Planning implementation",
      "blockedBy": ["A0"]
    },
    {
      "phaseId": "A2",
      "subject": "A2: Blueprint Review",
      "description": ("Review the plan for completeness, feasibility, and dependency correctness for: " + $task),
      "activeForm": "Reviewing plan",
      "blockedBy": ["A1"]
    },
    {
      "phaseId": "A3",
      "subject": "A3: Dual-Track Build",
      "description": ("Placeholder -- workers, sentinels, guardian, simplifier, and arbiter are created dynamically after A1 completes for: " + $task),
      "activeForm": "Building implementation",
      "blockedBy": ["A2"]
    },
    {
      "phaseId": "A4",
      "subject": "A4: Verdict Sync",
      "description": ("Placeholder -- verdict is evaluated inline by TaskCompleted hook after A3 arbiter completes for: " + $task),
      "activeForm": "Evaluating verdict",
      "blockedBy": ["A3"]
    },
    {
      "phaseId": "A5",
      "subject": "A5: Documentation + Ship",
      "description": ("Ship the completed work -- update docs, commit, and open PR for: " + $task),
      "activeForm": "Shipping work",
      "blockedBy": ["A4"]
    }
  ]'
}

# ---------------------------------------------------------------------------
# teams_add_a3_subtasks
# ---------------------------------------------------------------------------
# Reads A1-tasks.json (architect's task descriptors) and outputs JSON array
# of sub-task descriptors for A3 workers, sentinels, guardian, simplifier,
# arbiter, and review-fixer.
#
# Dependency structure:
#   - Worker tasks: inter-task deps from architect + all depend on A2
#   - Sentinel tasks: depend on ALL worker tasks
#   - Guardian task: depends on ALL worker tasks (parallel with sentinels)
#   - Simplifier task: depends on ALL worker tasks (parallel with sentinels)
#   - Review-arbiter task: depends on ALL sentinels + guardian + simplifier
#   - Review-fixer task: depends on review-arbiter (optional, dispatched if
#     arbiter finds critical issues)
#
# Arguments:
#   $1 -- path to A1-tasks.json
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

    # Worker tasks -- each depends on its declared dependencies (prefixed with A3-worker-)
    [.[] | {
      phaseId: ("A3-worker-" + .id),
      subject: ("A3 Worker: " + (.description // .id)),
      description: ("Implement task " + .id + ": " + (.description // "") + "\nFiles: " + (.files_owned // [] | join(", ")) + "\nAcceptance criteria: " + (.acceptance_criteria // "See plan")),
      activeForm: ("Building " + .id),
      agentType: "ants:worker",
      blockedBy: (["A2"] + [.dependencies // [] | .[] | "A3-worker-" + .])
    }] +

    # Sentinel tasks -- each depends on ALL worker tasks
    [$sentinel_names[] | . as $name | {
      phaseId: ("A3-" + $name),
      subject: ("A3 Sentinel " + (if $name == "sentinel-correctness" then "Correctness"
        elif $name == "sentinel-security" then "Security"
        elif $name == "sentinel-perf" then "Perf"
        else "Style" end) + ": Review"),
      description: ("Review implementation for " + (if $name == "sentinel-correctness" then "bugs, logic errors, and error handling"
        elif $name == "sentinel-security" then "OWASP top 10, injection, secrets, access control"
        elif $name == "sentinel-perf" then "N+1 queries, blocking I/O, complexity"
        else "code style, readability, maintainability" end)),
      activeForm: ("Reviewing " + $name),
      agentType: ("ants:" + $name),
      blockedBy: [$worker_ids[] | "A3-worker-" + .]
    }] +

    # Guardian task -- depends on ALL worker tasks (parallel with sentinels)
    [{
      phaseId: "A3-guardian",
      subject: "A3 Guardian: Write tests",
      description: "Write tests for the implemented code. Cover happy path, edge cases, and error paths.",
      activeForm: "Writing tests",
      agentType: "ants:guardian",
      blockedBy: [$worker_ids[] | "A3-worker-" + .]
    }] +

    # Simplifier task -- depends on ALL worker tasks (parallel with sentinels)
    [{
      phaseId: "A3-simplifier",
      subject: "A3 Simplifier: Code cleanup",
      description: "Apply targeted code cleanup to worker outputs -- dead code removal, complexity reduction, over-engineering cleanup without behavioral changes.",
      activeForm: "Simplifying code",
      agentType: "ants:simplifier",
      blockedBy: [$worker_ids[] | "A3-worker-" + .]
    }] +

    # Review-arbiter task -- depends on ALL sentinels + guardian + simplifier
    [{
      phaseId: "A3-arbiter",
      subject: "A3 Arbiter: Consolidate reviews",
      description: "Cross-reference and deduplicate sentinel findings into unified A3-quality.json",
      activeForm: "Consolidating reviews",
      agentType: "ants:review-arbiter",
      blockedBy: ["A3-sentinel-correctness", "A3-sentinel-security", "A3-sentinel-perf", "A3-sentinel-style", "A3-guardian", "A3-simplifier"]
    }] +

    # Review-fixer task -- depends on arbiter (optional, dispatched if arbiter finds critical issues)
    [{
      phaseId: "A3-review-fixer",
      subject: "A3 Review-Fixer: Apply targeted repairs",
      description: "Read A3-quality.json and apply targeted repairs for critical issues found by the review arbiter.",
      activeForm: "Fixing review issues",
      agentType: "ants:review-fixer",
      blockedBy: ["A3-arbiter"]
    }]
  ' "$tasks_file" 2>"${STATE_FILE}.a3sub-err")

  if [[ -z "$subtasks_output" ]]; then
    local a3sub_err
    a3sub_err=$(cat "${STATE_FILE}.a3sub-err" 2>/dev/null || echo "unknown jq error")
    rm -f "${STATE_FILE}.a3sub-err"
    teams_log "ERROR: jq failed to produce subtask descriptors from $tasks_file: $a3sub_err"
    return 1
  fi
  rm -f "${STATE_FILE}.a3sub-err" 2>/dev/null

  # Validate output is a non-empty JSON array
  if ! printf '%s' "$subtasks_output" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
    teams_log "ERROR: subtask output is not a non-empty JSON array"
    return 1
  fi

  printf '%s\n' "$subtasks_output"
}

# ---------------------------------------------------------------------------
# teams_create_sswarm_tasks
# ---------------------------------------------------------------------------
# Creates the sswarm-specific task graph with competing agents at A1 and A2.
#
# Structure:
#   A0: Single explore-aggregator task (same as swarm)
#   A1: 3 architect tasks (A1-architect-1,2,3 all blockedBy [A0]),
#       1 plan-arbiter blockedBy all 3 architects
#   A2: 3 reviewer tasks (A2-reviewer-1,2,3 all blockedBy [A1-plan-arbiter]),
#       1 review-lead blockedBy all 3 reviewers
#   A3-A5: Same placeholder pattern as swarm
#
# Each competing task outputs to a unique temp file.
#
# Output: JSON array of all tasks printed to stdout.
#
# Usage:
#   local tasks_json
#   tasks_json="$(teams_create_sswarm_tasks)"
# ---------------------------------------------------------------------------
teams_create_sswarm_tasks() {
  local task
  task="$(state_get '.task' --required)"

  local loop
  loop="$(state_get '.loop // 1')"
  loop=$(require_int "$loop" "loop")

  local phases_dir=".agents/tmp/phases/loop-${loop}"

  jq -n --arg task "$task" --arg phases_dir "$phases_dir" '[
    # A0: Colony Exploration (same as swarm)
    {
      "phaseId": "A0",
      "subject": "A0: Colony Exploration",
      "description": ("Explore the codebase to understand project structure, existing patterns, and relevant code for task: " + $task),
      "activeForm": "Exploring codebase",
      "blockedBy": []
    },

    # A1: 3 competing architects
    {
      "phaseId": "A1-architect-1",
      "subject": "A1 Architect 1: Competing plan",
      "description": ("Create a detailed implementation plan for: " + $task + "\nWrite plan output to: " + $phases_dir + "/A1-plan.architect.1.tmp\nWrite task descriptors to: " + $phases_dir + "/A1-tasks.architect.1.tmp"),
      "activeForm": "Planning (architect 1)",
      "agentType": "ants:architect",
      "blockedBy": ["A0"]
    },
    {
      "phaseId": "A1-architect-2",
      "subject": "A1 Architect 2: Competing plan",
      "description": ("Create a detailed implementation plan for: " + $task + "\nWrite plan output to: " + $phases_dir + "/A1-plan.architect.2.tmp\nWrite task descriptors to: " + $phases_dir + "/A1-tasks.architect.2.tmp"),
      "activeForm": "Planning (architect 2)",
      "agentType": "ants:architect",
      "blockedBy": ["A0"]
    },
    {
      "phaseId": "A1-architect-3",
      "subject": "A1 Architect 3: Competing plan",
      "description": ("Create a detailed implementation plan for: " + $task + "\nWrite plan output to: " + $phases_dir + "/A1-plan.architect.3.tmp\nWrite task descriptors to: " + $phases_dir + "/A1-tasks.architect.3.tmp"),
      "activeForm": "Planning (architect 3)",
      "agentType": "ants:architect",
      "blockedBy": ["A0"]
    },

    # A1: Plan arbiter consolidates 3 competing plans
    {
      "phaseId": "A1-plan-arbiter",
      "subject": "A1 Plan Arbiter: Consolidate plans",
      "description": ("Read the 3 competing plans and select/merge the best approach.\nInput files:\n- " + $phases_dir + "/A1-plan.architect.1.tmp\n- " + $phases_dir + "/A1-plan.architect.2.tmp\n- " + $phases_dir + "/A1-plan.architect.3.tmp\nOutput: " + $phases_dir + "/A1-plan.md and " + $phases_dir + "/A1-tasks.json"),
      "activeForm": "Consolidating plans",
      "agentType": "ants:plan-arbiter",
      "blockedBy": ["A1-architect-1", "A1-architect-2", "A1-architect-3"]
    },

    # A2: 3 competing reviewers
    {
      "phaseId": "A2-reviewer-1",
      "subject": "A2 Blueprint Reviewer 1: Competing review",
      "description": ("Review the consolidated plan for completeness and feasibility.\nInput: " + $phases_dir + "/A1-plan.md\nWrite review to: " + $phases_dir + "/A2-review.reviewer.1.tmp"),
      "activeForm": "Reviewing plan (reviewer 1)",
      "agentType": "ants:blueprint-reviewer",
      "blockedBy": ["A1-plan-arbiter"]
    },
    {
      "phaseId": "A2-reviewer-2",
      "subject": "A2 Blueprint Reviewer 2: Competing review",
      "description": ("Review the consolidated plan for completeness and feasibility.\nInput: " + $phases_dir + "/A1-plan.md\nWrite review to: " + $phases_dir + "/A2-review.reviewer.2.tmp"),
      "activeForm": "Reviewing plan (reviewer 2)",
      "agentType": "ants:blueprint-reviewer",
      "blockedBy": ["A1-plan-arbiter"]
    },
    {
      "phaseId": "A2-reviewer-3",
      "subject": "A2 Blueprint Reviewer 3: Competing review",
      "description": ("Review the consolidated plan for completeness and feasibility.\nInput: " + $phases_dir + "/A1-plan.md\nWrite review to: " + $phases_dir + "/A2-review.reviewer.3.tmp"),
      "activeForm": "Reviewing plan (reviewer 3)",
      "agentType": "ants:blueprint-reviewer",
      "blockedBy": ["A1-plan-arbiter"]
    },

    # A2: Review lead consolidates 3 competing reviews
    {
      "phaseId": "A2-review-lead",
      "subject": "A2 Review Lead: Consolidate reviews",
      "description": ("Read the 3 competing reviews and produce a unified review verdict.\nInput files:\n- " + $phases_dir + "/A2-review.reviewer.1.tmp\n- " + $phases_dir + "/A2-review.reviewer.2.tmp\n- " + $phases_dir + "/A2-review.reviewer.3.tmp\nOutput: " + $phases_dir + "/A2-review.json"),
      "activeForm": "Consolidating reviews",
      "agentType": "ants:review-lead",
      "blockedBy": ["A2-reviewer-1", "A2-reviewer-2", "A2-reviewer-3"]
    },

    # A3-A5: Same placeholder pattern as swarm
    {
      "phaseId": "A3",
      "subject": "A3: Dual-Track Build",
      "description": ("Placeholder -- workers, sentinels, guardian, simplifier, and arbiter are created dynamically after A1 completes for: " + $task),
      "activeForm": "Building implementation",
      "blockedBy": ["A2-review-lead"]
    },
    {
      "phaseId": "A4",
      "subject": "A4: Verdict Sync",
      "description": ("Placeholder -- verdict is evaluated inline by TaskCompleted hook after A3 arbiter completes for: " + $task),
      "activeForm": "Evaluating verdict",
      "blockedBy": ["A3"]
    },
    {
      "phaseId": "A5",
      "subject": "A5: Documentation + Ship",
      "description": ("Ship the completed work -- update docs, commit, and open PR for: " + $task),
      "activeForm": "Shipping work",
      "blockedBy": ["A4"]
    }
  ]'
}

# ---------------------------------------------------------------------------
# teams_create_verdict_tasks
# ---------------------------------------------------------------------------
# Creates A5 tasks (nurse + drone) after A4 verdict is clean.
#
# Two tasks:
#   1. A5-nurse: blockedBy [A3-arbiter], agentType ants:nurse
#   2. A5-drone: blockedBy [A5-nurse], agentType ants:drone
#
# Includes worktree context and loop number from state.
#
# Output: JSON array of 2 task objects printed to stdout.
#
# Usage:
#   local verdict_tasks
#   verdict_tasks="$(teams_create_verdict_tasks)"
# ---------------------------------------------------------------------------
teams_create_verdict_tasks() {
  local task
  task="$(state_get '.task' --required)"

  local loop
  loop="$(state_get '.loop // 1')"
  loop=$(require_int "$loop" "loop")

  local worktree_path
  worktree_path="$(state_get '.worktreePath' || {
    echo "WARNING: Failed to read worktreePath from state.json, treating as empty" >&2
    echo ""
  })"

  local phases_dir=".agents/tmp/phases/loop-${loop}"

  local worktree_desc=""
  if [[ -n "$worktree_path" ]]; then
    worktree_desc="\\nIMPORTANT: Use git worktree at: ${worktree_path}"
  fi

  jq -n --arg task "$task" --arg phases_dir "$phases_dir" \
    --arg loop "$loop" --arg worktree_desc "$worktree_desc" '[
    {
      "phaseId": "A5-nurse",
      "subject": "A5 Nurse: Update documentation",
      "description": ("Update documentation for completed work (loop " + $loop + "): " + $task + "\nInput: " + $phases_dir + "/A3-build.json\nOutput: " + $phases_dir + "/A5-docs.json" + $worktree_desc),
      "activeForm": "Updating documentation",
      "agentType": "ants:nurse",
      "blockedBy": ["A3-arbiter"]
    },
    {
      "phaseId": "A5-drone",
      "subject": "A5 Drone: Commit and ship",
      "description": ("Commit changes and open PR (loop " + $loop + "): " + $task + "\nInput: " + $phases_dir + "/A5-docs.json\nOutput: " + $phases_dir + "/A5-ship.json" + $worktree_desc),
      "activeForm": "Committing and shipping",
      "agentType": "ants:drone",
      "blockedBy": ["A5-nurse"]
    }
  ]'
}

# ---------------------------------------------------------------------------
# teams_create_pswarm_run_tasks
# ---------------------------------------------------------------------------
# Wrapper that generates a fresh task graph for pswarm run boundaries.
# Reads pipeline from state.json and delegates to the appropriate function.
#
# Logic:
#   1. Read pipeline from state.json (swarm or sswarm)
#   2. If sswarm: call teams_create_sswarm_tasks()
#   3. If swarm/pswarm: call teams_create_phase_tasks()
#   4. Return output
#
# Output: JSON array printed to stdout.
#
# Usage:
#   local run_tasks
#   run_tasks="$(teams_create_pswarm_run_tasks)"
# ---------------------------------------------------------------------------
teams_create_pswarm_run_tasks() {
  local pipeline
  pipeline="$(state_get '.pipeline // "swarm"')"

  local pswarm_run
  pswarm_run="$(state_get '.pswarmRun // 1')"

  local max_runs
  max_runs="$(state_get '.maxRuns // 50')"

  teams_log "Creating pswarm run tasks (pipeline=$pipeline, run=$pswarm_run/$max_runs)"

  local tasks_json
  case "$pipeline" in
    sswarm)
      tasks_json="$(teams_create_sswarm_tasks)"
      ;;
    *)
      tasks_json="$(teams_create_phase_tasks)"
      ;;
  esac

  # Add pswarmRun metadata to each task description
  printf '%s' "$tasks_json" | jq --arg run "$pswarm_run" --arg max "$max_runs" '
    map(.description = .description + "\n[pswarm run " + $run + "/" + $max + "]")
  '
}

# ---------------------------------------------------------------------------
# teams_get_a3_task_prompt
# ---------------------------------------------------------------------------
# Helper for worker-specific prompts from task pool state.
# Reads the claimed task descriptor from state.json taskPool[] and generates
# a full prompt for the worker agent.
#
# Arguments:
#   $1 -- task ID (e.g., "T1", "auth-module")
#
# Returns: formatted prompt string with task description, files, acceptance
# criteria, and output directory path.
#
# Usage:
#   local prompt
#   prompt="$(teams_get_a3_task_prompt "T1")"
# ---------------------------------------------------------------------------
teams_get_a3_task_prompt() {
  local task_id="${1:?teams_get_a3_task_prompt requires a task ID}"

  local loop
  loop="$(state_get '.loop // 1')"
  loop=$(require_int "$loop" "loop")

  local phases_dir=".agents/tmp/phases/loop-${loop}"

  # Read the task descriptor from the task pool
  local task_json
  task_json=$(jq -r --arg tid "$task_id" '
    .taskPool[] | select(.id == $tid)
  ' "$STATE_FILE" 2>/dev/null) || {
    teams_log "WARNING: jq failed reading taskPool for task $task_id from state.json"
    task_json=""
  }

  if [[ -z "$task_json" ]]; then
    teams_log "ERROR: Task $task_id not found in task pool"
    return 1
  fi

  # Batch-read task fields in a single jq call
  local task_fields
  task_fields=$(printf '%s' "$task_json" | jq -r '[
    (.description // "No description"),
    ((.files_owned // []) | join(", ")),
    (.acceptance_criteria // "See plan"),
    ((.dependencies // []) | join(", "))
  ] | join("\t")')
  local task_desc task_files task_criteria task_deps
  IFS=$'\t' read -r task_desc task_files task_criteria task_deps <<< "$task_fields"

  # Read A1 tasks file for extended description if available
  local extended_desc=""
  local tasks_file="${phases_dir}/A1-tasks.json"
  if [[ -f "$tasks_file" ]]; then
    local ext
    ext=$(jq -r --arg tid "$task_id" '
      .[] | select(.id == $tid) |
      "Full description: " + (.description // "") +
      (if .notes then "\nNotes: " + .notes else "" end)
    ' "$tasks_file" 2>/dev/null || echo "")
    if [[ -n "$ext" ]]; then
      extended_desc="$ext"
    fi
  fi

  # Build task context JSON for teams_build_teammate_prompt
  local task_context
  task_context=$(jq -n \
    --arg id "$task_id" \
    --arg desc "$task_desc" \
    --arg files "$task_files" \
    --arg criteria "$task_criteria" \
    --arg deps "$task_deps" \
    --arg extended "$extended_desc" \
    '{
      "taskId": $id,
      "description": $desc,
      "files_owned": $files,
      "acceptance_criteria": $criteria,
      "dependencies": $deps,
      "extended_description": $extended
    }')

  teams_build_teammate_prompt "A3" "$task_context"
}

# ---------------------------------------------------------------------------
# teams_build_teammate_prompt
# ---------------------------------------------------------------------------
# Generates a direct execution prompt for a teammate. Produces a prompt for
# the teammate to execute the work directly, with optional task-specific
# context for A3 workers and sswarm competing agents.
#
# Arguments:
#   $1 -- phase ID (A0, A1, A2, A3, A4, A5)
#   $2 -- (optional) task context JSON string with task-specific metadata
#
# Usage:
#   local prompt
#   prompt="$(teams_build_teammate_prompt "A1")"
#   prompt="$(teams_build_teammate_prompt "A3" "$task_context_json")"
# ---------------------------------------------------------------------------
teams_build_teammate_prompt() {
  local phase="${1:?teams_build_teammate_prompt requires a phase ID}"
  local task_context="${2:-}"

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

  # A0 output is top-level (not loop-scoped) so exploration persists across loops.
  # All other phases write to the loop-scoped directory.
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
      local known_agents='["architect","blueprint-reviewer","bug-scout","cartographer","drone","explore-aggregator","fix-worker","forager","guardian","nurse","plan-arbiter","queen","review-arbiter","review-fixer","review-lead","sentinel-correctness","sentinel-perf","sentinel-security","sentinel-style","simplifier","solution-aggregator","solution-proposer","worker"]'
      formatted_messages="$(printf '%s' "$messages_json" | jq -r --argjson allowed "$known_agents" '.[] | "- From \(if .from and (.from | IN($allowed[])) then .from else "unknown" end) (loop \(.loop // 0)): \(.content // "" | tostring | gsub("[\\u0000-\\u001f]"; "") | sub("^#+"; "") | .[0:2000])"' 2>/dev/null || { echo "WARNING: Failed to format messages for phase agent" >&2; echo "(Message formatting failed -- check .agents/tmp/state.json .messages array directly)"; })"
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

  # Task-specific context for A3 workers
  local worker_context=""
  if [[ "$phase" == "A3" && -n "$task_context" ]]; then
    # Batch-read worker task fields in a single jq call
    local tc_fields
    tc_fields=$(printf '%s' "$task_context" | jq -r '[
      (.taskId // ""),
      (.description // ""),
      (.files_owned // ""),
      (.acceptance_criteria // ""),
      (.extended_description // "")
    ] | join("\t")' 2>/dev/null || {
      echo "WARNING: Failed to parse worker task context JSON" >&2
      echo ""
    })
    local tc_id tc_desc tc_files tc_criteria tc_extended
    IFS=$'\t' read -r tc_id tc_desc tc_files tc_criteria tc_extended <<< "$tc_fields"

    if [[ -n "$tc_id" ]]; then
      worker_context="## Worker Task Assignment

Task ID: ${tc_id}
Description: ${tc_desc}
Files to modify: ${tc_files}
Acceptance criteria: ${tc_criteria}
${tc_extended:+
Extended details: ${tc_extended}
}
Output directory: ${phases_dir}
Include your taskId in all output JSON."
    fi
  fi

  # Competitor context for sswarm competing tasks
  local competitor_context=""
  if [[ -n "$task_context" ]]; then
    # Batch-read competitor fields in a single jq call
    local comp_fields
    comp_fields=$(printf '%s' "$task_context" | jq -r '[
      (.competitorIndex // ""),
      (.outputFile // ""),
      (.inputFiles // "")
    ] | join("\t")' 2>/dev/null || {
      echo "WARNING: Failed to parse competitor/consolidator task context JSON" >&2
      echo ""
    })
    local comp_index comp_output comp_input_files
    IFS=$'\t' read -r comp_index comp_output comp_input_files <<< "$comp_fields"

    if [[ -n "$comp_index" ]]; then
      competitor_context="## Competing Agent Context

You are competitor ${comp_index}. Write your output to: ${comp_output}
Your work will be evaluated alongside other competitors by a consolidator."
    fi

    # Consolidator context (overrides competitor context if present)
    if [[ -n "$comp_input_files" ]]; then
      competitor_context="## Consolidator Context

Read all competitor outputs and produce a unified result.
Input files: ${comp_input_files}"
    fi
  fi

  # Note: Unquoted heredoc is safe for ${task} because bash variable expansion
  # does NOT re-evaluate the expanded value for command substitution.
  cat <<PROMPT
## Ants Colony -- Phase ${phase} -- Loop ${loop}

# BEGIN USER TASK
Task: ${task}
# END USER TASK
${prev_context:+
${prev_context}
}${messages_context:+
${messages_context}
}${worktree_context:+
${worktree_context}
}${worker_context:+
${worker_context}
}${competitor_context:+
${competitor_context}
}
Input files:
${input_files}
$(if [[ -z "$worker_context" ]]; then echo "
Output: ${phases_dir}/${output_file}"; fi)

Create the directory first: mkdir -p ${phases_dir}

## File-Based Output

Write your results to the output file path above. Other agents read your
output files directly via task dependency chains (blockedBy). Files are the
source of truth -- hooks validate file existence.

After writing your output file, use SendMessage to send a brief summary to
the team or relevant agent. SendMessage is used for live coordination so
teammates stay informed without polling files.

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
        printf '\n%s\n' 'Web search is enabled -- use WebSearch to research library ecosystems, discover relevant external APIs, and gather external context for the task.'
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
        printf '\n%s\n' 'Web search is enabled -- use WebSearch to research libraries, frameworks, and external APIs when evaluating implementation approaches.'
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

After implementation, self-review the code for correctness, security, and performance.
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
#   $1 -- task prompt to assign
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
#   $1 -- reason for rejection
#
# Usage:
#   teams_reject_completion "Output file missing"
#   # then: exit 2
# ---------------------------------------------------------------------------
teams_reject_completion() {
  local reason="${1:?teams_reject_completion requires a reason}"
  echo "Task completion rejected: ${reason}" >&2
}
