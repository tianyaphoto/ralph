#!/usr/bin/env bash
# lib/develop.sh — Phase 3: Development loop (implements user stories)
# Source this file AFTER lib/utils.sh, lib/config.sh, lib/report.sh,
# and lib/worktree.sh; do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.  The entry-point script
# (ralph.sh) is responsible for `set -euo pipefail`.

# ── Guards ────────────────────────────────────────────────────
# Verify that required libraries have been sourced.
if ! declare -f log_info &>/dev/null; then
  echo "[ERROR] lib/develop.sh: must be sourced after lib/utils.sh" >&2
  return 1 2>/dev/null || exit 1
fi

if ! declare -f write_report &>/dev/null; then
  echo "[ERROR] lib/develop.sh: must be sourced after lib/report.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# ── run_develop ───────────────────────────────────────────────
# Runs the development iteration loop: invokes the AI coding tool
# repeatedly until all user stories pass or the iteration cap is
# reached.  Writes a dev-progress.md report when finished.
#
# Prerequisites (shell variables):
#   RALPH_DIR              — project root
#   RALPH_TOOL             — "claude" or "amp"
#   CFG_DEV_MAX_ITERATIONS — maximum iteration count
#
# Returns:
#   EXIT_OK           — all stories completed
#   EXIT_RECOVERABLE  — partial progress (some stories remain)
run_develop() {
  log_info "Phase 3: Development — starting"

  local prd_file="$RALPH_DIR/prd.json"
  if [[ ! -f "$prd_file" ]]; then
    log_error "prd.json not found at $prd_file"
    return "$EXIT_RECOVERABLE"
  fi

  # ── Count remaining stories ──────────────────────────────
  local remaining
  remaining="$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file")"
  if [[ "$remaining" -eq 0 ]]; then
    log_info "All stories already complete"
    return "$EXIT_OK"
  fi

  log_info "$remaining stories remaining"

  # ── Ensure correct branch ────────────────────────────────
  local branch_name
  branch_name="$(jq -r '.branchName // "ralph/auto"' "$prd_file")"

  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" != "$branch_name" ]]; then
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
      git checkout "$branch_name"
    else
      git checkout -b "$branch_name"
    fi
  fi

  # ── Determine prompt file ───────────────────────────────
  local prompt_file
  if [[ "$RALPH_TOOL" == "claude" ]]; then
    prompt_file="$RALPH_DIR/CLAUDE.md"
  else
    prompt_file="$RALPH_DIR/prompt.md"
  fi

  # ── Render constraints into prompt ─────────────────────────
  local rendered_prompt
  rendered_prompt="$(cat "$prompt_file")"
  rendered_prompt="${rendered_prompt//\{\{CONSTRAINTS\}\}/${CFG_CONSTRAINTS:-No project constraints defined.}}"

  # ── Development iterations ──────────────────────────────
  local max_iter="${CFG_DEV_MAX_ITERATIONS:-10}"
  local completed=0
  local iter=0

  for i in $(seq 1 "$max_iter"); do
    iter="$i"

    # Re-check remaining stories between iterations
    remaining="$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file")"
    if [[ "$remaining" -eq 0 ]]; then
      log_info "All stories complete after $i iterations"
      completed=1
      break
    fi

    log_info "Development iteration $i/$max_iter ($remaining stories remaining)"

    local output
    output="$(printf '%s\n' "$rendered_prompt" | invoke_ai 2>&1 | tee /dev/stderr)" || true

    # Check for completion signal
    if echo "$output" | grep -q "<promise>COMPLETE</promise>"; then
      log_info "All stories completed!"
      completed=1
      break
    fi

    sleep 2
  done

  # ── Final story count for report ────────────────────────
  local passed
  passed="$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_file")"
  local total
  total="$(jq '.userStories | length' "$prd_file")"

  local status_label
  if [[ "$completed" -eq 1 ]]; then
    status_label="COMPLETE"
  else
    status_label="PARTIAL"
  fi

  # ── Write dev-progress.md report ────────────────────────
  write_report "dev-progress.md" "$(phase_header "Development" "$status_label")

## Development Summary

**Stories completed:** $passed / $total
**Iterations used:** $iter / $max_iter
**Branch:** $branch_name
"

  if [[ "$completed" -eq 1 ]]; then
    log_info "Phase 3: Development — all stories complete"
    return "$EXIT_OK"
  else
    log_warn "Phase 3: Development — $((total - passed)) stories remain incomplete"
    return "$EXIT_RECOVERABLE"
  fi
}
