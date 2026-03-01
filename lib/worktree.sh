#!/usr/bin/env bash
# lib/worktree.sh — Git worktree management for Ralph autonomous agent
# Source this file AFTER lib/utils.sh; do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.  The entry-point script
# (ralph.sh) is responsible for `set -euo pipefail`.

# ── Worktree base path ────────────────────────────────────
WORKTREE_BASE="${RALPH_DIR}/.worktrees"

# ── worktree_create ───────────────────────────────────────
# Creates a git worktree at .worktrees/<story_id> on branch
# ralph/<story_id> from the given base_branch.
# Cleans up any leftover worktree for the same story_id first.
# Prints the worktree path to stdout.
#
# Usage: worktree_create "story_id" "base_branch"
worktree_create() {
  local story_id="$1"
  local base_branch="$2"
  local branch_name="ralph/${story_id}"
  local worktree_path="${WORKTREE_BASE}/${story_id}"

  # Clean up leftover worktree for this story if it exists
  if [[ -d "$worktree_path" ]]; then
    log_warn "Leftover worktree found at ${worktree_path}, cleaning up"
    worktree_remove "$story_id"
  fi

  mkdir -p "$WORKTREE_BASE"

  # Delete the branch if it already exists (leftover from a previous run)
  if project_git show-ref --verify --quiet "refs/heads/${branch_name}" 2>/dev/null; then
    log_warn "Leftover branch ${branch_name} found, deleting"
    project_git branch -D "$branch_name" 2>/dev/null || true
  fi

  log_info "Creating worktree at ${worktree_path} (branch: ${branch_name}, base: ${base_branch})"
  project_git worktree add -b "$branch_name" "$worktree_path" "$base_branch"

  log_info "Worktree created: ${worktree_path}"
  echo "$worktree_path"
}

# ── worktree_remove ───────────────────────────────────────
# Removes the worktree for a given story_id and deletes its branch.
#
# Usage: worktree_remove "story_id"
worktree_remove() {
  local story_id="$1"
  local branch_name="ralph/${story_id}"
  local worktree_path="${WORKTREE_BASE}/${story_id}"

  if [[ -d "$worktree_path" ]]; then
    log_info "Removing worktree at ${worktree_path}"
    project_git worktree remove --force "$worktree_path" 2>/dev/null || {
      log_warn "git worktree remove failed, falling back to manual cleanup"
      rm -rf "$worktree_path"
      project_git worktree prune
    }
  else
    log_warn "Worktree directory not found: ${worktree_path}"
    # Still prune in case git has a stale record
    project_git worktree prune
  fi

  # Delete the branch if it still exists
  if project_git show-ref --verify --quiet "refs/heads/${branch_name}" 2>/dev/null; then
    log_info "Deleting branch ${branch_name}"
    project_git branch -D "$branch_name" 2>/dev/null || log_warn "Failed to delete branch ${branch_name}"
  fi
}

# ── worktree_squash_merge ─────────────────────────────────
# Squash-merges the worktree branch into the target branch.
#
# Usage: worktree_squash_merge "story_id" "target_branch" "commit_msg"
worktree_squash_merge() {
  local story_id="$1"
  local target_branch="$2"
  local commit_msg="$3"
  local branch_name="ralph/${story_id}"

  # Verify the branch exists
  if ! project_git show-ref --verify --quiet "refs/heads/${branch_name}" 2>/dev/null; then
    log_error "Branch ${branch_name} does not exist, cannot squash-merge"
    return "$EXIT_RECOVERABLE"
  fi

  log_info "Squash-merging ${branch_name} into ${target_branch}"

  # Save current branch to restore on failure
  local original_branch
  original_branch="$(project_git rev-parse --abbrev-ref HEAD)"

  if ! project_git checkout "$target_branch"; then
    log_error "Failed to checkout ${target_branch}"
    project_git checkout "$original_branch" 2>/dev/null || true
    return "$EXIT_RECOVERABLE"
  fi

  if ! project_git merge --squash "$branch_name"; then
    log_error "Squash-merge failed for ${branch_name}"
    project_git merge --abort 2>/dev/null
    project_git checkout "$original_branch" 2>/dev/null || true
    return "$EXIT_RECOVERABLE"
  fi

  if ! project_git commit -m "$commit_msg"; then
    log_error "Commit failed after squash-merge"
    project_git merge --abort 2>/dev/null
    project_git checkout "$original_branch" 2>/dev/null || true
    return "$EXIT_RECOVERABLE"
  fi

  log_info "Squash-merge complete: ${branch_name} -> ${target_branch}"

  # Return to original branch if different
  if [[ "$original_branch" != "$target_branch" ]]; then
    project_git checkout "$original_branch" 2>/dev/null || true
  fi
}

# ── worktree_cleanup_all ──────────────────────────────────
# Removes ALL worktrees under the worktree base directory and
# prunes stale worktree references.
#
# Usage: worktree_cleanup_all
worktree_cleanup_all() {
  log_info "Cleaning up all worktrees under ${WORKTREE_BASE}"

  if [[ -d "$WORKTREE_BASE" ]]; then
    local entry
    for entry in "$WORKTREE_BASE"/*/; do
      # Skip if glob didn't match anything
      [[ -d "$entry" ]] || continue
      local story_id
      story_id="$(basename "$entry")"
      log_info "Removing worktree for story: ${story_id}"
      worktree_remove "$story_id"
    done

    # Remove the base directory if empty
    rmdir "$WORKTREE_BASE" 2>/dev/null || true
  fi

  project_git worktree prune
  log_info "Worktree cleanup complete"
}
