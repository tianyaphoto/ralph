#!/usr/bin/env bash
# lib/utils.sh — Common utilities for Ralph autonomous agent
# Source this file; do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.  The entry-point script
# (ralph.sh) is responsible for `set -euo pipefail`.

# ── Exit codes ──────────────────────────────────────────────
readonly EXIT_OK=0
readonly EXIT_RECOVERABLE=1
readonly EXIT_FATAL=2

# ── Paths ───────────────────────────────────────────────────
# RALPH_DIR must be set by the sourcing script (ralph.sh sets it).
# Fallback: derive from this file's location (lib/ -> parent).
: "${RALPH_DIR:="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}"
STATE_DIR="$RALPH_DIR/.ralph-state"
REPORTS_BASE="$RALPH_DIR/reports"

# ── Logging ─────────────────────────────────────────────────
_LOG_FILE=""

_log() {
  local level="$1"; shift
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  local msg="[$ts] [$level] $*"
  echo "$msg" >&2
  [[ -n "$_LOG_FILE" ]] && echo "$msg" >> "$_LOG_FILE"
  return 0
}

log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@"; }
log_error() { _log "ERROR" "$@"; }

init_log() {
  local date_dir
  date_dir="$(today_dir)"
  mkdir -p "$date_dir"
  _LOG_FILE="$date_dir/ralph.log"
}

# ── Date helpers ────────────────────────────────────────────
today_stamp() { date '+%Y-%m-%d'; }
today_dir()   { echo "$REPORTS_BASE/$(today_stamp)"; }
now_iso()     { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# ── Process lock (mkdir-based, atomic) ─────────────────────
acquire_lock() {
  mkdir -p "$STATE_DIR"
  local lockdir="$STATE_DIR/lock.d"

  if mkdir "$lockdir" 2>/dev/null; then
    # Lock acquired — record our PID
    echo $$ > "$lockdir/pid"
    trap 'release_lock' EXIT
    return 0
  fi

  # Lock directory already exists — check for stale lock
  local pidfile="$lockdir/pid"
  if [[ -f "$pidfile" ]]; then
    local old_pid
    old_pid="$(cat "$pidfile")"
    if kill -0 "$old_pid" 2>/dev/null; then
      log_error "Another Ralph instance is running (PID $old_pid)"
      return "$EXIT_FATAL"
    else
      log_warn "Stale lock found (PID $old_pid), removing"
      rm -rf "$lockdir"
    fi
  else
    # Lock dir exists but no pid file — treat as stale
    log_warn "Stale lock directory found (no pid file), removing"
    rm -rf "$lockdir"
  fi

  # Retry after removing stale lock
  if mkdir "$lockdir" 2>/dev/null; then
    echo $$ > "$lockdir/pid"
    trap 'release_lock' EXIT
    return 0
  fi

  log_error "Failed to acquire lock after removing stale lock"
  return "$EXIT_FATAL"
}

release_lock() {
  rm -rf "$STATE_DIR/lock.d"
}

# ── State management ────────────────────────────────────────
save_state() {
  local cycle="$1" phase="$2" status="$3"
  mkdir -p "$STATE_DIR"
  jq -n \
    --argjson cycle "$cycle" \
    --arg phase "$phase" \
    --arg status "$status" \
    --arg timestamp "$(now_iso)" \
    '{"cycle": $cycle, "phase": $phase, "timestamp": $timestamp, "status": $status}' \
    > "$STATE_DIR/last-run.json"
}

load_state() {
  local state_file="$STATE_DIR/last-run.json"
  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo '{}'
  fi
}

increment_cycle_count() {
  local count_file="$STATE_DIR/cycle-count"
  local count=0
  [[ -f "$count_file" ]] && count="$(cat "$count_file")"
  count=$((count + 1))

  local tmpfile
  tmpfile="$(mktemp "$STATE_DIR/cycle-count.XXXXXX")"
  echo "$count" > "$tmpfile"
  mv -f "$tmpfile" "$count_file"

  echo "$count"
}

# ── Dependency checking ─────────────────────────────────────
check_dependency() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    log_error "Required dependency not found: $cmd"
    return "$EXIT_FATAL"
  fi
}

check_all_dependencies() {
  local deps=("jq" "yq" "gh" "git")
  local missing=0
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      log_error "Missing dependency: $dep"
      missing=1
    fi
  done
  # Check for configured AI tool (RALPH_TOOL defaults to claude)
  local tool="${RALPH_TOOL:-claude}"
  if ! command -v "$tool" &>/dev/null; then
    log_error "Missing AI tool: $tool"
    missing=1
  fi
  return "$missing"
}

# ── AI tool invocation ──────────────────────────────────────
# invoke_ai — Run the configured AI tool.
# Reads prompt from stdin, writes output to stdout.
# Passes through any extra arguments (e.g. -p dir).
#
# Usage:
#   printf '%s' "$prompt" | invoke_ai
#   invoke_ai < prompt.md
#   invoke_ai -p "$work_dir" < prompt.md
invoke_ai() {
  local tool="${RALPH_TOOL:-claude}"
  if ! command -v "$tool" &>/dev/null; then
    log_error "AI tool not found: $tool"
    return 1
  fi
  case "$tool" in
    claude) "$tool" --dangerously-skip-permissions --print "$@" ;;
    amp)    "$tool" --dangerously-allow-all "$@" ;;
    *)      log_error "Unknown AI tool: $tool"; return 1 ;;
  esac
}

# ── Misc helpers ────────────────────────────────────────────
# Parse interval string like "30m", "1h", "2h30m", or plain seconds.
# Returns 1 on empty or unrecognized input.
parse_interval() {
  local input="${1:-}"

  if [[ -z "$input" ]]; then
    log_error "parse_interval: empty input"
    return 1
  fi

  local seconds=0
  local matched=0

  # Extract hours
  if [[ "$input" =~ ([0-9]+)h ]]; then
    seconds=$((seconds + ${BASH_REMATCH[1]} * 3600))
    matched=1
  fi

  # Extract minutes
  if [[ "$input" =~ ([0-9]+)m ]]; then
    seconds=$((seconds + ${BASH_REMATCH[1]} * 60))
    matched=1
  fi

  # Plain number = treat as seconds
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    seconds=$input
    matched=1
  fi

  if (( matched == 0 )); then
    log_error "parse_interval: unrecognized format '$input'"
    return 1
  fi

  echo "$seconds"
}
