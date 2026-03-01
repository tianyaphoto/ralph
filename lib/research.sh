#!/usr/bin/env bash
# lib/research.sh — Research phase for Ralph autonomous agent
# Source this file AFTER lib/utils.sh, lib/config.sh, and lib/report.sh;
# do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.

# ── Guards ────────────────────────────────────────────────────
if ! declare -f today_dir &>/dev/null; then
  echo "[ERROR] lib/research.sh: must be sourced after lib/utils.sh" >&2
  return 1 2>/dev/null || exit 1
fi

if ! declare -f load_config &>/dev/null; then
  echo "[ERROR] lib/research.sh: must be sourced after lib/config.sh" >&2
  return 1 2>/dev/null || exit 1
fi

if ! declare -f write_report &>/dev/null; then
  echo "[ERROR] lib/research.sh: must be sourced after lib/report.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# ── Prompt template path ──────────────────────────────────────
RESEARCH_PROMPT_TEMPLATE="${RALPH_DIR}/prompts/research.md"

# ── _build_competitor_text ────────────────────────────────────
# Converts the CFG_RESEARCH_COMPETITORS JSON array into a
# human-readable markdown list suitable for prompt injection.
# Output is written to stdout.
_build_competitor_text() {
  local json="${1:-"[]"}"

  local count
  count="$(jq 'length' <<< "$json")"

  if [[ "$count" -eq 0 ]]; then
    echo "(No competitors configured.)"
    return 0
  fi

  jq -r '
    .[] |
    "- **" + (.name // "unknown") + "**"
    + (if .github  then "\n  - GitHub: "  + .github  else "" end)
    + (if .website then "\n  - Website: " + .website else "" end)
  ' <<< "$json"
}

# ── _build_requirements_text ──────────────────────────────────
# Converts a JSON array of user requirements into a
# human-readable markdown list for prompt injection.
# Output is written to stdout.
_build_requirements_text() {
  local json="${1:-"[]"}"

  local count
  count="$(jq 'length' <<< "$json")"

  if [[ "$count" -eq 0 ]]; then
    echo "(No user requirements provided.)"
    return 0
  fi

  # Warn about items missing required fields
  local invalid
  invalid="$(jq '[.[] | select(.title == null or .description == null or .priority == null)] | length' <<< "$json")"
  if [[ "$invalid" -gt 0 ]]; then
    log_warn "$invalid requirement(s) missing required fields (title, description, priority)" >&2
  fi

  jq -r '
    .[] |
    "- **" + (.title // "untitled") + "** (" + (.priority // "medium") + ")\n"
    + "  " + (.description // "")
    + (if .context then "\n  Context: " + (.context | gsub("\n"; "\n  ")) else "" end)
  ' <<< "$json"
}

# ── _build_dimension_text ─────────────────────────────────────
# Converts the CFG_RESEARCH_DIMENSIONS JSON array into a
# numbered markdown list.  Output is written to stdout.
_build_dimension_text() {
  local json="${1:-"[]"}"

  local count
  count="$(jq 'length' <<< "$json")"

  if [[ "$count" -eq 0 ]]; then
    echo "(No dimensions configured.)"
    return 0
  fi

  jq -r 'to_entries | .[] | "\(.key + 1). \(.value)"' <<< "$json"
}

# ── _render_prompt ────────────────────────────────────────────
# Reads the prompt template and substitutes {{PLACEHOLDER}}
# tokens with actual config values.  Returns rendered text on
# stdout, or returns EXIT_RECOVERABLE on error.
_render_prompt() {
  if [[ ! -f "$RESEARCH_PROMPT_TEMPLATE" ]]; then
    log_error "Research prompt template not found: $RESEARCH_PROMPT_TEMPLATE"
    return "$EXIT_RECOVERABLE"
  fi

  local template
  template="$(cat "$RESEARCH_PROMPT_TEMPLATE")"

  local competitor_text
  competitor_text="$(_build_competitor_text "$CFG_RESEARCH_COMPETITORS")"

  local dimension_text
  dimension_text="$(_build_dimension_text "$CFG_RESEARCH_DIMENSIONS")"

  local requirements_text
  requirements_text="$(_build_requirements_text "${CFG_USER_REQUIREMENTS:-[]}")"

  # Perform substitutions using simple parameter expansion.
  # Each placeholder is replaced exactly once — order does not matter.
  local rendered="$template"
  rendered="${rendered//\{\{PROJECT_NAME\}\}/${CFG_PROJECT_NAME}}"
  rendered="${rendered//\{\{PROJECT_DESC\}\}/${CFG_PROJECT_DESCRIPTION}}"
  rendered="${rendered//\{\{COMPETITORS\}\}/${competitor_text}}"
  rendered="${rendered//\{\{DIMENSIONS\}\}/${dimension_text}}"
  rendered="${rendered//\{\{AUTO_DISCOVER\}\}/${CFG_RESEARCH_AUTO_DISCOVER}}"
  rendered="${rendered//\{\{REQUIREMENTS\}\}/${requirements_text}}"

  printf '%s\n' "$rendered"
}

# ── _validate_gaps_json ───────────────────────────────────────
# Checks that a file exists and contains a valid JSON array.
# Returns 0 on success, 1 on failure.
_validate_gaps_json() {
  local filepath="$1"

  if [[ ! -f "$filepath" ]]; then
    log_error "gaps.json not found at: $filepath"
    return 1
  fi

  if ! jq 'if type == "array" then empty else error("not an array") end' "$filepath" >/dev/null 2>&1; then
    log_error "gaps.json is not a valid JSON array"
    return 1
  fi

  local item_count
  item_count="$(jq 'length' "$filepath")"
  log_info "gaps.json validated: $item_count gap(s) found"

  # Warn if any entries are missing the source field
  local missing_source
  missing_source="$(jq '[.[] | select(.source == null)] | length' "$filepath")"
  if [[ "$missing_source" -gt 0 ]]; then
    log_warn "gaps.json: $missing_source entry/entries missing 'source' field"
  fi

  return 0
}

# ── run_research ──────────────────────────────────────────────
# Main entry point for the research phase.
#
# 1. Renders the prompt template with config values.
# 2. Invokes the configured AI tool (claude or amp).
# 3. Validates that gaps.json was produced.
# 4. Archives reports to today's report directory.
#
# Returns EXIT_OK on success, EXIT_RECOVERABLE on failure.
run_research() {
  log_info "Research phase: starting"

  # ── Render the prompt ───────────────────────────────────
  local rendered_prompt
  rendered_prompt="$(_render_prompt)" || return "$EXIT_RECOVERABLE"

  # ── Prepare a working directory for AI output ───────────
  local work_dir
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-research.XXXXXX")"
  log_info "Research working directory: $work_dir"

  # Write rendered prompt to a file so the AI tool can read it
  local prompt_file="$work_dir/prompt.md"
  printf '%s\n' "$rendered_prompt" > "$prompt_file"

  # ── Invoke AI tool ──────────────────────────────────────
  local ai_exit=0
  log_info "Invoking $RALPH_TOOL for research analysis"

  (cd "$work_dir" && invoke_ai < "$prompt_file") \
    > "$work_dir/ai-output.log" 2>&1 || ai_exit=$?

  if [[ "$ai_exit" -ne 0 ]]; then
    log_warn "AI tool exited with code $ai_exit (may still have produced output)"
  fi

  # ── Validate outputs ───────────────────────────────────
  local gaps_file="$work_dir/gaps.json"
  local report_file="$work_dir/research-report.md"

  if ! _validate_gaps_json "$gaps_file"; then
    log_error "Research phase failed: gaps.json validation failed"
    rm -rf "$work_dir"
    return "$EXIT_RECOVERABLE"
  fi

  # ── Archive reports to today's directory ────────────────
  local date_dir
  date_dir="$(today_dir)"
  mkdir -p "$date_dir"

  cp "$gaps_file" "$date_dir/gaps.json"
  log_info "Archived: $date_dir/gaps.json"

  # Also copy gaps.json to .ralph-state/ so prd-gen phase can find it
  local state_dir="${RALPH_DIR}/.ralph-state"
  mkdir -p "$state_dir"
  cp "$gaps_file" "$state_dir/gaps.json"
  log_info "Copied gaps.json to: $state_dir/gaps.json"

  if [[ -f "$report_file" ]]; then
    cp "$report_file" "$date_dir/research-report.md"
    log_info "Archived: $date_dir/research-report.md"
  else
    log_warn "research-report.md was not produced by AI tool"
  fi

  # Copy AI output log for debugging
  if [[ -f "$work_dir/ai-output.log" ]]; then
    cp "$work_dir/ai-output.log" "$date_dir/research-ai-output.log"
  fi

  # ── Cleanup ─────────────────────────────────────────────
  rm -rf "$work_dir"

  log_info "Research phase: complete"
  return "$EXIT_OK"
}
