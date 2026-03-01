#!/usr/bin/env bash
# tests/test-research-helpers.sh — Unit tests for research helper functions

set -uo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export RALPH_DIR

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected to contain '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "Research Helper Tests"
echo "====================="
echo ""

# Source modules
source "$RALPH_DIR/lib/utils.sh"
source "$RALPH_DIR/lib/config.sh"
source "$RALPH_DIR/lib/report.sh"
source "$RALPH_DIR/lib/research.sh"

# ── _build_requirements_text tests ────────────────────────────

echo "1. _build_requirements_text"
echo "---"

# Empty array
result="$(_build_requirements_text '[]')"
assert_eq "empty array returns placeholder" \
  "(No user requirements provided.)" "$result"

# Single requirement
json='[{"title":"Dark mode","description":"Add dark mode support","priority":"high"}]'
result="$(_build_requirements_text "$json")"
assert_contains "contains title" "**Dark mode**" "$result"
assert_contains "contains priority" "high" "$result"
assert_contains "contains description" "Add dark mode support" "$result"

# Multiple requirements
json='[{"title":"A","description":"desc A","priority":"high"},{"title":"B","description":"desc B","priority":"low"}]'
result="$(_build_requirements_text "$json")"
assert_contains "multi: contains first title" "**A**" "$result"
assert_contains "multi: contains second title" "**B**" "$result"

# With optional context field
json='[{"title":"Offline","description":"Work offline","priority":"medium","context":"Users need this for travel"}]'
result="$(_build_requirements_text "$json")"
assert_contains "context field rendered" "Users need this for travel" "$result"

# Without context field (should not error)
json='[{"title":"Simple","description":"Simple feature","priority":"low"}]'
result="$(_build_requirements_text "$json")"
assert_contains "no context: still works" "**Simple**" "$result"

# Default argument (no args)
result="$(_build_requirements_text)"
assert_eq "no args returns placeholder" \
  "(No user requirements provided.)" "$result"

echo ""

# ── Summary ────────────────────────────────────────────────────
echo "====================="
TOTAL=$((PASS + FAIL))
echo "Results: $PASS passed, $FAIL failed (out of $TOTAL)"
echo "====================="

[[ "$FAIL" -eq 0 ]] || exit 1
