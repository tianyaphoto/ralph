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

  # Parse YAML once into JSON, then extract all fields with jq
  local full_json
  full_json="$(yq -o=json '.' "$config_file")" || {
    log_error "Failed to parse config file: $config_file"
    return "$EXIT_FATAL"
  }

  _cfg() { jq -r "$1" <<< "$full_json"; }

  # ── Project ──────────────────────────────────────────────
  export CFG_PROJECT_NAME;          CFG_PROJECT_NAME="$(_cfg          '.project.name // "my-app"')"
  export CFG_PROJECT_REPO;          CFG_PROJECT_REPO="$(_cfg          '.project.repo // "."')"
  export CFG_PROJECT_DESCRIPTION;   CFG_PROJECT_DESCRIPTION="$(_cfg   '.project.description // ""')"
  export CFG_PROJECT_BUILD_COMMAND; CFG_PROJECT_BUILD_COMMAND="$(_cfg '.project.build_command // ""')"
  export CFG_PROJECT_TEST_COMMAND;  CFG_PROJECT_TEST_COMMAND="$(_cfg  '.project.test_command // ""')"
  export CFG_PROJECT_LINT_COMMAND;  CFG_PROJECT_LINT_COMMAND="$(_cfg  '.project.lint_command // ""')"

  # ── Research ─────────────────────────────────────────────
  export CFG_RESEARCH_COMPETITORS;  CFG_RESEARCH_COMPETITORS="$(_cfg  '.research.competitors // []')"
  export CFG_RESEARCH_DIMENSIONS;   CFG_RESEARCH_DIMENSIONS="$(_cfg   '.research.dimensions // []')"
  export CFG_RESEARCH_AUTO_DISCOVER; CFG_RESEARCH_AUTO_DISCOVER="$(_cfg '.research.auto_discover // true')"

  # ── User Requirements (separate file) ───────────────────────
  local req_file="${RALPH_DIR}/requirements.yaml"
  if [[ -f "$req_file" ]]; then
    export CFG_USER_REQUIREMENTS
    CFG_USER_REQUIREMENTS="$(yq -o=json '.' "$req_file")" || {
      log_warn "Failed to parse requirements.yaml — defaulting to empty"
      CFG_USER_REQUIREMENTS="[]"
    }
    log_info "User requirements loaded: $(jq 'length' <<< "$CFG_USER_REQUIREMENTS") item(s)"
  else
    export CFG_USER_REQUIREMENTS="[]"
  fi

  # ── Schedule ─────────────────────────────────────────────
  export CFG_SCHEDULE_INTERVAL;     CFG_SCHEDULE_INTERVAL="$(_cfg     '.schedule.interval // "30m"')"
  export CFG_SCHEDULE_MAX_STORIES;  CFG_SCHEDULE_MAX_STORIES="$(_cfg  '.schedule.max_stories_per_cycle // 3')"

  # ── Development ──────────────────────────────────────────
  export CFG_DEV_TOOL;              CFG_DEV_TOOL="$(_cfg              '.development.tool // "claude"')"
  export CFG_DEV_MAX_ITERATIONS;    CFG_DEV_MAX_ITERATIONS="$(_cfg    '.development.max_iterations // 10')"
  export CFG_DEV_TDD;               CFG_DEV_TDD="$(_cfg               '.development.tdd // true')"
  export CFG_DEV_WORKTREE;          CFG_DEV_WORKTREE="$(_cfg          '.development.worktree // false')"

  # ── Release ──────────────────────────────────────────────
  export CFG_RELEASE_AUTO_PR;       CFG_RELEASE_AUTO_PR="$(_cfg       '.release.auto_pr // true')"
  export CFG_RELEASE_AUTO_MERGE;    CFG_RELEASE_AUTO_MERGE="$(_cfg    '.release.auto_merge // false')"
  export CFG_RELEASE_AUTO_TAG;      CFG_RELEASE_AUTO_TAG="$(_cfg      '.release.auto_tag // false')"
  export CFG_RELEASE_AUTO_RELEASE;  CFG_RELEASE_AUTO_RELEASE="$(_cfg  '.release.auto_release // false')"

  unset -f _cfg

  # ── Derived: set RALPH_TOOL for the rest of the system ──
  export RALPH_TOOL="$CFG_DEV_TOOL"

  # ── Load project constraints ────────────────────────────────
  load_constraints

  log_info "Config loaded: project=$CFG_PROJECT_NAME tool=$RALPH_TOOL"
  return 0
}

# ── Constraints loader ──────────────────────────────────────
# Reads {PROJECT_REPO}/constraints.md if it exists and exports
# CFG_CONSTRAINTS with the file contents.  Returns empty string
# if the file does not exist.  Safe to call before or after
# load_config — uses CFG_PROJECT_REPO if set, falls back to ".".
load_constraints() {
  local repo="${CFG_PROJECT_REPO:-.}"
  local constraints_file="$repo/constraints.md"

  if [[ -f "$constraints_file" ]]; then
    local max_size=32768  # 32 KB — generous for a constraints doc
    local file_size
    file_size="$(wc -c < "$constraints_file")"
    export CFG_CONSTRAINTS
    if [[ "$file_size" -gt "$max_size" ]]; then
      log_warn "constraints.md exceeds ${max_size} bytes (${file_size}); truncating"
      CFG_CONSTRAINTS="$(head -c "$max_size" "$constraints_file")"
    else
      CFG_CONSTRAINTS="$(cat "$constraints_file")"
    fi
    log_info "Constraints loaded from: $constraints_file"
  else
    export CFG_CONSTRAINTS=""
    log_info "No constraints file found at: $constraints_file (proceeding without constraints)"
  fi

  return 0
}
