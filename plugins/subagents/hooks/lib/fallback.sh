#!/usr/bin/env bash
# fallback.sh -- Codex timeout detection and Claude fallback logic.
# Requires state.sh and schedule.sh to be sourced first.
set -euo pipefail

DEFAULT_MAX_DISPATCH_RETRIES=2

# ---------------------------------------------------------------------------
# get_max_dispatch_retries -- Read configured max dispatch retries, or default.
# ---------------------------------------------------------------------------
get_max_dispatch_retries() {
  local configured
  configured="$(state_get '.codexTimeout.maxRetries // empty')"
  if [[ -n "$configured" && "$configured" != "null" ]]; then
    echo "$configured"
  else
    echo "$DEFAULT_MAX_DISPATCH_RETRIES"
  fi
}

# ---------------------------------------------------------------------------
# is_codex_timeout <phase> -- Check if the phase output has codexTimeout flag.
#   Returns 0 (true) if the output file exists and contains codexTimeout: true.
# ---------------------------------------------------------------------------
is_codex_timeout() {
  local phase="${1:?is_codex_timeout requires a phase ID}"
  local output_file
  output_file="$(get_phase_output "$phase")"
  local path="$PHASES_DIR/$output_file"
  [[ -f "$path" ]] && jq -e '.codexTimeout == true' "$path" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# switch_to_claude <reason> -- Replace all Codex agents with Claude fallback
#   agents in state.json. Records the switch in state.codexFallback.
# ---------------------------------------------------------------------------
switch_to_claude() {
  local reason="${1:-unknown}"
  state_update "
    .reviewer = \"subagents:claude-reviewer\" |
    .failureAnalyzer = \"subagents:failure-analyzer\" |
    .difficultyEstimator = \"subagents:difficulty-estimator\" |
    .testDeveloper = \"subagents:test-developer\" |
    .docUpdater = \"subagents:doc-updater\" |
    .exploreAggregator = \"subagents:explore-aggregator\" |
    .planAggregator = \"subagents:plan-aggregator\" |
    .codexAvailable = false |
    .codexFallback = {
      \"switchedAt\": (now | todate),
      \"reason\": \"$reason\"
    }
  "
}

# ---------------------------------------------------------------------------
# handle_missing_or_timeout <phase> <stage> -- Track dispatch retries and
#   trigger Claude fallback if retry limit reached.
#
#   Increments the per-phase dispatchRetries counter. If the counter reaches
#   maxRetries AND the current agent is Codex-based, switches all Codex agents
#   to Claude and deletes the timeout output for a fresh retry.
#
#   Always returns 0 (caller should exit 0 to let Stop hook re-inject).
# ---------------------------------------------------------------------------
handle_missing_or_timeout() {
  local phase="${1:?handle_missing_or_timeout requires a phase ID}"
  local stage="${2:?handle_missing_or_timeout requires a stage}"
  local max_retries
  max_retries="$(get_max_dispatch_retries)"

  local retry_count
  retry_count="$(state_get ".stages[\"$stage\"].phases[\"$phase\"].dispatchRetries // 0")"
  local next_retry=$((retry_count + 1))

  # Check if we should switch to Claude — use the phase's actual agent,
  # not just .reviewer, to catch non-review Codex agents (testDeveloper, etc.)
  if [[ "$next_retry" -ge "$max_retries" ]]; then
    local phase_agent
    phase_agent="$(get_phase_subagent "$phase" 2>/dev/null || state_get '.reviewer // empty')"
    if [[ "$phase_agent" == *"codex"* ]]; then
      switch_to_claude "dispatch retry limit ($next_retry attempts) at phase $phase"
      # Delete the timeout output so the review runs fresh with Claude
      local output_file
      output_file="$(get_phase_output "$phase")"
      rm -f "$PHASES_DIR/$output_file"
    fi
  fi

  state_update ".stages[\"$stage\"].phases[\"$phase\"].dispatchRetries = $next_retry"
  return 0
}
