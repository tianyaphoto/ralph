#!/usr/bin/env bash
# tests/smoke-test.sh — Smoke tests for Ralph autonomous agent
#
# Verifies:
#   1. All .sh files pass bash -n syntax check
#   2. Modules can be sourced together without errors
#   3. Key functions are available after sourcing
#   4. Utils functions produce correct output
#   5. Config example is valid YAML
#   6. CLI --help exits 0
#
# Usage: bash tests/smoke-test.sh

set -uo pipefail

# ── Resolve project root ─────────────────────────────────────
RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RALPH_DIR

PASS=0
FAIL=0

# ── Assert helper ─────────────────────────────────────────────
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

# ── Assert equality helper ────────────────────────────────────
assert_eq() {
  local desc="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

# ── Assert failure helper (command should return non-zero) ────
assert_fail() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "  FAIL: $desc (expected failure but got success)"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  fi
}

# ==============================================================
echo ""
echo "Ralph Smoke Tests"
echo "================="
echo ""

# ── 1. Syntax checks ─────────────────────────────────────────
echo "1. Syntax checks (bash -n)"
echo "---"

assert "ralph.sh passes syntax check"    bash -n "$RALPH_DIR/ralph.sh"
assert "lib/utils.sh passes syntax check" bash -n "$RALPH_DIR/lib/utils.sh"
assert "lib/config.sh passes syntax check" bash -n "$RALPH_DIR/lib/config.sh"
assert "lib/report.sh passes syntax check" bash -n "$RALPH_DIR/lib/report.sh"
assert "lib/worktree.sh passes syntax check" bash -n "$RALPH_DIR/lib/worktree.sh"
assert "lib/research.sh passes syntax check" bash -n "$RALPH_DIR/lib/research.sh"
assert "lib/prd-gen.sh passes syntax check" bash -n "$RALPH_DIR/lib/prd-gen.sh"
assert "lib/develop.sh passes syntax check" bash -n "$RALPH_DIR/lib/develop.sh"
assert "lib/review.sh passes syntax check" bash -n "$RALPH_DIR/lib/review.sh"
assert "lib/release.sh passes syntax check" bash -n "$RALPH_DIR/lib/release.sh"

echo ""

# ── 2. Module loading ────────────────────────────────────────
echo "2. Module loading (source)"
echo "---"

assert "utils.sh loads alone" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'"

assert "utils.sh + config.sh load together" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; source '$RALPH_DIR/lib/config.sh'"

assert "utils.sh + report.sh load together" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; source '$RALPH_DIR/lib/report.sh'"

assert "utils.sh + worktree.sh load together" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; source '$RALPH_DIR/lib/worktree.sh'"

assert "utils.sh + config.sh + report.sh + research.sh load together" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; source '$RALPH_DIR/lib/config.sh'; source '$RALPH_DIR/lib/report.sh'; source '$RALPH_DIR/lib/research.sh'"

assert "utils.sh + config.sh + report.sh + prd-gen.sh load together" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; source '$RALPH_DIR/lib/config.sh'; source '$RALPH_DIR/lib/report.sh'; source '$RALPH_DIR/lib/prd-gen.sh'"

assert "utils.sh + config.sh + report.sh + worktree.sh + develop.sh load together" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; source '$RALPH_DIR/lib/config.sh'; source '$RALPH_DIR/lib/report.sh'; source '$RALPH_DIR/lib/worktree.sh'; source '$RALPH_DIR/lib/develop.sh'"

assert "utils.sh + config.sh + report.sh + review.sh load together" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; source '$RALPH_DIR/lib/config.sh'; source '$RALPH_DIR/lib/report.sh'; source '$RALPH_DIR/lib/review.sh'"

assert "utils.sh + config.sh + report.sh + release.sh load together" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; source '$RALPH_DIR/lib/config.sh'; source '$RALPH_DIR/lib/report.sh'; source '$RALPH_DIR/lib/release.sh'"

echo ""

# ── 3. Function availability ─────────────────────────────────
echo "3. Function availability (type -t)"
echo "---"

# Source all modules in a subshell and check function availability
_check_fn() {
  local fn_name="$1"
  bash -c "
    export RALPH_DIR='$RALPH_DIR'
    source '$RALPH_DIR/lib/utils.sh'
    source '$RALPH_DIR/lib/config.sh'
    source '$RALPH_DIR/lib/report.sh'
    source '$RALPH_DIR/lib/worktree.sh'
    source '$RALPH_DIR/lib/research.sh'
    source '$RALPH_DIR/lib/prd-gen.sh'
    source '$RALPH_DIR/lib/develop.sh'
    source '$RALPH_DIR/lib/review.sh'
    source '$RALPH_DIR/lib/release.sh'
    type -t '$fn_name' | grep -q function
  "
}

assert "log_info is available"      _check_fn log_info
assert "invoke_ai is available"    _check_fn invoke_ai
assert "load_config is available"   _check_fn load_config
assert "write_report is available"  _check_fn write_report
assert "worktree_create is available" _check_fn worktree_create
assert "run_research is available"  _check_fn run_research
assert "run_prd_gen is available"   _check_fn run_prd_gen
assert "run_develop is available"   _check_fn run_develop
assert "run_review is available"    _check_fn run_review
assert "run_release is available"   _check_fn run_release

echo ""

# ── 4. Utils function tests ──────────────────────────────────
echo "4. Utils function tests"
echo "---"

# parse_interval tests — run in subshells that source utils.sh
_parse_interval() {
  bash -c "
    export RALPH_DIR='$RALPH_DIR'
    source '$RALPH_DIR/lib/utils.sh'
    parse_interval '$1'
  "
}

result_30m="$(_parse_interval "30m" 2>/dev/null)"
assert_eq "parse_interval '30m' == 1800" "1800" "$result_30m"

result_1h="$(_parse_interval "1h" 2>/dev/null)"
assert_eq "parse_interval '1h' == 3600" "3600" "$result_1h"

result_1h30m="$(_parse_interval "1h30m" 2>/dev/null)"
assert_eq "parse_interval '1h30m' == 5400" "5400" "$result_1h30m"

# today_stamp should match YYYY-MM-DD format
today_result="$(bash -c "
  export RALPH_DIR='$RALPH_DIR'
  source '$RALPH_DIR/lib/utils.sh'
  today_stamp
" 2>/dev/null)"

assert "today_stamp matches YYYY-MM-DD format" \
  bash -c "[[ '$today_result' =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]"

# parse_interval with empty string should return error
assert_fail "parse_interval '' returns error" \
  bash -c "export RALPH_DIR='$RALPH_DIR'; source '$RALPH_DIR/lib/utils.sh'; parse_interval ''"

echo ""

# ── 5. Config validation ─────────────────────────────────────
echo "5. Config validation"
echo "---"

assert "config/ralph-config.yaml.example is valid YAML" \
  yq '.' "$RALPH_DIR/config/ralph-config.yaml.example"

echo ""

# ── 6. CLI test ──────────────────────────────────────────────
echo "6. CLI test"
echo "---"

assert "./ralph.sh --help exits 0" \
  bash "$RALPH_DIR/ralph.sh" --help

echo ""

# ── Summary ──────────────────────────────────────────────────
echo "================="
TOTAL=$((PASS + FAIL))
echo "Results: $PASS passed, $FAIL failed (out of $TOTAL)"
echo "================="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi

exit 0
