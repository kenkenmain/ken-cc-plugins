#!/usr/bin/env bash
# gates.sh -- Stage gate validation library for checking required output files.
# Requires state.sh to be sourced first by the caller (provides $PHASES_DIR,
# read_state, and phase_file_exists).
set -euo pipefail

# ---------------------------------------------------------------------------
# get_gate_for_phase <phase_id> -- Find the gate whose .phase matches the
#   given phase ID (e.g., "0", "1.3", "2.3").
#   Prints the gate key string (e.g., "EXPLORE->PLAN") on stdout, or prints
#   nothing if no gate is associated with the given phase.
# ---------------------------------------------------------------------------
get_gate_for_phase() {
  local phase_id="${1:?get_gate_for_phase requires a phase ID}"

  read_state | jq -r --arg phase "$phase_id" \
    '.gates | to_entries[] | select(.value.phase == $phase) | .key // empty'
}

# ---------------------------------------------------------------------------
# validate_gate <gate_key> -- Check whether all required output files for a
#   gate exist in $PHASES_DIR.
#   Prints a JSON object on stdout:
#     {"passed":true,"missing":[]}        -- all files present
#     {"passed":false,"missing":["..."]}  -- one or more files missing
# ---------------------------------------------------------------------------
validate_gate() {
  local gate_key="${1:?validate_gate requires a gate key}"

  local required
  required="$(read_state | jq -c --arg key "$gate_key" '.gates[$key].required // []')"

  local missing=()
  local file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if ! phase_file_exists "$file"; then
      missing+=("$file")
    fi
  done < <(echo "$required" | jq -r '.[]')

  # Build the result JSON via jq
  if [[ ${#missing[@]} -eq 0 ]]; then
    jq -n '{"passed":true,"missing":[]}'
  else
    printf '%s\n' "${missing[@]}" | jq -R -s -c \
      'split("\n") | map(select(length > 0)) | {"passed":false,"missing":.}'
  fi
}
