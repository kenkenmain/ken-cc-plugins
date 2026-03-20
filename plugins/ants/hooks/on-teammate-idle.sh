#!/usr/bin/env bash
# on-teammate-idle.sh -- Full task router for Agent Teams delegate mode (v0.6)
#
# Fires when a teammate goes idle. Routes the next ready task to the idle
# teammate by building a phase-specific prompt and returning it via exit 2.
#
# Routing logic:
#   - Sequential phases (A0, A1, A2, A5): single-agent dispatch with
#     atomic in_progress claim to prevent double-dispatch
#   - A3: dual-track routing -- worker tasks from the task pool (build
#     track), then quality agents (sentinels, guardian, simplifier),
#     then review-arbiter
#   - A4: no direct dispatch (verdict evaluated inline by TaskCompleted
#     hook when A3 arbiter completes)
#   - sswarm A1/A2: competing agent dispatch (3 parallel + 1 consolidator)
#   - pswarm: run-boundary safety net (core logic in TaskCompleted hook)
#
# Exit paths:
#   exit 0: allow idle (no work, complete/stopped/blocked/shutdown/waiting)
#   exit 2 + stderr: assign work (next ready task found)
# Never blocks indefinitely. Every path either assigns work or allows idle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
source "$SCRIPT_DIR/lib/teams.sh"
source "$SCRIPT_DIR/lib/swarm.sh"
source "$SCRIPT_DIR/lib/dag.sh"
source "$SCRIPT_DIR/lib/task-pool.sh"

check_ants_workflow

# Consume stdin (Agent Teams passes hook input JSON) -- cap at 1MB.
# The input is not used; all routing data comes from state.json.
# Stdin must be consumed to prevent pipe buffer issues.
head -c 1048576 > /dev/null

# ---------------------------------------------------------------------------
# Batch-read all needed state fields in a single jq call
# v5/v6 compat: teamCreated falls back to queenDispatched for v5 state files
# ---------------------------------------------------------------------------
if ! local_fields=$(jq -r '[
  (.shutdown // false | tostring),
  (.status // "unknown"),
  (.currentPhase // "DONE"),
  (.task // ""),
  ((.loop // 1) | tostring),
  (.pipeline // "swarm"),
  ((.teamCreated // .queenDispatched // false) | tostring),
  ((.maxLoops // 5) | tostring)
] | join("\t")' "$STATE_FILE" 2>"${STATE_FILE}.idle-err"); then
  jq_err_output=$(cat "${STATE_FILE}.idle-err" 2>/dev/null || echo "unknown error")
  rm -f "${STATE_FILE}.idle-err"
  echo "[TEAMS] ERROR: Failed to read state.json (${jq_err_output}), allowing idle" >&2
  exit 0
fi
rm -f "${STATE_FILE}.idle-err" 2>/dev/null
IFS=$'\t' read -r shutdown_flag status current_phase task loop pipeline team_created max_loops <<< "$local_fields"

# ===========================================================================
# Precondition checks
# ===========================================================================

# Shutdown check
if [[ "$shutdown_flag" == "true" ]]; then
  teams_log "Shutdown flag set, allowing idle (graceful shutdown)"
  exit 0
fi

# Status check -- terminal states allow idle
case "$status" in
  complete|blocked|stopped)
    teams_log "Workflow status is ${status}, allowing idle"
    exit 0
    ;;
esac

# Circuit breaker check
if cb_is_tripped; then
  teams_log "Circuit breaker tripped, blocking workflow"
  if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Circuit breaker tripped: too many consecutive failures"'; then
    echo "ERROR: Failed to update state to blocked after circuit breaker trip." >&2
    exit 2
  fi
  exit 0
fi

# Terminal phase check
case "$current_phase" in
  DONE|STOPPED|BLOCKED)
    teams_log "Phase is ${current_phase}, allowing idle"
    exit 0
    ;;
esac

# pswarm run-boundary safety net
if [[ "$pipeline" == "pswarm" ]]; then
  local_pswarm=$(jq -r '[((.pswarmRun // 1) | tostring), ((.maxRuns // 50) | tostring)] | join("\t")' "$STATE_FILE" 2>/dev/null || { echo "WARNING: Failed to read pswarm fields from state.json, using defaults" >&2; echo "1	50"; })
  IFS=$'\t' read -r pswarm_run max_runs <<< "$local_pswarm"
  pswarm_run=$(require_int "$pswarm_run" "pswarmRun")
  max_runs=$(require_int "$max_runs" "maxRuns")
  if [[ "$pswarm_run" -gt "$max_runs" ]]; then
    teams_log "pswarm run ${pswarm_run} exceeds maxRuns ${max_runs}, completing workflow"
    if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts'; then
      echo "ERROR: Failed to mark workflow complete at pswarm run limit" >&2
      exit 2
    fi
    exit 0
  fi
fi

# Validate task field
if [[ -z "$task" ]]; then
  echo "ERROR: state.json field '.task' is missing or empty. Workflow state is incomplete." >&2
  exit 2
fi

# Sanitize task description before interpolation into prompts.
# Note: ${task} in unquoted heredocs is safe because bash variable expansion
# does NOT re-evaluate the expanded value for command substitution. A task
# containing '$(cmd)' or backticks expands to the literal string, not executed.
task="$(printf '%s' "$task" | head -c 2000 | tr -d '\000-\031')"

# Validate loop
loop=$(require_int "$loop" "loop")

# Resolve phases directory
phases_dir=".agents/tmp/phases/loop-${loop}"

# ===========================================================================
# Helper: dispatch_phase -- atomic claim + prompt for sequential phases
# ===========================================================================
# For phases A0, A1, A2, A5 (single-agent sequential dispatch).
# Checks if the phase is pending, atomically marks it in_progress,
# builds the prompt, and exits 2 to assign work.
#
# Arguments:
#   $1 -- phase ID (A0, A1, A2, A5)
#   $2 -- (optional) task context JSON for prompt builder
dispatch_phase() {
  local phase="$1"
  local task_ctx="${2:-}"

  local phase_status
  phase_status=$(jq -r --arg p "$phase" '.phases[$p].status // "pending"' "$STATE_FILE" 2>/dev/null || {
    teams_log "WARNING: Failed to read phase $phase status from state.json, allowing idle"
    exit 0
  })

  case "$phase_status" in
    complete)
      teams_log "Phase $phase already complete, allowing idle"
      exit 0
      ;;
    in_progress)
      # Another teammate already claimed this phase
      teams_log "Phase $phase already in_progress (claimed by another teammate), allowing idle"
      exit 0
      ;;
    pending)
      # Atomically mark phase as in_progress to prevent double-dispatch
      if ! update_state --arg p "$phase" \
        '.phases[$p].status = "in_progress" | .phases[$p].startedAt = $ts | .updatedAt = $ts'; then
        # Record failure to detect persistent state corruption
        cb_record_failure 2>/dev/null || true
        teams_log "WARNING: Failed to claim phase $phase (state update failed). If this persists, check state.json integrity."
        exit 0
      fi

      # Build prompt -- validate non-empty before dispatch
      local prompt
      if [[ -n "$task_ctx" ]]; then
        prompt="$(teams_build_teammate_prompt "$phase" "$task_ctx")" || true
      else
        prompt="$(teams_build_teammate_prompt "$phase")" || true
      fi

      if [[ -z "$prompt" ]]; then
        teams_log "ERROR: teams_build_teammate_prompt returned empty for phase $phase"
        cb_record_failure 2>/dev/null || true
        # Roll back phase to pending so another idle event can retry
        update_state --arg p "$phase" '.phases[$p].status = "pending" | .updatedAt = $ts' 2>/dev/null || true
        exit 0
      fi

      teams_log "Dispatching phase $phase to idle teammate"
      teams_assign_idle_teammate "$prompt"
      exit 2
      ;;
    *)
      teams_log "Phase $phase has unexpected status '${phase_status}', allowing idle"
      exit 0
      ;;
  esac
}

# ===========================================================================
# Helper: dispatch_a3_task -- dual-track A3 routing
# ===========================================================================
# Routes idle teammates to A3 sub-tasks:
#   Sub-phase 1 (build track): claim worker tasks from the pool
#   Sub-phase 2 (quality track): dispatch sentinels, guardian, simplifier
#   Sub-phase 3 (consolidation): dispatch review-arbiter after all quality done
dispatch_a3_task() {
  local build_complete
  build_complete=$(jq -r '.phases.A3.buildTrackComplete // false' "$STATE_FILE" 2>/dev/null || {
    teams_log "WARNING: Failed to read A3 buildTrackComplete from state.json, allowing idle"
    exit 0
  })

  # --- Sub-phase 1: Worker tasks (build track) ---
  if [[ "$build_complete" != "true" ]]; then
    # Try to claim a ready task from the pool
    local task_id
    if task_id=$(pool_claim_task "teammate-$$"); then
      # Build worker-specific prompt -- validate non-empty before dispatch
      local prompt
      prompt="$(teams_get_a3_task_prompt "$task_id")" || true

      if [[ -z "$prompt" ]]; then
        teams_log "ERROR: teams_get_a3_task_prompt returned empty for task $task_id"
        pool_fail_task "$task_id" "prompt generation failed" 2>/dev/null || true
        cb_record_failure 2>/dev/null || true
        exit 0
      fi

      teams_log "Dispatching A3 worker task ${task_id} to idle teammate"
      teams_assign_idle_teammate "$prompt"
      exit 2
    fi

    # No ready tasks but build not complete -- workers still running
    teams_log "A3 build track: no ready tasks available, allowing idle"
    exit 0
  fi

  # --- Sub-phase 2: Quality track agents ---
  dispatch_a3_quality
}

# ===========================================================================
# Helper: dispatch_a3_quality -- quality track dispatch
# ===========================================================================
# Dispatches sentinels, guardian, simplifier in parallel using marker files
# to prevent double-dispatch. After all quality agents complete, dispatches
# the review-arbiter.
dispatch_a3_quality() {
  local marker_dir="${phases_dir}"
  mkdir -p "$marker_dir"

  # Quality agents to dispatch (parallel)
  local quality_agents=("sentinel-correctness" "sentinel-security" "sentinel-perf" "sentinel-style" "guardian" "simplifier")

  # Track completion
  local all_quality_done=true

  for agent in "${quality_agents[@]}"; do
    local dispatched_marker="${marker_dir}/.${agent}.dispatched"
    local done_marker="${marker_dir}/.${agent}.done"

    if [[ -f "$done_marker" ]]; then
      # This agent already completed
      continue
    fi

    all_quality_done=false

    if [[ -f "$dispatched_marker" ]]; then
      # Already dispatched but not done -- skip (it is running)
      continue
    fi

    # Atomic dispatch claim via mkdir (prevents double-dispatch)
    local lock_marker="${marker_dir}/.${agent}.dispatch-lock"
    if ! mkdir "$lock_marker" 2>/dev/null; then
      # Check for stale lock (>120s old) -- if the script crashed between mkdir and rm,
      # the lock persists and the agent can never be dispatched.
      if [[ -d "$lock_marker" ]]; then
        local lock_mtime
        if lock_mtime=$(lock_dir_mtime_epoch "$lock_marker"); then
          local lock_age
          lock_age=$(( $(date +%s) - lock_mtime ))
          if [[ "$lock_age" -gt 120 ]]; then
            teams_log "WARNING: Removing stale dispatch-lock for ${agent} (age: ${lock_age}s)"
            rm -rf "$lock_marker"
            if ! mkdir "$lock_marker" 2>/dev/null; then
              continue
            fi
          else
            continue
          fi
        else
          continue
        fi
      else
        continue
      fi
    fi

    # Create dispatched marker atomically: write a file inside the lock dir,
    # then mv it to the marker path. This eliminates the TOCTOU window between
    # touch and rm where neither lock nor marker would be visible.
    touch "${lock_marker}/marker"
    mv "${lock_marker}/marker" "$dispatched_marker"
    rm -rf "$lock_marker" 2>/dev/null || true

    # Build quality agent prompt -- validate non-empty before dispatch
    local prompt
    prompt="$(build_a3_quality_prompt "$agent")" || true

    if [[ -z "$prompt" ]]; then
      teams_log "ERROR: build_a3_quality_prompt returned empty for agent $agent"
      rm -f "$dispatched_marker" 2>/dev/null || true
      exit 0
    fi

    teams_log "Dispatching A3 quality agent ${agent} to idle teammate"
    teams_assign_idle_teammate "$prompt"
    exit 2
  done

  if [[ "$all_quality_done" != "true" ]]; then
    # Some quality agents still running, no undispatched ones left
    teams_log "A3 quality track: all agents dispatched but not all complete, allowing idle"
    exit 0
  fi

  # --- Sub-phase 3: Review arbiter (all quality agents done) ---
  local arbiter_dispatched="${marker_dir}/.arbiter.dispatched"
  local arbiter_done="${marker_dir}/.arbiter.done"

  if [[ -f "$arbiter_done" ]]; then
    # Arbiter already completed -- A3 is fully done, waiting for phase transition
    teams_log "A3 arbiter already complete, allowing idle"
    exit 0
  fi

  if [[ -f "$arbiter_dispatched" ]]; then
    # Arbiter already dispatched
    teams_log "A3 arbiter already dispatched, allowing idle"
    exit 0
  fi

  # Dispatch arbiter with stale lock recovery (matching quality agent pattern)
  local arbiter_lock="${marker_dir}/.arbiter.dispatch-lock"
  if ! mkdir "$arbiter_lock" 2>/dev/null; then
    # Check for stale lock (>120s old)
    if [[ -d "$arbiter_lock" ]]; then
      local lock_mtime
      if lock_mtime=$(lock_dir_mtime_epoch "$arbiter_lock"); then
        local lock_age
        lock_age=$(( $(date +%s) - lock_mtime ))
        if [[ "$lock_age" -gt 120 ]]; then
          teams_log "WARNING: Removing stale arbiter dispatch-lock (age: ${lock_age}s)"
          rm -rf "$arbiter_lock"
          if ! mkdir "$arbiter_lock" 2>/dev/null; then
            teams_log "A3 arbiter dispatch race after stale lock removal, allowing idle"
            exit 0
          fi
        else
          teams_log "A3 arbiter dispatch race, allowing idle"
          exit 0
        fi
      else
        teams_log "A3 arbiter dispatch race, allowing idle"
        exit 0
      fi
    else
      teams_log "A3 arbiter dispatch race, allowing idle"
      exit 0
    fi
  fi

  # Create dispatched marker atomically (write inside lock, mv, rm)
  touch "${arbiter_lock}/marker"
  mv "${arbiter_lock}/marker" "$arbiter_dispatched"
  rm -rf "$arbiter_lock" 2>/dev/null || true

  local prompt
  prompt="$(build_a3_arbiter_prompt)" || true

  if [[ -z "$prompt" ]]; then
    teams_log "ERROR: build_a3_arbiter_prompt returned empty"
    rm -f "$arbiter_dispatched" 2>/dev/null || true
    exit 0
  fi

  teams_log "Dispatching A3 review-arbiter to idle teammate"
  teams_assign_idle_teammate "$prompt"
  exit 2
}

# ===========================================================================
# Helper: build_a3_quality_prompt -- prompt for quality track agents
# ===========================================================================
build_a3_quality_prompt() {
  local agent="$1"

  # Map agent name to subject and description in a single case block
  local subject="" agent_desc=""
  case "$agent" in
    sentinel-correctness)
      subject="A3 Sentinel Correctness: Review"
      agent_desc="Review the implementation for bugs, logic errors, missing error handling, and race conditions." ;;
    sentinel-security)
      subject="A3 Sentinel Security: Review"
      agent_desc="Review the implementation for OWASP top 10, injection, authentication, secrets exposure, and access control." ;;
    sentinel-perf)
      subject="A3 Sentinel Perf: Review"
      agent_desc="Review the implementation for N+1 queries, blocking I/O, unnecessary allocations, and algorithmic complexity." ;;
    sentinel-style)
      subject="A3 Sentinel Style: Review"
      agent_desc="Review the implementation for code style, readability, maintainability, excessive nesting, magic numbers, and dead code." ;;
    guardian)
      subject="A3 Guardian: Write tests"
      agent_desc="Write tests for the implemented code. Cover happy path, edge cases, and error paths." ;;
    simplifier)
      subject="A3 Simplifier: Code cleanup"
      agent_desc="Apply targeted code cleanup to worker outputs -- dead code removal, complexity reduction, over-engineering cleanup without behavioral changes." ;;
  esac

  # Determine the specific output filename for this agent
  local output_file=""
  case "$agent" in
    sentinel-correctness) output_file="A3-review.sentinel-correctness.json" ;;
    sentinel-security)    output_file="A3-review.sentinel-security.json" ;;
    sentinel-perf)        output_file="A3-review.sentinel-perf.json" ;;
    sentinel-style)       output_file="A3-review.sentinel-style.json" ;;
    guardian)             output_file="A3-guardian.json" ;;
    simplifier)           output_file="" ;; # simplifier uses Edit, no file output needed
  esac

  cat <<__ANTS_PROMPT_EOF__
## Ants Colony -- Phase A3 Quality Track -- Loop ${loop}

# BEGIN USER TASK
Task: ${task}
# END USER TASK
Subject: ${subject}
Agent: ${agent}

${agent_desc}

Input files:
- .agents/tmp/phases/loop-${loop}/A1-plan.md (implementation plan)
- .agents/tmp/phases/loop-${loop}/A1-tasks.json (task descriptors)
- .agents/tmp/phases/loop-${loop}/A3-build.json (list of files changed by workers)

Output directory: ${phases_dir}
${output_file:+Output: ${phases_dir}/${output_file}
}Create the directory first: mkdir -p ${phases_dir}

## File-Based Output

Write your results to the output file path above. Other agents read your
output files directly via task dependency chains (blockedBy). Files are the
source of truth -- hooks validate file existence.

After writing your output file, use SendMessage to notify the team with a
brief summary. SendMessage provides live coordination so teammates stay
informed without polling files.
__ANTS_PROMPT_EOF__
}

# ===========================================================================
# Helper: build_a3_arbiter_prompt -- prompt for review-arbiter
# ===========================================================================
build_a3_arbiter_prompt() {
  cat <<__ANTS_PROMPT_EOF__
## Ants Colony -- Phase A3 Review Arbiter -- Loop ${loop}

# BEGIN USER TASK
Task: ${task}
# END USER TASK

Cross-reference and deduplicate sentinel findings into a unified quality verdict.

Input files:
- ${phases_dir}/A3-review.sentinel-correctness.json
- ${phases_dir}/A3-review.sentinel-security.json
- ${phases_dir}/A3-review.sentinel-perf.json
- ${phases_dir}/A3-review.sentinel-style.json

Output: ${phases_dir}/A3-quality.json

Create the directory first: mkdir -p ${phases_dir}

Produce a JSON verdict with:
{
  "summary": {"verdict": "clean|issues_found", "total_issues": N},
  "issues": [{"severity": "critical|warning|info", "description": "...", "file": "...", "line": N}]
}

## File-Based Output

Write your consolidated verdict to A3-quality.json. The TaskCompleted hook
reads this file to evaluate the A4 verdict inline.
__ANTS_PROMPT_EOF__
}

# ===========================================================================
# Helper: dispatch_sswarm_a1 -- competing architect dispatch
# ===========================================================================
dispatch_sswarm_a1() {
  local phase_status
  phase_status=$(jq -r '.phases.A1.status // "pending"' "$STATE_FILE" 2>/dev/null || {
    teams_log "WARNING: Failed to read A1 status from state.json, allowing idle"
    exit 0
  })

  if [[ "$phase_status" == "complete" ]]; then
    teams_log "sswarm A1 already complete, allowing idle"
    exit 0
  fi

  # Mark A1 as in_progress if still pending
  if [[ "$phase_status" == "pending" ]]; then
    if ! update_state '.phases.A1.status = "in_progress" | .phases.A1.startedAt = $ts | .updatedAt = $ts'; then
      teams_log "Failed to claim A1 for sswarm, allowing idle"
      exit 0
    fi
  fi

  local marker_dir="${phases_dir}"
  mkdir -p "$marker_dir"

  # Dispatch 3 competing architects
  local slot
  for slot in 1 2 3; do
    local dispatched_marker="${marker_dir}/.architect.${slot}.dispatched"
    if [[ -f "$dispatched_marker" ]]; then
      continue
    fi

    # Atomic claim with stale lock recovery (>120s)
    local lock_marker="${marker_dir}/.architect.${slot}.dispatch-lock"
    if ! mkdir "$lock_marker" 2>/dev/null; then
      if [[ -d "$lock_marker" ]]; then
        local lm_mtime
        if lm_mtime=$(lock_dir_mtime_epoch "$lock_marker"); then
          local lm_age
          lm_age=$(( $(date +%s) - lm_mtime ))
          if [[ "$lm_age" -gt 120 ]]; then
            teams_log "WARNING: Removing stale architect.${slot} dispatch-lock (age: ${lm_age}s)"
            rm -rf "$lock_marker"
            if ! mkdir "$lock_marker" 2>/dev/null; then
              continue
            fi
          else
            continue
          fi
        else
          continue
        fi
      else
        continue
      fi
    fi
    # Create dispatched marker atomically (write inside lock, mv, rm)
    touch "${lock_marker}/marker"
    mv "${lock_marker}/marker" "$dispatched_marker"
    rm -rf "$lock_marker" 2>/dev/null || true

    local task_ctx
    task_ctx=$(jq -n \
      --arg idx "$slot" \
      --arg out "${phases_dir}/A1-plan.architect.${slot}.tmp" \
      --arg tasks_out "${phases_dir}/A1-tasks.architect.${slot}.tmp" \
      '{
        "competitorIndex": $idx,
        "outputFile": $out,
        "tasksOutputFile": $tasks_out
      }')

    local prompt
    prompt="$(teams_build_teammate_prompt "A1" "$task_ctx")" || true
    if [[ -z "$prompt" ]]; then
      teams_log "ERROR: teams_build_teammate_prompt returned empty for sswarm A1 architect ${slot}"
      rm -f "$dispatched_marker" 2>/dev/null || true
      exit 0
    fi
    teams_log "Dispatching sswarm A1 architect ${slot} to idle teammate"
    teams_assign_idle_teammate "$prompt"
    exit 2
  done

  # All 3 architects dispatched. Check if plan-arbiter needs dispatch.
  local arbiter_dispatched="${marker_dir}/.plan-arbiter.dispatched"
  if [[ -f "$arbiter_dispatched" ]]; then
    teams_log "sswarm A1 plan-arbiter already dispatched, allowing idle"
    exit 0
  fi

  # Check if all 3 architect outputs exist
  local all_done=true
  for slot in 1 2 3; do
    if [[ ! -f "${phases_dir}/A1-plan.architect.${slot}.tmp" ]]; then
      all_done=false
      break
    fi
  done

  if [[ "$all_done" != "true" ]]; then
    teams_log "sswarm A1: waiting for architect outputs, allowing idle"
    exit 0
  fi

  # Dispatch plan-arbiter
  if mkdir "${marker_dir}/.plan-arbiter.dispatch-lock" 2>/dev/null; then
    touch "$arbiter_dispatched"
    rm -rf "${marker_dir}/.plan-arbiter.dispatch-lock" 2>/dev/null || true

    local task_ctx
    task_ctx=$(jq -n \
      --arg in1 "${phases_dir}/A1-plan.architect.1.tmp" \
      --arg in2 "${phases_dir}/A1-plan.architect.2.tmp" \
      --arg in3 "${phases_dir}/A1-plan.architect.3.tmp" \
      '{"inputFiles": ($in1 + "\n" + $in2 + "\n" + $in3)}')

    local prompt
    prompt="$(teams_build_teammate_prompt "A1" "$task_ctx")" || true
    if [[ -z "$prompt" ]]; then
      teams_log "ERROR: teams_build_teammate_prompt returned empty for sswarm A1 plan-arbiter"
      rm -f "$arbiter_dispatched" 2>/dev/null || true
      exit 0
    fi
    teams_log "Dispatching sswarm A1 plan-arbiter to idle teammate"
    teams_assign_idle_teammate "$prompt"
    exit 2
  fi

  teams_log "sswarm A1 plan-arbiter dispatch race, allowing idle"
  exit 0
}

# ===========================================================================
# Helper: dispatch_sswarm_a2 -- competing reviewer dispatch
# ===========================================================================
dispatch_sswarm_a2() {
  local phase_status
  phase_status=$(jq -r '.phases.A2.status // "pending"' "$STATE_FILE" 2>/dev/null || {
    teams_log "WARNING: Failed to read A2 status from state.json, allowing idle"
    exit 0
  })

  if [[ "$phase_status" == "complete" ]]; then
    teams_log "sswarm A2 already complete, allowing idle"
    exit 0
  fi

  # Mark A2 as in_progress if still pending
  if [[ "$phase_status" == "pending" ]]; then
    if ! update_state '.phases.A2.status = "in_progress" | .phases.A2.startedAt = $ts | .updatedAt = $ts'; then
      teams_log "Failed to claim A2 for sswarm, allowing idle"
      exit 0
    fi
  fi

  local marker_dir="${phases_dir}"
  mkdir -p "$marker_dir"

  # Dispatch 3 competing reviewers
  local slot
  for slot in 1 2 3; do
    local dispatched_marker="${marker_dir}/.reviewer.${slot}.dispatched"
    if [[ -f "$dispatched_marker" ]]; then
      continue
    fi

    # Atomic claim with stale lock recovery (>120s)
    local lock_marker="${marker_dir}/.reviewer.${slot}.dispatch-lock"
    if ! mkdir "$lock_marker" 2>/dev/null; then
      if [[ -d "$lock_marker" ]]; then
        local lm_mtime
        if lm_mtime=$(lock_dir_mtime_epoch "$lock_marker"); then
          local lm_age
          lm_age=$(( $(date +%s) - lm_mtime ))
          if [[ "$lm_age" -gt 120 ]]; then
            teams_log "WARNING: Removing stale reviewer.${slot} dispatch-lock (age: ${lm_age}s)"
            rm -rf "$lock_marker"
            if ! mkdir "$lock_marker" 2>/dev/null; then
              continue
            fi
          else
            continue
          fi
        else
          continue
        fi
      else
        continue
      fi
    fi
    # Create dispatched marker atomically (write inside lock, mv, rm)
    touch "${lock_marker}/marker"
    mv "${lock_marker}/marker" "$dispatched_marker"
    rm -rf "$lock_marker" 2>/dev/null || true

    local task_ctx
    task_ctx=$(jq -n \
      --arg idx "$slot" \
      --arg out "${phases_dir}/A2-review.reviewer.${slot}.tmp" \
      --arg plan "${phases_dir}/A1-plan.md" \
      '{
        "competitorIndex": $idx,
        "outputFile": $out,
        "inputPlan": $plan
      }')

    local prompt
    prompt="$(teams_build_teammate_prompt "A2" "$task_ctx")" || true
    if [[ -z "$prompt" ]]; then
      teams_log "ERROR: teams_build_teammate_prompt returned empty for sswarm A2 reviewer ${slot}"
      rm -f "$dispatched_marker" 2>/dev/null || true
      exit 0
    fi
    teams_log "Dispatching sswarm A2 reviewer ${slot} to idle teammate"
    teams_assign_idle_teammate "$prompt"
    exit 2
  done

  # All 3 reviewers dispatched. Check if review-lead needs dispatch.
  local lead_dispatched="${marker_dir}/.review-lead.dispatched"
  if [[ -f "$lead_dispatched" ]]; then
    teams_log "sswarm A2 review-lead already dispatched, allowing idle"
    exit 0
  fi

  # Check if all 3 reviewer outputs exist
  local all_done=true
  for slot in 1 2 3; do
    if [[ ! -f "${phases_dir}/A2-review.reviewer.${slot}.tmp" ]]; then
      all_done=false
      break
    fi
  done

  if [[ "$all_done" != "true" ]]; then
    teams_log "sswarm A2: waiting for reviewer outputs, allowing idle"
    exit 0
  fi

  # Dispatch review-lead
  if mkdir "${marker_dir}/.review-lead.dispatch-lock" 2>/dev/null; then
    touch "$lead_dispatched"
    rm -rf "${marker_dir}/.review-lead.dispatch-lock" 2>/dev/null || true

    local task_ctx
    task_ctx=$(jq -n \
      --arg in1 "${phases_dir}/A2-review.reviewer.1.tmp" \
      --arg in2 "${phases_dir}/A2-review.reviewer.2.tmp" \
      --arg in3 "${phases_dir}/A2-review.reviewer.3.tmp" \
      '{"inputFiles": ($in1 + "\n" + $in2 + "\n" + $in3)}')

    local prompt
    prompt="$(teams_build_teammate_prompt "A2" "$task_ctx")" || true
    if [[ -z "$prompt" ]]; then
      teams_log "ERROR: teams_build_teammate_prompt returned empty for sswarm A2 review-lead"
      rm -f "$lead_dispatched" 2>/dev/null || true
      exit 0
    fi
    teams_log "Dispatching sswarm A2 review-lead to idle teammate"
    teams_assign_idle_teammate "$prompt"
    exit 2
  fi

  teams_log "sswarm A2 review-lead dispatch race, allowing idle"
  exit 0
}

# ===========================================================================
# Main routing function: route_idle_teammate
# ===========================================================================
route_idle_teammate() {
  case "$current_phase" in
    A0)
      dispatch_phase "A0"
      ;;
    A1)
      if [[ "$pipeline" == "sswarm" ]]; then
        dispatch_sswarm_a1
      else
        dispatch_phase "A1"
      fi
      ;;
    A2)
      if [[ "$pipeline" == "sswarm" ]]; then
        dispatch_sswarm_a2
      else
        dispatch_phase "A2"
      fi
      ;;
    A3)
      # Mark A3 in_progress if pending
      local a3_status
      a3_status=$(jq -r '.phases.A3.status // "pending"' "$STATE_FILE" 2>/dev/null || {
        teams_log "WARNING: Failed to read A3 status from state.json, allowing idle"
        exit 0
      })
      if [[ "$a3_status" == "pending" ]]; then
        if ! update_state '.phases.A3.status = "in_progress" | .phases.A3.startedAt = $ts | .updatedAt = $ts'; then
          teams_log "Failed to claim A3 in_progress (state update failed), allowing idle"
          exit 0
        fi
      fi
      dispatch_a3_task
      ;;
    A4)
      # A4 verdict is handled inline by TaskCompleted hook (handle_a3_arbiter).
      # No direct dispatch needed. Allow idle.
      teams_log "A4 is handled inline by TaskCompleted hook, allowing idle"
      exit 0
      ;;
    A5)
      dispatch_phase "A5"
      ;;
    # DONE|STOPPED|BLOCKED already handled by precondition check above
    *)
      teams_log "WARNING: Unknown phase '${current_phase}', allowing idle (possible state corruption or migration issue)"
      exit 0
      ;;
  esac
}

# ===========================================================================
# Entry point
# ===========================================================================

route_idle_teammate

# Defensive catch-all: if route_idle_teammate returns without exiting, allow idle
teams_log "Route returned without explicit exit (phase=${current_phase}), allowing idle"
exit 0
