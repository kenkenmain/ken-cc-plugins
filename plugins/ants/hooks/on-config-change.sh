#!/usr/bin/env bash
# on-config-change.sh -- ConfigChange event handler for ants workflow.
# Detects configuration changes during active workflows and updates
# the config snapshot in state.json.
#
# NOTE: ConfigChange is a newer hook event. This handler is defensive
# and will exit 0 gracefully if stdin format is unexpected.
#
# Exit codes:
#   0 -- always (ConfigChange cannot block)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

check_ants_workflow

# Read stdin defensively (1MB cap for consistency with other hooks)
input=$(head -c 1048576 2>/dev/null || echo "")
if [[ -z "$input" ]] || ! printf '%s' "$input" | jq empty 2>/dev/null; then
  echo "INFO: ConfigChange hook received empty or invalid stdin. Ignoring." >&2
  exit 0
fi

# Extract config source if available
config_source=$(printf '%s' "$input" | jq -r '.config_source // .hook_event_name // "unknown"' 2>/dev/null || echo "unknown")
echo "INFO: Configuration change detected (source: ${config_source})" >&2

# Update config snapshot timestamp in state
if ! update_state --arg src "$config_source" \
  '.configSnapshot = {"lastChangeAt": $ts, "source": $src}'; then
  echo "WARNING: Failed to update configSnapshot in state.json" >&2
fi

exit 0
