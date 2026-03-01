#!/usr/bin/env bash
# lib/init.sh — Initialize a target project with Ralph
# Source this file AFTER lib/utils.sh; do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.  The entry-point script
# (ralph.sh) is responsible for `set -euo pipefail`.

# ── run_init ──────────────────────────────────────────────
# Bootstraps a target project directory with Ralph files.
#
# Reads from environment variables (set by ralph.sh arg parser):
#   INIT_TARGET_DIR    — target project directory (required)
#   INIT_TOOL          — default AI tool: claude|amp (default: claude)
#   INIT_PROJECT_NAME  — project name override (default: dir basename)
#   INIT_FORCE         — "true" to overwrite existing .ralph/ (default: false)
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
  sed "s|my-app|$project_name|g" "$RALPH_DIR/config/ralph-config.yaml.example" \
    > "$ralph_dest/config/ralph-config.yaml.example"

  # Generate a starter ralph-config.yaml with project name filled in
  sed "s|my-app|$project_name|g" "$RALPH_DIR/config/ralph-config.yaml.example" \
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

    echo "  Updated CLAUDE.md with Ralph section"
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
  echo "  1. Create a PRD:        cd \"$target_dir\" && claude  # then use /prd"
  echo "  2. Convert to prd.json: use /ralph in Claude Code"
  echo "  3. Copy prd.json to:    .ralph/prd.json"
  echo "  4. Run Ralph:           .ralph/ralph.sh"
  echo ""
  echo "Configuration:  .ralph/ralph-config.yaml"
  echo "Skills:         .claude/skills/prd/ and .claude/skills/ralph/"
}
