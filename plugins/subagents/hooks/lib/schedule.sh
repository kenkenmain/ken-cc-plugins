#!/usr/bin/env bash
# schedule.sh -- Phase advancement logic for the subagents workflow.
# Requires state.sh to be sourced first (provides: read_state, state_get, STATE_FILE, etc.)
set -euo pipefail

# ---------------------------------------------------------------------------
# get_phase_output <phase> -- Return the expected output filename for a phase.
# ---------------------------------------------------------------------------
get_phase_output() {
  local phase="${1:?get_phase_output requires a phase ID}"

  case "$phase" in
    0)   echo "0-explore.md" ;;
    1.1) echo "1.1-brainstorm.md" ;;
    1.2) echo "1.2-plan.md" ;;
    1.3) echo "1.3-plan-review.json" ;;
    2.1) echo "2.1-tasks.json" ;;
    2.2) echo "2.2-simplify.md" ;;
    2.3) echo "2.3-impl-review.json" ;;
    3.1) echo "3.1-test-results.json" ;;
    3.2) echo "3.2-analysis.md" ;;
    3.3) echo "3.3-test-review.json" ;;
    4.1) echo "4.1-docs.md" ;;
    4.2) echo "4.2-final-review.json" ;;
    4.3) echo "4.3-completion.json" ;;
    *)   echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# get_next_phase <current_phase> -- Return the next schedule entry as JSON,
#   or the string "null" if current_phase is the last entry.
# ---------------------------------------------------------------------------
get_next_phase() {
  local current_phase="${1:?get_next_phase requires a phase ID}"

  local result
  result="$(read_state | jq -r --arg cp "$current_phase" '
    .schedule as $sched |
    ($sched | to_entries | map(select(.value.phase == $cp)) | .[0].key) as $idx |
    if $idx == null then "null"
    elif ($idx + 1) >= ($sched | length) then "null"
    else $sched[$idx + 1] | tojson
    end
  ')"

  echo "$result"
}

# ---------------------------------------------------------------------------
# is_last_phase <phase> -- Return 0 (true) if phase is the last in the
#   schedule, 1 (false) otherwise.
# ---------------------------------------------------------------------------
is_last_phase() {
  local phase="${1:?is_last_phase requires a phase ID}"

  local next
  next="$(get_next_phase "$phase")"
  [[ "$next" == "null" ]]
}

# ---------------------------------------------------------------------------
# get_phase_input_files <phase> -- Return a human-readable description of
#   the input files or sources for a given phase.
# ---------------------------------------------------------------------------
get_phase_input_files() {
  local phase="${1:?get_phase_input_files requires a phase ID}"

  case "$phase" in
    0)   echo "task description (from state.json)" ;;
    1.1) echo ".agents/tmp/phases/0-explore.md" ;;
    1.2) echo ".agents/tmp/phases/1.1-brainstorm.md" ;;
    1.3) echo ".agents/tmp/phases/1.2-plan.md" ;;
    2.1) echo ".agents/tmp/phases/1.2-plan.md" ;;
    2.2) echo ".agents/tmp/phases/2.1-tasks.json" ;;
    2.3) echo ".agents/tmp/phases/1.2-plan.md, git diff" ;;
    3.1) echo "config test commands" ;;
    3.2) echo ".agents/tmp/phases/3.1-test-results.json" ;;
    3.3) echo ".agents/tmp/phases/3.1-test-results.json, .agents/tmp/phases/3.2-analysis.md" ;;
    4.1) echo ".agents/tmp/phases/1.2-plan.md, .agents/tmp/phases/2.1-tasks.json" ;;
    4.2) echo "all .agents/tmp/phases/*.json" ;;
    4.3) echo ".agents/tmp/phases/4.2-final-review.json" ;;
    *)   echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# build_chain_instruction <next_json> -- Build a human-readable instruction
#   string for the next phase from a JSON schedule entry.
#   Example output:
#     "Phase complete. Execute next: Phase 1.1 (PLAN) -- Brainstorm [inline].
#      Read prompt template from prompts/phases/1.1-brainstorm.md.
#      Input files: .agents/tmp/phases/0-explore.md"
# ---------------------------------------------------------------------------
build_chain_instruction() {
  local next_json="${1:?build_chain_instruction requires a JSON string}"

  local phase name stage type
  phase="$(echo "$next_json" | jq -r '.phase')"
  name="$(echo "$next_json" | jq -r '.name')"
  stage="$(echo "$next_json" | jq -r '.stage')"
  type="$(echo "$next_json" | jq -r '.type')"

  local input_files
  input_files="$(get_phase_input_files "$phase")"

  echo "Phase complete. Execute next: Phase ${phase} (${stage}) -- ${name} [${type}]. Read prompt template from prompts/phases/${phase}-$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').md. Input files: ${input_files}"
}
