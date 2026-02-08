#!/usr/bin/env bash
# on-subagent-stop.sh — Validate output, advance state, handle loop-back
# Fires when any subagent finishes. Validates output exists, updates state,
# and determines whether to advance or loop back.
#
# Exit codes:
#   0 silent — allow (non-minions agent or no active workflow)
#   0 with JSON — provide context to orchestrator
#   2 with stderr — block, output file missing or corrupt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

check_workflow_active

# Read input from stdin
INPUT=$(cat)
if [[ -z "$INPUT" ]] || ! printf '%s' "$INPUT" | jq empty 2>/dev/null; then
  echo "ERROR: No valid JSON received on stdin for SubagentStop hook." >&2
  exit 2
fi

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_name // empty')

# Delegate to superlaunch handler if applicable (stdin already consumed, pass via env)
if [[ "$(state_get '.pipeline // "launch"')" == "superlaunch" ]]; then
  export SL_AGENT_TYPE="$AGENT_TYPE"
  exec "$SCRIPT_DIR/on-subagent-stop-superlaunch.sh"
fi

# Only handle minions agents
case "$AGENT_TYPE" in
  explorer-files|minions:explorer-files) exit 0 ;;
  explorer-architecture|minions:explorer-architecture) exit 0 ;;
  explorer-tests|minions:explorer-tests) exit 0 ;;
  explorer-patterns|minions:explorer-patterns) exit 0 ;;
  scout|minions:scout) AGENT="scout" ;;
  builder|minions:builder) AGENT="builder" ;;
  critic|minions:critic) AGENT="critic" ;;
  pedant|minions:pedant) AGENT="pedant" ;;
  witness|minions:witness) AGENT="witness" ;;
  security-reviewer|minions:security-reviewer) AGENT="security-reviewer" ;;
  silent-failure-hunter|minions:silent-failure-hunter) AGENT="silent-failure-hunter" ;;
  shipper|minions:shipper) AGENT="shipper" ;;
  *) exit 0 ;;
esac

LOOP=$(state_get '.loop')
MAX_LOOPS=$(state_get '.maxLoops')

# Validate both are positive integers
LOOP=$(require_int "$LOOP" "loop")
MAX_LOOPS=$(require_int "$MAX_LOOPS" "maxLoops")

PHASES_DIR=".agents/tmp/phases/loop-${LOOP}"

# Helper to safely extract issue count as integer from a review file.
# Expected schema: { "summary": { "critical": N, "warning": N, "info": N } }
_issue_count() {
  local file="$1"
  local raw

  # Validate schema: check that .summary exists and has expected fields
  if ! jq -e '.summary | has("critical") and has("warning") and has("info")' "$file" >/dev/null 2>&1; then
    echo "WARNING: $(basename "$file") missing expected .summary.{critical,warning,info} fields. Issue count may be inaccurate." >&2
  fi

  raw=$(jq -r '((.summary.critical // 0) + (.summary.warning // 0) + (.summary.info // 0)) | floor' "$file" 2>/dev/null || echo "")
  # Sanitize: strip decimals, ensure integer
  raw="${raw%%.*}"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo "WARNING: Could not extract issue count from $(basename "$file"); defaulting to 0. Agent output may have unexpected schema." >&2
    echo "0"
  fi
}

case "$AGENT" in
  scout)
    # Validate F1 output exists
    if [[ ! -f "${PHASES_DIR}/f1-plan.md" ]]; then
      echo "Scout completed but f1-plan.md not found. Scout must write plan to ${PHASES_DIR}/f1-plan.md" >&2
      exit 2
    fi

    # Advance to F2
    if ! update_state '.currentPhase = "F2" | .updatedAt = $ts | .loops[-1].f1.status = "complete"'; then
      echo "ERROR: Failed to advance state from F1 to F2." >&2
      exit 2
    fi
    ;;

  builder)
    # When f2-tasks.json exists and is valid, advance to F3.
    # Note: the orchestrator writes f2-tasks.json after aggregating all builders.
    # Also triggered by the Stop hook's F2→F3 advancement path.
    if [[ -f "${PHASES_DIR}/f2-tasks.json" ]]; then
      if ! validate_json_file "${PHASES_DIR}/f2-tasks.json" "f2-tasks.json"; then
        echo "ERROR: f2-tasks.json exists but is invalid. Builders must produce valid JSON." >&2
        exit 2
      fi
      if ! jq -e '.tasks and .files_changed and .all_complete == true' "${PHASES_DIR}/f2-tasks.json" >/dev/null 2>&1; then
        echo "ERROR: f2-tasks.json missing required fields or all_complete is not true." >&2
        exit 2
      fi
      # Use mkdir lock to prevent duplicate advancement (same pattern as F3)
      F2_LOCK_DIR="${PHASES_DIR}/.f2-advance.lock"
      F2_LOCK_STALE_SECONDS=60
      if ! mkdir "$F2_LOCK_DIR" 2>/dev/null; then
        # Check if lock is stale (older than threshold) — prevents deadlock if hook crashes
        if [[ -d "$F2_LOCK_DIR" ]]; then
          f2_lock_mtime=""
          if f2_lock_mtime=$(lock_dir_mtime_epoch "$F2_LOCK_DIR"); then
            f2_lock_age=$(( $(date +%s) - f2_lock_mtime ))
            if [[ "$f2_lock_age" -gt "$F2_LOCK_STALE_SECONDS" ]]; then
              echo "WARNING: Removing stale F2 lock directory (age: ${f2_lock_age}s)" >&2
              rm -rf "$F2_LOCK_DIR"
              mkdir "$F2_LOCK_DIR" 2>/dev/null || exit 0
            else
              exit 0
            fi
          else
            exit 0  # Cannot determine age, fail-closed
          fi
        else
          exit 0
        fi
      fi
      # Idempotency: only advance if still in F2
      CURRENT=$(jq -r '.currentPhase // empty' "$STATE_FILE" 2>/dev/null || echo "")
      if [[ "$CURRENT" == "F2" ]]; then
        if ! update_state '.currentPhase = "F3" | .updatedAt = $ts | .loops[-1].f2.status = "complete"'; then
          rm -rf "$F2_LOCK_DIR" 2>/dev/null || true
          echo "ERROR: Failed to advance state from F2 to F3." >&2
          exit 2
        fi
      fi
      rm -rf "$F2_LOCK_DIR" 2>/dev/null || true
    fi
    ;;

  critic|pedant|witness|security-reviewer|silent-failure-hunter)
    # F3 agents run in parallel. Only advance when all 5 have completed.
    CRITIC_FILE="${PHASES_DIR}/f3-critic.json"
    PEDANT_FILE="${PHASES_DIR}/f3-pedant.json"
    WITNESS_FILE="${PHASES_DIR}/f3-witness.json"
    SECURITY_FILE="${PHASES_DIR}/f3-security-reviewer.json"
    SILENT_FILE="${PHASES_DIR}/f3-silent-failure-hunter.json"
    VERDICT_FILE="${PHASES_DIR}/f3-verdict.json"
    LOCK_DIR="${PHASES_DIR}/.f3-advance.lock"

    # Not all complete yet — wait
    if [[ ! -f "$CRITIC_FILE" || ! -f "$PEDANT_FILE" || ! -f "$WITNESS_FILE" || ! -f "$SECURITY_FILE" || ! -f "$SILENT_FILE" ]]; then
      exit 0
    fi

    # Acquire lock to prevent duplicate F3 advancement (race condition guard)
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
      # Check if lock is stale (older than 60 seconds)
      if [[ -d "$LOCK_DIR" ]]; then
        f3_lock_mtime=""
        if f3_lock_mtime=$(lock_dir_mtime_epoch "$LOCK_DIR"); then
          lock_age=$(( $(date +%s) - f3_lock_mtime ))
          if [[ "$lock_age" -gt 60 ]]; then
            echo "WARNING: Removing stale F3 lock directory (age: ${lock_age}s)" >&2
            rm -rf "$LOCK_DIR"
            mkdir "$LOCK_DIR" 2>/dev/null || exit 0
          else
            exit 0
          fi
        else
          exit 0  # Cannot determine age, fail-closed
        fi
      else
        exit 0
      fi
    fi

    # Override ERR trap to include lock cleanup
    trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true; echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR

    # Check state hasn't already been advanced (idempotency guard)
    F3_STATUS=$(jq -r '.loops[-1].f3.status // "pending"' "$STATE_FILE" 2>/dev/null || echo "pending")
    if [[ "$F3_STATUS" == "complete" ]]; then
      rm -rf "$LOCK_DIR" 2>/dev/null || true
      exit 0
    fi

    # Validate all 5 files are valid JSON
    for f in "$CRITIC_FILE" "$PEDANT_FILE" "$WITNESS_FILE" "$SECURITY_FILE" "$SILENT_FILE"; do
      if ! validate_json_file "$f" "$(basename "$f")"; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        echo "ERROR: F3 output file $(basename "$f") is invalid JSON." >&2
        exit 2
      fi
    done

    # Read verdicts — FAIL-SAFE: default to "issues_found" on any failure
    CRITIC_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$CRITIC_FILE") || CRITIC_VERDICT="issues_found"
    PEDANT_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$PEDANT_FILE") || PEDANT_VERDICT="issues_found"
    WITNESS_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$WITNESS_FILE") || WITNESS_VERDICT="issues_found"
    SECURITY_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$SECURITY_FILE") || SECURITY_VERDICT="issues_found"
    SILENT_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$SILENT_FILE") || SILENT_VERDICT="issues_found"

    # Validate verdicts are expected values
    for v in "$CRITIC_VERDICT" "$PEDANT_VERDICT" "$WITNESS_VERDICT" "$SECURITY_VERDICT" "$SILENT_VERDICT"; do
      if [[ "$v" != "clean" && "$v" != "issues_found" ]]; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        echo "ERROR: Unexpected verdict value '$v'. Expected 'clean' or 'issues_found'." >&2
        exit 2
      fi
    done

    # Count issues — sanitized to integers
    CRITIC_ISSUES=$(_issue_count "$CRITIC_FILE")
    PEDANT_ISSUES=$(_issue_count "$PEDANT_FILE")
    WITNESS_ISSUES=$(_issue_count "$WITNESS_FILE")
    SECURITY_ISSUES=$(_issue_count "$SECURITY_FILE")
    SILENT_ISSUES=$(_issue_count "$SILENT_FILE")
    TOTAL_ISSUES=$((CRITIC_ISSUES + PEDANT_ISSUES + WITNESS_ISSUES + SECURITY_ISSUES + SILENT_ISSUES))

    OVERALL="clean"
    if [[ "$CRITIC_VERDICT" == "issues_found" || "$PEDANT_VERDICT" == "issues_found" || "$WITNESS_VERDICT" == "issues_found" || "$SECURITY_VERDICT" == "issues_found" || "$SILENT_VERDICT" == "issues_found" || "$TOTAL_ISSUES" -gt 0 ]]; then
      OVERALL="issues_found"
    fi

    # Write f3-verdict.json (required by F4 gate)
    # Use separate statements (not &&) so set -e catches failures
    jq -n \
      --arg cv "$CRITIC_VERDICT" --argjson ci "$CRITIC_ISSUES" \
      --arg pv "$PEDANT_VERDICT" --argjson pi "$PEDANT_ISSUES" \
      --arg wv "$WITNESS_VERDICT" --argjson wi "$WITNESS_ISSUES" \
      --arg sv "$SECURITY_VERDICT" --argjson si "$SECURITY_ISSUES" \
      --arg slv "$SILENT_VERDICT" --argjson sli "$SILENT_ISSUES" \
      --arg ov "$OVERALL" --argjson ti "$TOTAL_ISSUES" \
      '{
        critic: { verdict: $cv, issues: $ci },
        pedant: { verdict: $pv, issues: $pi },
        witness: { verdict: $wv, issues: $wi },
        security_reviewer: { verdict: $sv, issues: $si },
        silent_failure_hunter: { verdict: $slv, issues: $sli },
        overall_verdict: $ov,
        total_issues: $ti
      }' > "${VERDICT_FILE}.tmp"

    # Validate written file before moving into place (catches disk-full / truncation)
    if ! jq empty "${VERDICT_FILE}.tmp" 2>/dev/null; then
      rm -rf "$LOCK_DIR" 2>/dev/null || true
      rm -f "${VERDICT_FILE}.tmp"
      echo "ERROR: Generated f3-verdict.json is invalid (possible disk full or write error)" >&2
      exit 2
    fi
    mv "${VERDICT_FILE}.tmp" "$VERDICT_FILE"

    if [[ "$OVERALL" == "clean" ]]; then
      # All clean — advance to F4
      if ! update_state --arg verdict "$OVERALL" \
        '.currentPhase = "F4" | .updatedAt = $ts | .loops[-1].f3.status = "complete" | .loops[-1].f3.verdict = $verdict | .loops[-1].verdict = "clean"'; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        echo "ERROR: Failed to advance state from F3 to F4." >&2
        exit 2
      fi
    else
      # Issues found — check loop limit
      NEXT_LOOP=$((LOOP + 1))
      if [[ "$NEXT_LOOP" -gt "$MAX_LOOPS" ]]; then
        # Max loops reached — stop
        if ! update_state --arg verdict "$OVERALL" \
          '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .loops[-1].f3.status = "complete" | .loops[-1].f3.verdict = $verdict | .loops[-1].verdict = "issues_found" | .failure = "Max loops reached with unresolved issues"'; then
          rm -rf "$LOCK_DIR" 2>/dev/null || true
          echo "ERROR: Failed to update state to STOPPED." >&2
          exit 2
        fi

        jq -n --arg reason "WORKFLOW STOPPED: Maximum loops (${MAX_LOOPS}) reached with unresolved issues. Review the latest F3 outputs in .agents/tmp/phases/loop-${LOOP}/ for remaining issues." \
          '{"decision":"block","reason":$reason}'
      else
        # Loop back to F1
        if ! update_state --arg verdict "$OVERALL" --argjson nextLoop "$NEXT_LOOP" \
          '.currentPhase = "F1" | .loop = $nextLoop | .updatedAt = $ts | .loops[-1].f3.status = "complete" | .loops[-1].f3.verdict = $verdict | .loops[-1].verdict = "issues_found" | .loops += [{"loop": $nextLoop, "startedAt": $ts, "f1": {"status": "pending"}, "f2": {"status": "pending"}, "f3": {"status": "pending"}}]'; then
          rm -rf "$LOCK_DIR" 2>/dev/null || true
          echo "ERROR: Failed to loop back to F1." >&2
          exit 2
        fi
      fi
    fi

    rm -rf "$LOCK_DIR" 2>/dev/null || true

    # Restore original ERR trap (overridden at lock acquisition for cleanup)
    trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
    ;;

  shipper)
    # Validate F4 output exists
    if [[ ! -f "${PHASES_DIR}/f4-ship.json" ]]; then
      echo "Shipper completed but f4-ship.json not found." >&2
      exit 2
    fi
    if ! validate_json_file "${PHASES_DIR}/f4-ship.json" "f4-ship.json"; then
      echo "ERROR: f4-ship.json is invalid JSON." >&2
      exit 2
    fi
    if ! jq -e '.commit_sha and .docs_updated' "${PHASES_DIR}/f4-ship.json" >/dev/null 2>&1; then
      echo "ERROR: f4-ship.json missing required fields (commit_sha, docs_updated)." >&2
      exit 2
    fi

    # Workflow complete
    if ! update_state '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts | .loops[-1].f4 = {"status": "complete"}'; then
      echo "ERROR: Failed to mark workflow as complete." >&2
      exit 2
    fi
    ;;
esac

exit 0
