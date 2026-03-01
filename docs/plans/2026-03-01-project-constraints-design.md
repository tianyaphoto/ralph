# Design: Project-Level Constraints via `constraints.md`

**Date:** 2026-03-01
**Status:** Approved

## Problem

Ralph's autonomous pipeline (research -> prd-gen -> develop -> review -> release) has no mechanism for projects to define restrictions like allowed tech stacks, coding conventions, or forbidden patterns. The AI agents can propose and implement anything, which may conflict with project standards.

## Solution

Allow projects to define free-form constraints in a `constraints.md` file at the project root. Ralph reads this file and injects its contents into the PRD-gen and develop prompts via `{{CONSTRAINTS}}` template placeholders.

## Design

### File Convention

- **Path:** `{PROJECT_REPO}/constraints.md`
- **Format:** Free-form markdown
- **Required:** No — Ralph works without it (constraints section shows "No project constraints defined.")

### Enforcement Points

| Phase | Enforced? | How |
|-------|-----------|-----|
| Research | No | Competitor analysis is unconstrained |
| PRD-gen | Yes | `{{CONSTRAINTS}}` in `prompts/prd-gen.md` — stories respect constraints |
| Develop | Yes | `{{CONSTRAINTS}}` in `CLAUDE.md` and `prompt.md` — coding agent follows constraints |
| Review | No | Reviews against code quality, not project constraints |
| Release | No | Mechanical — no AI decisions |

### Changes

#### 1. `constraints.md.example` (new file, project root)

Template showing users how to write constraints.

#### 2. `lib/config.sh` — `load_constraints()`

New function that reads `{CFG_PROJECT_REPO}/constraints.md` and exports `CFG_CONSTRAINTS`. Returns empty string if file doesn't exist.

#### 3. `prompts/prd-gen.md`

Add `{{CONSTRAINTS}}` placeholder with framing text instructing the PRD generator to respect constraints when generating user stories.

#### 4. `CLAUDE.md` and `prompt.md`

Add `{{CONSTRAINTS}}` placeholder with framing text instructing the coding agent to follow constraints during implementation.

#### 5. `lib/prd-gen.sh` — `run_prd_gen()`

Add `CFG_CONSTRAINTS` substitution alongside existing placeholders.

#### 6. `lib/develop.sh` — `run_develop()`

Render constraints into the develop prompt before passing to the AI tool. This requires reading the prompt template and substituting `{{CONSTRAINTS}}` before piping to `invoke_ai`.

### What Doesn't Change

- Research phase and review phase
- `ralph-config.yaml` — no new fields
- Legacy mode — continues as-is
