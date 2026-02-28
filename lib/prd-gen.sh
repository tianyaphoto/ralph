#!/usr/bin/env bash
# lib/prd-gen.sh — Phase 2: Generate PRD from research gaps
# Source this file AFTER lib/utils.sh, lib/config.sh, and lib/report.sh;
# do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.

# ── Guards ────────────────────────────────────────────────────
if ! declare -f today_stamp &>/dev/null; then
  echo "[ERROR] lib/prd-gen.sh: must be sourced after lib/utils.sh" >&2
  return 1 2>/dev/null || exit 1
fi

if ! declare -f write_report &>/dev/null; then
  echo "[ERROR] lib/prd-gen.sh: must be sourced after lib/report.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# ── run_prd_gen ───────────────────────────────────────────────
# Reads gaps.json from the project repo, substitutes placeholders in
# the prompt template, invokes the configured AI tool, and validates
# the resulting prd.json.
#
# Requires: CFG_PROJECT_NAME, CFG_PROJECT_DESCRIPTION,
#           CFG_PROJECT_REPO, CFG_SCHEDULE_MAX_STORIES, RALPH_TOOL
#
# Returns: EXIT_OK on success, EXIT_RECOVERABLE on failure.
run_prd_gen() {
  log_info "Phase 2: PRD Generation — starting"

  # ── Validate gaps.json exists ─────────────────────────────
  local gaps_file="${RALPH_DIR}/.ralph-state/gaps.json"
  if [[ ! -f "$gaps_file" ]]; then
    log_error "gaps.json not found at ${gaps_file}. Run research phase first."
    return "$EXIT_RECOVERABLE"
  fi

  local gap_count
  gap_count="$(jq 'length' "$gaps_file" 2>/dev/null)" || {
    log_error "gaps.json is not valid JSON"
    return "$EXIT_RECOVERABLE"
  }

  if [[ "$gap_count" -eq 0 ]]; then
    log_info "No gaps found — nothing to generate"
    return "$EXIT_OK"
  fi

  log_info "Found ${gap_count} gaps in ${gaps_file}"

  # ── Validate prompt template exists ───────────────────────
  local prompt_file="${RALPH_DIR}/prompts/prd-gen.md"
  if [[ ! -f "$prompt_file" ]]; then
    log_error "PRD generation prompt not found: ${prompt_file}"
    return "$EXIT_RECOVERABLE"
  fi

  # ── Read gaps and build prompt ────────────────────────────
  local gaps_text
  gaps_text="$(cat "$gaps_file")"

  local today
  today="$(today_stamp)"

  # Substitute placeholders into a new copy of the prompt
  local prompt
  prompt="$(cat "$prompt_file")"
  prompt="${prompt//\{\{PROJECT_NAME\}\}/${CFG_PROJECT_NAME}}"
  prompt="${prompt//\{\{PROJECT_DESC\}\}/${CFG_PROJECT_DESCRIPTION}}"
  prompt="${prompt//\{\{MAX_STORIES\}\}/${CFG_SCHEDULE_MAX_STORIES}}"
  prompt="${prompt//\{\{GAPS_JSON\}\}/${gaps_text}}"
  prompt="${prompt//\{\{TODAY\}\}/${today}}"

  # ── Archive existing prd.json if present ──────────────────
  local prd_file="${RALPH_DIR}/prd.json"
  if [[ -f "$prd_file" ]]; then
    local archive_dir="${RALPH_DIR}/archive/${today}-pre-auto"
    mkdir -p "$archive_dir"
    cp "$prd_file" "$archive_dir/prd.json"
    if [[ -f "${RALPH_DIR}/progress.txt" ]]; then
      cp "${RALPH_DIR}/progress.txt" "$archive_dir/"
    fi
    log_info "Archived existing prd.json to ${archive_dir}"
  fi

  # ── Invoke AI tool ────────────────────────────────────────
  local work_dir="${CFG_PROJECT_REPO}"
  log_info "Running ${RALPH_TOOL} for PRD generation in: ${work_dir}"

  local output
  if [[ "$RALPH_TOOL" == "claude" ]]; then
    output="$(printf '%s\n' "$prompt" \
      | claude --dangerously-skip-permissions --print -p "$work_dir" 2>&1 \
      | tee /dev/stderr)" || true
  else
    output="$(printf '%s\n' "$prompt" \
      | amp --dangerously-allow-all 2>&1 \
      | tee /dev/stderr)" || true
  fi

  # ── Validate prd.json was created ─────────────────────────
  if [[ ! -f "$prd_file" ]]; then
    log_error "PRD generation did not produce prd.json"
    return "$EXIT_RECOVERABLE"
  fi

  # ── Validate prd.json structure ───────────────────────────
  local stories_valid
  stories_valid="$(jq -e '.userStories | type == "array"' "$prd_file" 2>/dev/null)" || {
    log_error "prd.json has invalid structure (missing or non-array .userStories)"
    return "$EXIT_RECOVERABLE"
  }

  if [[ "$stories_valid" != "true" ]]; then
    log_error "prd.json .userStories is not an array"
    return "$EXIT_RECOVERABLE"
  fi

  local story_count
  story_count="$(jq '.userStories | length' "$prd_file")"
  log_info "PRD generated with ${story_count} user stories"

  # ── Reset progress.txt for new run ────────────────────────
  {
    echo "# Ralph Progress Log"
    echo "Started: $(date)"
    echo "---"
  } > "${RALPH_DIR}/progress.txt"
  log_info "Reset progress.txt for new PRD run"

  # ── Generate report ───────────────────────────────────────
  local branch_name
  branch_name="$(jq -r '.branchName // "unknown"' "$prd_file")"

  local story_list
  story_list="$(jq -r '.userStories[] | "- \(.id): \(.title) (priority: \(.priority))"' "$prd_file")"

  local report_header
  report_header="$(phase_header "PRD Generation" "SUCCESS")"

  write_report "prd-generated.md" "${report_header}

## Generated PRD

**Stories:** ${story_count}
**Branch:** ${branch_name}

### User Stories

${story_list}
"

  log_info "Phase 2: PRD Generation — complete"
  return "$EXIT_OK"
}
