#!/usr/bin/env bash
# Ralph — Autonomous AI agent orchestrator
#
# Usage: ./ralph.sh [options]
#
# Modes:
#   --auto              Single full cycle (research → prd-gen → develop → review → release)
#   --daemon            Continuous mode (while true + sleep)
#   --legacy            Original dev-only loop (backwards compat with current behavior)
#   --phase PHASE       Run single phase (research|prd-gen|develop|review|release)
#
# Options:
#   --tool amp|claude   Override AI tool
#   --interval 30m      Override daemon interval
#   --max-iterations N  Override max dev iterations
#   --config FILE       Override config file path
#   -h|--help           Show usage
#
# Default mode (no flags) = --auto

set -euo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RALPH_DIR

# ── Source all lib modules ──────────────────────────────────
source "$RALPH_DIR/lib/utils.sh"
source "$RALPH_DIR/lib/config.sh"
source "$RALPH_DIR/lib/report.sh"
source "$RALPH_DIR/lib/worktree.sh"
source "$RALPH_DIR/lib/research.sh"
source "$RALPH_DIR/lib/prd-gen.sh"
source "$RALPH_DIR/lib/develop.sh"
source "$RALPH_DIR/lib/review.sh"
source "$RALPH_DIR/lib/release.sh"

# ── Usage ───────────────────────────────────────────────────
usage() {
  cat <<'USAGE'
Ralph — Autonomous AI agent orchestrator

Usage: ./ralph.sh [options]

Modes:
  --auto              Single full cycle (research -> prd-gen -> develop -> review -> release)
  --daemon            Continuous mode (while true + sleep)
  --legacy            Original dev-only loop (backwards compat with current behavior)
  --phase PHASE       Run single phase (research|prd-gen|develop|review|release)

Options:
  --tool amp|claude   Override AI tool
  --interval 30m      Override daemon interval
  --max-iterations N  Override max dev iterations
  --config FILE       Override config file path
  -h|--help           Show usage

Default mode (no flags) = --auto
USAGE
}

# ── Argument parsing ────────────────────────────────────────
MODE=""
PHASE_NAME=""
OPT_TOOL=""
OPT_INTERVAL=""
OPT_MAX_ITERATIONS=""
OPT_CONFIG=""
LEGACY_MAX_ITERATIONS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)
      MODE="auto"
      shift
      ;;
    --daemon)
      MODE="daemon"
      shift
      ;;
    --legacy)
      MODE="legacy"
      shift
      ;;
    --phase)
      MODE="phase"
      PHASE_NAME="${2:-}"
      if [[ -z "$PHASE_NAME" ]]; then
        echo "Error: --phase requires a phase name (research|prd-gen|develop|review|release)" >&2
        exit 1
      fi
      shift 2
      ;;
    --phase=*)
      MODE="phase"
      PHASE_NAME="${1#*=}"
      shift
      ;;
    --tool)
      OPT_TOOL="${2:-}"
      if [[ -z "$OPT_TOOL" ]]; then
        echo "Error: --tool requires a value (amp|claude)" >&2
        exit 1
      fi
      shift 2
      ;;
    --tool=*)
      OPT_TOOL="${1#*=}"
      shift
      ;;
    --interval)
      OPT_INTERVAL="${2:-}"
      if [[ -z "$OPT_INTERVAL" ]]; then
        echo "Error: --interval requires a value (e.g. 30m)" >&2
        exit 1
      fi
      shift 2
      ;;
    --interval=*)
      OPT_INTERVAL="${1#*=}"
      shift
      ;;
    --max-iterations)
      OPT_MAX_ITERATIONS="${2:-}"
      if [[ -z "$OPT_MAX_ITERATIONS" ]]; then
        echo "Error: --max-iterations requires a number" >&2
        exit 1
      fi
      shift 2
      ;;
    --max-iterations=*)
      OPT_MAX_ITERATIONS="${1#*=}"
      shift
      ;;
    --config)
      OPT_CONFIG="${2:-}"
      if [[ -z "$OPT_CONFIG" ]]; then
        echo "Error: --config requires a file path" >&2
        exit 1
      fi
      shift 2
      ;;
    --config=*)
      OPT_CONFIG="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      # Bare number → legacy mode with max iterations (backwards compat)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        LEGACY_MAX_ITERATIONS="$1"
        if [[ -z "$MODE" ]]; then
          MODE="legacy"
        fi
      else
        echo "Error: Unknown option '$1'" >&2
        echo "Run './ralph.sh --help' for usage." >&2
        exit 1
      fi
      shift
      ;;
  esac
done

# Default mode: auto
: "${MODE:=auto}"

# ── Validate phase name ────────────────────────────────────
if [[ "$MODE" == "phase" ]]; then
  case "$PHASE_NAME" in
    research|prd-gen|develop|review|release) ;;
    *)
      echo "Error: Invalid phase '$PHASE_NAME'. Must be one of: research, prd-gen, develop, review, release" >&2
      exit 1
      ;;
  esac
fi

# ── Validate tool override ─────────────────────────────────
if [[ -n "$OPT_TOOL" ]]; then
  if [[ "$OPT_TOOL" != "amp" && "$OPT_TOOL" != "claude" ]]; then
    echo "Error: Invalid tool '$OPT_TOOL'. Must be 'amp' or 'claude'." >&2
    exit 1
  fi
fi

# ── run_phase ───────────────────────────────────────────────
# Logs phase start, saves state, dispatches to the appropriate
# phase function, logs result, and returns the exit code.
#
# Usage: run_phase "phase_name"
run_phase() {
  local phase="$1"
  local cycle="${CURRENT_CYCLE:-0}"

  log_info "Phase '$phase' starting (cycle $cycle)"
  save_state "$cycle" "$phase" "running"

  local rc=0
  case "$phase" in
    research)  run_research  || rc=$? ;;
    prd-gen)   run_prd_gen   || rc=$? ;;
    develop)   run_develop   || rc=$? ;;
    review)    run_review    || rc=$? ;;
    release)   run_release   || rc=$? ;;
    *)
      log_error "Unknown phase: $phase"
      return "$EXIT_FATAL"
      ;;
  esac

  local status_label
  case "$rc" in
    "$EXIT_OK")          status_label="success" ;;
    "$EXIT_RECOVERABLE") status_label="recoverable" ;;
    *)                   status_label="fatal" ;;
  esac

  save_state "$cycle" "$phase" "$status_label"
  log_info "Phase '$phase' finished with status: $status_label (exit $rc)"

  return "$rc"
}

# ── run_full_cycle ──────────────────────────────────────────
# Increments the cycle count, runs all 5 phases in order.
# Stops on EXIT_FATAL.  Skips remaining phases on EXIT_RECOVERABLE.
# Returns overall status.
run_full_cycle() {
  CURRENT_CYCLE="$(increment_cycle_count)"
  export CURRENT_CYCLE

  log_info "=========================================="
  log_info "  Cycle $CURRENT_CYCLE starting"
  log_info "=========================================="

  local phases=("research" "prd-gen" "develop" "review" "release")
  local overall="$EXIT_OK"

  for phase in "${phases[@]}"; do
    local rc=0
    run_phase "$phase" || rc=$?

    if [[ "$rc" -eq "$EXIT_FATAL" ]]; then
      log_error "Fatal error in phase '$phase' — aborting cycle"
      return "$EXIT_FATAL"
    fi

    if [[ "$rc" -eq "$EXIT_RECOVERABLE" ]]; then
      log_warn "Recoverable error in phase '$phase' — skipping remaining phases"
      overall="$EXIT_RECOVERABLE"
      break
    fi
  done

  log_info "=========================================="
  log_info "  Cycle $CURRENT_CYCLE finished (exit $overall)"
  log_info "=========================================="

  return "$overall"
}

# ── run_legacy ──────────────────────────────────────────────
# Preserves the EXACT behavior of the original ralph.sh:
# branch archival, iteration loop, completion detection.
# Skips config loading (users may not have ralph-config.yaml).
run_legacy() {
  local tool="${OPT_TOOL:-amp}"
  local max_iterations="${LEGACY_MAX_ITERATIONS:-${OPT_MAX_ITERATIONS:-10}}"

  # Validate tool choice
  if [[ "$tool" != "amp" && "$tool" != "claude" ]]; then
    echo "Error: Invalid tool '$tool'. Must be 'amp' or 'claude'."
    exit 1
  fi

  local prd_file="$RALPH_DIR/prd.json"
  local progress_file="$RALPH_DIR/progress.txt"
  local archive_dir="$RALPH_DIR/archive"
  local last_branch_file="$RALPH_DIR/.last-branch"

  # Archive previous run if branch changed
  if [[ -f "$prd_file" ]] && [[ -f "$last_branch_file" ]]; then
    local current_branch
    current_branch="$(jq -r '.branchName // empty' "$prd_file" 2>/dev/null || echo "")"
    local last_branch
    last_branch="$(cat "$last_branch_file" 2>/dev/null || echo "")"

    if [[ -n "$current_branch" ]] && [[ -n "$last_branch" ]] && [[ "$current_branch" != "$last_branch" ]]; then
      # Archive the previous run
      local date_stamp
      date_stamp="$(date +%Y-%m-%d)"
      # Strip "ralph/" prefix from branch name for folder
      local folder_name
      folder_name="$(echo "$last_branch" | sed 's|^ralph/||')"
      local archive_folder="$archive_dir/$date_stamp-$folder_name"

      echo "Archiving previous run: $last_branch"
      mkdir -p "$archive_folder"
      [[ -f "$prd_file" ]] && cp "$prd_file" "$archive_folder/"
      [[ -f "$progress_file" ]] && cp "$progress_file" "$archive_folder/"
      echo "   Archived to: $archive_folder"

      # Reset progress file for new run
      echo "# Ralph Progress Log" > "$progress_file"
      echo "Started: $(date)" >> "$progress_file"
      echo "---" >> "$progress_file"
    fi
  fi

  # Track current branch
  if [[ -f "$prd_file" ]]; then
    local current_branch
    current_branch="$(jq -r '.branchName // empty' "$prd_file" 2>/dev/null || echo "")"
    if [[ -n "$current_branch" ]]; then
      echo "$current_branch" > "$last_branch_file"
    fi
  fi

  # Initialize progress file if it doesn't exist
  if [[ ! -f "$progress_file" ]]; then
    echo "# Ralph Progress Log" > "$progress_file"
    echo "Started: $(date)" >> "$progress_file"
    echo "---" >> "$progress_file"
  fi

  echo "Starting Ralph - Tool: $tool - Max iterations: $max_iterations"

  for i in $(seq 1 "$max_iterations"); do
    echo ""
    echo "==============================================================="
    echo "  Ralph Iteration $i of $max_iterations ($tool)"
    echo "==============================================================="

    # Run the selected tool with the ralph prompt
    local output
    if [[ "$tool" == "amp" ]]; then
      output="$(cat "$RALPH_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr)" || true
    else
      # Claude Code: use --dangerously-skip-permissions for autonomous operation, --print for output
      output="$(claude --dangerously-skip-permissions --print < "$RALPH_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr)" || true
    fi

    # Check for completion signal
    if echo "$output" | grep -q "<promise>COMPLETE</promise>"; then
      echo ""
      echo "Ralph completed all tasks!"
      echo "Completed at iteration $i of $max_iterations"
      exit 0
    fi

    echo "Iteration $i complete. Continuing..."
    sleep 2
  done

  echo ""
  echo "Ralph reached max iterations ($max_iterations) without completing all tasks."
  echo "Check $progress_file for status."
  exit 1
}

# ── Initialize for non-legacy modes ────────────────────────
if [[ "$MODE" != "legacy" ]]; then
  # Apply config file override before loading
  if [[ -n "$OPT_CONFIG" ]]; then
    export CONFIG_FILE="$OPT_CONFIG"
  fi

  # Load config
  load_config

  # Apply CLI overrides AFTER load_config
  if [[ -n "$OPT_TOOL" ]]; then
    export CFG_DEV_TOOL="$OPT_TOOL"
    export RALPH_TOOL="$OPT_TOOL"
  fi

  if [[ -n "$OPT_INTERVAL" ]]; then
    export CFG_SCHEDULE_INTERVAL="$OPT_INTERVAL"
  fi

  if [[ -n "$OPT_MAX_ITERATIONS" ]]; then
    export CFG_DEV_MAX_ITERATIONS="$OPT_MAX_ITERATIONS"
  fi

  # Initialize logging
  init_log

  # Check dependencies
  check_all_dependencies

  # Acquire process lock
  acquire_lock
fi

# ── Dispatch ────────────────────────────────────────────────
case "$MODE" in
  auto)
    run_full_cycle
    ;;

  daemon)
    log_info "Daemon mode: running continuous cycles"
    local_interval="$(parse_interval "${CFG_SCHEDULE_INTERVAL:-30m}")"
    log_info "Daemon interval: ${CFG_SCHEDULE_INTERVAL} (${local_interval}s)"

    while true; do
      run_full_cycle || true
      log_info "Sleeping ${local_interval}s before next cycle..."
      sleep "$local_interval"
    done
    ;;

  legacy)
    run_legacy
    ;;

  phase)
    # Initialize cycle counter for single-phase runs
    CURRENT_CYCLE="$(increment_cycle_count)"
    export CURRENT_CYCLE
    run_phase "$PHASE_NAME"
    ;;

  *)
    echo "Error: Unknown mode '$MODE'" >&2
    exit 1
    ;;
esac
