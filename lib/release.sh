#!/usr/bin/env bash
# lib/release.sh — Release automation for Ralph autonomous agent
# Source this file AFTER lib/utils.sh, lib/config.sh, and lib/report.sh;
# do not execute directly.
# NOTE: Do NOT set shell options here — sourced libraries must not
# alter the caller's shell behaviour.  The entry-point script
# (ralph.sh) is responsible for `set -euo pipefail`.

# ── Guards ────────────────────────────────────────────────────
# Verify that utils.sh, config.sh, and report.sh have been sourced.
if ! declare -f log_info &>/dev/null; then
  echo "[ERROR] lib/release.sh: must be sourced after lib/utils.sh" >&2
  return 1 2>/dev/null || exit 1
fi

if ! declare -f write_report &>/dev/null; then
  echo "[ERROR] lib/release.sh: must be sourced after lib/report.sh" >&2
  return 1 2>/dev/null || exit 1
fi

# ── _get_pr_title ─────────────────────────────────────────────
# Extract a PR title from prd.json description field, falling
# back to the current branch name.
#
# Usage: _get_pr_title
_get_pr_title() {
  local prd_file="${RALPH_DIR}/prd.json"
  local title=""

  if [[ -f "$prd_file" ]]; then
    title="$(jq -r '.description // empty' "$prd_file" 2>/dev/null || true)"
  fi

  if [[ -z "$title" ]]; then
    title="$(git rev-parse --abbrev-ref HEAD)"
  fi

  echo "$title"
}

# ── _get_pr_body ──────────────────────────────────────────────
# Generate a PR body with the commit log since divergence from
# main/master and references to today's reports.
#
# Usage: _get_pr_body "base_branch"
_get_pr_body() {
  local base_branch="${1:-main}"

  local commit_log
  commit_log="$(git log --oneline "${base_branch}..HEAD" 2>/dev/null || echo "(no commits)")"

  local report_dir
  report_dir="$(today_dir)"

  local body=""
  body+="## Commits"$'\n'
  body+=$'\n'
  body+="\`\`\`"$'\n'
  body+="${commit_log}"$'\n'
  body+="\`\`\`"$'\n'
  body+=$'\n'
  body+="## Reports"$'\n'
  body+=$'\n'
  body+="Report directory: \`${report_dir}\`"$'\n'

  echo "$body"
}

# ── _detect_base_branch ──────────────────────────────────────
# Detect whether the repo uses "main" or "master" as its default
# branch.  Falls back to "main".
#
# Usage: _detect_base_branch
_detect_base_branch() {
  if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
    echo "master"
  else
    echo "main"
  fi
}

# ── _bump_minor_version ──────────────────────────────────────
# Given a semver tag like "v1.2.3", bump the minor version and
# reset patch to 0.  Returns "v1.3.0".  Handles the "v" prefix.
#
# Usage: _bump_minor_version "v1.2.3"
_bump_minor_version() {
  local tag="${1:-v0.0.0}"
  # Strip the leading "v" if present
  local version="${tag#v}"

  local major minor patch
  IFS='.' read -r major minor patch <<< "$version"

  major="${major:-0}"
  minor="${minor:-0}"

  local new_minor=$((minor + 1))
  echo "v${major}.${new_minor}.0"
}

# ── run_release ──────────────────────────────────────────────
# Orchestrates the release phase: push, PR, CI check, merge,
# tag, GitHub Release, and summary report.
#
# Uses CFG_RELEASE_AUTO_PR, CFG_RELEASE_AUTO_MERGE,
# CFG_RELEASE_AUTO_TAG, CFG_RELEASE_AUTO_RELEASE from config.sh.
#
# Returns EXIT_OK on success, EXIT_RECOVERABLE on non-fatal errors.
#
# Usage: run_release
run_release() {
  log_info "=== Release phase started ==="

  # ── Step 1: Check current branch ──────────────────────────
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"

  local base_branch
  base_branch="$(_detect_base_branch)"

  if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
    log_warn "On ${current_branch} branch — nothing to release"
    return "$EXIT_OK"
  fi

  log_info "Releasing branch: ${current_branch} (base: ${base_branch})"

  # Track state for the summary report
  local pr_url=""
  local pr_number=""
  local ci_status="skipped"
  local merge_status="skipped"
  local new_tag=""
  local release_url=""
  local overall_status="success"

  # ── Step 2: Push branch to origin ─────────────────────────
  log_info "Pushing branch ${current_branch} to origin"
  if ! git push -u origin "$current_branch" 2>&1; then
    log_error "Failed to push branch ${current_branch}"
    overall_status="failed"
    _write_release_summary "$current_branch" "$pr_url" "$ci_status" \
      "$merge_status" "$new_tag" "$release_url" "$overall_status"
    return "$EXIT_RECOVERABLE"
  fi

  # ── Step 3: Create PR ─────────────────────────────────────
  if [[ "${CFG_RELEASE_AUTO_PR:-false}" == "true" ]]; then
    log_info "Creating pull request"

    local pr_title
    pr_title="$(_get_pr_title)"

    local pr_body
    pr_body="$(_get_pr_body "$base_branch")"

    # Check if a PR already exists for this branch
    local existing_pr
    existing_pr="$(gh pr view "$current_branch" --json number,url 2>/dev/null || true)"

    if [[ -n "$existing_pr" ]]; then
      pr_number="$(echo "$existing_pr" | jq -r '.number')"
      pr_url="$(echo "$existing_pr" | jq -r '.url')"
      log_info "PR already exists: #${pr_number} (${pr_url})"
    else
      local pr_output
      if pr_output="$(gh pr create \
          --title "$pr_title" \
          --body "$pr_body" \
          --base "$base_branch" 2>&1)"; then
        pr_url="$pr_output"
        # Extract PR number from the URL
        pr_number="$(echo "$pr_url" | grep -oE '[0-9]+$' || true)"
        log_info "PR created: #${pr_number} (${pr_url})"
      else
        log_error "Failed to create PR: ${pr_output}"
        overall_status="failed"
        _write_release_summary "$current_branch" "$pr_url" "$ci_status" \
          "$merge_status" "$new_tag" "$release_url" "$overall_status"
        return "$EXIT_RECOVERABLE"
      fi
    fi
  fi

  # ── Step 4: Wait for CI ───────────────────────────────────
  if [[ -n "$pr_url" ]]; then
    log_info "Checking CI status for PR #${pr_number}"
    if gh pr checks "$current_branch" --watch 2>&1; then
      ci_status="passed"
      log_info "CI checks passed"
    else
      ci_status="failed"
      log_warn "CI checks failed or timed out — continuing anyway"
    fi
  fi

  # ── Step 5: Auto-merge ────────────────────────────────────
  if [[ "${CFG_RELEASE_AUTO_MERGE:-false}" == "true" && -n "$pr_url" ]]; then
    log_info "Auto-merging PR #${pr_number}"
    if gh pr merge --squash --delete-branch 2>&1; then
      merge_status="merged"
      log_info "PR #${pr_number} merged successfully"

      # Checkout base branch and pull latest
      log_info "Checking out ${base_branch} and pulling latest"
      git checkout "$base_branch"
      git pull origin "$base_branch"
    else
      merge_status="failed"
      log_error "Failed to merge PR #${pr_number}"
      overall_status="failed"
      _write_release_summary "$current_branch" "$pr_url" "$ci_status" \
        "$merge_status" "$new_tag" "$release_url" "$overall_status"
      return "$EXIT_RECOVERABLE"
    fi
  fi

  # ── Step 6: Semantic tag ──────────────────────────────────
  if [[ "${CFG_RELEASE_AUTO_TAG:-false}" == "true" ]]; then
    log_info "Creating semantic version tag"

    local latest_tag
    latest_tag="$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")"
    log_info "Latest tag: ${latest_tag}"

    new_tag="$(_bump_minor_version "$latest_tag")"
    log_info "New tag: ${new_tag}"

    if git tag -a "$new_tag" -m "Release ${new_tag}" 2>&1; then
      log_info "Tag ${new_tag} created"

      if git push origin "$new_tag" 2>&1; then
        log_info "Tag ${new_tag} pushed to origin"
      else
        log_error "Failed to push tag ${new_tag}"
        overall_status="failed"
      fi
    else
      log_error "Failed to create tag ${new_tag}"
      new_tag=""
      overall_status="failed"
    fi
  fi

  # ── Step 7: GitHub Release ────────────────────────────────
  if [[ "${CFG_RELEASE_AUTO_RELEASE:-false}" == "true" && -n "$new_tag" ]]; then
    log_info "Creating GitHub Release for ${new_tag}"
    local release_output
    if release_output="$(gh release create "$new_tag" \
        --generate-notes \
        --title "$new_tag" 2>&1)"; then
      release_url="$release_output"
      log_info "GitHub Release created: ${release_url}"
    else
      log_error "Failed to create GitHub Release: ${release_output}"
      release_url=""
      overall_status="failed"
    fi
  fi

  # ── Step 8: Write release summary report ──────────────────
  _write_release_summary "$current_branch" "$pr_url" "$ci_status" \
    "$merge_status" "$new_tag" "$release_url" "$overall_status"

  # ── Step 9: Return status ─────────────────────────────────
  if [[ "$overall_status" == "success" ]]; then
    log_info "=== Release phase completed successfully ==="
    return "$EXIT_OK"
  else
    log_warn "=== Release phase completed with errors ==="
    return "$EXIT_RECOVERABLE"
  fi
}

# ── _write_release_summary ───────────────────────────────────
# Write a release-summary.md report for the current cycle.
#
# Usage: _write_release_summary branch pr_url ci merge tag release status
_write_release_summary() {
  local branch="${1:-}"
  local pr_url="${2:-}"
  local ci_status="${3:-skipped}"
  local merge_status="${4:-skipped}"
  local tag="${5:-}"
  local release_url="${6:-}"
  local status="${7:-unknown}"

  local header
  header="$(phase_header "Release" "$status")"

  local content=""
  content+="${header}"$'\n'
  content+=$'\n'
  content+="## Details"$'\n'
  content+=$'\n'
  content+="| Step | Result |"$'\n'
  content+="| ---- | ------ |"$'\n'
  content+="| Branch | \`${branch}\` |"$'\n'
  content+="| PR | ${pr_url:-none} |"$'\n'
  content+="| CI | ${ci_status} |"$'\n'
  content+="| Merge | ${merge_status} |"$'\n'
  content+="| Tag | ${tag:-none} |"$'\n'
  content+="| Release | ${release_url:-none} |"$'\n'

  write_report "release-summary.md" "$content" > /dev/null
}
