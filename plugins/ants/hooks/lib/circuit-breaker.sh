#!/usr/bin/env bash
# circuit-breaker.sh -- Circuit breaker and fix-budget tracking for ants hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/circuit-breaker.sh"
#
# Provides two-tier retry logic:
#   Tier 1: Per-review fix attempts (maxFixAttempts per review phase)
#   Tier 2: Stage restarts / loop-backs from A4 to A1 (maxStageRestarts)
#
# Circuit breaker trips when consecutiveFailures >= maxConsecutiveFailures,
# halting the workflow to prevent infinite failure loops.
#
# State schema (nested under .circuitBreaker in state.json):
# {
#   "consecutiveFailures": 0,
#   "maxConsecutiveFailures": 5,
#   "maxFixAttempts": 5,
#   "maxStageRestarts": 2,
#   "fixAttempts": {},
#   "stageRestarts": 0
# }

set -euo pipefail

# Default circuit breaker parameters (per S3 plan review standardization)
CB_MAX_FIX_ATTEMPTS=5
CB_MAX_STAGE_RESTARTS=2
CB_MAX_CONSECUTIVE_FAILURES=5

# ===========================================================================
# Initialization
# ===========================================================================

# Initialize circuit breaker fields in state.json if missing.
# Safe to call multiple times -- only sets fields that do not exist.
# Usage: cb_init
cb_init() {
  update_state \
    --argjson maxFix "$CB_MAX_FIX_ATTEMPTS" \
    --argjson maxRestart "$CB_MAX_STAGE_RESTARTS" \
    --argjson maxFail "$CB_MAX_CONSECUTIVE_FAILURES" \
    '.circuitBreaker //= {} |
     .circuitBreaker.consecutiveFailures //= 0 |
     .circuitBreaker.maxConsecutiveFailures //= $maxFail |
     .circuitBreaker.maxFixAttempts //= $maxFix |
     .circuitBreaker.maxStageRestarts //= $maxRestart |
     .circuitBreaker.fixAttempts //= {} |
     .circuitBreaker.stageRestarts //= 0'
}

# ===========================================================================
# Consecutive Failure Tracking (Circuit Breaker Core)
# ===========================================================================

# Record a failure. Increments consecutiveFailures.
# Returns 0 if the circuit breaker is now tripped, 1 if still healthy (delegates to cb_is_tripped).
# On state update error, returns 1 and logs an error.
# Usage: if cb_record_failure; then echo "TRIPPED"; fi
cb_record_failure() {
  if ! update_state \
    '.circuitBreaker.consecutiveFailures = ((.circuitBreaker.consecutiveFailures // 0) + 1)'; then
    echo "ERROR: Failed to record failure in circuit breaker" >&2
    return 1
  fi

  # Check if tripped after increment
  cb_is_tripped
}

# Record a success. Resets consecutiveFailures to 0.
# Usage: cb_record_success
cb_record_success() {
  if ! update_state \
    '.circuitBreaker.consecutiveFailures = 0'; then
    echo "ERROR: Failed to record success in circuit breaker" >&2
    return 1
  fi
}

# Check if the circuit breaker is tripped.
# Returns 0 (true) if tripped, 1 (false) if healthy.
# Usage: if cb_is_tripped; then echo "TRIPPED"; fi
cb_is_tripped() {
  local cb_meta
  cb_meta=$(jq -r "[(.circuitBreaker.consecutiveFailures // 0), (.circuitBreaker.maxConsecutiveFailures // $CB_MAX_CONSECUTIVE_FAILURES)] | map(tostring) | join(\"\t\")" "$STATE_FILE")
  local failures max_failures
  IFS=$'\t' read -r failures max_failures <<< "$cb_meta"
  failures=$(require_int "$failures" "circuitBreaker.consecutiveFailures")
  max_failures=$(require_int "$max_failures" "circuitBreaker.maxConsecutiveFailures")

  [[ "$failures" -ge "$max_failures" ]]
}

# ===========================================================================
# Fix Attempt Tracking (Per-Phase)
# ===========================================================================

# Get fix attempt count for a specific phase.
# Usage: count=$(cb_get_fix_attempts "A2")
cb_get_fix_attempts() {
  local phase="${1:?cb_get_fix_attempts requires a phase ID}"
  local count
  count=$(jq -r --arg p "$phase" '.circuitBreaker.fixAttempts[$p] // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  count=$(require_int "$count" "circuitBreaker.fixAttempts.$phase")
  echo "$count"
}

# Increment fix attempts for a phase. Returns 1 if max exceeded after increment.
# Usage: if ! cb_increment_fix_attempts "A2"; then echo "BUDGET EXHAUSTED"; fi
cb_increment_fix_attempts() {
  local phase="${1:?cb_increment_fix_attempts requires a phase ID}"

  local max_attempts
  max_attempts=$(state_get ".circuitBreaker.maxFixAttempts // $CB_MAX_FIX_ATTEMPTS")
  max_attempts=$(require_int "$max_attempts" "circuitBreaker.maxFixAttempts")

  # Atomic check-then-increment: if current count >= max, jq error() fires,
  # update_state returns non-zero, and we return 1 (budget exhausted).
  if ! update_state --arg phase "$phase" --argjson max "$max_attempts" \
    'if (.circuitBreaker.fixAttempts[$phase] // 0) >= $max then
       error("fix attempt budget exhausted for phase " + $phase)
     else
       .circuitBreaker.fixAttempts[$phase] = ((.circuitBreaker.fixAttempts[$phase] // 0) + 1)
     end'; then
    return 1
  fi
  return 0
}

# ===========================================================================
# Stage Restart Tracking (Loop-Back from A4 to A1)
# ===========================================================================

# Get current stage restart count.
# Usage: count=$(cb_get_stage_restarts)
cb_get_stage_restarts() {
  local count
  count=$(state_get '.circuitBreaker.stageRestarts // 0')
  count=$(require_int "$count" "circuitBreaker.stageRestarts")
  echo "$count"
}

# Increment stage restarts. Returns 1 if max exceeded after increment.
# Usage: if ! cb_increment_stage_restarts; then echo "MAX RESTARTS"; fi
cb_increment_stage_restarts() {
  local max_restarts
  max_restarts=$(state_get ".circuitBreaker.maxStageRestarts // $CB_MAX_STAGE_RESTARTS")
  max_restarts=$(require_int "$max_restarts" "circuitBreaker.maxStageRestarts")

  # Atomic check-then-increment: if current count >= max, jq error() fires,
  # update_state returns non-zero, and we return 1 (max restarts exceeded).
  if ! update_state --argjson max "$max_restarts" \
    'if (.circuitBreaker.stageRestarts // 0) >= $max then
       error("stage restart budget exhausted")
     else
       .circuitBreaker.stageRestarts = ((.circuitBreaker.stageRestarts // 0) + 1)
     end'; then
    return 1
  fi
  return 0
}

# ===========================================================================
# Loop Reset
# ===========================================================================

# Reset per-loop counters when a loop-back occurs (A4 -> A1).
# Clears fixAttempts for all phases but preserves stageRestarts and
# consecutiveFailures (those track cross-loop state).
# Usage: cb_reset_for_loop
cb_reset_for_loop() {
  if ! update_state \
    '.circuitBreaker.fixAttempts = {}'; then
    echo "ERROR: Failed to reset fix attempts for loop" >&2
    return 1
  fi
}

# ===========================================================================
# Run Reset (pswarm)
# ===========================================================================

# Reset all circuit breaker counters for pswarm run boundaries.
# Called between full A0→A5 runs in the pswarm pipeline.
# Unlike cb_reset_for_loop() which only clears fixAttempts, this fully resets
# all counters because each pswarm run is an independent attempt.
# Usage: cb_reset_for_run
cb_reset_for_run() {
  if ! update_state \
    '.circuitBreaker.stageRestarts = 0 |
     .circuitBreaker.fixAttempts = {} |
     .circuitBreaker.consecutiveFailures = 0'; then
    echo "ERROR: Failed to reset circuit breaker counters for run" >&2
    return 1
  fi
}
