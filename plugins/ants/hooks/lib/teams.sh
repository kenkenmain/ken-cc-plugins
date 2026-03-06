#!/usr/bin/env bash
# teams.sh — Agent Teams readiness layer for ants hooks.
# Source this from hook scripts after state.sh:
#   source "$SCRIPT_DIR/lib/state.sh"
#   source "$SCRIPT_DIR/lib/teams.sh"
#
# =============================================================================
# Purpose
# =============================================================================
#
# All ants dispatch currently uses the Task tool (subagents). This library
# provides detection and future-ready interfaces for the Claude Code Agent
# Teams API (currently experimental behind CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS).
#
# When Teams API becomes stable, the migration path is:
#   1. teams_detect() returns TEAMS_AVAILABLE=true
#   2. teams_get_dispatch_mode() returns "teams" instead of "subagent"
#   3. Callers switch from Task tool dispatch to TeammateTool dispatch
#   4. Task descriptors (from teams_build_task_descriptor) are already
#      compatible with both dispatch modes — no descriptor changes needed
#
# The key design principle: all dispatch-related logic flows through this
# library so that the Teams migration is a single-file change (swap the
# dispatch mode logic) rather than a shotgun surgery across all hooks.
#
# See also: docs/teams-migration.md (step-by-step migration guide)
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Environment variable that enables the experimental Agent Teams API.
# When set to "1", the Teams API is available for dispatch.
TEAMS_ENV_VAR="CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"

# Current dispatch mode. Updated by teams_detect().
# Values: "subagent" (Task tool) or "teams" (TeammateTool, future)
TEAMS_AVAILABLE=false

# ---------------------------------------------------------------------------
# teams_detect
# ---------------------------------------------------------------------------
# Check if the Agent Teams API is available by inspecting the
# CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS environment variable.
#
# Sets global TEAMS_AVAILABLE to "true" or "false".
#
# Usage:
#   teams_detect
#   if [[ "$TEAMS_AVAILABLE" == "true" ]]; then
#     teams_log "Teams API detected"
#   fi
#
# Future: When Teams API graduates from experimental, this function
# may also check for API version compatibility or feature flags.
# ---------------------------------------------------------------------------
teams_detect() {
  local env_value
  env_value="${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}"

  if [[ "$env_value" == "1" ]]; then
    TEAMS_AVAILABLE=true
    teams_log "Agent Teams API detected (${TEAMS_ENV_VAR}=1)"
  else
    TEAMS_AVAILABLE=false
    teams_log "Agent Teams API not available (${TEAMS_ENV_VAR}=${env_value:-unset})"
  fi
}

# ---------------------------------------------------------------------------
# teams_get_dispatch_mode
# ---------------------------------------------------------------------------
# Returns the current dispatch mode: "subagent" or "teams".
#
# Currently always returns "subagent" because the Teams API is experimental
# and the dispatch adapter is not yet implemented.
#
# Future migration path:
#   1. Teams API becomes stable
#   2. Dispatch adapter is implemented in swarm.sh
#   3. This function returns "teams" when TEAMS_AVAILABLE=true
#   4. Callers use the returned mode to choose dispatch method:
#      - "subagent" -> Task tool with subagent_type
#      - "teams"    -> TeammateTool with teammate assignment
#
# Usage:
#   local mode
#   mode="$(teams_get_dispatch_mode)"
#   case "$mode" in
#     subagent) # dispatch via Task tool
#     teams)    # dispatch via TeammateTool (future)
#   esac
# ---------------------------------------------------------------------------
teams_get_dispatch_mode() {
  # TODO(teams): When Teams dispatch adapter is ready, uncomment:
  #   if [[ "$TEAMS_AVAILABLE" == "true" ]]; then
  #     echo "teams"
  #     return 0
  #   fi
  echo "subagent"
}

# ---------------------------------------------------------------------------
# teams_log
# ---------------------------------------------------------------------------
# Log teams-related information to stderr with a [TEAMS] prefix.
# All teams diagnostics go through this function for consistent formatting
# and easy filtering (grep '\[TEAMS\]').
#
# Usage:
#   teams_log "Agent Teams API detected"
#   teams_log "Dispatch mode: subagent"
#   teams_log "WARNING: Teams fallback to subagent mode"
# ---------------------------------------------------------------------------
teams_log() {
  local message="${1:?teams_log requires a message}"
  echo "[TEAMS] ${message}" >&2
}

# ---------------------------------------------------------------------------
# teams_build_task_descriptor
# ---------------------------------------------------------------------------
# Build a JSON task descriptor that is compatible with both Task tool
# dispatch (current) and future TeammateTool dispatch.
#
# The descriptor contains all information needed to dispatch a unit of work,
# regardless of the dispatch mechanism. This is the key abstraction that
# makes the Teams migration seamless — callers build descriptors once, and
# the dispatch layer (in swarm.sh) translates them to the appropriate API.
#
# Arguments:
#   $1 — agent_type:  The agent to dispatch (e.g., "ants:worker", "ants:sentinel-correctness")
#   $2 — prompt:      The task prompt / instructions for the agent
#   $3 — model:       Model hint (e.g., "sonnet", "opus", "inherit")
#   $4 — task_id:     Unique task identifier (e.g., "T1", "review-wave-1")
#
# Output (stdout):
#   JSON object with the following structure:
#   {
#     "taskId":     "T1",
#     "agentType":  "ants:worker",
#     "prompt":     "Implement the auth module...",
#     "model":      "sonnet",
#     "dispatch":   "subagent",
#     "createdAt":  "2026-03-06T12:00:00+00:00"
#   }
#
# Field mapping for future Teams migration:
#   Current (Task tool)          ->  Future (TeammateTool)
#   -----------------------------------------------------------
#   agentType                    ->  teammate agent selection
#   prompt                       ->  teammate task description
#   model                        ->  teammate model preference
#   taskId                       ->  teammate task tracking ID
#   dispatch: "subagent"         ->  dispatch: "teams"
#
# Usage:
#   local descriptor
#   descriptor="$(teams_build_task_descriptor "ants:worker" "Implement auth" "sonnet" "T1")"
#   echo "$descriptor" | jq '.agentType'
# ---------------------------------------------------------------------------
teams_build_task_descriptor() {
  local agent_type="${1:?teams_build_task_descriptor requires agent_type}"
  local prompt="${2:?teams_build_task_descriptor requires prompt}"
  local model="${3:?teams_build_task_descriptor requires model}"
  local task_id="${4:?teams_build_task_descriptor requires task_id}"

  local dispatch_mode
  dispatch_mode="$(teams_get_dispatch_mode)"

  local timestamp
  timestamp="$(date -Iseconds)"

  jq -n \
    --arg tid "$task_id" \
    --arg agent "$agent_type" \
    --arg p "$prompt" \
    --arg m "$model" \
    --arg d "$dispatch_mode" \
    --arg ts "$timestamp" \
    '{
      taskId: $tid,
      agentType: $agent,
      prompt: $p,
      model: $m,
      dispatch: $d,
      createdAt: $ts
    }'
}
