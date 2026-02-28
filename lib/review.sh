#!/usr/bin/env bash
# lib/review.sh — Review phase: build/test/lint verification + AI code review
# Source this file AFTER lib/utils.sh, lib/config.sh, and lib/report.sh;
# do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.  The entry-point script
# (ralph.sh) is responsible for `set -euo pipefail`.

# ── Guards ────────────────────────────────────────────────────
if ! declare -f today_dir &>/dev/null; then
  echo "[ERROR] lib/review.sh: must be sourced after lib/utils.sh" >&2
  return 1 2>/dev/null || exit 1
fi

if ! declare -f write_report &>/dev/null; then
  echo "[ERROR] lib/review.sh: must be sourced after lib/report.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# ── Constants ─────────────────────────────────────────────────
readonly MAX_REVIEW_RETRIES=3

# ── Internal helpers ──────────────────────────────────────────

# _run_check — Execute a configured check command.
# Arguments:
#   $1 — label (e.g. "build", "tests", "lint")
#   $2 — command string from config (may be empty → skip)
#   $3 — "blocking" or "non-blocking" (non-blocking always returns 0)
# Returns 0 on pass/skip, 1 on blocking failure.
_run_check() {
  local label="$1"
  local cmd="${2:-}"
  local mode="${3:-blocking}"

  if [[ -z "$cmd" ]]; then
    log_info "No ${label} command configured, skipping ${label}"
    return 0
  fi

  local work_dir="${CFG_PROJECT_REPO:-.}"
  log_info "Running ${label}: ${cmd} (in ${work_dir})"

  if (cd "$work_dir" && bash -c "$cmd"); then
    log_info "${label^} passed"
    return 0
  fi

  if [[ "$mode" == "non-blocking" ]]; then
    log_warn "${label^} reported issues (non-blocking)"
    return 0
  fi

  log_error "${label^} failed"
  return 1
}

# _ask_ai_to_fix — Ask the AI tool to diagnose and fix build/test failures.
# Arguments: $1 = description of what failed
_ask_ai_to_fix() {
  local failure_description="$1"

  log_info "Asking ${RALPH_TOOL:-claude} to fix: $failure_description"

  local fix_prompt
  fix_prompt="The following check failed: ${failure_description}. "
  fix_prompt+="Diagnose the root cause and apply a minimal fix. "
  fix_prompt+="Then commit with message: fix: ${failure_description}"

  printf '%s\n' "$fix_prompt" | invoke_ai 2>&1 | while IFS= read -r line; do
    log_info "[${RALPH_TOOL:-claude}] $line"
  done
}

# _run_ai_review — Run AI code review using prompts/review.md.
_run_ai_review() {
  local prompt_file="${RALPH_DIR}/prompts/review.md"

  if [[ ! -f "$prompt_file" ]]; then
    log_warn "Review prompt not found: $prompt_file — skipping AI review"
    return 0
  fi

  log_info "Running AI code review via $prompt_file"

  invoke_ai < "$prompt_file" 2>&1 | while IFS= read -r line; do
    log_info "[review] $line"
  done
}

# _archive_review_report — Move review-report.md to the dated report directory.
_archive_review_report() {
  local report_file="review-report.md"

  # Check current directory first, then RALPH_DIR
  local source=""
  if [[ -f "$report_file" ]]; then
    source="$report_file"
  elif [[ -f "${RALPH_DIR}/${report_file}" ]]; then
    source="${RALPH_DIR}/${report_file}"
  fi

  if [[ -z "$source" ]]; then
    log_warn "No review-report.md found to archive"
    return 0
  fi

  local date_dir
  date_dir="$(today_dir)"
  mkdir -p "$date_dir"

  local dest="${date_dir}/${report_file}"
  cp "$source" "$dest"
  rm -f "$source"

  log_info "Review report archived: $dest"
  return 0
}

# ── Public API ────────────────────────────────────────────────

# run_review — Build/test/lint verification loop with AI-assisted
# fix-up and code review.
#
# Loops up to MAX_REVIEW_RETRIES times:
#   1. Run build (if configured) — check exit code
#   2. Run tests (if configured and build passed)
#   3. Run lint  (if configured, non-blocking)
#   4. If build/test failed and retries remain → ask AI to fix
#   5. If all passed → run AI code review
#   6. Archive review-report.md to today_dir
#
# Returns EXIT_OK (0) if all checks pass, EXIT_RECOVERABLE (1)
# if checks still fail after all retries.
run_review() {
  log_info "=== Review phase starting (max retries: $MAX_REVIEW_RETRIES) ==="

  local attempt=0
  local build_ok=0
  local tests_ok=0

  while (( attempt < MAX_REVIEW_RETRIES )); do
    attempt=$((attempt + 1))
    log_info "--- Review attempt $attempt of $MAX_REVIEW_RETRIES ---"

    build_ok=0
    tests_ok=0

    # ── Build ──
    if _run_check "build" "${CFG_PROJECT_BUILD_COMMAND:-}" "blocking"; then
      build_ok=1
    fi

    # ── Tests (only if build passed) ──
    if (( build_ok == 1 )); then
      if _run_check "tests" "${CFG_PROJECT_TEST_COMMAND:-}" "blocking"; then
        tests_ok=1
      fi
    fi

    # ── Lint (non-blocking, run regardless) ──
    _run_check "lint" "${CFG_PROJECT_LINT_COMMAND:-}" "non-blocking"

    # ── Evaluate results ──
    if (( build_ok == 1 && tests_ok == 1 )); then
      log_info "Build and tests passed on attempt $attempt"
      break
    fi

    # Determine what failed for the AI fix prompt
    local failure=""
    if (( build_ok == 0 )); then
      failure="build failure — command: ${CFG_PROJECT_BUILD_COMMAND:-unknown}"
    else
      failure="test failure — command: ${CFG_PROJECT_TEST_COMMAND:-unknown}"
    fi

    if (( attempt < MAX_REVIEW_RETRIES )); then
      log_warn "Checks failed on attempt $attempt, asking AI to fix"
      _ask_ai_to_fix "$failure"
    else
      log_error "Checks failed after $MAX_REVIEW_RETRIES attempts"
    fi
  done

  # ── Final verdict ──
  if (( build_ok == 0 || tests_ok == 0 )); then
    log_error "Review phase FAILED after $MAX_REVIEW_RETRIES retries"
    return "$EXIT_RECOVERABLE"
  fi

  # ── All checks passed — run AI code review ──
  _run_ai_review
  _archive_review_report

  log_info "=== Review phase PASSED ==="
  return "$EXIT_OK"
}
