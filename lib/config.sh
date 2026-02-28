#!/usr/bin/env bash
# lib/config.sh — YAML config loader for Ralph autonomous agent
# Source this file; do not execute directly.
# Requires: yq, lib/utils.sh (for logging)

# ── Config loader ────────────────────────────────────────────
# Reads ralph-config.yaml and exports CFG_* shell variables.
# Arrays (competitors, dimensions) are exported as JSON strings.

load_config() {
  local config_file="${CONFIG_FILE:-$RALPH_DIR/ralph-config.yaml}"

  if [[ ! -f "$config_file" ]]; then
    log_error "Config file not found: $config_file"
    return "$EXIT_FATAL"
  fi

  # ── Project ──────────────────────────────────────────────
  export CFG_PROJECT_NAME
  CFG_PROJECT_NAME="$(yq '.project.name // "my-app"' "$config_file")"

  export CFG_PROJECT_REPO
  CFG_PROJECT_REPO="$(yq '.project.repo // "."' "$config_file")"

  export CFG_PROJECT_DESCRIPTION
  CFG_PROJECT_DESCRIPTION="$(yq '.project.description // ""' "$config_file")"

  export CFG_PROJECT_BUILD_COMMAND
  CFG_PROJECT_BUILD_COMMAND="$(yq '.project.build_command // ""' "$config_file")"

  export CFG_PROJECT_TEST_COMMAND
  CFG_PROJECT_TEST_COMMAND="$(yq '.project.test_command // ""' "$config_file")"

  export CFG_PROJECT_LINT_COMMAND
  CFG_PROJECT_LINT_COMMAND="$(yq '.project.lint_command // ""' "$config_file")"

  # ── Research ─────────────────────────────────────────────
  export CFG_RESEARCH_COMPETITORS
  CFG_RESEARCH_COMPETITORS="$(yq -o=json '.research.competitors // []' "$config_file")"

  export CFG_RESEARCH_DIMENSIONS
  CFG_RESEARCH_DIMENSIONS="$(yq -o=json '.research.dimensions // []' "$config_file")"

  export CFG_RESEARCH_AUTO_DISCOVER
  CFG_RESEARCH_AUTO_DISCOVER="$(yq '.research.auto_discover // true' "$config_file")"

  # ── Schedule ─────────────────────────────────────────────
  export CFG_SCHEDULE_INTERVAL
  CFG_SCHEDULE_INTERVAL="$(yq '.schedule.interval // "30m"' "$config_file")"

  export CFG_SCHEDULE_MAX_STORIES
  CFG_SCHEDULE_MAX_STORIES="$(yq '.schedule.max_stories_per_cycle // 3' "$config_file")"

  # ── Development ──────────────────────────────────────────
  export CFG_DEV_TOOL
  CFG_DEV_TOOL="$(yq '.development.tool // "claude"' "$config_file")"

  export CFG_DEV_MAX_ITERATIONS
  CFG_DEV_MAX_ITERATIONS="$(yq '.development.max_iterations // 10' "$config_file")"

  export CFG_DEV_TDD
  CFG_DEV_TDD="$(yq '.development.tdd // true' "$config_file")"

  export CFG_DEV_WORKTREE
  CFG_DEV_WORKTREE="$(yq '.development.worktree // false' "$config_file")"

  # ── Release ──────────────────────────────────────────────
  export CFG_RELEASE_AUTO_PR
  CFG_RELEASE_AUTO_PR="$(yq '.release.auto_pr // true' "$config_file")"

  export CFG_RELEASE_AUTO_MERGE
  CFG_RELEASE_AUTO_MERGE="$(yq '.release.auto_merge // false' "$config_file")"

  export CFG_RELEASE_AUTO_TAG
  CFG_RELEASE_AUTO_TAG="$(yq '.release.auto_tag // false' "$config_file")"

  export CFG_RELEASE_AUTO_RELEASE
  CFG_RELEASE_AUTO_RELEASE="$(yq '.release.auto_release // false' "$config_file")"

  # ── Derived: set RALPH_TOOL for the rest of the system ──
  export RALPH_TOOL="$CFG_DEV_TOOL"

  log_info "Config loaded: project=$CFG_PROJECT_NAME tool=$RALPH_TOOL"
  return 0
}
