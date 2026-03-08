#!/usr/bin/env bash
# on-teammate-idle.sh — TeammateIdle handler for Agent Teams dispatch
# Fires when a teammate goes idle. Finds the next ready task from state.json,
# generates a teammate execution prompt, and assigns it via exit 2.
#
# Exit codes:
#   0 silent — allow idle (no tasks ready or workflow complete/blocked)
#   2 with stderr — assign work (teammate continues with new task)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/swarm.sh"
source "$SCRIPT_DIR/lib/circuit-breaker.sh"
source "$SCRIPT_DIR/lib/teams.sh"

check_ants_workflow

# Read stdin (Agent Teams passes hook input JSON)
INPUT=$(cat)

# Check for graceful shutdown
shutdown_flag=$(state_get '.shutdown // false')
if [[ "$shutdown_flag" == "true" ]]; then
  teams_log "Shutdown flag set, allowing idle (graceful shutdown)"
  exit 0
fi

# Circuit breaker check: if tripped, stop assigning work
if cb_is_tripped; then
  teams_log "Circuit breaker tripped, allowing idle"
  if ! update_state '.status = "blocked" | .updatedAt = $ts | .failure = "Circuit breaker tripped: too many consecutive failures"'; then
    echo "ERROR: Failed to update state to blocked after circuit breaker trip." >&2
    exit 2
  fi
  exit 0
fi

# Find next ready task
NEXT_PHASE="$(teams_get_next_ready_task)"

if [[ -z "$NEXT_PHASE" ]]; then
  # No tasks ready — workflow is complete, blocked, or waiting
  teams_log "No tasks ready, allowing idle"
  exit 0
fi

# Generate teammate execution prompt
PROMPT=""
if ! PROMPT="$(teams_build_teammate_prompt "$NEXT_PHASE")" || [[ -z "$PROMPT" ]]; then
  FAILURE_DESC="prompt generation"
  [[ -z "$PROMPT" ]] && FAILURE_DESC="empty prompt generation"
  teams_log "ERROR: Failed to generate prompt for phase $NEXT_PHASE ($FAILURE_DESC) — recording failure"
  if cb_record_failure; then
    teams_log "Circuit breaker TRIPPED after $FAILURE_DESC failure"
    if ! update_state --arg fail "Circuit breaker tripped: $FAILURE_DESC failure" \
      '.status = "blocked" | .updatedAt = $ts | .failure = $fail'; then
      echo "ERROR: Failed to persist blocked status — breaker is tripped but state.json not updated" >&2
      exit 2
    fi
  else
    teams_log "Failure recorded (breaker not yet tripped), will retry on next idle"
  fi
  exit 0  # Allow idle — don't send error text as work assignment
fi

# Assign work via exit 2
teams_assign_idle_teammate "$PROMPT"
exit 2
