#!/usr/bin/env bash
# on-stop.sh — Graceful shutdown for ants workflow via continue:false
# Sets .shutdown=true in state and signals Claude to stop.
# For complete/blocked/stopped workflows, allows stop without intervention.
#
# Exit codes:
#   0 — allow stop (complete/blocked/stopped or no active workflow)
#   0 — continue:false JSON output (in_progress → graceful shutdown)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/state.sh"

# check_ants_workflow exits 0 if no state file, wrong plugin, wrong session,
# or status is not in_progress. Only returns 0 (continues) for in_progress.
check_ants_workflow

# Workflow is in_progress — set shutdown flag
update_state '.shutdown = true | .updatedAt = $ts'

# Signal Claude to stop gracefully
continue_false_exit "Ants workflow shutdown initiated. Teammates will complete current tasks."
