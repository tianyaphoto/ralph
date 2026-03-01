#!/usr/bin/env bash
# tests/test_init.sh — Smoke tests for ralph init
set -euo pipefail

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

# Create a temporary directory for test targets
TEST_TMPDIR="$(mktemp -d)"
TARGET="$TEST_TMPDIR/test-project"
mkdir -p "$TARGET"
git -C "$TARGET" init --quiet

cleanup() { rm -rf "$TEST_TMPDIR"; }
trap cleanup EXIT

echo "=== Test: ralph init ==="

# Test 1: Basic init succeeds
echo "Test 1: Basic init"
"$RALPH_DIR/ralph.sh" init "$TARGET" --name test-app
if [[ $? -eq 0 ]]; then pass "init exits 0"; else fail "init exits 0"; fi

# Test 2: .ralph/ directory exists with key files
echo "Test 2: Runtime files"
[[ -f "$TARGET/.ralph/ralph.sh" ]]          && pass ".ralph/ralph.sh exists"     || fail ".ralph/ralph.sh exists"
[[ -x "$TARGET/.ralph/ralph.sh" ]]          && pass ".ralph/ralph.sh executable" || fail ".ralph/ralph.sh executable"
[[ -d "$TARGET/.ralph/lib" ]]               && pass ".ralph/lib/ exists"         || fail ".ralph/lib/ exists"
[[ -d "$TARGET/.ralph/prompts" ]]           && pass ".ralph/prompts/ exists"     || fail ".ralph/prompts/ exists"
[[ -f "$TARGET/.ralph/prd.json.example" ]]  && pass "prd.json.example exists"    || fail "prd.json.example exists"
[[ -f "$TARGET/.ralph/ralph-config.yaml" ]] && pass "ralph-config.yaml exists"   || fail "ralph-config.yaml exists"
[[ -f "$TARGET/.ralph/prompt.md" ]]         && pass "prompt.md exists"           || fail "prompt.md exists"
[[ -f "$TARGET/.ralph/CLAUDE.md" ]]         && pass ".ralph/CLAUDE.md exists"    || fail ".ralph/CLAUDE.md exists"

# Test 3: Skills installed to .claude/skills/
echo "Test 3: Skills"
[[ -f "$TARGET/.claude/skills/prd/SKILL.md" ]]   && pass "prd skill exists"   || fail "prd skill exists"
[[ -f "$TARGET/.claude/skills/ralph/SKILL.md" ]] && pass "ralph skill exists" || fail "ralph skill exists"

# Test 4: CLAUDE.md updated in project root
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
NON_GIT="$TEST_TMPDIR/not-a-repo"
mkdir -p "$NON_GIT"
if "$RALPH_DIR/ralph.sh" init "$NON_GIT" 2>/dev/null; then
  fail "non-git dir should fail"
else
  pass "non-git dir rejected"
fi

# Test 10: Existing CLAUDE.md is preserved, Ralph section appended
echo "Test 10: Existing CLAUDE.md preserved"
TARGET2="$TEST_TMPDIR/test-project-2"
mkdir -p "$TARGET2"
git -C "$TARGET2" init --quiet
echo "# My Project" > "$TARGET2/CLAUDE.md"
echo "Existing content here." >> "$TARGET2/CLAUDE.md"
"$RALPH_DIR/ralph.sh" init "$TARGET2" --name test-app-2
grep -qF "My Project" "$TARGET2/CLAUDE.md" && pass "existing content preserved" || fail "existing content preserved"
grep -qF "Ralph Agent" "$TARGET2/CLAUDE.md" && pass "ralph section appended" || fail "ralph section appended"

# Test 11: --tool value written to config
echo "Test 11: --tool written to config"
TARGET3="$TEST_TMPDIR/test-project-3"
mkdir -p "$TARGET3"
git -C "$TARGET3" init --quiet
"$RALPH_DIR/ralph.sh" init "$TARGET3" --name test-app-3 --tool amp
grep -qF "tool: amp" "$TARGET3/.ralph/ralph-config.yaml" && pass "--tool amp in config" || fail "--tool amp in config"

echo ""
echo "=== Results: $TESTS_PASSED passed, $TESTS_FAILED failed ==="
[[ "$TESTS_FAILED" -eq 0 ]]
