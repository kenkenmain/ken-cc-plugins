#!/usr/bin/env bash
# common-state.sh — Shared bootstrap for plugin state helpers
# Source this from plugin-specific state.sh files.
# Provides: STATE_FILE, jq dependency check, ERR trap.

set -euo pipefail

STATE_FILE=".agents/tmp/state.json"

# Dependency check — jq is required by all hooks that source this file
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed" >&2
  exit 2
fi

# ERR trap — convert unexpected failures into informative exit-2 errors.
# Note: does NOT fire for arithmetic expansion or set -u violations (bash limitation).
trap 'echo "ERROR: ${BASH_SOURCE[1]:-unknown} failed at line ${BASH_LINENO[0]:-?} (exit code $?)" >&2; exit 2' ERR
