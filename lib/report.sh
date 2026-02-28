#!/usr/bin/env bash
# lib/report.sh — Report generation utilities for Ralph autonomous agent
# Source this file AFTER lib/utils.sh; do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.

# ── Guards ────────────────────────────────────────────────────
# Verify that utils.sh has been sourced (provides today_dir, now_iso,
# log_info, and the REPORTS_BASE variable).
if ! declare -f today_dir &>/dev/null; then
  echo "[ERROR] lib/report.sh: must be sourced after lib/utils.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# ── write_report ──────────────────────────────────────────────
# Write content to a dated report file, creating the directory if
# needed.  Prints the absolute filepath to stdout.
#
# Usage: write_report "filename.md" "content"
write_report() {
  local filename="${1:-}"
  local content="${2:-}"

  if [[ -z "$filename" ]]; then
    log_error "write_report: filename is required"
    return 1
  fi

  local date_dir
  date_dir="$(today_dir)"
  mkdir -p "$date_dir"

  local filepath="$date_dir/$filename"
  printf '%s\n' "$content" > "$filepath"

  log_info "Report written: $filepath"
  echo "$filepath"
}

# ── append_report ─────────────────────────────────────────────
# Append content to an existing dated report file.  Creates the file
# (and directory) if it does not yet exist.  Prints the absolute
# filepath to stdout.
#
# Usage: append_report "filename.md" "content"
append_report() {
  local filename="${1:-}"
  local content="${2:-}"

  if [[ -z "$filename" ]]; then
    log_error "append_report: filename is required"
    return 1
  fi

  local date_dir
  date_dir="$(today_dir)"
  mkdir -p "$date_dir"

  local filepath="$date_dir/$filename"
  printf '%s\n' "$content" >> "$filepath"

  log_info "Report appended: $filepath"
  echo "$filepath"
}

# ── phase_header ──────────────────────────────────────────────
# Output a markdown header block for a phase report.  Includes the
# phase name, status, ISO-8601 timestamp, and current cycle number.
#
# Usage: phase_header "PhaseName" "status"
# Output (stdout):
#   # PhaseName
#   **Status:** status
#   **Timestamp:** 2026-02-28T12:00:00Z
#   **Cycle:** 1
phase_header() {
  local phase_name="${1:-}"
  local status="${2:-}"

  if [[ -z "$phase_name" ]]; then
    log_error "phase_header: phase name is required"
    return 1
  fi

  local timestamp
  timestamp="$(now_iso)"

  local cycle="${CURRENT_CYCLE:-0}"

  printf '# %s\n' "$phase_name"
  printf '**Status:** %s\n' "$status"
  printf '**Timestamp:** %s\n' "$timestamp"
  printf '**Cycle:** %s\n' "$cycle"
}
