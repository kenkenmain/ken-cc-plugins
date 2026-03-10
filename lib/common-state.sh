#!/usr/bin/env bash
###############################################################################
# DEPRECATED since v0.5.3 / v0.15.3
#
# This file is no longer sourced by any plugin. The bootstrap logic has been
# inlined directly into each plugin's own state.sh to avoid breakage when
# plugins run from the Claude plugin cache (~/.claude/plugins/cache/).
#
# Inlined versions live at:
#   - plugins/ants/hooks/lib/state.sh
#   - plugins/minions/hooks/lib/state.sh
#   - plugins/subagents/hooks/lib/state.sh
#
# Do NOT delete this file — it is kept for reference.
###############################################################################
#
# common-state.sh — Shared bootstrap for plugin state helpers
# HISTORICAL: Was sourced from plugin-specific state.sh files (see deprecation notice above).
# Provides: STATE_FILE, jq dependency check, ERR trap.

set -Eeuo pipefail

STATE_FILE=".agents/tmp/state.json"

# Dependency check — jq is required by all hooks that source this file
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed" >&2
  exit 2
fi

# ERR trap — convert unexpected failures into informative exit-2 errors.
# Note: does NOT fire for arithmetic expansion or set -u violations (bash limitation).
trap 'echo "ERROR: ${BASH_SOURCE[0]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
