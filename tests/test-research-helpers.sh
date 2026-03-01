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

# ── Config loading: requirements.yaml ──────────────────────────

echo "2. Config: requirements.yaml loading"
echo "---"

# Create a temp dir with a requirements.yaml
_test_dir="$(mktemp -d)"
cat > "$_test_dir/requirements.yaml" <<'YAML'
- title: "Test feature"
  description: "A test requirement"
  priority: high
  context: "Testing context"
YAML

# Also need a minimal ralph-config.yaml for load_config
cat > "$_test_dir/ralph-config.yaml" <<'YAML'
project:
  name: test-project
  description: "Test"
research:
  competitors: []
  dimensions: []
YAML

# Symlink lib/ into temp dir so RALPH_DIR can point there
ln -s "$RALPH_DIR/lib" "$_test_dir/lib"

# Load config from temp dir
result="$(
  bash -c "
    export RALPH_DIR='$_test_dir'
    export CONFIG_FILE='$_test_dir/ralph-config.yaml'
    source '$_test_dir/lib/utils.sh'
    source '$_test_dir/lib/config.sh'
    load_config >/dev/null 2>&1
    echo \"\$CFG_USER_REQUIREMENTS\"
  "
)"
assert_contains "requirements loaded from YAML" "Test feature" "$result"

# Without requirements.yaml — should default to []
_test_dir2="$(mktemp -d)"
cat > "$_test_dir2/ralph-config.yaml" <<'YAML'
project:
  name: test-project
  description: "Test"
research:
  competitors: []
  dimensions: []
YAML
ln -s "$RALPH_DIR/lib" "$_test_dir2/lib"

result2="$(
  bash -c "
    export RALPH_DIR='$_test_dir2'
    export CONFIG_FILE='$_test_dir2/ralph-config.yaml'
    source '$_test_dir2/lib/utils.sh'
    source '$_test_dir2/lib/config.sh'
    load_config >/dev/null 2>&1
    echo \"\$CFG_USER_REQUIREMENTS\"
  "
)"
assert_eq "missing requirements.yaml defaults to []" "[]" "$result2"

rm -rf "$_test_dir" "$_test_dir2"

echo ""

# ── _render_prompt: {{REQUIREMENTS}} substitution ─────────────

echo "3. _render_prompt includes requirements"
echo "---"

# Set up a temp environment with all needed files
_test_dir3="$(mktemp -d)"
mkdir -p "$_test_dir3/prompts"
cat > "$_test_dir3/prompts/research.md" <<'MD'
# Test Prompt
Project: {{PROJECT_NAME}}
Requirements: {{REQUIREMENTS}}
Competitors: {{COMPETITORS}}
Dimensions: {{DIMENSIONS}}
Auto: {{AUTO_DISCOVER}}
Description: {{PROJECT_DESC}}
MD

cat > "$_test_dir3/ralph-config.yaml" <<'YAML'
project:
  name: test-app
  description: "Test app"
research:
  competitors: []
  dimensions: []
  auto_discover: false
YAML

cat > "$_test_dir3/requirements.yaml" <<'YAML'
- title: "My Feature"
  description: "Build my feature"
  priority: high
YAML

# Symlink lib/ so sourcing works in subshell
ln -s "$RALPH_DIR/lib" "$_test_dir3/lib"

result3="$(
  bash -c "
    export RALPH_DIR='$_test_dir3'
    export CONFIG_FILE='$_test_dir3/ralph-config.yaml'
    source '$_test_dir3/lib/utils.sh'
    source '$_test_dir3/lib/config.sh'
    source '$_test_dir3/lib/report.sh'
    source '$_test_dir3/lib/research.sh'
    load_config >/dev/null 2>&1
    RESEARCH_PROMPT_TEMPLATE='$_test_dir3/prompts/research.md'
    _render_prompt 2>/dev/null
  "
)"
assert_contains "rendered prompt contains requirement title" "My Feature" "$result3"
assert_contains "rendered prompt contains project name" "test-app" "$result3"

rm -rf "$_test_dir3"

echo ""

# ── Summary ────────────────────────────────────────────────────
echo "====================="
TOTAL=$((PASS + FAIL))
echo "Results: $PASS passed, $FAIL failed (out of $TOTAL)"
echo "====================="

[[ "$FAIL" -eq 0 ]] || exit 1
