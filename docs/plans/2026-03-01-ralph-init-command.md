# Ralph Init Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `ralph init <target-dir>` subcommand that bootstraps any existing project to use Ralph's autonomous agent workflow.

**Architecture:** New `lib/init.sh` module with `run_init()` function, wired into `ralph.sh` argument parser as a new mode. Copies runtime files to `.ralph/`, skills to `.claude/skills/`, appends Ralph instructions to target's `CLAUDE.md`, and updates `.gitignore`.

**Tech Stack:** Bash, cp, mkdir, cat

---

### Task 1: Create `lib/init.sh` — the core init function

**Files:**
- Create: `lib/init.sh`

**Step 1: Write `lib/init.sh`**

```bash
#!/usr/bin/env bash
# lib/init.sh — Initialize a target project with Ralph
# Source this file AFTER lib/utils.sh; do not execute directly.

# ── run_init ──────────────────────────────────────────────
# Bootstraps a target project directory with Ralph files.
#
# Usage: run_init <target_dir> [--tool amp|claude] [--name project-name] [--force]
#
# Creates:
#   <target>/.ralph/          — runtime (ralph.sh, lib/, prompts/, config/, etc.)
#   <target>/.claude/skills/  — prd and ralph skills
#   <target>/CLAUDE.md        — appended Ralph agent instructions
#   <target>/.gitignore       — appended .ralph/ ignore entries
run_init() {
  local target_dir="${INIT_TARGET_DIR:?}"
  local tool="${INIT_TOOL:-claude}"
  local project_name="${INIT_PROJECT_NAME:-}"
  local force="${INIT_FORCE:-false}"

  # ── Validate target ─────────────────────────────────────
  if [[ ! -d "$target_dir" ]]; then
    echo "Error: Target directory does not exist: $target_dir" >&2
    return 1
  fi

  # Resolve to absolute path
  target_dir="$(cd "$target_dir" && pwd)"

  # Check it's a git repo
  if ! git -C "$target_dir" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: Target is not a git repository: $target_dir" >&2
    return 1
  fi

  # Auto-detect project name from directory basename
  if [[ -z "$project_name" ]]; then
    project_name="$(basename "$target_dir")"
  fi

  local ralph_dest="$target_dir/.ralph"

  # ── Check for existing .ralph/ ──────────────────────────
  if [[ -d "$ralph_dest" ]]; then
    if [[ "$force" == "true" ]]; then
      echo "Removing existing .ralph/ directory (--force)"
      rm -rf "$ralph_dest"
    else
      echo "Error: .ralph/ already exists in $target_dir" >&2
      echo "Use --force to overwrite." >&2
      return 1
    fi
  fi

  echo "Initializing Ralph in: $target_dir"
  echo "  Project name: $project_name"
  echo "  Default tool: $tool"

  # ── Copy runtime files to .ralph/ ───────────────────────
  mkdir -p "$ralph_dest"

  # ralph.sh (main entry point)
  cp "$RALPH_DIR/ralph.sh" "$ralph_dest/ralph.sh"
  chmod +x "$ralph_dest/ralph.sh"

  # lib/ (all shell modules)
  cp -R "$RALPH_DIR/lib" "$ralph_dest/lib"

  # prompts/ (phase-specific prompts)
  cp -R "$RALPH_DIR/prompts" "$ralph_dest/prompts"

  # prompt.md (Amp instructions)
  cp "$RALPH_DIR/prompt.md" "$ralph_dest/prompt.md"

  # CLAUDE.md (Claude Code instructions — goes inside .ralph/ for the agent loop)
  cp "$RALPH_DIR/CLAUDE.md" "$ralph_dest/CLAUDE.md"

  # prd.json.example
  cp "$RALPH_DIR/prd.json.example" "$ralph_dest/prd.json.example"

  # config/ with populated ralph-config.yaml
  mkdir -p "$ralph_dest/config"
  sed "s/my-app/$project_name/g" "$RALPH_DIR/config/ralph-config.yaml.example" \
    > "$ralph_dest/config/ralph-config.yaml.example"

  # Generate a starter ralph-config.yaml with project name filled in
  sed "s/my-app/$project_name/g" "$RALPH_DIR/config/ralph-config.yaml.example" \
    > "$ralph_dest/ralph-config.yaml"

  echo "  Copied runtime files to .ralph/"

  # ── Copy skills to .claude/skills/ ──────────────────────
  local skills_dest="$target_dir/.claude/skills"
  mkdir -p "$skills_dest"

  # Only copy if not already present (or --force)
  local skill
  for skill in prd ralph; do
    local skill_dest="$skills_dest/$skill"
    if [[ -d "$skill_dest" && "$force" != "true" ]]; then
      echo "  Skill '$skill' already exists, skipping (use --force to overwrite)"
    else
      mkdir -p "$skill_dest"
      cp "$RALPH_DIR/skills/$skill/SKILL.md" "$skill_dest/SKILL.md"
      echo "  Installed skill: $skill -> .claude/skills/$skill/"
    fi
  done

  # ── Append Ralph instructions to CLAUDE.md ──────────────
  local claude_md="$target_dir/CLAUDE.md"
  local marker="# Ralph Agent — Autonomous Mode"

  if [[ -f "$claude_md" ]] && grep -qF "$marker" "$claude_md"; then
    echo "  CLAUDE.md already contains Ralph section, skipping"
  else
    # Append with clear separator
    {
      echo ""
      echo "---"
      echo ""
      echo "$marker"
      echo ""
      echo "Ralph is configured in this project. Run the autonomous agent with:"
      echo ""
      echo '```bash'
      echo ".ralph/ralph.sh            # Single full cycle"
      echo ".ralph/ralph.sh --legacy   # Dev-only loop"
      echo ".ralph/ralph.sh --daemon   # Continuous mode"
      echo '```'
      echo ""
      echo "Configuration: \`.ralph/ralph-config.yaml\`"
      echo "PRD template:  \`.ralph/prd.json.example\`"
      echo ""
      echo "Use \`/prd\` to generate a PRD, then \`/ralph\` to convert it to \`prd.json\`."
    } >> "$claude_md"

    if [[ -f "$claude_md" ]]; then
      echo "  Appended Ralph section to existing CLAUDE.md"
    else
      echo "  Created CLAUDE.md with Ralph section"
    fi
  fi

  # ── Update .gitignore ───────────────────────────────────
  local gitignore="$target_dir/.gitignore"
  local ignore_marker="# Ralph runtime files"

  if [[ -f "$gitignore" ]] && grep -qF "$ignore_marker" "$gitignore"; then
    echo "  .gitignore already contains Ralph entries, skipping"
  else
    {
      echo ""
      echo "$ignore_marker"
      echo ".ralph/.ralph-state/"
      echo ".ralph/.worktrees/"
      echo ".ralph/prd.json"
      echo ".ralph/progress.txt"
      echo ".ralph/.last-branch"
      echo ".ralph/reports/"
      echo ".ralph/ralph-config.yaml"
    } >> "$gitignore"
    echo "  Updated .gitignore with Ralph entries"
  fi

  # ── Print quick-start guide ─────────────────────────────
  echo ""
  echo "Ralph initialized successfully!"
  echo ""
  echo "Quick start:"
  echo "  1. Create a PRD:        cd $target_dir && claude  # then use /prd"
  echo "  2. Convert to prd.json: use /ralph in Claude Code"
  echo "  3. Copy prd.json to:    .ralph/prd.json"
  echo "  4. Run Ralph:           .ralph/ralph.sh"
  echo ""
  echo "Configuration:  .ralph/ralph-config.yaml"
  echo "Skills:         .claude/skills/prd/ and .claude/skills/ralph/"
}
```

**Step 2: Commit**

```bash
git add lib/init.sh
git commit -m "feat: add lib/init.sh — core init function for bootstrapping projects"
```

---

### Task 2: Wire `init` mode into `ralph.sh` argument parser

**Files:**
- Modify: `ralph.sh` (source init.sh, add --init / init parsing, dispatch)

**Step 1: Add `source lib/init.sh` to the source block (line 27-35)**

After line 35 (`source "$RALPH_DIR/lib/release.sh"`), add:

```bash
source "$RALPH_DIR/lib/init.sh"
```

**Step 2: Add `init` to the usage text (line 39-58)**

Add under Modes section:

```
  init <dir>          Initialize Ralph in a target project
```

**Step 3: Add argument parsing for `init` mode (inside the `while` loop, line 70-165)**

Add a new case before `*)`:

```bash
    init)
      MODE="init"
      INIT_TARGET_DIR="${2:-}"
      if [[ -z "$INIT_TARGET_DIR" ]]; then
        echo "Error: init requires a target directory" >&2
        echo "Usage: ./ralph.sh init <target-dir> [--tool amp|claude] [--name project] [--force]" >&2
        exit 1
      fi
      shift 2
      # Parse init-specific options
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --tool)   INIT_TOOL="${2:-}"; shift 2 ;;
          --tool=*) INIT_TOOL="${1#*=}"; shift ;;
          --name)   INIT_PROJECT_NAME="${2:-}"; shift 2 ;;
          --name=*) INIT_PROJECT_NAME="${1#*=}"; shift ;;
          --force)  INIT_FORCE="true"; shift ;;
          *) echo "Error: Unknown init option '$1'" >&2; exit 1 ;;
        esac
      done
      export INIT_TARGET_DIR INIT_TOOL INIT_PROJECT_NAME INIT_FORCE
      break
      ;;
```

**Step 4: Add dispatch case (line 399-431)**

Before the `*)` fallback case, add:

```bash
  init)
    run_init
    ;;
```

**Step 5: Skip config/lock/deps for init mode (line 365-396)**

Change the guard from `[[ "$MODE" != "legacy" ]]` to `[[ "$MODE" != "legacy" && "$MODE" != "init" ]]`.

**Step 6: Commit**

```bash
git add ralph.sh
git commit -m "feat: wire init subcommand into ralph.sh CLI"
```

---

### Task 3: Write smoke tests

**Files:**
- Create: `tests/test_init.sh`

**Step 1: Write test script**

```bash
#!/usr/bin/env bash
# tests/test_init.sh — Smoke tests for ralph init
set -euo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Create a temporary git repo as target
TMPDIR="$(mktemp -d)"
TARGET="$TMPDIR/test-project"
mkdir -p "$TARGET"
git -C "$TARGET" init --quiet

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

echo "=== Test: ralph init ==="

# Test 1: Basic init succeeds
echo "Test 1: Basic init"
"$RALPH_DIR/ralph.sh" init "$TARGET" --name test-app
if [[ $? -eq 0 ]]; then pass "init exits 0"; else fail "init exits 0"; fi

# Test 2: .ralph/ directory exists with key files
echo "Test 2: Runtime files"
[[ -f "$TARGET/.ralph/ralph.sh" ]]         && pass ".ralph/ralph.sh exists"     || fail ".ralph/ralph.sh exists"
[[ -x "$TARGET/.ralph/ralph.sh" ]]         && pass ".ralph/ralph.sh executable" || fail ".ralph/ralph.sh executable"
[[ -d "$TARGET/.ralph/lib" ]]              && pass ".ralph/lib/ exists"         || fail ".ralph/lib/ exists"
[[ -d "$TARGET/.ralph/prompts" ]]          && pass ".ralph/prompts/ exists"     || fail ".ralph/prompts/ exists"
[[ -f "$TARGET/.ralph/prd.json.example" ]] && pass "prd.json.example exists"    || fail "prd.json.example exists"
[[ -f "$TARGET/.ralph/ralph-config.yaml" ]]&& pass "ralph-config.yaml exists"   || fail "ralph-config.yaml exists"

# Test 3: Skills installed
echo "Test 3: Skills"
[[ -f "$TARGET/.claude/skills/prd/SKILL.md" ]]   && pass "prd skill exists"   || fail "prd skill exists"
[[ -f "$TARGET/.claude/skills/ralph/SKILL.md" ]] && pass "ralph skill exists" || fail "ralph skill exists"

# Test 4: CLAUDE.md updated
echo "Test 4: CLAUDE.md"
grep -qF "Ralph Agent" "$TARGET/CLAUDE.md" && pass "CLAUDE.md has Ralph section" || fail "CLAUDE.md has Ralph section"

# Test 5: .gitignore updated
echo "Test 5: .gitignore"
grep -qF ".ralph/.ralph-state/" "$TARGET/.gitignore" && pass ".gitignore updated" || fail ".gitignore updated"

# Test 6: Config has project name
echo "Test 6: Config project name"
grep -qF "test-app" "$TARGET/.ralph/ralph-config.yaml" && pass "config has project name" || fail "config has project name"

# Test 7: Re-run without --force fails
echo "Test 7: Idempotency guard"
if "$RALPH_DIR/ralph.sh" init "$TARGET" 2>/dev/null; then
  fail "re-init without --force should fail"
else
  pass "re-init without --force fails"
fi

# Test 8: Re-run with --force succeeds
echo "Test 8: --force"
"$RALPH_DIR/ralph.sh" init "$TARGET" --force --name test-app
if [[ $? -eq 0 ]]; then pass "--force re-init succeeds"; else fail "--force re-init succeeds"; fi

# Test 9: Non-git directory fails
echo "Test 9: Non-git dir"
NON_GIT="$TMPDIR/not-a-repo"
mkdir -p "$NON_GIT"
if "$RALPH_DIR/ralph.sh" init "$NON_GIT" 2>/dev/null; then
  fail "non-git dir should fail"
else
  pass "non-git dir rejected"
fi

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ "$TESTS_FAILED" -eq 0 ]]
```

**Step 2: Run tests**

```bash
bash tests/test_init.sh
```

Expected: All tests pass.

**Step 3: Commit**

```bash
git add tests/test_init.sh
git commit -m "test: add smoke tests for ralph init command"
```

---

### Task 4: Update README with init documentation

**Files:**
- Modify: `README.md`

**Step 1: Add init section to README**

Add after the existing usage section:

```markdown
## Initialize Ralph in Another Project

```bash
# Basic usage
./ralph.sh init /path/to/your-project

# With options
./ralph.sh init /path/to/your-project --tool claude --name my-app

# Overwrite existing setup
./ralph.sh init /path/to/your-project --force
```

This creates:
- `.ralph/` — Runtime files (ralph.sh, lib/, prompts/, config/)
- `.claude/skills/prd/` — PRD generator skill
- `.claude/skills/ralph/` — PRD-to-JSON converter skill
- Appends Ralph instructions to your `CLAUDE.md`
- Updates `.gitignore` with Ralph runtime entries

### Quick Start After Init

1. Open your project in Claude Code
2. Use `/prd` to write a Product Requirements Document
3. Use `/ralph` to convert it to `.ralph/prd.json`
4. Run `.ralph/ralph.sh` to start the autonomous agent loop
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add ralph init usage to README"
```
