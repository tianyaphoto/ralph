# Project-Level Constraints Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow projects to define restrictions (tech stacks, coding conventions) in a `constraints.md` file that gets injected into PRD-gen and develop prompts.

**Architecture:** Add a `load_constraints()` function to `lib/config.sh` that reads `{PROJECT_REPO}/constraints.md`. Add `{{CONSTRAINTS}}` placeholders to `prompts/prd-gen.md`, `CLAUDE.md`, and `prompt.md`. Wire substitution into `lib/prd-gen.sh` and `lib/develop.sh`.

**Tech Stack:** Bash, YAML (yq), jq — all existing tools.

---

### Task 1: Add `load_constraints()` to `lib/config.sh`

**Files:**
- Modify: `lib/config.sh:56` (after `unset -f _cfg`, before derived section)

**Step 1: Write the test**

Add a test to `tests/smoke-test.sh` that verifies `load_constraints` is available after sourcing.

In `tests/smoke-test.sh`, after line 141 (`assert "load_config is available" _check_fn load_config`), add:

```bash
assert "load_constraints is available" _check_fn load_constraints
```

**Step 2: Run test to verify it fails**

Run: `bash tests/smoke-test.sh`
Expected: FAIL on "load_constraints is available"

**Step 3: Write the implementation**

In `lib/config.sh`, after the closing `}` of `load_config()` (after line 63), add:

```bash

# ── Constraints loader ──────────────────────────────────────
# Reads {PROJECT_REPO}/constraints.md if it exists and exports
# CFG_CONSTRAINTS with the file contents.  Returns empty string
# if the file does not exist.  Safe to call before or after
# load_config — uses CFG_PROJECT_REPO if set, falls back to ".".
load_constraints() {
  local repo="${CFG_PROJECT_REPO:-.}"
  local constraints_file="$repo/constraints.md"

  if [[ -f "$constraints_file" ]]; then
    export CFG_CONSTRAINTS
    CFG_CONSTRAINTS="$(cat "$constraints_file")"
    log_info "Constraints loaded from: $constraints_file"
  else
    export CFG_CONSTRAINTS=""
    log_info "No constraints file found at: $constraints_file (proceeding without constraints)"
  fi

  return 0
}
```

**Step 4: Run test to verify it passes**

Run: `bash tests/smoke-test.sh`
Expected: PASS on "load_constraints is available"

**Step 5: Commit**

```bash
git add lib/config.sh tests/smoke-test.sh
git commit -m "feat: add load_constraints() to config loader"
```

---

### Task 2: Add `{{CONSTRAINTS}}` to PRD-gen prompt template

**Files:**
- Modify: `prompts/prd-gen.md` (after line 13, the `{{GAPS_JSON}}` block)

**Step 1: Add the constraints section**

In `prompts/prd-gen.md`, after the `## Feature Gaps to Address` section (after line 13 `{{GAPS_JSON}}`), add:

```markdown

## Project Constraints

{{CONSTRAINTS}}

When generating user stories, you MUST respect these constraints. Do not propose stories that violate them (e.g., if the project restricts the tech stack to React, do not generate stories that use Vue).
```

**Step 2: Verify prompt template is still readable**

Run: `cat prompts/prd-gen.md | head -25`
Expected: Shows the new constraints section between gaps and "Your Task"

**Step 3: Commit**

```bash
git add prompts/prd-gen.md
git commit -m "feat: add {{CONSTRAINTS}} placeholder to PRD-gen prompt"
```

---

### Task 3: Add `{{CONSTRAINTS}}` to develop prompts (`CLAUDE.md` and `prompt.md`)

**Files:**
- Modify: `CLAUDE.md` (after "Quality Requirements" section, before "Browser Testing")
- Modify: `prompt.md` (after "Quality Requirements" section, before "Browser Testing")

**Step 1: Add constraints section to CLAUDE.md**

In `CLAUDE.md`, after line 79 (`- Follow existing code patterns`), add:

```markdown

## Project Constraints

{{CONSTRAINTS}}

You MUST follow these constraints when implementing stories. If a constraint conflicts with a story's requirements, prioritize the constraint and note the conflict in your progress report.
```

**Step 2: Add constraints section to prompt.md**

In `prompt.md`, after line 81 (`- Follow existing code patterns`), add the same block:

```markdown

## Project Constraints

{{CONSTRAINTS}}

You MUST follow these constraints when implementing stories. If a constraint conflicts with a story's requirements, prioritize the constraint and note the conflict in your progress report.
```

**Step 3: Verify both files have the placeholder**

Run: `grep -n 'CONSTRAINTS' CLAUDE.md prompt.md`
Expected: Both files show the `{{CONSTRAINTS}}` line

**Step 4: Commit**

```bash
git add CLAUDE.md prompt.md
git commit -m "feat: add {{CONSTRAINTS}} placeholder to develop prompts"
```

---

### Task 4: Wire constraints substitution into `lib/prd-gen.sh`

**Files:**
- Modify: `lib/prd-gen.sh:65-72` (the placeholder substitution block in `run_prd_gen()`)

**Step 1: Add constraints loading and substitution**

In `lib/prd-gen.sh`, after line 72 (`prompt="${prompt//\{\{TODAY\}\}/${today}}"`), add:

```bash

  # Load constraints if available
  load_constraints
  prompt="${prompt//\{\{CONSTRAINTS\}\}/${CFG_CONSTRAINTS:-No project constraints defined.}}"
```

**Step 2: Run smoke tests to verify nothing broke**

Run: `bash tests/smoke-test.sh`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add lib/prd-gen.sh
git commit -m "feat: wire constraints substitution into PRD-gen phase"
```

---

### Task 5: Wire constraints substitution into `lib/develop.sh`

**Files:**
- Modify: `lib/develop.sh:67-94` (the prompt file and iteration block in `run_develop()`)

**Step 1: Add constraints rendering**

In `lib/develop.sh`, after line 73 (`fi` that closes the prompt_file selection), add:

```bash

  # ── Load and render constraints into prompt ────────────────
  load_constraints
  local rendered_prompt
  rendered_prompt="$(cat "$prompt_file")"
  rendered_prompt="${rendered_prompt//\{\{CONSTRAINTS\}\}/${CFG_CONSTRAINTS:-No project constraints defined.}}"
```

Then change line 94 from:

```bash
    output="$(invoke_ai < "$prompt_file" 2>&1 | tee /dev/stderr)" || true
```

to:

```bash
    output="$(printf '%s\n' "$rendered_prompt" | invoke_ai 2>&1 | tee /dev/stderr)" || true
```

**Step 2: Run smoke tests to verify nothing broke**

Run: `bash tests/smoke-test.sh`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add lib/develop.sh
git commit -m "feat: wire constraints substitution into develop phase"
```

---

### Task 6: Create `constraints.md.example`

**Files:**
- Create: `constraints.md.example` (project root)

**Step 1: Create the example file**

```markdown
# Project Constraints

These constraints are injected into Ralph's PRD generation and development prompts.
The AI agent will respect these rules when proposing and implementing features.

## Tech Stack

- Frontend: React 18 + Tailwind CSS
- Backend: Node.js with Express
- Database: PostgreSQL
- Language: TypeScript (strict mode)

## Coding Rules

- Use functional components only, no class components
- No ORMs — use raw SQL with parameterized queries
- All API routes must validate input with zod schemas
- Use server actions for mutations, not API routes

## Forbidden

- Do not introduce new dependencies without justification
- Do not use jQuery, Lodash, or Moment.js
- Do not write CSS-in-JS — use Tailwind utility classes only
```

**Step 2: Verify the file exists**

Run: `ls -la constraints.md.example`
Expected: File exists

**Step 3: Commit**

```bash
git add constraints.md.example
git commit -m "docs: add constraints.md.example template"
```

---

### Task 7: Add smoke test for constraints loading

**Files:**
- Modify: `tests/smoke-test.sh` (add a new test section after section 5)

**Step 1: Add constraints test section**

In `tests/smoke-test.sh`, after the config validation section (after line 196), add:

```bash
# ── 5b. Constraints loading ──────────────────────────────────
echo "5b. Constraints loading"
echo "---"

# Test: load_constraints with no file returns empty CFG_CONSTRAINTS
result_no_constraints="$(bash -c "
  export RALPH_DIR='$RALPH_DIR'
  source '$RALPH_DIR/lib/utils.sh'
  source '$RALPH_DIR/lib/config.sh'
  export CFG_PROJECT_REPO='/tmp/ralph-test-no-constraints'
  mkdir -p /tmp/ralph-test-no-constraints
  load_constraints
  echo \"\$CFG_CONSTRAINTS\"
" 2>/dev/null)"
assert_eq "load_constraints with no file returns empty" "" "$result_no_constraints"

# Test: load_constraints with file returns contents
_test_constraints_dir="$(mktemp -d)"
echo "# Test Constraints" > "$_test_constraints_dir/constraints.md"
result_with_constraints="$(bash -c "
  export RALPH_DIR='$RALPH_DIR'
  source '$RALPH_DIR/lib/utils.sh'
  source '$RALPH_DIR/lib/config.sh'
  export CFG_PROJECT_REPO='$_test_constraints_dir'
  load_constraints
  echo \"\$CFG_CONSTRAINTS\"
" 2>/dev/null)"
assert_eq "load_constraints with file returns contents" "# Test Constraints" "$result_with_constraints"
rm -rf "$_test_constraints_dir"

echo ""
```

**Step 2: Run the tests**

Run: `bash tests/smoke-test.sh`
Expected: All tests PASS including the new constraints tests

**Step 3: Commit**

```bash
git add tests/smoke-test.sh
git commit -m "test: add smoke tests for constraints loading"
```

---

### Task 8: Call `load_constraints` from `load_config`

**Files:**
- Modify: `lib/config.sh` (inside `load_config()`, after the derived section)

**Step 1: Add `load_constraints` call at end of `load_config`**

In `lib/config.sh`, after line 59 (`export RALPH_TOOL="$CFG_DEV_TOOL"`), before the log_info line, add:

```bash

  # ── Load project constraints ────────────────────────────────
  load_constraints
```

This ensures constraints are loaded automatically whenever config is loaded (non-legacy modes), so `run_prd_gen` and `run_develop` don't each need to call it independently.

**Step 2: Remove redundant `load_constraints` calls from Task 4 and Task 5**

In `lib/prd-gen.sh`, remove the `load_constraints` line added in Task 4 (keep only the substitution).

In `lib/develop.sh`, remove the `load_constraints` line added in Task 5 (keep only the rendering).

**Step 3: Run smoke tests**

Run: `bash tests/smoke-test.sh`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add lib/config.sh lib/prd-gen.sh lib/develop.sh
git commit -m "refactor: call load_constraints from load_config for single load point"
```

---

### Task 9: Update README with constraints documentation

**Files:**
- Modify: `README.md` (add constraints section)

**Step 1: Add constraints docs to README**

Find the configuration section in `README.md` and add a subsection about `constraints.md`. Include:
- What it does
- Where to put it
- Example content
- Reference to `constraints.md.example`

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add constraints.md documentation to README"
```

---

### Task 10: Final verification

**Step 1: Run full smoke test suite**

Run: `bash tests/smoke-test.sh`
Expected: All tests PASS, 0 failures

**Step 2: Verify all placeholders are wired**

Run: `grep -rn 'CONSTRAINTS' lib/ prompts/ CLAUDE.md prompt.md`
Expected: Shows placeholder in templates AND substitution in lib files

**Step 3: Verify no broken placeholder remains**

Run: `grep -rn '{{CONSTRAINTS}}' lib/`
Expected: Only substitution lines (no un-rendered placeholders in lib code)

**Step 4: Review git log**

Run: `git log --oneline`
Expected: Clean commit history with feat/test/docs prefixes
