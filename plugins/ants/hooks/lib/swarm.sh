#!/usr/bin/env bash
# swarm.sh — Pipeline-specific helpers for ants 6-phase workflow hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/swarm.sh"
#
# Ants phases: A0 (explore) -> A1 (plan) -> A2 (review) -> A3 (build) -> A4 (queen) -> A5 (ship)
#
# Provides:
#   get_phase_output()      — Expected output filename for each phase
#   get_phase_input()       — Input file dependencies for each phase
#   parse_queen_verdict()   — Parse and validate A4 verdict from JSON file
#   handle_a4_verdict()     — Shared verdict handler (ship/loop/block)

set -euo pipefail

# ===========================================================================
# Phase Output Files
# ===========================================================================

get_phase_output() {
  local phase="${1:?get_phase_output requires a phase ID}"
  case "$phase" in
    A0) echo "A0-explore.md" ;;
    A1) echo "A1-plan.md" ;;
    A2) echo "A2-review.json" ;;
    A3) echo "A3-build.json" ;;
    A4) echo "A4-queen-verdict.json" ;;
    A5) echo "A5-ship.json" ;;
    *)  echo "ERROR: Unknown phase ID '${phase}' in get_phase_output" >&2; return 1 ;;
  esac
}

# ===========================================================================
# Phase Input Files
# ===========================================================================

get_phase_input() {
  local phase="${1:?get_phase_input requires a phase ID}"
  case "$phase" in
    A0)
      echo "- Task description from state.json \`.task\` field"
      ;;
    A1)
      echo "- \`.agents/tmp/phases/A0-explore.md\`"
      ;;
    A2)
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A1-plan.md\`"
      ;;
    A3)
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A1-plan.md\`"
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A2-review.json\` (if plan was revised)"
      ;;
    A4)
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A3-build.json\`"
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A3-quality.json\`"
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A1-plan.md\`"
      echo "- Run \`git diff\` for current changes"
      ;;
    A5)
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A4-queen-verdict.json\`"
      echo "- \`.agents/tmp/phases/loop-{LOOP}/A3-build.json\`"
      ;;
    *)
      echo "- None"
      ;;
  esac
}

# ===========================================================================
# A4 Verdict Parsing
# ===========================================================================

# Parse and validate a queen verdict JSON file.
# Sets VERDICT (clean|issues_found) in the caller's scope.
# Usage: parse_queen_verdict "/path/to/A4-queen-verdict.json"
parse_queen_verdict() {
  local verdict_file="${1:?parse_queen_verdict requires a file path}"

  # Validate verdict file has required structure
  if ! jq -e 'has("verdict")' "$verdict_file" >/dev/null 2>&1; then
    echo "ERROR: $verdict_file missing required 'verdict' field." >&2
    exit 2
  fi
  # Validate verdict value is a string
  local verdict_type
  verdict_type=$(jq -r '.verdict | type' "$verdict_file" 2>/dev/null || echo "null")
  if [[ "$verdict_type" != "string" ]]; then
    echo "ERROR: $verdict_file .verdict is type '$verdict_type', expected string." >&2
    exit 2
  fi

  VERDICT=$(jq -r '.verdict // empty' "$verdict_file") || {
    echo "ERROR: Failed to read verdict from $verdict_file." >&2
    exit 2
  }
  # Validate issues array type if present
  local has_issues
  has_issues=$(jq -r 'has("issues")' "$verdict_file" 2>/dev/null || echo "false")
  if [[ "$has_issues" == "true" ]]; then
    local issues_type
    issues_type=$(jq -r '.issues | type' "$verdict_file" 2>/dev/null || echo "null")
    if [[ "$issues_type" != "array" ]]; then
      echo "WARNING: $verdict_file .issues is type '$issues_type', expected array. Treating as 0 issues." >&2
    fi
  fi

  # .total_issues is the canonical field — written by the inline A4 evaluator
  # in on-task-completed.sh handle_a3_arbiter(). No fallback to legacy field names.
  total_issues=$(jq -r '(.total_issues // 0) | floor | tostring' "$verdict_file") || {
    echo "WARNING: Failed to parse .total_issues from $verdict_file, defaulting to 0" >&2
    total_issues="0"
  }

  # Sanitize total_issues to integer
  if ! [[ "$total_issues" =~ ^[0-9]+$ ]]; then
    echo "WARNING: total_issues is not a valid integer ('$total_issues'), defaulting to 0" >&2
    total_issues="0"
  fi

  # Fail-safe: issue counts take precedence over declared verdict
  if [[ "$VERDICT" == "clean" && "$total_issues" -gt 0 ]]; then
    echo "WARNING: Queen reports clean with ${total_issues} issues. Forcing issues_found." >&2
    VERDICT="issues_found"
  fi

  if [[ "$VERDICT" != "clean" && "$VERDICT" != "issues_found" ]]; then
    if [[ "$total_issues" -gt 0 ]]; then
      echo "WARNING: Unexpected verdict '${VERDICT}'. Inferred issues_found from issue count." >&2
      VERDICT="issues_found"
    else
      echo "ERROR: Unexpected verdict '$VERDICT' and no issues in $verdict_file." >&2
      exit 2
    fi
  fi
}

# ===========================================================================
# Verdict Handling (shared by on-task-completed.sh)
# ===========================================================================

# ─────────────────────────────────────────────────────────────
# Shared verdict handler called by on-task-completed.sh (handle_a3_arbiter)
# for issues_found loop-back logic. When the A3 arbiter completes with
# issues, handle_a3_arbiter() evaluates the inline A4 verdict and delegates
# loop-back/stop/block transitions to this function.
# ─────────────────────────────────────────────────────────────

# Handle A4 verdict result: advance to A5 (clean) or loop back to A1 (issues_found).
#
# Arguments:
#   $1 — VERDICT value ("clean" or "issues_found")
#   $2 — LOOP (current loop number)
#   $3 — MAX_LOOPS
#
# Returns: 0 on success, exits 2 on failure.
# Side effects: updates state.json, may call reset_phases_for_loop and circuit breaker functions.
# Sets RESULT_PHASE in caller scope to the new phase ("A5", "A1", "STOPPED", "BLOCKED").
#
# Idempotency: checks currentPhase == "A4" before updating.
handle_a4_verdict() {
  local verdict="${1:?handle_a4_verdict requires VERDICT}"
  local loop="${2:?handle_a4_verdict requires LOOP}"
  local max_loops="${3:?handle_a4_verdict requires MAX_LOOPS}"

  # Idempotency guard: only process if still in A4
  local current_phase
  current_phase=$(state_get '.currentPhase' --required)
  if [[ "$current_phase" != "A4" ]]; then
    echo "INFO: handle_a4_verdict called but currentPhase is '${current_phase}' (not A4). Skipping (already processed)." >&2
    RESULT_PHASE="$current_phase"
    return 0
  fi

  if [[ "$verdict" == "clean" ]]; then
    if ! update_state --arg verdict "$verdict" \
      '.currentPhase = "A5" | .updatedAt = $ts | .phases.A4.status = "complete" | .phases.A4.verdict = $verdict'; then
      echo "ERROR: Failed to advance state from A4 to A5." >&2
      exit 2
    fi
    RESULT_PHASE="A5"
    return 0
  fi

  # issues_found — loop back or stop
  local next_loop=$((loop + 1))
  if [[ "$next_loop" -gt "$max_loops" ]]; then
    if ! update_state --arg verdict "$verdict" \
      '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .phases.A4.status = "complete" | .phases.A4.verdict = $verdict | .failure = "Max loops reached with unresolved issues"'; then
      echo "ERROR: Failed to update state to STOPPED." >&2
      exit 2
    fi
    RESULT_PHASE="STOPPED"
    return 0
  fi

  # Check stage restart budget BEFORE updating state to avoid orphaned loop entries
  if ! cb_increment_stage_restarts; then
    echo "WARNING: Stage restart budget exhausted." >&2
    if ! update_state --arg verdict "$verdict" \
      '.status = "blocked" | .updatedAt = $ts | .phases.A4.status = "complete" | .phases.A4.verdict = $verdict | .failure = "Stage restart budget exhausted"'; then
      echo "ERROR: Failed to set blocked status." >&2
      exit 2
    fi
    RESULT_PHASE="BLOCKED"
    return 0
  fi

  # Loop back to A1
  # IMPORTANT: reset_phases_for_loop clears A1-A4 to pending, so call it BEFORE
  # setting A4 completion state (matches the A2 loop-back pattern in on-task-completed.sh).
  if ! reset_phases_for_loop; then
    echo "ERROR: Failed to reset phases for loop-back from A4" >&2
    exit 2
  fi
  if ! update_state --arg verdict "$verdict" --argjson nextLoop "$next_loop" \
    '.currentPhase = "A1" | .loop = $nextLoop | .updatedAt = $ts | .phases.A4.status = "complete" | .phases.A4.verdict = $verdict | .loops += [{"loop": $nextLoop, "startedAt": $ts}]'; then
    echo "ERROR: Failed to loop back to A1." >&2
    exit 2
  fi
  if ! cb_reset_for_loop; then
    echo "ERROR: Failed to reset circuit breaker for loop -- blocking workflow to prevent stale counters" >&2
    if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Circuit breaker reset failed during loop-back"'; then
      echo "ERROR: Failed to set blocked status after cb_reset_for_loop failure" >&2
      exit 2
    fi
    RESULT_PHASE="BLOCKED"
    return 0
  fi
  RESULT_PHASE="A1"
  return 0
}
