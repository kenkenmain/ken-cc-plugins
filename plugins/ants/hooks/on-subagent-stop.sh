#!/usr/bin/env bash
# on-subagent-stop.sh — No-op in Agent Teams mode
# Teams mode: TaskCompleted handles validation and state advancement.
# SubagentStop may still fire for internal subagents. Allow silently.
#
# Exit codes:
#   0 — allow (always)

exit 0
