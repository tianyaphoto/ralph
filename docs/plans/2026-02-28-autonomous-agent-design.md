# Ralph Autonomous AI Programming Agent - Design Document

**Date**: 2026-02-28
**Status**: Approved

## Overview

Extend Ralph from a "PRD executor" into a fully autonomous AI programming agent that can:
- Autonomously analyze competitors and discover feature gaps
- Generate requirements from research findings
- Break down tasks and execute development
- Review, build-verify, and release automatically
- Run as a background daemon on configurable intervals

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Tech stack | Bash (shell scripts) | Consistent with existing Ralph; no new runtime dependencies |
| Architecture | Modular script collection | Clean separation of concerns, independently testable |
| Scheduling | Bash daemon (while+sleep) | Simple, self-contained, no external scheduler needed |
| Target | General-purpose tool | Works with any repo (iOS, Web, Python, Go, etc.) |
| Autonomy | Fully automatic, no human approval | Direct merge to main via PR |
| Research data | Config + web search + GitHub analysis | Multi-source cross-validation |
| Build verification | Pluggable commands from config | User defines build/test/lint per project |
| Reports | Markdown to `reports/YYYY-MM-DD/` | Human-readable, git-friendly |

## Architecture

### Global Flow

```
ralph.sh (orchestrator)

  --auto         Single full cycle
  --daemon       Daemon mode (while true + sleep)
  --interval 30m Cycle interval
  --phase X      Run single phase (for debugging)

  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ research │→│ prd-gen  │→│ develop  │→│  review  │→│ release  │
  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘
       ↓             ↓             ↓             ↓             ↓
   report.sh     report.sh     report.sh     report.sh     report.sh
```

### File Structure

```
ralph/
  ralph.sh                      # Main entry + orchestrator + daemon mode
  lib/
    config.sh                   # Load ralph-config.yaml → env vars
    research.sh                 # Phase 1: Competitor analysis + gap discovery
    prd-gen.sh                  # Phase 2: PRD generation + task breakdown
    develop.sh                  # Phase 3: Development loop (existing core logic)
    review.sh                   # Phase 4: Code review + build verification
    release.sh                  # Phase 5: PR + merge + tag + release
    worktree.sh                 # Git worktree create/cleanup
    report.sh                   # Report generation to reports/YYYY-MM-DD/
    utils.sh                    # Common functions (logging, error handling, lock)
  config/
    ralph-config.yaml.example   # Configuration template
  prompts/
    research.md                 # Claude Code prompt for research phase
    prd-gen.md                  # Claude Code prompt for PRD generation
    review.md                   # Claude Code prompt for code review
  reports/                      # Auto-generated reports directory
```

### Configuration Format (`ralph-config.yaml`)

```yaml
project:
  name: "my-app"
  repo: "."
  description: "A note-taking app"
  build_command: "xcodebuild -scheme MyApp -sdk iphonesimulator"
  test_command: "xcodebuild test -scheme MyApp -sdk iphonesimulator"
  lint_command: "swiftlint"

research:
  competitors:
    - name: "Notion"
      github: "notion-so/notion"
      website: "https://notion.so"
    - name: "Obsidian"
      github: "obsidianmd/obsidian-releases"
  dimensions:
    - "UI/UX"
    - "Performance"
    - "Plugin ecosystem"
  auto_discover: true

schedule:
  interval: "30m"
  max_stories_per_cycle: 3

development:
  tool: "claude"
  max_iterations: 10
  tdd: true
  worktree: true

release:
  auto_pr: true
  auto_merge: true
  auto_tag: true
  auto_release: true
```

## Phase Details

### Phase 1: Research (`lib/research.sh`)

**Input**: `ralph-config.yaml` (competitors + dimensions) + current project code
**Output**: `reports/YYYY-MM-DD/research-report.md` + `gaps.json`

Workflow:
1. Load competitors list and focus dimensions from config
2. Call Claude Code CLI with `prompts/research.md`:
   - Web search each competitor's latest features/updates
   - GitHub analysis (README, Issues, PRs, Stars trends)
   - If `auto_discover=true`, search for additional competitors in the domain
   - Cross-compare with current project code to find feature gaps
3. Claude Code outputs structured results:
   - `research-report.md` (human-readable)
   - `gaps.json` (machine-readable for next phase)
     ```json
     [{"gap": "Missing dark mode", "priority": "high",
       "competitors": ["Notion","Obsidian"], "effort": "medium"}]
     ```
4. Archive to `reports/YYYY-MM-DD/`

### Phase 2: PRD Generation (`lib/prd-gen.sh`)

**Input**: `gaps.json` + current project code + config
**Output**: `prd.json` (compatible with existing format)

Workflow:
1. Read `gaps.json`, sort by priority
2. Select top N gaps based on `max_stories_per_cycle`
3. Call Claude Code CLI with `prompts/prd-gen.md`:
   - Analyze current code architecture
   - Generate user stories for each gap
   - Ensure each story fits single context window
   - Order by dependency (schema -> logic -> UI)
   - Generate automatable verification criteria
4. Output `prd.json` (reuse existing format)
5. Archive `prd-generated.md` to reports

### Phase 3: Develop (`lib/develop.sh`)

**Input**: `prd.json`
**Output**: Code changes + commits

Based on existing `ralph.sh` core logic, enhanced with:
- **Git worktree isolation**: Each story developed in isolated worktree
  ```bash
  git worktree add .worktrees/US-001 -b ralph/US-001
  cd .worktrees/US-001
  # ... develop ...
  git worktree remove .worktrees/US-001
  ```
- **TDD enforcement**: Prompt injects TDD workflow (RED-GREEN-REFACTOR)
- **Story completion**: Worktree commits squashed back to feature branch

### Phase 4: Review (`lib/review.sh`)

**Input**: Completed code from develop phase
**Output**: `review-report.md`

Workflow:
1. Call Claude Code CLI for code review (/simplify, /review)
2. Execute build verification (commands from config):
   - `build_command` (xcodebuild / npm run build / go build)
   - `test_command` (xctest / npm test / go test)
   - `lint_command` (swiftlint / eslint / golangci-lint)
3. If review finds issues -> return to develop phase (max 3 retries)
4. Generate `review-report.md`

### Phase 5: Release (`lib/release.sh`)

**Input**: Reviewed and verified code
**Output**: GitHub PR, merge, tag, release

Workflow:
1. Create PR (`gh pr create`) with change summary + related gaps
2. Wait for CI to pass (`gh pr checks --watch`) if CI exists
3. Auto-merge (`gh pr merge --squash`)
4. Semantic version tag (analyze commits for major/minor/patch)
5. Create GitHub Release (`gh release create`) with auto-generated notes
6. Generate `release-summary.md`

## Error Handling

### Exit Code Convention

```
exit 0  -> Success, continue to next phase
exit 1  -> Recoverable error, log and skip this cycle
exit 2  -> Fatal error, stop daemon
```

### Phase-specific Recovery

| Phase | Failure | Action |
|-------|---------|--------|
| Research | API/website unavailable | Skip cycle, retry next time |
| PRD Gen | Generation fails | Skip cycle |
| Develop | Iteration limit exceeded | Log incomplete stories, continue next cycle |
| Review | Build/test fails | Return to develop, max 3 retries |
| Release | PR/merge fails | Keep code on branch, log for manual intervention |

## State Management

```
.ralph-state/
  lock.pid              # Process lock (prevent concurrent runs)
  last-run.json         # Last run state for resume
  cycle-count           # Cumulative cycle count
```

### Process Lock

Daemon checks `lock.pid` on startup to prevent multiple instances.

### Checkpoint Resume

`last-run.json` records where the last run stopped:
```json
{
  "cycle": 15,
  "phase": "develop",
  "story": "US-003",
  "timestamp": "2026-02-28T10:30:00Z",
  "status": "interrupted"
}
```

## Security Constraints

- **Branch protection**: Never push directly to main; always via PR
- **Change limit**: Single PR max 500 lines changed (configurable)
- **Sensitive file exclusion**: Never modify `.env`, `Secrets/`, CI configs
- **Rollback**: `git stash` before each PR; recoverable on failure

## Logging

```bash
# utils.sh provides unified logging
log_info  "Phase 1: Research started"
log_warn  "Competitor API rate limited, retrying..."
log_error "Build failed: exit code 65"

# Logs written to reports/YYYY-MM-DD/ralph.log
# Also to stdout in non-daemon mode
```

## Non-Goals

- No web UI / dashboard (CLI only)
- No database (all state in git + JSON + text files)
- No API server
- No multi-repo orchestration (one config per repo)
- No Python or other runtime dependencies
