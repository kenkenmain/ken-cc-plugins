#!/usr/bin/env bash
# task-pool.sh — Self-organizing task pool for A3 build phase.
# Replaces wave barriers with dependency-driven task dispatch.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/task-pool.sh"
#
# Task descriptor format in state.json .taskPool[]:
#   {
#     "id": "T1",
#     "description": "...",
#     "dependencies": [],
#     "files_owned": ["src/foo.ts"],
#     "status": "ready",       // pending | ready | claimed | complete | failed
#     "claimed_by": null
#   }
#
# Status lifecycle: pending -> ready -> claimed -> complete | failed
#
# Provides:
#   pool_init              — Initialize taskPool from architect's plan
#   pool_claim_task        — Atomically claim the first available task
#   pool_complete_task     — Mark task complete and recompute ready set
#   pool_fail_task         — Mark task as failed
#   pool_recompute_ready   — Promote pending tasks whose deps are all complete
#   pool_get_available     — List all ready, unclaimed tasks
#   pool_is_complete       — Check if all tasks are complete or failed
#   pool_get_file_owner    — Find which task (and claimer) owns a file path

set -euo pipefail

# ---------------------------------------------------------------------------
# Lock directory for task claims (mkdir-based atomic lock)
# ---------------------------------------------------------------------------
_POOL_LOCK_STALE_SECONDS=30

# Resolve lock dir at call time (not source time) so tests can override STATE_FILE.
_pool_lock_dir() {
  echo "${STATE_FILE:-.agents/tmp/state.json}.pool.lockdir"
}

# Acquire the pool lock. Returns 0 on success, 1 on failure.
# Callers MUST call _pool_unlock after the critical section.
_pool_lock() {
  local lock_dir
  lock_dir="$(_pool_lock_dir)"
  local attempt
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if mkdir "$lock_dir" 2>/dev/null; then
      return 0
    fi

    # Check for stale lock
    if [[ -d "$lock_dir" ]]; then
      local lock_mtime
      if lock_mtime=$(lock_dir_mtime_epoch "$lock_dir"); then
        local now
        now=$(date +%s)
        local lock_age
        lock_age=$(( now - lock_mtime ))
        if [[ "$lock_age" -gt "$_POOL_LOCK_STALE_SECONDS" ]]; then
          echo "WARNING: Removing stale pool lock (age: ${lock_age}s)" >&2
          rm -rf "$lock_dir"
          if mkdir "$lock_dir" 2>/dev/null; then
            return 0
          fi
        fi
      fi
    fi

    sleep 0.5
  done

  echo "ERROR: Could not acquire pool lock after 5 seconds" >&2
  return 1
}

# Release the pool lock.
_pool_unlock() {
  rm -rf "$(_pool_lock_dir)" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# pool_init — Initialize taskPool array in state from architect's plan.
# Reads A1-tasks.json from the current loop's phases directory and writes
# the task descriptors into state.json .taskPool[].
# Tasks with no dependencies start as "ready"; others start as "pending".
#
# Usage: pool_init
# ---------------------------------------------------------------------------
pool_init() {
  local loop
  loop="$(state_get '.loop // 1')"
  loop=$(require_int "$loop" "loop")

  local tasks_file=".agents/tmp/phases/loop-${loop}/A1-tasks.json"

  if [[ ! -f "$tasks_file" ]]; then
    echo "ERROR: Task descriptor file not found: $tasks_file" >&2
    return 1
  fi

  if ! jq empty "$tasks_file" 2>/dev/null; then
    echo "ERROR: Invalid JSON in $tasks_file" >&2
    return 1
  fi

  # Transform architect's tasks into pool format.
  # Tasks with empty dependencies[] start as "ready", others as "pending".
  local pool_json
  pool_json=$(jq '[.[] | {
    id: .id,
    description: .description,
    dependencies: (.dependencies // []),
    files_owned: (.files_owned // []),
    status: (if (.dependencies // []) | length == 0 then "ready" else "pending" end),
    claimed_by: null
  }]' "$tasks_file")

  # Validate we got a non-empty array
  local count
  count=$(echo "$pool_json" | jq 'length')
  if [[ "$count" == "0" ]]; then
    echo "ERROR: No tasks found in $tasks_file" >&2
    return 1
  fi

  # Check for duplicate task IDs
  local dupes
  dupes=$(echo "$pool_json" | jq '[.[].id] | group_by(.) | map(select(length > 1)) | length')
  if [[ "$dupes" != "0" ]]; then
    echo "ERROR: Duplicate task IDs found in $tasks_file" >&2
    return 1
  fi

  # Check for references to non-existent dependencies
  local bad_deps
  bad_deps=$(echo "$pool_json" | jq '
    [.[].id] as $ids |
    [.[] | .dependencies[] | select(. as $d | $ids | index($d) | not)] |
    length
  ')
  if [[ "$bad_deps" != "0" ]]; then
    echo "ERROR: Tasks reference non-existent dependency IDs in $tasks_file" >&2
    return 1
  fi

  if ! update_state --argjson pool "$pool_json" '.taskPool = $pool'; then
    echo "ERROR: Failed to write taskPool to state" >&2
    return 1
  fi

  echo "Initialized task pool with $count tasks" >&2
  return 0
}

# ---------------------------------------------------------------------------
# pool_claim_task — Atomically claim the first available task.
# A task is available when status == "ready" and claimed_by == null.
# Uses mkdir-based locking for atomicity.
#
# Usage: task_id=$(pool_claim_task "worker-1") || echo "none available"
# Arguments: $1 = claimer identifier (e.g., agent name or worker ID)
# Stdout: task ID on success
# Returns: 0 on success, 1 if no task available
# ---------------------------------------------------------------------------
pool_claim_task() {
  local claimer="${1:?pool_claim_task requires a claimer identifier}"

  _pool_lock || return 1

  # Find first ready, unclaimed task
  local task_id
  task_id=$(jq -r '
    [.taskPool[] | select(.status == "ready" and .claimed_by == null)] |
    first | .id // empty
  ' "$STATE_FILE")

  if [[ -z "$task_id" ]]; then
    _pool_unlock
    return 1
  fi

  # Claim it
  local claim_ok=true
  if ! update_state --arg tid "$task_id" --arg cl "$claimer" '
    .taskPool |= map(
      if .id == $tid then .status = "claimed" | .claimed_by = $cl
      else . end
    )
  '; then
    claim_ok=false
  fi

  _pool_unlock

  if [[ "$claim_ok" != "true" ]]; then
    echo "ERROR: Failed to claim task $task_id" >&2
    return 1
  fi

  echo "$task_id"
  return 0
}

# ---------------------------------------------------------------------------
# pool_complete_task — Mark a task as complete, then recompute ready set.
#
# Usage: pool_complete_task "T1"
# Returns: 0 on success, 1 on failure
# ---------------------------------------------------------------------------
pool_complete_task() {
  local task_id="${1:?pool_complete_task requires a task ID}"

  # Verify task exists and is claimed
  local current_status
  current_status=$(jq -r --arg tid "$task_id" '
    .taskPool[] | select(.id == $tid) | .status // empty
  ' "$STATE_FILE")

  if [[ -z "$current_status" ]]; then
    echo "ERROR: Task $task_id not found in pool" >&2
    return 1
  fi

  if [[ "$current_status" != "claimed" ]]; then
    echo "WARNING: Task $task_id has status '$current_status', expected 'claimed'. Completing anyway." >&2
  fi

  if ! update_state --arg tid "$task_id" '
    .taskPool |= map(
      if .id == $tid then .status = "complete"
      else . end
    )
  '; then
    echo "ERROR: Failed to complete task $task_id" >&2
    return 1
  fi

  # Recompute which pending tasks are now ready
  pool_recompute_ready
}

# ---------------------------------------------------------------------------
# pool_fail_task — Mark a task as failed.
# Does NOT recompute ready set (failed deps block dependents).
#
# Usage: pool_fail_task "T2" "compilation error"
# Returns: 0 on success, 1 on failure
# ---------------------------------------------------------------------------
pool_fail_task() {
  local task_id="${1:?pool_fail_task requires a task ID}"
  local reason="${2:-unknown}"

  local current_status
  current_status=$(jq -r --arg tid "$task_id" '
    .taskPool[] | select(.id == $tid) | .status // empty
  ' "$STATE_FILE")

  if [[ -z "$current_status" ]]; then
    echo "ERROR: Task $task_id not found in pool" >&2
    return 1
  fi

  if ! update_state --arg tid "$task_id" --arg reason "$reason" '
    .taskPool |= map(
      if .id == $tid then .status = "failed" | .failure_reason = $reason
      else . end
    )
  '; then
    echo "ERROR: Failed to mark task $task_id as failed" >&2
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# pool_recompute_ready — Find all pending tasks whose dependencies are all
# complete. Set their status to "ready".
#
# Usage: pool_recompute_ready
# Returns: 0 always (idempotent)
# ---------------------------------------------------------------------------
pool_recompute_ready() {
  # Use a single jq pass: collect complete IDs, then update pending tasks
  # whose dependencies are a subset of the complete set.
  if ! update_state '
    (.taskPool | map(select(.status == "complete")) | map(.id)) as $done |
    .taskPool |= map(
      if .status == "pending" and
         (.dependencies | length > 0) and
         (.dependencies | all(. as $d | $done | index($d) | . != null))
      then .status = "ready"
      elif .status == "pending" and (.dependencies | length == 0)
      then .status = "ready"
      else . end
    )
  '; then
    echo "ERROR: Failed to recompute ready set" >&2
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# pool_get_available — List all tasks with status == "ready" and no claimer.
# Outputs JSON array of task objects.
#
# Usage: available=$(pool_get_available)
# Returns: JSON array (may be empty [])
# ---------------------------------------------------------------------------
pool_get_available() {
  jq '[.taskPool[] | select(.status == "ready" and .claimed_by == null)]' "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# pool_is_complete — Return 0 if all tasks are complete or failed
# (i.e., no tasks remain in pending, ready, or claimed status).
#
# Usage: if pool_is_complete; then echo "done"; fi
# Returns: 0 if complete, 1 if tasks remain
# ---------------------------------------------------------------------------
pool_is_complete() {
  local remaining
  remaining=$(jq '
    [.taskPool[] | select(.status == "pending" or .status == "ready" or .status == "claimed")] | length
  ' "$STATE_FILE")

  [[ "$remaining" == "0" ]]
}

# ---------------------------------------------------------------------------
# pool_get_file_owner — Given a file path, find which task owns it.
# Outputs JSON: {"task_id": "T1", "claimed_by": "worker-1"} or empty string.
#
# Usage: owner=$(pool_get_file_owner "src/foo.ts")
# Returns: 0 if owner found (JSON on stdout), 1 if no owner
# ---------------------------------------------------------------------------
pool_get_file_owner() {
  local file_path="${1:?pool_get_file_owner requires a file path}"

  local result
  result=$(jq -r --arg fp "$file_path" '
    [.taskPool[] | select(.files_owned[]? == $fp)] |
    first |
    if . then {task_id: .id, claimed_by: .claimed_by} | tojson
    else empty end
  ' "$STATE_FILE")

  if [[ -z "$result" ]]; then
    return 1
  fi

  echo "$result"
  return 0
}
