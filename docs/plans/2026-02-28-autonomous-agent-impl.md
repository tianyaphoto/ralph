# Autonomous Agent Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend Ralph from a PRD executor into a fully autonomous AI programming agent with research, PRD generation, development, review, and release phases.

**Architecture:** Modular Bash script collection. A lightweight orchestrator (`ralph.sh`) calls phase scripts in `lib/`. Each phase is independently runnable/testable. Daemon mode uses while+sleep loop. Config via YAML (`yq` for parsing, like `jq` already used).

**Tech Stack:** Bash, jq (already used), yq (YAML parser), gh CLI (GitHub), Claude Code CLI

**Dependencies to verify:** `jq`, `yq`, `gh`, `claude` must be in PATH. Task 1 includes a dependency checker.

---

## Task 1: Foundation — `lib/utils.sh`

**Files:**
- Create: `lib/utils.sh`
- Test: Manual — `source lib/utils.sh && log_info "test"`

**Step 1: Create `lib/` directory**

```bash
mkdir -p lib
```

**Step 2: Write `lib/utils.sh`**

This is the foundation every other module sources. It provides: logging, process lock, exit code constants, dependency checking, date helpers.

```bash
#!/usr/bin/env bash
# lib/utils.sh — Common utilities for Ralph autonomous agent
# Source this file; do not execute directly.

set -euo pipefail

# ── Exit codes ──────────────────────────────────────────────
EXIT_OK=0
EXIT_RECOVERABLE=1
EXIT_FATAL=2

# ── Paths ───────────────────────────────────────────────────
# RALPH_DIR must be set by the sourcing script (ralph.sh sets it)
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

# ── Process lock ────────────────────────────────────────────
acquire_lock() {
  mkdir -p "$STATE_DIR"
  local lockfile="$STATE_DIR/lock.pid"
  if [[ -f "$lockfile" ]]; then
    local old_pid
    old_pid="$(cat "$lockfile")"
    if kill -0 "$old_pid" 2>/dev/null; then
      log_error "Another Ralph instance is running (PID $old_pid)"
      return "$EXIT_FATAL"
    else
      log_warn "Stale lock found (PID $old_pid), removing"
      rm -f "$lockfile"
    fi
  fi
  echo $$ > "$lockfile"
  trap 'release_lock' EXIT
}

release_lock() {
  rm -f "$STATE_DIR/lock.pid"
}

# ── State management ────────────────────────────────────────
save_state() {
  local cycle="$1" phase="$2" status="$3"
  mkdir -p "$STATE_DIR"
  cat > "$STATE_DIR/last-run.json" <<JSONEOF
{
  "cycle": $cycle,
  "phase": "$phase",
  "timestamp": "$(now_iso)",
  "status": "$status"
}
JSONEOF
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
  echo "$count" > "$count_file"
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
  # Check for configured AI tool
  local tool="${RALPH_TOOL:-claude}"
  if ! command -v "$tool" &>/dev/null; then
    log_error "Missing AI tool: $tool"
    missing=1
  fi
  return "$missing"
}

# ── Misc helpers ────────────────────────────────────────────
# Parse interval string like "30m", "1h", "2h30m" to seconds
parse_interval() {
  local input="$1"
  local seconds=0
  # Extract hours
  if [[ "$input" =~ ([0-9]+)h ]]; then
    seconds=$((seconds + ${BASH_REMATCH[1]} * 3600))
  fi
  # Extract minutes
  if [[ "$input" =~ ([0-9]+)m ]]; then
    seconds=$((seconds + ${BASH_REMATCH[1]} * 60))
  fi
  # Plain number = seconds
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    seconds=$input
  fi
  echo "$seconds"
}
```

**Step 3: Verify it loads without errors**

```bash
bash -n lib/utils.sh   # syntax check
source lib/utils.sh && log_info "utils.sh loaded OK"
```

Expected: No errors, prints `[timestamp] [INFO] utils.sh loaded OK`

**Step 4: Commit**

```bash
git add lib/utils.sh
git commit -m "feat: add lib/utils.sh — logging, lock, state, dependency checking"
```

---

## Task 2: Config System — `lib/config.sh` + example config

**Files:**
- Create: `lib/config.sh`
- Create: `config/ralph-config.yaml.example`

**Step 1: Create config directory and example**

```bash
mkdir -p config
```

Write `config/ralph-config.yaml.example`:

```yaml
# Ralph Autonomous Agent Configuration
# Copy this file to ralph-config.yaml and customize for your project.

project:
  name: "my-app"
  repo: "."
  description: "Short description of your project"
  build_command: ""       # e.g. "xcodebuild -scheme MyApp -sdk iphonesimulator"
  test_command: ""        # e.g. "npm test" or "go test ./..."
  lint_command: ""        # e.g. "swiftlint" or "eslint ."

research:
  competitors:
    - name: "Competitor1"
      github: ""          # e.g. "owner/repo"
      website: ""         # e.g. "https://example.com"
  dimensions:
    - "Features"
    - "Performance"
    - "Developer Experience"
  auto_discover: true

schedule:
  interval: "30m"
  max_stories_per_cycle: 3

development:
  tool: "claude"          # claude | amp
  max_iterations: 10
  tdd: true
  worktree: true

release:
  auto_pr: true
  auto_merge: true
  auto_tag: true
  auto_release: true
```

**Step 2: Write `lib/config.sh`**

Uses `yq` to parse YAML into shell variables with a `CFG_` prefix.

```bash
#!/usr/bin/env bash
# lib/config.sh — Load ralph-config.yaml into environment variables
# Source this after utils.sh

CONFIG_FILE="${RALPH_DIR}/ralph-config.yaml"

load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config not found: $CONFIG_FILE"
    log_error "Copy config/ralph-config.yaml.example to ralph-config.yaml"
    return "$EXIT_FATAL"
  fi

  # Project settings
  CFG_PROJECT_NAME="$(yq '.project.name // ""' "$CONFIG_FILE")"
  CFG_PROJECT_REPO="$(yq '.project.repo // "."' "$CONFIG_FILE")"
  CFG_PROJECT_DESC="$(yq '.project.description // ""' "$CONFIG_FILE")"
  CFG_BUILD_CMD="$(yq '.project.build_command // ""' "$CONFIG_FILE")"
  CFG_TEST_CMD="$(yq '.project.test_command // ""' "$CONFIG_FILE")"
  CFG_LINT_CMD="$(yq '.project.lint_command // ""' "$CONFIG_FILE")"

  # Research settings
  CFG_AUTO_DISCOVER="$(yq '.research.auto_discover // true' "$CONFIG_FILE")"
  CFG_COMPETITORS_JSON="$(yq -o=json '.research.competitors // []' "$CONFIG_FILE")"
  CFG_DIMENSIONS_JSON="$(yq -o=json '.research.dimensions // []' "$CONFIG_FILE")"

  # Schedule
  CFG_INTERVAL="$(yq '.schedule.interval // "30m"' "$CONFIG_FILE")"
  CFG_MAX_STORIES="$(yq '.schedule.max_stories_per_cycle // 3' "$CONFIG_FILE")"

  # Development
  RALPH_TOOL="$(yq '.development.tool // "claude"' "$CONFIG_FILE")"
  CFG_MAX_ITERATIONS="$(yq '.development.max_iterations // 10' "$CONFIG_FILE")"
  CFG_TDD="$(yq '.development.tdd // true' "$CONFIG_FILE")"
  CFG_WORKTREE="$(yq '.development.worktree // true' "$CONFIG_FILE")"

  # Release
  CFG_AUTO_PR="$(yq '.release.auto_pr // true' "$CONFIG_FILE")"
  CFG_AUTO_MERGE="$(yq '.release.auto_merge // true' "$CONFIG_FILE")"
  CFG_AUTO_TAG="$(yq '.release.auto_tag // true' "$CONFIG_FILE")"
  CFG_AUTO_RELEASE="$(yq '.release.auto_release // true' "$CONFIG_FILE")"

  export CFG_PROJECT_NAME CFG_PROJECT_REPO CFG_PROJECT_DESC
  export CFG_BUILD_CMD CFG_TEST_CMD CFG_LINT_CMD
  export CFG_AUTO_DISCOVER CFG_COMPETITORS_JSON CFG_DIMENSIONS_JSON
  export CFG_INTERVAL CFG_MAX_STORIES
  export RALPH_TOOL CFG_MAX_ITERATIONS CFG_TDD CFG_WORKTREE
  export CFG_AUTO_PR CFG_AUTO_MERGE CFG_AUTO_TAG CFG_AUTO_RELEASE

  log_info "Config loaded: project=$CFG_PROJECT_NAME tool=$RALPH_TOOL"
}
```

**Step 3: Verify config loading**

```bash
cp config/ralph-config.yaml.example ralph-config.yaml
source lib/utils.sh && source lib/config.sh && load_config && echo "OK: $CFG_PROJECT_NAME"
rm ralph-config.yaml   # clean up test file
```

Expected: `OK: my-app`

**Step 4: Commit**

```bash
git add lib/config.sh config/ralph-config.yaml.example
git commit -m "feat: add config system — YAML config loading with yq"
```

---

## Task 3: Report Infrastructure — `lib/report.sh`

**Files:**
- Create: `lib/report.sh`
- Create: `reports/.gitkeep`

**Step 1: Write `lib/report.sh`**

```bash
#!/usr/bin/env bash
# lib/report.sh — Generate and archive phase reports
# Source this after utils.sh

# Write a report file into today's reports directory
# Usage: write_report "filename.md" "content"
write_report() {
  local filename="$1"
  local content="$2"
  local dir
  dir="$(today_dir)"
  mkdir -p "$dir"
  local filepath="$dir/$filename"
  echo "$content" > "$filepath"
  log_info "Report written: $filepath"
  echo "$filepath"
}

# Append to an existing report
# Usage: append_report "filename.md" "additional content"
append_report() {
  local filename="$1"
  local content="$2"
  local dir
  dir="$(today_dir)"
  mkdir -p "$dir"
  local filepath="$dir/$filename"
  echo "$content" >> "$filepath"
}

# Generate a phase summary header
# Usage: phase_header "Research" "started"
phase_header() {
  local phase="$1"
  local status="$2"
  cat <<EOF
# Ralph Phase Report: $phase

**Status:** $status
**Timestamp:** $(now_iso)
**Cycle:** ${CURRENT_CYCLE:-unknown}

---

EOF
}
```

**Step 2: Create reports directory placeholder**

```bash
mkdir -p reports
touch reports/.gitkeep
```

**Step 3: Verify**

```bash
source lib/utils.sh && source lib/report.sh
write_report "test.md" "hello" && cat "$(today_dir)/test.md"
rm -rf "reports/$(today_stamp)"  # clean up
```

Expected: prints `hello`

**Step 4: Commit**

```bash
git add lib/report.sh reports/.gitkeep
git commit -m "feat: add report infrastructure — write/append reports to dated dirs"
```

---

## Task 4: Worktree Management — `lib/worktree.sh`

**Files:**
- Create: `lib/worktree.sh`

**Step 1: Write `lib/worktree.sh`**

```bash
#!/usr/bin/env bash
# lib/worktree.sh — Git worktree management for isolated development
# Source this after utils.sh

WORKTREE_BASE="${RALPH_DIR}/.worktrees"

# Create a worktree for a story
# Usage: worktree_create "US-001" "ralph/feature-branch"
# Prints: path to the worktree directory
worktree_create() {
  local story_id="$1"
  local base_branch="$2"
  local wt_path="$WORKTREE_BASE/$story_id"
  local wt_branch="ralph/$story_id"

  mkdir -p "$WORKTREE_BASE"

  # Clean up if leftover worktree exists
  if [[ -d "$wt_path" ]]; then
    log_warn "Cleaning up leftover worktree: $wt_path"
    git worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path"
  fi

  # Remove stale branch if it exists
  git branch -D "$wt_branch" 2>/dev/null || true

  # Create worktree from the base branch
  log_info "Creating worktree: $wt_path (branch: $wt_branch from $base_branch)"
  git worktree add "$wt_path" -b "$wt_branch" "$base_branch"

  echo "$wt_path"
}

# Remove a worktree after story completion
# Usage: worktree_remove "US-001"
worktree_remove() {
  local story_id="$1"
  local wt_path="$WORKTREE_BASE/$story_id"
  local wt_branch="ralph/$story_id"

  if [[ -d "$wt_path" ]]; then
    log_info "Removing worktree: $wt_path"
    git worktree remove --force "$wt_path" 2>/dev/null || rm -rf "$wt_path"
  fi
  # Clean up branch
  git branch -D "$wt_branch" 2>/dev/null || true
}

# Merge worktree commits back to the feature branch via squash
# Usage: worktree_squash_merge "US-001" "ralph/feature-branch" "feat: US-001 - Story Title"
worktree_squash_merge() {
  local story_id="$1"
  local target_branch="$2"
  local commit_msg="$3"
  local wt_branch="ralph/$story_id"

  log_info "Squash-merging $wt_branch into $target_branch"
  git checkout "$target_branch"
  git merge --squash "$wt_branch"
  git commit -m "$commit_msg"
}

# Clean up all worktrees (e.g., after a cycle)
worktree_cleanup_all() {
  if [[ -d "$WORKTREE_BASE" ]]; then
    log_info "Cleaning up all worktrees"
    # List and remove each worktree
    for wt_dir in "$WORKTREE_BASE"/*/; do
      [[ -d "$wt_dir" ]] || continue
      git worktree remove --force "$wt_dir" 2>/dev/null || rm -rf "$wt_dir"
    done
    # Prune stale worktree references
    git worktree prune
  fi
}
```

**Step 2: Add `.worktrees` to `.gitignore`**

Check if `.gitignore` exists; if not create it. Append `.worktrees/` and `.ralph-state/`.

```bash
# Append to .gitignore (create if missing)
echo ".worktrees/" >> .gitignore
echo ".ralph-state/" >> .gitignore
```

**Step 3: Commit**

```bash
git add lib/worktree.sh .gitignore
git commit -m "feat: add worktree management — create/remove/squash-merge isolated worktrees"
```

---

## Task 5: Research Phase — `lib/research.sh` + `prompts/research.md`

**Files:**
- Create: `prompts/research.md`
- Create: `lib/research.sh`

**Step 1: Create prompts directory**

```bash
mkdir -p prompts
```

**Step 2: Write `prompts/research.md`**

This is the prompt that gets piped to Claude Code CLI during the research phase. It instructs Claude to do competitive analysis and output structured results.

```markdown
# Research Phase — Competitive Analysis

You are a market research analyst AI. Your job is to analyze competitors and identify feature gaps for the target project.

## Context

**Project:** {{PROJECT_NAME}}
**Description:** {{PROJECT_DESC}}

**Known Competitors:**
{{COMPETITORS}}

**Analysis Dimensions:**
{{DIMENSIONS}}

**Auto-discover additional competitors:** {{AUTO_DISCOVER}}

## Your Task

1. **Analyze each competitor:**
   - Search the web for their latest features, updates, and roadmap
   - If a GitHub repo is provided, analyze their README, recent Issues, and PRs
   - Note key features and strengths

2. **If auto-discover is true:**
   - Search for other tools/products in the same space
   - Add any significant competitors you find

3. **Cross-compare with the target project:**
   - Read the target project's codebase to understand current capabilities
   - Identify features that competitors have but the target project lacks
   - Prioritize gaps by user impact and implementation effort

4. **Output TWO files:**

### File 1: `research-report.md`
A human-readable report with:
- Executive summary
- Competitor profiles (features, strengths, weaknesses)
- Feature gap analysis table
- Prioritized recommendations

### File 2: `gaps.json`
A machine-readable JSON array:
```json
[
  {
    "gap": "Short description of missing feature",
    "priority": "high|medium|low",
    "competitors": ["List", "of", "competitors", "that", "have", "it"],
    "effort": "small|medium|large",
    "rationale": "Why this matters for users"
  }
]
```

**Priority rules:**
- `high`: Multiple competitors have it, significant user impact
- `medium`: Some competitors have it, moderate impact
- `low`: Nice to have, few competitors have it

**Effort rules:**
- `small`: <100 lines of code, single file change
- `medium`: 100-500 lines, multiple files
- `large`: >500 lines, architectural changes

## Important

- Be specific about gaps — "add dark mode" not "improve UX"
- Only include gaps that are actionable and implementable
- Focus on the configured dimensions
- Output both files to the current directory
```

**Step 3: Write `lib/research.sh`**

```bash
#!/usr/bin/env bash
# lib/research.sh — Phase 1: Competitive research and gap analysis
# Source utils.sh and config.sh before calling run_research

run_research() {
  log_info "Phase 1: Research — starting competitive analysis"

  local prompt_file="$RALPH_DIR/prompts/research.md"
  if [[ ! -f "$prompt_file" ]]; then
    log_error "Research prompt not found: $prompt_file"
    return "$EXIT_RECOVERABLE"
  fi

  # Build competitor list for the prompt
  local competitors_text
  competitors_text="$(echo "$CFG_COMPETITORS_JSON" | jq -r '.[] | "- \(.name): GitHub=\(.github // "N/A"), Website=\(.website // "N/A")"')"

  local dimensions_text
  dimensions_text="$(echo "$CFG_DIMENSIONS_JSON" | jq -r '.[] | "- \(.)"')"

  # Substitute placeholders in the prompt
  local prompt
  prompt="$(cat "$prompt_file")"
  prompt="${prompt//\{\{PROJECT_NAME\}\}/$CFG_PROJECT_NAME}"
  prompt="${prompt//\{\{PROJECT_DESC\}\}/$CFG_PROJECT_DESC}"
  prompt="${prompt//\{\{COMPETITORS\}\}/$competitors_text}"
  prompt="${prompt//\{\{DIMENSIONS\}\}/$dimensions_text}"
  prompt="${prompt//\{\{AUTO_DISCOVER\}\}/$CFG_AUTO_DISCOVER}"

  # Run Claude Code CLI
  local work_dir="$CFG_PROJECT_REPO"
  log_info "Running Claude Code for research in: $work_dir"

  local output
  if [[ "$RALPH_TOOL" == "claude" ]]; then
    output="$(echo "$prompt" | claude --dangerously-skip-permissions --print -p "$work_dir" 2>&1 | tee /dev/stderr)" || true
  else
    output="$(echo "$prompt" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr)" || true
  fi

  # Check if gaps.json was created
  local gaps_file="$work_dir/gaps.json"
  local report_file="$work_dir/research-report.md"

  if [[ ! -f "$gaps_file" ]]; then
    log_error "Research did not produce gaps.json"
    write_report "research-report.md" "$(phase_header "Research" "FAILED")

Research phase did not produce structured output.

## Raw Output
$output"
    return "$EXIT_RECOVERABLE"
  fi

  # Validate gaps.json is valid JSON array
  if ! jq 'type == "array"' "$gaps_file" >/dev/null 2>&1; then
    log_error "gaps.json is not a valid JSON array"
    return "$EXIT_RECOVERABLE"
  fi

  local gap_count
  gap_count="$(jq 'length' "$gaps_file")"
  log_info "Research found $gap_count feature gaps"

  # Archive reports
  if [[ -f "$report_file" ]]; then
    cp "$report_file" "$(today_dir)/research-report.md"
  fi
  cp "$gaps_file" "$(today_dir)/gaps.json"

  # Keep gaps.json in work_dir for the next phase
  log_info "Phase 1: Research — complete ($gap_count gaps found)"
  return "$EXIT_OK"
}
```

**Step 4: Commit**

```bash
git add prompts/research.md lib/research.sh
git commit -m "feat: add research phase — competitor analysis and gap discovery"
```

---

## Task 6: PRD Generation Phase — `lib/prd-gen.sh` + `prompts/prd-gen.md`

**Files:**
- Create: `prompts/prd-gen.md`
- Create: `lib/prd-gen.sh`

**Step 1: Write `prompts/prd-gen.md`**

```markdown
# PRD Generation Phase

You are a technical product manager AI. Your job is to convert feature gaps into a structured PRD (prd.json) that Ralph can execute.

## Context

**Project:** {{PROJECT_NAME}}
**Description:** {{PROJECT_DESC}}
**Max stories this cycle:** {{MAX_STORIES}}

## Feature Gaps to Address

{{GAPS_JSON}}

## Your Task

1. **Read the current codebase** to understand the architecture
2. **Select the top {{MAX_STORIES}} gaps** by priority (high > medium > low)
3. **For each selected gap**, generate user stories that:
   - Are small enough to complete in ONE context window (~200-400 lines of changes)
   - Have verifiable acceptance criteria (not vague)
   - Are ordered by dependency (schema → backend logic → UI)
4. **Output `prd.json`** in the following exact format:

```json
{
  "project": "{{PROJECT_NAME}}",
  "branchName": "ralph/auto-YYYY-MM-DD",
  "description": "Auto-generated: [summary of gaps being addressed]",
  "userStories": [
    {
      "id": "US-001",
      "title": "Short title",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Specific, verifiable criterion",
        "Another criterion",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Story Size Rules

**Right-sized** (one context window):
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic

**Too big** (must split):
- "Build the entire feature" → split into schema, backend, UI stories
- More than 3-4 files changed

## Acceptance Criteria Rules

- Every story MUST include "Typecheck passes" (or equivalent quality check)
- UI stories MUST include "Verify in browser" if applicable
- Criteria must be checkable by automated tools or visual inspection
- NO vague criteria like "works correctly" or "good UX"

## Important

- Use today's date in the branchName: `ralph/auto-{{TODAY}}`
- The branchName must be kebab-case
- Output ONLY the prd.json file — no other files
- Ensure no story depends on a later story
```

**Step 2: Write `lib/prd-gen.sh`**

```bash
#!/usr/bin/env bash
# lib/prd-gen.sh — Phase 2: Generate PRD from research gaps
# Source utils.sh and config.sh before calling run_prd_gen

run_prd_gen() {
  log_info "Phase 2: PRD Generation — starting"

  local gaps_file="$CFG_PROJECT_REPO/gaps.json"
  if [[ ! -f "$gaps_file" ]]; then
    log_error "gaps.json not found. Run research phase first."
    return "$EXIT_RECOVERABLE"
  fi

  local gap_count
  gap_count="$(jq 'length' "$gaps_file")"
  if [[ "$gap_count" -eq 0 ]]; then
    log_info "No gaps found — nothing to generate"
    return "$EXIT_OK"
  fi

  local prompt_file="$RALPH_DIR/prompts/prd-gen.md"
  if [[ ! -f "$prompt_file" ]]; then
    log_error "PRD generation prompt not found: $prompt_file"
    return "$EXIT_RECOVERABLE"
  fi

  # Read gaps as text for the prompt
  local gaps_text
  gaps_text="$(cat "$gaps_file")"

  local today
  today="$(today_stamp)"

  # Substitute placeholders
  local prompt
  prompt="$(cat "$prompt_file")"
  prompt="${prompt//\{\{PROJECT_NAME\}\}/$CFG_PROJECT_NAME}"
  prompt="${prompt//\{\{PROJECT_DESC\}\}/$CFG_PROJECT_DESC}"
  prompt="${prompt//\{\{MAX_STORIES\}\}/$CFG_MAX_STORIES}"
  prompt="${prompt//\{\{GAPS_JSON\}\}/$gaps_text}"
  prompt="${prompt//\{\{TODAY\}\}/$today}"

  local work_dir="$CFG_PROJECT_REPO"
  log_info "Running Claude Code for PRD generation in: $work_dir"

  # Archive existing prd.json if present
  local prd_file="$RALPH_DIR/prd.json"
  if [[ -f "$prd_file" ]]; then
    local archive_dir="$RALPH_DIR/archive/$(today_stamp)-pre-auto"
    mkdir -p "$archive_dir"
    cp "$prd_file" "$archive_dir/prd.json"
    [[ -f "$RALPH_DIR/progress.txt" ]] && cp "$RALPH_DIR/progress.txt" "$archive_dir/"
    log_info "Archived existing prd.json to $archive_dir"
  fi

  local output
  if [[ "$RALPH_TOOL" == "claude" ]]; then
    output="$(echo "$prompt" | claude --dangerously-skip-permissions --print -p "$work_dir" 2>&1 | tee /dev/stderr)" || true
  else
    output="$(echo "$prompt" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr)" || true
  fi

  # Validate prd.json was created/updated
  if [[ ! -f "$prd_file" ]]; then
    log_error "PRD generation did not produce prd.json"
    return "$EXIT_RECOVERABLE"
  fi

  # Validate structure
  if ! jq '.userStories | type == "array"' "$prd_file" >/dev/null 2>&1; then
    log_error "prd.json has invalid structure"
    return "$EXIT_RECOVERABLE"
  fi

  local story_count
  story_count="$(jq '.userStories | length' "$prd_file")"
  log_info "PRD generated with $story_count user stories"

  # Reset progress file for new run
  echo "# Ralph Progress Log" > "$RALPH_DIR/progress.txt"
  echo "Started: $(date)" >> "$RALPH_DIR/progress.txt"
  echo "---" >> "$RALPH_DIR/progress.txt"

  # Archive report
  write_report "prd-generated.md" "$(phase_header "PRD Generation" "SUCCESS")

## Generated PRD

**Stories:** $story_count
**Branch:** $(jq -r '.branchName' "$prd_file")

### User Stories

$(jq -r '.userStories[] | "- \(.id): \(.title) (priority: \(.priority))"' "$prd_file")
"

  log_info "Phase 2: PRD Generation — complete"
  return "$EXIT_OK"
}
```

**Step 3: Commit**

```bash
git add prompts/prd-gen.md lib/prd-gen.sh
git commit -m "feat: add PRD generation phase — convert gaps to prd.json"
```

---

## Task 7: Development Phase — `lib/develop.sh`

**Files:**
- Create: `lib/develop.sh`

This extracts the core development loop from the existing `ralph.sh` (lines 84-108) into a reusable module, enhanced with worktree support.

**Step 1: Write `lib/develop.sh`**

```bash
#!/usr/bin/env bash
# lib/develop.sh — Phase 3: Development loop (implements user stories)
# Source utils.sh, config.sh, worktree.sh before calling run_develop

run_develop() {
  log_info "Phase 3: Development — starting"

  local prd_file="$RALPH_DIR/prd.json"
  if [[ ! -f "$prd_file" ]]; then
    log_error "prd.json not found"
    return "$EXIT_RECOVERABLE"
  fi

  # Check for remaining stories
  local remaining
  remaining="$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file")"
  if [[ "$remaining" -eq 0 ]]; then
    log_info "All stories already complete"
    return "$EXIT_OK"
  fi

  log_info "$remaining stories remaining"

  # Get branch name from PRD
  local branch_name
  branch_name="$(jq -r '.branchName // "ralph/auto"' "$prd_file")"

  # Ensure we're on the correct branch
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  if [[ "$current_branch" != "$branch_name" ]]; then
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
      git checkout "$branch_name"
    else
      git checkout -b "$branch_name"
    fi
  fi

  # Determine the prompt file based on tool
  local prompt_file
  if [[ "$RALPH_TOOL" == "claude" ]]; then
    prompt_file="$RALPH_DIR/CLAUDE.md"
  else
    prompt_file="$RALPH_DIR/prompt.md"
  fi

  # Run development iterations
  local max_iter="$CFG_MAX_ITERATIONS"
  local completed=0

  for i in $(seq 1 "$max_iter"); do
    # Re-check remaining stories
    remaining="$(jq '[.userStories[] | select(.passes == false)] | length' "$prd_file")"
    if [[ "$remaining" -eq 0 ]]; then
      log_info "All stories complete after $i iterations"
      break
    fi

    log_info "Development iteration $i/$max_iter ($remaining stories remaining)"

    local output
    if [[ "$RALPH_TOOL" == "claude" ]]; then
      output="$(claude --dangerously-skip-permissions --print < "$prompt_file" 2>&1 | tee /dev/stderr)" || true
    else
      output="$(cat "$prompt_file" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr)" || true
    fi

    # Check for completion signal
    if echo "$output" | grep -q "<promise>COMPLETE</promise>"; then
      log_info "All stories completed!"
      completed=1
      break
    fi

    sleep 2
  done

  # Count completed stories for report
  local passed
  passed="$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_file")"
  local total
  total="$(jq '.userStories | length' "$prd_file")"

  write_report "dev-progress.md" "$(phase_header "Development" "$([ $completed -eq 1 ] && echo "COMPLETE" || echo "PARTIAL")")

## Development Summary

**Stories completed:** $passed / $total
**Iterations used:** $i / $max_iter
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
```

**Step 2: Commit**

```bash
git add lib/develop.sh
git commit -m "feat: add development phase — extracted loop with worktree support"
```

---

## Task 8: Review Phase — `lib/review.sh` + `prompts/review.md`

**Files:**
- Create: `prompts/review.md`
- Create: `lib/review.sh`

**Step 1: Write `prompts/review.md`**

```markdown
# Code Review Phase

You are a senior code reviewer. Review the recent changes on this branch for quality, security, and correctness.

## Your Task

1. Run `git diff main...HEAD` to see all changes on this branch
2. Review for:
   - Code quality and readability
   - Security vulnerabilities (OWASP top 10)
   - Error handling completeness
   - Test coverage
   - Performance concerns
3. Run `/simplify` on changed files to identify simplification opportunities
4. Apply any safe improvements directly (fix typos, simplify logic, remove dead code)
5. Output a `review-report.md` with:
   - Summary of changes reviewed
   - Issues found (CRITICAL / HIGH / MEDIUM / LOW)
   - Improvements applied
   - Remaining concerns

## Important

- Fix CRITICAL and HIGH issues directly in the code
- Log MEDIUM and LOW issues in the report
- Do NOT break existing functionality
- Commit any fixes with message: `fix: code review — [description]`
```

**Step 2: Write `lib/review.sh`**

```bash
#!/usr/bin/env bash
# lib/review.sh — Phase 4: Code review and build verification
# Source utils.sh and config.sh before calling run_review

MAX_REVIEW_RETRIES=3

run_review() {
  log_info "Phase 4: Review — starting code review and build verification"

  local retry=0
  while [[ "$retry" -lt "$MAX_REVIEW_RETRIES" ]]; do
    retry=$((retry + 1))
    log_info "Review attempt $retry/$MAX_REVIEW_RETRIES"

    # Step 1: Run build verification
    local build_ok=true

    if [[ -n "$CFG_BUILD_CMD" ]]; then
      log_info "Running build: $CFG_BUILD_CMD"
      if ! eval "$CFG_BUILD_CMD"; then
        log_error "Build failed"
        build_ok=false
      fi
    fi

    if [[ -n "$CFG_TEST_CMD" ]] && [[ "$build_ok" == true ]]; then
      log_info "Running tests: $CFG_TEST_CMD"
      if ! eval "$CFG_TEST_CMD"; then
        log_error "Tests failed"
        build_ok=false
      fi
    fi

    if [[ -n "$CFG_LINT_CMD" ]] && [[ "$build_ok" == true ]]; then
      log_info "Running lint: $CFG_LINT_CMD"
      if ! eval "$CFG_LINT_CMD"; then
        log_warn "Lint failed (non-blocking)"
      fi
    fi

    if [[ "$build_ok" == false ]] && [[ "$retry" -lt "$MAX_REVIEW_RETRIES" ]]; then
      log_warn "Build/test failed, invoking Claude Code for fixes"
      # Let Claude fix build errors
      local fix_prompt="The build or tests failed. Please read the error output above, fix the issues, and commit the fix."
      if [[ "$RALPH_TOOL" == "claude" ]]; then
        echo "$fix_prompt" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr || true
      else
        echo "$fix_prompt" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr || true
      fi
      continue
    fi

    # Step 2: Run AI code review
    local review_prompt_file="$RALPH_DIR/prompts/review.md"
    if [[ -f "$review_prompt_file" ]]; then
      log_info "Running AI code review"
      if [[ "$RALPH_TOOL" == "claude" ]]; then
        claude --dangerously-skip-permissions --print < "$review_prompt_file" 2>&1 | tee /dev/stderr || true
      else
        cat "$review_prompt_file" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr || true
      fi
    fi

    # If we got here, build passed (or no build commands configured)
    if [[ "$build_ok" == true ]]; then
      # Archive review report if Claude created one
      local review_file="review-report.md"
      if [[ -f "$review_file" ]]; then
        cp "$review_file" "$(today_dir)/review-report.md"
        rm -f "$review_file"
      else
        write_report "review-report.md" "$(phase_header "Review" "PASSED")

## Build Verification

- Build: $([ -n "$CFG_BUILD_CMD" ] && echo "PASSED" || echo "N/A")
- Tests: $([ -n "$CFG_TEST_CMD" ] && echo "PASSED" || echo "N/A")
- Lint: $([ -n "$CFG_LINT_CMD" ] && echo "PASSED" || echo "N/A")
"
      fi

      log_info "Phase 4: Review — passed"
      return "$EXIT_OK"
    fi
  done

  log_error "Phase 4: Review — failed after $MAX_REVIEW_RETRIES attempts"
  write_report "review-report.md" "$(phase_header "Review" "FAILED")

Build/test verification failed after $MAX_REVIEW_RETRIES attempts.
Manual intervention required.
"
  return "$EXIT_RECOVERABLE"
}
```

**Step 3: Commit**

```bash
git add prompts/review.md lib/review.sh
git commit -m "feat: add review phase — AI code review + build/test/lint verification"
```

---

## Task 9: Release Phase — `lib/release.sh`

**Files:**
- Create: `lib/release.sh`

**Step 1: Write `lib/release.sh`**

```bash
#!/usr/bin/env bash
# lib/release.sh — Phase 5: PR, merge, tag, release
# Source utils.sh and config.sh before calling run_release

run_release() {
  log_info "Phase 5: Release — starting"

  local branch_name
  branch_name="$(git rev-parse --abbrev-ref HEAD)"

  if [[ "$branch_name" == "main" || "$branch_name" == "master" ]]; then
    log_warn "Already on main branch, nothing to release"
    return "$EXIT_OK"
  fi

  # Ensure branch is pushed to remote
  log_info "Pushing branch $branch_name to origin"
  git push -u origin "$branch_name" 2>&1 || {
    log_error "Failed to push branch"
    return "$EXIT_RECOVERABLE"
  }

  # Step 1: Create PR
  local pr_url=""
  if [[ "$CFG_AUTO_PR" == "true" ]]; then
    log_info "Creating pull request"

    # Generate PR body from reports
    local pr_body="## Summary

Auto-generated by Ralph Autonomous Agent.

### Changes
$(git log main.."$branch_name" --oneline --no-decorate 2>/dev/null || echo "See commits on branch")

### Reports
- Research: see reports/$(today_stamp)/research-report.md
- Development: see reports/$(today_stamp)/dev-progress.md
- Review: see reports/$(today_stamp)/review-report.md
"

    pr_url="$(gh pr create \
      --title "feat: auto — $(jq -r '.description // "automated changes"' "$RALPH_DIR/prd.json" 2>/dev/null)" \
      --body "$pr_body" \
      --base main \
      --head "$branch_name" 2>&1)" || {
      log_error "Failed to create PR: $pr_url"
      return "$EXIT_RECOVERABLE"
    }
    log_info "PR created: $pr_url"
  fi

  # Step 2: Wait for CI (if configured)
  if [[ -n "$pr_url" ]]; then
    log_info "Checking CI status"
    gh pr checks "$branch_name" --watch 2>&1 || {
      log_warn "CI checks failed or not configured, continuing"
    }
  fi

  # Step 3: Auto-merge
  if [[ "$CFG_AUTO_MERGE" == "true" && -n "$pr_url" ]]; then
    log_info "Merging PR via squash"
    gh pr merge "$branch_name" --squash --delete-branch 2>&1 || {
      log_error "Failed to merge PR"
      return "$EXIT_RECOVERABLE"
    }
    git checkout main
    git pull origin main
    log_info "PR merged successfully"
  fi

  # Step 4: Semantic version tag
  if [[ "$CFG_AUTO_TAG" == "true" ]]; then
    log_info "Creating semantic version tag"
    local latest_tag
    latest_tag="$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")"

    # Simple bump: always minor for auto-generated features
    local major minor patch
    IFS='.' read -r major minor patch <<< "${latest_tag#v}"
    minor=$((minor + 1))
    patch=0
    local new_tag="v${major}.${minor}.${patch}"

    git tag -a "$new_tag" -m "Auto-release: $(today_stamp)" 2>&1 || {
      log_warn "Failed to create tag $new_tag"
    }
    git push origin "$new_tag" 2>&1 || {
      log_warn "Failed to push tag"
    }
    log_info "Tagged: $new_tag"
  fi

  # Step 5: GitHub Release
  if [[ "$CFG_AUTO_RELEASE" == "true" ]]; then
    local release_tag
    release_tag="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"
    if [[ -n "$release_tag" ]]; then
      log_info "Creating GitHub Release for $release_tag"
      gh release create "$release_tag" \
        --generate-notes \
        --title "Release $release_tag" 2>&1 || {
        log_warn "Failed to create GitHub release"
      }
    fi
  fi

  # Step 6: Release report
  write_report "release-summary.md" "$(phase_header "Release" "SUCCESS")

## Release Summary

**Branch:** $branch_name
**PR:** ${pr_url:-N/A}
**Tag:** $(git describe --tags --abbrev=0 2>/dev/null || echo "N/A")
**Merged:** $CFG_AUTO_MERGE
"

  log_info "Phase 5: Release — complete"
  return "$EXIT_OK"
}
```

**Step 2: Commit**

```bash
git add lib/release.sh
git commit -m "feat: add release phase — auto PR, merge, tag, and GitHub Release"
```

---

## Task 10: Orchestrator Rewrite — `ralph.sh`

**Files:**
- Modify: `ralph.sh` (complete rewrite)
- Preserve: Original `ralph.sh` logic in `lib/develop.sh` (already done in Task 7)

This is the main entry point rewrite. The current `ralph.sh` (114 lines) becomes the orchestrator that chains all phases together.

**Step 1: Back up old ralph.sh**

```bash
cp ralph.sh ralph.sh.bak
```

**Step 2: Rewrite `ralph.sh`**

```bash
#!/usr/bin/env bash
# Ralph — Autonomous AI Programming Agent
# Usage: ./ralph.sh [options]
#
# Modes:
#   --auto              Run a single full cycle (research → develop → release)
#   --daemon            Run continuously with --interval delay between cycles
#   --legacy            Run the original development-only loop (backwards compat)
#
# Options:
#   --tool amp|claude   AI tool to use (default: from config, fallback: claude)
#   --interval 30m      Daemon cycle interval (default: from config)
#   --phase PHASE       Run a single phase: research|prd-gen|develop|review|release
#   --max-iterations N  Max dev iterations per story (default: from config)
#   --config FILE       Path to config file (default: ralph-config.yaml)
#
# Examples:
#   ./ralph.sh --auto                    # Single full autonomous cycle
#   ./ralph.sh --daemon --interval 1h    # Run every hour
#   ./ralph.sh --phase research          # Just run research
#   ./ralph.sh --legacy 10              # Original mode: 10 dev iterations
#   ./ralph.sh --legacy --tool amp 5    # Original mode with Amp

set -euo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RALPH_DIR

# Source all libraries
source "$RALPH_DIR/lib/utils.sh"
source "$RALPH_DIR/lib/config.sh"
source "$RALPH_DIR/lib/report.sh"
source "$RALPH_DIR/lib/worktree.sh"
source "$RALPH_DIR/lib/research.sh"
source "$RALPH_DIR/lib/prd-gen.sh"
source "$RALPH_DIR/lib/develop.sh"
source "$RALPH_DIR/lib/review.sh"
source "$RALPH_DIR/lib/release.sh"

# ── Parse arguments ─────────────────────────────────────────
MODE=""
PHASE_OVERRIDE=""
INTERVAL_OVERRIDE=""
TOOL_OVERRIDE=""
MAX_ITER_OVERRIDE=""
CONFIG_OVERRIDE=""
LEGACY_MAX=10

while [[ $# -gt 0 ]]; do
  case $1 in
    --auto)       MODE="auto";     shift ;;
    --daemon)     MODE="daemon";   shift ;;
    --legacy)     MODE="legacy";   shift ;;
    --phase)      PHASE_OVERRIDE="$2"; MODE="phase"; shift 2 ;;
    --phase=*)    PHASE_OVERRIDE="${1#*=}"; MODE="phase"; shift ;;
    --tool)       TOOL_OVERRIDE="$2";      shift 2 ;;
    --tool=*)     TOOL_OVERRIDE="${1#*=}";  shift ;;
    --interval)   INTERVAL_OVERRIDE="$2";  shift 2 ;;
    --interval=*) INTERVAL_OVERRIDE="${1#*=}"; shift ;;
    --max-iterations)   MAX_ITER_OVERRIDE="$2"; shift 2 ;;
    --max-iterations=*) MAX_ITER_OVERRIDE="${1#*=}"; shift ;;
    --config)     CONFIG_OVERRIDE="$2"; shift 2 ;;
    --config=*)   CONFIG_OVERRIDE="${1#*=}"; shift ;;
    -h|--help)
      head -n 20 "$0" | tail -n +2 | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      # Legacy compat: bare number = max iterations for legacy mode
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        LEGACY_MAX="$1"
        [[ -z "$MODE" ]] && MODE="legacy"
      fi
      shift
      ;;
  esac
done

# Default mode
[[ -z "$MODE" ]] && MODE="auto"

# ── Initialize ──────────────────────────────────────────────

# For legacy mode, skip config loading (may not have ralph-config.yaml)
if [[ "$MODE" != "legacy" ]]; then
  [[ -n "$CONFIG_OVERRIDE" ]] && CONFIG_FILE="$CONFIG_OVERRIDE"
  load_config
fi

# Apply overrides
[[ -n "$TOOL_OVERRIDE" ]] && RALPH_TOOL="$TOOL_OVERRIDE"
[[ -n "$MAX_ITER_OVERRIDE" ]] && CFG_MAX_ITERATIONS="$MAX_ITER_OVERRIDE"
[[ -n "$INTERVAL_OVERRIDE" ]] && CFG_INTERVAL="$INTERVAL_OVERRIDE"

init_log

# ── Phase runner ────────────────────────────────────────────
run_phase() {
  local phase="$1"
  log_info "═══════════════════════════════════════"
  log_info "  Phase: $phase"
  log_info "═══════════════════════════════════════"

  save_state "${CURRENT_CYCLE:-0}" "$phase" "running"

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

  if [[ "$rc" -eq "$EXIT_OK" ]]; then
    save_state "${CURRENT_CYCLE:-0}" "$phase" "completed"
    log_info "Phase $phase completed successfully"
  elif [[ "$rc" -eq "$EXIT_RECOVERABLE" ]]; then
    save_state "${CURRENT_CYCLE:-0}" "$phase" "failed-recoverable"
    log_warn "Phase $phase failed (recoverable)"
  else
    save_state "${CURRENT_CYCLE:-0}" "$phase" "failed-fatal"
    log_error "Phase $phase failed (fatal)"
  fi

  return "$rc"
}

# ── Full cycle ──────────────────────────────────────────────
run_full_cycle() {
  CURRENT_CYCLE="$(increment_cycle_count)"
  export CURRENT_CYCLE
  log_info "Starting cycle #$CURRENT_CYCLE"

  local phases=("research" "prd-gen" "develop" "review" "release")

  for phase in "${phases[@]}"; do
    local rc=0
    run_phase "$phase" || rc=$?

    if [[ "$rc" -eq "$EXIT_FATAL" ]]; then
      log_error "Fatal error in phase $phase — stopping"
      return "$EXIT_FATAL"
    elif [[ "$rc" -eq "$EXIT_RECOVERABLE" ]]; then
      log_warn "Phase $phase failed — skipping rest of cycle"
      return "$EXIT_RECOVERABLE"
    fi
  done

  log_info "Cycle #$CURRENT_CYCLE completed successfully"
  return "$EXIT_OK"
}

# ── Legacy mode (backwards compatible) ──────────────────────
run_legacy() {
  local tool="${RALPH_TOOL:-claude}"
  local max="$LEGACY_MAX"

  echo "Starting Ralph (legacy mode) — Tool: $tool — Max iterations: $max"

  # Handle branch archival (same as original ralph.sh)
  local prd_file="$RALPH_DIR/prd.json"
  local progress_file="$RALPH_DIR/progress.txt"
  local archive_dir="$RALPH_DIR/archive"
  local last_branch_file="$RALPH_DIR/.last-branch"

  if [[ -f "$prd_file" && -f "$last_branch_file" ]]; then
    local current_branch last_branch
    current_branch="$(jq -r '.branchName // empty' "$prd_file" 2>/dev/null || echo "")"
    last_branch="$(cat "$last_branch_file" 2>/dev/null || echo "")"
    if [[ -n "$current_branch" && -n "$last_branch" && "$current_branch" != "$last_branch" ]]; then
      local folder_name date_str
      date_str="$(date +%Y-%m-%d)"
      folder_name="$(echo "$last_branch" | sed 's|^ralph/||')"
      local af="$archive_dir/$date_str-$folder_name"
      echo "Archiving previous run: $last_branch"
      mkdir -p "$af"
      cp "$prd_file" "$af/" 2>/dev/null || true
      [[ -f "$progress_file" ]] && cp "$progress_file" "$af/"
      echo "# Ralph Progress Log" > "$progress_file"
      echo "Started: $(date)" >> "$progress_file"
      echo "---" >> "$progress_file"
    fi
  fi

  if [[ -f "$prd_file" ]]; then
    local cb
    cb="$(jq -r '.branchName // empty' "$prd_file" 2>/dev/null || echo "")"
    [[ -n "$cb" ]] && echo "$cb" > "$last_branch_file"
  fi

  [[ ! -f "$progress_file" ]] && {
    echo "# Ralph Progress Log" > "$progress_file"
    echo "Started: $(date)" >> "$progress_file"
    echo "---" >> "$progress_file"
  }

  for i in $(seq 1 "$max"); do
    echo ""
    echo "==============================================================="
    echo "  Ralph Iteration $i of $max ($tool)"
    echo "==============================================================="

    local output
    if [[ "$tool" == "amp" ]]; then
      output="$(cat "$RALPH_DIR/prompt.md" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr)" || true
    else
      output="$(claude --dangerously-skip-permissions --print < "$RALPH_DIR/CLAUDE.md" 2>&1 | tee /dev/stderr)" || true
    fi

    if echo "$output" | grep -q "<promise>COMPLETE</promise>"; then
      echo ""
      echo "Ralph completed all tasks!"
      echo "Completed at iteration $i of $max"
      exit 0
    fi

    echo "Iteration $i complete. Continuing..."
    sleep 2
  done

  echo ""
  echo "Ralph reached max iterations ($max) without completing all tasks."
  echo "Check $progress_file for status."
  exit 1
}

# ── Main dispatch ───────────────────────────────────────────
case "$MODE" in
  auto)
    check_all_dependencies
    acquire_lock
    log_info "Ralph Autonomous Agent — single cycle mode"
    run_full_cycle
    ;;

  daemon)
    check_all_dependencies
    acquire_lock
    local interval_sec
    interval_sec="$(parse_interval "${CFG_INTERVAL:-30m}")"
    log_info "Ralph Autonomous Agent — daemon mode (interval: ${CFG_INTERVAL:-30m} = ${interval_sec}s)"
    while true; do
      run_full_cycle || true  # Don't exit daemon on recoverable errors
      log_info "Sleeping ${CFG_INTERVAL:-30m} until next cycle..."
      sleep "$interval_sec"
    done
    ;;

  phase)
    check_all_dependencies
    run_phase "$PHASE_OVERRIDE"
    ;;

  legacy)
    run_legacy
    ;;

  *)
    echo "Unknown mode: $MODE"
    exit 1
    ;;
esac
```

**Step 3: Run syntax check**

```bash
bash -n ralph.sh
```

Expected: No output (clean syntax)

**Step 4: Verify legacy mode still works**

```bash
./ralph.sh --legacy --tool claude 1
```

Expected: Behaves identically to the original ralph.sh with 1 iteration

**Step 5: Remove backup**

```bash
rm ralph.sh.bak
```

**Step 6: Commit**

```bash
git add ralph.sh
git commit -m "feat: rewrite ralph.sh as modular orchestrator with --auto, --daemon, --legacy modes"
```

---

## Task 11: Integration Test — Smoke Tests

**Files:**
- Create: `tests/smoke-test.sh`

A basic smoke test that verifies all modules load, config parses, and each phase function exists.

**Step 1: Write `tests/smoke-test.sh`**

```bash
#!/usr/bin/env bash
# tests/smoke-test.sh — Verify all Ralph modules load and key functions exist
set -euo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RALPH_DIR

PASS=0
FAIL=0

assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Ralph Smoke Tests ==="
echo ""

# Test 1: All scripts pass bash syntax check
echo "--- Syntax checks ---"
for f in "$RALPH_DIR"/lib/*.sh; do
  assert "syntax: $(basename "$f")" bash -n "$f"
done
assert "syntax: ralph.sh" bash -n "$RALPH_DIR/ralph.sh"

# Test 2: Source all modules
echo ""
echo "--- Module loading ---"
assert "load utils.sh" bash -c "source '$RALPH_DIR/lib/utils.sh'"
assert "load config.sh" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh'"
assert "load report.sh" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/report.sh'"
assert "load worktree.sh" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/worktree.sh'"
assert "load research.sh" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/research.sh'"
assert "load prd-gen.sh" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/report.sh' && source '$RALPH_DIR/lib/prd-gen.sh'"
assert "load develop.sh" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/develop.sh'"
assert "load review.sh" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/report.sh' && source '$RALPH_DIR/lib/review.sh'"
assert "load release.sh" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/report.sh' && source '$RALPH_DIR/lib/release.sh'"

# Test 3: Key functions exist after sourcing
echo ""
echo "--- Function availability ---"
assert "fn: log_info" bash -c "source '$RALPH_DIR/lib/utils.sh' && type log_info"
assert "fn: load_config" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && type load_config"
assert "fn: write_report" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/report.sh' && type write_report"
assert "fn: worktree_create" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/worktree.sh' && type worktree_create"
assert "fn: run_research" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/research.sh' && type run_research"
assert "fn: run_prd_gen" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/report.sh' && source '$RALPH_DIR/lib/prd-gen.sh' && type run_prd_gen"
assert "fn: run_develop" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/develop.sh' && type run_develop"
assert "fn: run_review" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/report.sh' && source '$RALPH_DIR/lib/review.sh' && type run_review"
assert "fn: run_release" bash -c "source '$RALPH_DIR/lib/utils.sh' && source '$RALPH_DIR/lib/config.sh' && source '$RALPH_DIR/lib/report.sh' && source '$RALPH_DIR/lib/release.sh' && type run_release"

# Test 4: Utils functions work
echo ""
echo "--- Utils functions ---"
assert "parse_interval 30m = 1800" bash -c "source '$RALPH_DIR/lib/utils.sh' && [[ \$(parse_interval '30m') -eq 1800 ]]"
assert "parse_interval 1h = 3600" bash -c "source '$RALPH_DIR/lib/utils.sh' && [[ \$(parse_interval '1h') -eq 3600 ]]"
assert "parse_interval 1h30m = 5400" bash -c "source '$RALPH_DIR/lib/utils.sh' && [[ \$(parse_interval '1h30m') -eq 5400 ]]"
assert "today_stamp format" bash -c "source '$RALPH_DIR/lib/utils.sh' && [[ \$(today_stamp) =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]"

# Test 5: Config example is valid YAML
echo ""
echo "--- Config validation ---"
assert "example config is valid YAML" yq '.' "$RALPH_DIR/config/ralph-config.yaml.example"

# Test 6: Help works
echo ""
echo "--- CLI ---"
assert "ralph.sh --help exits 0" bash -c "'$RALPH_DIR/ralph.sh' --help"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
```

**Step 2: Make executable and run**

```bash
chmod +x tests/smoke-test.sh
bash tests/smoke-test.sh
```

Expected: All tests PASS

**Step 3: Commit**

```bash
git add tests/smoke-test.sh
git commit -m "test: add smoke tests — verify all modules load and functions exist"
```

---

## Task 12: Documentation Update

**Files:**
- Modify: `README.md` (if it exists, otherwise create briefly)
- Create: `.gitignore` entries (already done in Task 4 partially)

**Step 1: Update `.gitignore`**

Ensure these entries are present (some may already be added):

```
.worktrees/
.ralph-state/
ralph-config.yaml
reports/
!reports/.gitkeep
```

**Step 2: Update CLAUDE.md**

Add a note about the new autonomous mode at the bottom of CLAUDE.md so the develop phase (which reads CLAUDE.md) can benefit from it:

Append after the existing content — add a new section:

```markdown

# Autonomous Mode

Ralph can now run in autonomous mode (`--auto` or `--daemon`), where it:
1. Researches competitors and discovers feature gaps
2. Auto-generates PRDs from research findings
3. Runs the development loop (this is what you do)
4. Reviews and verifies builds
5. Creates PRs, merges, tags, and releases

When running in autonomous mode, the prd.json you receive was auto-generated.
Follow the same instructions above — implement the highest-priority story with `passes: false`.
```

**Step 3: Commit**

```bash
git add .gitignore CLAUDE.md
git commit -m "docs: update gitignore and CLAUDE.md for autonomous mode"
```

---

## Summary: Task Dependency Graph

```
Task 1 (utils.sh)
  ├── Task 2 (config.sh) ── depends on utils.sh
  ├── Task 3 (report.sh) ── depends on utils.sh
  └── Task 4 (worktree.sh) ── depends on utils.sh
        │
        ├── Task 5 (research.sh) ── depends on 1,2,3
        ├── Task 6 (prd-gen.sh) ── depends on 1,2,3
        ├── Task 7 (develop.sh) ── depends on 1,2,4
        ├── Task 8 (review.sh) ── depends on 1,2,3
        └── Task 9 (release.sh) ── depends on 1,2,3
              │
              └── Task 10 (ralph.sh rewrite) ── depends on ALL above
                    │
                    └── Task 11 (smoke tests) ── depends on 10
                          │
                          └── Task 12 (docs) ── depends on 10
```

Tasks 2, 3, 4 can run in parallel. Tasks 5-9 can run in parallel. Task 10 must wait for all phases. Tasks 11-12 run last.
