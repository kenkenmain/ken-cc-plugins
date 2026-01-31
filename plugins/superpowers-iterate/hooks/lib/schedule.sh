#!/usr/bin/env bash
# schedule.sh -- Phase advancement logic for the superpowers-iterate workflow.
# Requires state.sh to be sourced first (provides: read_state, state_get, STATE_FILE, etc.)
set -euo pipefail

# ---------------------------------------------------------------------------
# get_phase_output <phase> -- Return the expected output filename for a phase.
# ---------------------------------------------------------------------------
get_phase_output() {
  local phase="${1:?get_phase_output requires a phase ID}"

  case "$phase" in
    1)   echo "1-brainstorm.md" ;;
    2)   echo "2-plan.md" ;;
    3)   echo "3-plan-review.json" ;;
    4)   echo "4-tasks.json" ;;
    5)   echo "5-review.json" ;;
    6)   echo "6-test-results.json" ;;
    7)   echo "7-simplify.md" ;;
    8)   echo "8-final-review.json" ;;
    9)   echo "9-codex-final.json" ;;
    C)   echo "C-completion.json" ;;
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
    1)   echo "task description (from state.json)" ;;
    2)   echo ".agents/tmp/iterate/phases/1-brainstorm.md" ;;
    3)   echo ".agents/tmp/iterate/phases/2-plan.md" ;;
    4)   echo ".agents/tmp/iterate/phases/2-plan.md" ;;
    5)   echo ".agents/tmp/iterate/phases/2-plan.md, git diff" ;;
    6)   echo "config test commands" ;;
    7)   echo ".agents/tmp/iterate/phases/4-tasks.json" ;;
    8)   echo "all .agents/tmp/iterate/phases/*.json, git diff" ;;
    9)   echo ".agents/tmp/iterate/phases/8-final-review.json" ;;
    C)   echo ".agents/tmp/iterate/phases/8-final-review.json" ;;
    *)   echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# get_phase_template <phase> -- Return the prompt template filename for a phase.
#   Uses a deterministic lookup (not slug generation) to avoid mismatches.
# ---------------------------------------------------------------------------
get_phase_template() {
  local phase="${1:?get_phase_template requires a phase ID}"

  case "$phase" in
    1)   echo "1-brainstorm.md" ;;
    2)   echo "2-plan.md" ;;
    3)   echo "3-plan-review.md" ;;
    4)   echo "4-implement.md" ;;
    5)   echo "5-review.md" ;;
    6)   echo "6-test.md" ;;
    7)   echo "7-simplify.md" ;;
    8)   echo "8-final-review.md" ;;
    9)   echo "9-codex-final.md" ;;
    C)   echo "C-completion.md" ;;
    *)   echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# build_chain_instruction <next_json> -- Build a human-readable instruction
#   string for the next phase from a JSON schedule entry.
#   Example output:
#     "Phase complete. Execute next: Phase 1 (PLAN) -- Brainstorm [subagent].
#      Read prompt template from prompts/phases/1-brainstorm.md.
#      Input files: task description (from state.json)"
# ---------------------------------------------------------------------------
build_chain_instruction() {
  local next_json="${1:?build_chain_instruction requires a JSON string}"

  local phase name stage type
  phase="$(echo "$next_json" | jq -r '.phase')"
  name="$(echo "$next_json" | jq -r '.name')"
  stage="$(echo "$next_json" | jq -r '.stage')"
  type="$(echo "$next_json" | jq -r '.type')"

  local template_file
  template_file="$(get_phase_template "$phase")"

  local input_files
  input_files="$(get_phase_input_files "$phase")"

  echo "Phase complete. Execute next: Phase ${phase} (${stage}) -- ${name} [${type}]. Read prompt template from prompts/phases/${template_file}. Input files: ${input_files}"
}
