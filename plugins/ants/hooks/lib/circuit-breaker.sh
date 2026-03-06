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
# Returns 0 normally, returns 1 if the circuit breaker is now tripped.
# Usage: if ! cb_record_failure; then echo "TRIPPED"; fi
cb_record_failure() {
  update_state \
    '.circuitBreaker.consecutiveFailures = ((.circuitBreaker.consecutiveFailures // 0) + 1)'

  # Check if tripped after increment
  cb_is_tripped
}

# Record a success. Resets consecutiveFailures to 0.
# Usage: cb_record_success
cb_record_success() {
  update_state \
    '.circuitBreaker.consecutiveFailures = 0'
}

# Check if the circuit breaker is tripped.
# Returns 0 (true) if tripped, 1 (false) if healthy.
# Usage: if cb_is_tripped; then echo "TRIPPED"; fi
cb_is_tripped() {
  local failures
  failures=$(state_get '.circuitBreaker.consecutiveFailures // 0')
  failures=$(require_int "$failures" "circuitBreaker.consecutiveFailures")

  local max_failures
  max_failures=$(state_get ".circuitBreaker.maxConsecutiveFailures // $CB_MAX_CONSECUTIVE_FAILURES")
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
  count=$(state_get ".circuitBreaker.fixAttempts[\"$phase\"] // 0")
  count=$(require_int "$count" "circuitBreaker.fixAttempts.$phase")
  echo "$count"
}

# Increment fix attempts for a phase. Returns 1 if max exceeded after increment.
# Usage: if ! cb_increment_fix_attempts "A2"; then echo "BUDGET EXHAUSTED"; fi
cb_increment_fix_attempts() {
  local phase="${1:?cb_increment_fix_attempts requires a phase ID}"

  update_state --arg phase "$phase" \
    '.circuitBreaker.fixAttempts[$phase] = ((.circuitBreaker.fixAttempts[$phase] // 0) + 1)'

  local new_count
  new_count=$(cb_get_fix_attempts "$phase")

  local max_attempts
  max_attempts=$(state_get ".circuitBreaker.maxFixAttempts // $CB_MAX_FIX_ATTEMPTS")
  max_attempts=$(require_int "$max_attempts" "circuitBreaker.maxFixAttempts")

  if [[ "$new_count" -gt "$max_attempts" ]]; then
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
  update_state \
    '.circuitBreaker.stageRestarts = ((.circuitBreaker.stageRestarts // 0) + 1)'

  local new_count
  new_count=$(cb_get_stage_restarts)

  local max_restarts
  max_restarts=$(state_get ".circuitBreaker.maxStageRestarts // $CB_MAX_STAGE_RESTARTS")
  max_restarts=$(require_int "$max_restarts" "circuitBreaker.maxStageRestarts")

  if [[ "$new_count" -gt "$max_restarts" ]]; then
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
  update_state \
    '.circuitBreaker.fixAttempts = {}'
}
