#!/usr/bin/env bash
# on-stop.sh -- Stop hook: prevents Claude from stopping while a workflow is active.
# Exits 0 to allow stop, exits 2 to block stop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

# Consume stdin (hook input)
cat > /dev/null

# Allow stop if no state file exists (no workflow)
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Check workflow status
STATUS="$(state_get '.status // empty')"

case "$STATUS" in
  completed|stopped|failed|blocked)
    # Terminal states -- allow stop
    exit 0
    ;;
  in_progress)
    CURRENT_PHASE="$(state_get '.currentPhase // "unknown"')"
    CURRENT_STAGE="$(state_get '.currentStage // "unknown"')"
    echo "Subagent workflow active at Phase $CURRENT_PHASE ($CURRENT_STAGE). Do not stop — continue executing the workflow. Read state from .agents/tmp/state.json and dispatch the current phase." >&2
    exit 2
    ;;
  *)
    # Unknown or empty status -- allow stop
    exit 0
    ;;
esac
