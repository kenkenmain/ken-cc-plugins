#!/usr/bin/env bash
# on-subagent-stop-review.sh -- SubagentStop hook for the review pipeline.
# Invoked via exec from on-subagent-stop.sh when pipeline == "review".
# Validates review/fix outputs and advances review pipeline state.
#
# Receives agent type via REVIEW_AGENT_TYPE env var (stdin already consumed by parent hook).
#
# Exit codes:
#   0 silent    -- allow (non-review agent or waiting for parallel batch)
#   0 with JSON -- block notice (terminal STOPPED message)
#   2 with stderr -- error condition

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

AGENT_TYPE="${REVIEW_AGENT_TYPE:?on-subagent-stop-review.sh requires REVIEW_AGENT_TYPE}"

case "$AGENT_TYPE" in
  critic|minions:critic) AGENT="critic" ;;
  pedant|minions:pedant) AGENT="pedant" ;;
  witness|minions:witness) AGENT="witness" ;;
  security-reviewer|minions:security-reviewer) AGENT="security-reviewer" ;;
  silent-failure-hunter|minions:silent-failure-hunter) AGENT="silent-failure-hunter" ;;
  review-fixer|minions:review-fixer) AGENT="review-fixer" ;;
  *) exit 0 ;;
esac

ITERATION=$(state_get '.iteration')
MAX_ITERATIONS=$(state_get '.maxIterations')
CURRENT_PHASE=$(state_get '.currentPhase' --required)

ITERATION=$(require_int "$ITERATION" "iteration")
MAX_ITERATIONS=$(require_int "$MAX_ITERATIONS" "maxIterations")

ITER_DIR=".agents/tmp/phases/review-${ITERATION}"

_issue_count() {
  local file="$1"
  local raw

  if ! jq -e '.summary | has("critical") and has("warning") and has("info")' "$file" >/dev/null 2>&1; then
    echo "WARNING: $(basename "$file") missing expected .summary.{critical,warning,info}. Issue count may be inaccurate." >&2
  fi

  if ! raw=$(jq -r '((.summary.critical // 0) + (.summary.warning // 0) + (.summary.info // 0)) | floor' "$file" 2>/dev/null); then
    raw=""
  fi

  raw="${raw%%.*}"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "$raw"
  else
    echo "WARNING: Could not extract issue count from $(basename "$file"); defaulting to 0." >&2
    echo "0"
  fi
}

case "$AGENT" in
  critic|pedant|witness|security-reviewer|silent-failure-hunter)
    if [[ "$CURRENT_PHASE" != "R1" ]]; then
      exit 0
    fi

    CRITIC_FILE="${ITER_DIR}/r1-critic.json"
    PEDANT_FILE="${ITER_DIR}/r1-pedant.json"
    WITNESS_FILE="${ITER_DIR}/r1-witness.json"
    SECURITY_FILE="${ITER_DIR}/r1-security-reviewer.json"
    SILENT_FILE="${ITER_DIR}/r1-silent-failure-hunter.json"
    VERDICT_FILE="${ITER_DIR}/r1-verdict.json"
    LOCK_DIR="${ITER_DIR}/.r1-advance.lock"

    if [[ ! -f "$CRITIC_FILE" || ! -f "$PEDANT_FILE" || ! -f "$WITNESS_FILE" || ! -f "$SECURITY_FILE" || ! -f "$SILENT_FILE" ]]; then
      exit 0
    fi

    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
      if [[ -d "$LOCK_DIR" ]]; then
        lock_mtime=""
        if lock_mtime=$(lock_dir_mtime_epoch "$LOCK_DIR"); then
          lock_age=$(( $(date +%s) - lock_mtime ))
          if [[ "$lock_age" -gt 60 ]]; then
            echo "WARNING: Removing stale R1 lock directory (age: ${lock_age}s)" >&2
            rm -rf "$LOCK_DIR"
            mkdir "$LOCK_DIR" 2>/dev/null || exit 0
          else
            exit 0
          fi
        else
          exit 0
        fi
      else
        exit 0
      fi
    fi

    trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true; echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR

    LIVE_PHASE=$(jq -r '.currentPhase // empty' "$STATE_FILE" 2>/dev/null || echo "")
    R1_STATUS=$(jq -r '.iterations[-1].r1.status // "pending"' "$STATE_FILE" 2>/dev/null || echo "pending")
    if [[ "$LIVE_PHASE" != "R1" || "$R1_STATUS" == "complete" ]]; then
      rm -rf "$LOCK_DIR" 2>/dev/null || true
      trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
      exit 0
    fi

    for file in "$CRITIC_FILE" "$PEDANT_FILE" "$WITNESS_FILE" "$SECURITY_FILE" "$SILENT_FILE"; do
      if ! validate_json_file "$file" "$(basename "$file")"; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
        echo "ERROR: R1 output file $(basename "$file") is invalid JSON." >&2
        exit 2
      fi
    done

    CRITIC_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$CRITIC_FILE") || CRITIC_VERDICT="issues_found"
    PEDANT_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$PEDANT_FILE") || PEDANT_VERDICT="issues_found"
    WITNESS_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$WITNESS_FILE") || WITNESS_VERDICT="issues_found"
    SECURITY_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$SECURITY_FILE") || SECURITY_VERDICT="issues_found"
    SILENT_VERDICT=$(jq -r '.summary.verdict // "issues_found"' "$SILENT_FILE") || SILENT_VERDICT="issues_found"

    for verdict in "$CRITIC_VERDICT" "$PEDANT_VERDICT" "$WITNESS_VERDICT" "$SECURITY_VERDICT" "$SILENT_VERDICT"; do
      if [[ "$verdict" != "clean" && "$verdict" != "issues_found" ]]; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
        echo "ERROR: Unexpected reviewer verdict '$verdict'. Expected clean or issues_found." >&2
        exit 2
      fi
    done

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

    if ! jq empty "${VERDICT_FILE}.tmp" 2>/dev/null; then
      rm -rf "$LOCK_DIR" 2>/dev/null || true
      rm -f "${VERDICT_FILE}.tmp"
      trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
      echo "ERROR: Generated r1-verdict.json is invalid (possible write error)." >&2
      exit 2
    fi
    mv "${VERDICT_FILE}.tmp" "$VERDICT_FILE"

    BLOCK_REASON=""

    if [[ "$OVERALL" == "clean" ]]; then
      if ! update_state --arg verdict "$OVERALL" \
        '.status = "complete" | .currentPhase = "DONE" | .updatedAt = $ts | .iterations[-1].r1.status = "complete" | .iterations[-1].r1.verdict = $verdict | .iterations[-1].verdict = "clean"'; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
        echo "ERROR: Failed to mark review workflow as complete." >&2
        exit 2
      fi
    elif [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
      if ! update_state --arg verdict "$OVERALL" \
        '.status = "stopped" | .currentPhase = "STOPPED" | .updatedAt = $ts | .iterations[-1].r1.status = "complete" | .iterations[-1].r1.verdict = $verdict | .iterations[-1].verdict = "issues_found" | .failure = "Max review iterations reached with unresolved issues"'; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
        echo "ERROR: Failed to set review workflow to STOPPED." >&2
        exit 2
      fi
      BLOCK_REASON="WORKFLOW STOPPED: Maximum review iterations (${MAX_ITERATIONS}) reached with unresolved issues. Review the latest R1 outputs in ${ITER_DIR}/ for remaining issues."
    else
      if ! update_state --arg verdict "$OVERALL" \
        '.currentPhase = "R2" | .updatedAt = $ts | .iterations[-1].r1.status = "complete" | .iterations[-1].r1.verdict = $verdict'; then
        rm -rf "$LOCK_DIR" 2>/dev/null || true
        trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
        echo "ERROR: Failed to advance from R1 to R2." >&2
        exit 2
      fi
    fi

    rm -rf "$LOCK_DIR" 2>/dev/null || true
    trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR

    if [[ -n "$BLOCK_REASON" ]]; then
      jq -n --arg reason "$BLOCK_REASON" '{"decision":"block","reason":$reason}'
    fi
    ;;

  review-fixer)
    if [[ "$CURRENT_PHASE" != "R2" ]]; then
      exit 0
    fi

    if [[ ! -f "${ITER_DIR}/r2-fix-summary.md" ]]; then
      echo "Review-fixer completed but r2-fix-summary.md not found at ${ITER_DIR}/r2-fix-summary.md" >&2
      exit 2
    fi
    if [[ ! -s "${ITER_DIR}/r2-fix-summary.md" ]]; then
      echo "ERROR: r2-fix-summary.md is empty." >&2
      exit 2
    fi

    NEXT_ITERATION=$((ITERATION + 1))
    NEXT_ITER_DIR=".agents/tmp/phases/review-${NEXT_ITERATION}"
    mkdir -p "$NEXT_ITER_DIR"

    if ! update_state --argjson nextIter "$NEXT_ITERATION" \
      '.currentPhase = "R1" | .iteration = $nextIter | .updatedAt = $ts | .iterations[-1].r2.status = "complete" | .iterations += [{"iteration": $nextIter, "startedAt": $ts, "r1": {"status": "pending"}, "r2": {"status": "pending"}, "verdict": null}]'; then
      echo "ERROR: Failed to advance from R2 to R1 for iteration ${NEXT_ITERATION}." >&2
      exit 2
    fi
    ;;
esac

exit 0
