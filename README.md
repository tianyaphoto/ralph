# Ralph

![Ralph](ralph.webp)

Ralph is an autonomous AI programming agent that runs AI coding tools ([Claude Code](https://docs.anthropic.com/en/docs/claude-code) or [Amp](https://ampcode.com)) to autonomously research competitors, discover feature gaps, generate requirements, implement code, review, and release — all without human intervention.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Features

- **Autonomous Pipeline** — 5-phase cycle: Research → PRD Generation → Development → Review → Release
- **Competitive Analysis** — Discovers feature gaps by analyzing competitors (GitHub repos, websites)
- **Auto PRD Generation** — Converts research findings into structured user stories
- **TDD Development** — Implements stories with test-driven development in isolated git worktrees
- **Build Verification** — Pluggable build/test/lint commands with AI-assisted auto-fix (up to 3 retries)
- **Auto Release** — Creates PRs, waits for CI, merges, tags, and creates GitHub Releases
- **Daemon Mode** — Runs continuously on a configurable interval
- **Multi-tool Support** — Works with Claude Code or Amp CLI
- **Legacy Mode** — Backwards-compatible with the original PRD-executor workflow

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`) or [Amp CLI](https://ampcode.com)
- `jq` (`brew install jq` on macOS)
- `yq` (`brew install yq` on macOS) — required for autonomous mode
- `gh` ([GitHub CLI](https://cli.github.com/)) — required for release automation
- A git repository for your project

## Quick Start

### Option A: Install as Subdirectory (Recommended)

Install Ralph into an existing project as `.ralph/`:

```bash
# From a cloned copy of Ralph (or wherever ralph.sh lives)
./ralph.sh --init /path/to/my-project

# Or from the target project directory
/path/to/ralph/ralph.sh --init .
```

This creates:

```
my-project/
  .ralph/                # Ralph internals (ralph.sh, lib/, prompts/, config/)
  CLAUDE.md              # AI agent instructions (project root)
  prd.json               # Generated at project root (git-ignored)
  progress.txt           # Generated at project root (git-ignored)
```

Then edit `.ralph/ralph-config.yaml` and run:

```bash
.ralph/ralph.sh --auto
```

### Option B: Standalone Clone

Clone Ralph as its own project:

```bash
git clone https://github.com/snarktank/ralph.git
cd ralph
```

### Create your config

```bash
cp config/ralph-config.yaml.example ralph-config.yaml
```

Edit `ralph-config.yaml` for your project:

```yaml
project:
  name: my-app
  description: "A note-taking app"
  repo: "/path/to/my-app"
  build_command: "npm run build"
  test_command: "npm test"
  lint_command: "npm run lint"

research:
  competitors:
    - name: Notion
      github: "https://github.com/notion-so/notion"
      website: "https://notion.so"
    - name: Obsidian
      github: "https://github.com/obsidianmd/obsidian-releases"
  dimensions:
    - UI/UX
    - Performance
    - Plugin ecosystem
  auto_discover: true

schedule:
  interval: "30m"
  max_stories_per_cycle: 3

development:
  tool: claude       # claude | amp
  max_iterations: 10
  tdd: true

release:
  auto_pr: true
  auto_merge: false  # set to true for fully autonomous merging
  auto_tag: false
  auto_release: false
```

### 3. Run a single autonomous cycle

```bash
./ralph.sh --auto
```

### 4. Or run as a background daemon

```bash
./ralph.sh --daemon --interval 1h
```

## Usage

```
./ralph.sh [options]

Modes:
  --auto              Single full cycle (research -> develop -> review -> release)
  --daemon            Continuous mode (runs cycles on an interval)
  --legacy            Original dev-only loop (backwards compat)
  --phase PHASE       Run a single phase (research|prd-gen|develop|review|release)
  --init [DIR]        Install Ralph as .ralph/ subdirectory in DIR (default: current dir)

Options:
  --tool amp|claude   Override AI tool (default: from config)
  --interval 30m      Override daemon interval (supports: 30m, 1h, 2h30m)
  --max-iterations N  Override max development iterations
  --config FILE       Override config file path
  -h|--help           Show usage
```

### Autonomous Mode (`--auto`)

Runs the full 5-phase pipeline once:

```
Research → PRD Generation → Development → Review → Release
```

Each phase generates a report to `reports/YYYY-MM-DD/`.

### Daemon Mode (`--daemon`)

Runs autonomous cycles continuously:

```bash
# Run every 30 minutes (default)
./ralph.sh --daemon

# Run every 2 hours
./ralph.sh --daemon --interval 2h

# Run with Amp instead of Claude
./ralph.sh --daemon --tool amp
```

The daemon acquires a process lock (`.ralph-state/lock.d/`) to prevent concurrent runs.

### Single Phase (`--phase`)

Run one phase at a time for debugging or manual control:

```bash
./ralph.sh --phase research    # Just run competitive analysis
./ralph.sh --phase prd-gen     # Just generate PRD from existing gaps.json
./ralph.sh --phase develop     # Just run the development loop
./ralph.sh --phase review      # Just run build/test/lint + code review
./ralph.sh --phase release     # Just create PR/merge/tag/release
```

### Legacy Mode (`--legacy`)

Preserves the original Ralph behavior — a simple iteration loop that picks up stories from an existing `prd.json`:

```bash
# Using Amp (default in legacy mode)
./ralph.sh --legacy 10

# Using Claude Code
./ralph.sh --legacy --tool claude 10
```

## The 5-Phase Pipeline

### Phase 1: Research

Analyzes competitors and discovers feature gaps:
- Web searches for competitor features and updates
- GitHub analysis (README, issues, PRs, star trends)
- Auto-discovers additional competitors if enabled
- Cross-compares with your project code
- Outputs: `reports/YYYY-MM-DD/research-report.md` + `gaps.json`

### Phase 2: PRD Generation

Converts research gaps into actionable user stories:
- Reads `gaps.json`, sorts by priority
- Selects top N gaps (configurable via `max_stories_per_cycle`)
- Generates `prd.json` compatible with the existing Ralph format
- Archives any existing `prd.json` before overwriting

### Phase 3: Development

Implements user stories using the AI coding tool:
- Creates a feature branch from `prd.json` `branchName`
- Iterates through stories in priority order
- Each iteration spawns a fresh AI instance with clean context
- Stops when all stories pass or max iterations reached

### Phase 4: Review

Verifies code quality with build/test/lint + AI code review:
- Runs configured `build_command`, `test_command`, `lint_command`
- If checks fail, asks AI to diagnose and fix (up to 3 retries)
- Runs AI code review via `prompts/review.md`
- Outputs: `reports/YYYY-MM-DD/review-report.md`

### Phase 5: Release

Automates the release workflow (each step gated by config):
- Pushes branch to origin
- Creates a Pull Request (`auto_pr`)
- Waits for CI checks to pass
- Squash-merges the PR (`auto_merge`)
- Creates a semantic version tag (`auto_tag`)
- Creates a GitHub Release with auto-generated notes (`auto_release`)
- Outputs: `reports/YYYY-MM-DD/release-summary.md`

## Project Structure

### Standalone layout

```
ralph/
  ralph.sh                      # Main orchestrator + CLI
  lib/
    utils.sh                    # Logging, lock, state, AI tool invocation
    config.sh                   # YAML config loader (ralph-config.yaml → env vars)
    research.sh                 # Phase 1: Competitive analysis + gap discovery
    prd-gen.sh                  # Phase 2: PRD generation from gaps
    develop.sh                  # Phase 3: Development iteration loop
    review.sh                   # Phase 4: Build/test/lint + AI code review
    release.sh                  # Phase 5: PR + merge + tag + release
    worktree.sh                 # Git worktree create/remove/squash-merge
    report.sh                   # Report generation utilities
  config/
    ralph-config.yaml.example   # Configuration template
  prompts/
    research.md                 # Prompt template for research phase
    prd-gen.md                  # Prompt template for PRD generation
    review.md                   # Prompt template for code review
  tests/
    smoke-test.sh               # Smoke tests (syntax, loading, functions, CLI)
  reports/                      # Auto-generated reports (git-ignored)
  skills/                       # PRD and Ralph skills for Amp/Claude
  CLAUDE.md                     # Agent instructions for development phase
  prompt.md                     # Amp prompt template
```

### Subdirectory layout (after `--init`)

```
my-project/                     # $PROJECT_ROOT
  .ralph/                       # $RALPH_DIR
    ralph.sh                    # Main orchestrator + CLI
    ralph-config.yaml           # Project config (repo: "..")
    lib/                        # All library modules
    prompts/                    # Prompt templates
    config/                     # Config example
    .ralph-state/               # Internal state (git-ignored)
    reports/                    # Auto-generated reports (git-ignored)
  CLAUDE.md                     # AI agent instructions (project root)
  prd.json                      # Generated at project root
  progress.txt                  # Generated at project root
```

## Configuration Reference

| Section | Key | Default | Description |
|---------|-----|---------|-------------|
| `project` | `name` | `my-app` | Project name used in reports |
| | `repo` | `.` | Path to the project repository |
| | `description` | `""` | Project description for AI context |
| | `build_command` | `""` | Build command (e.g. `npm run build`, `go build ./...`) |
| | `test_command` | `""` | Test command (e.g. `npm test`, `pytest`) |
| | `lint_command` | `""` | Lint command (e.g. `eslint .`, `golangci-lint run`) |
| `research` | `competitors` | `[]` | List of competitors with `name`, `github`, `website` |
| | `dimensions` | `[]` | Analysis dimensions (e.g. `performance`, `UX`) |
| | `auto_discover` | `true` | Auto-discover additional competitors |
| `schedule` | `interval` | `30m` | Daemon cycle interval (`30m`, `1h`, `2h30m`) |
| | `max_stories_per_cycle` | `3` | Max stories to generate per cycle |
| `development` | `tool` | `claude` | AI tool: `claude` or `amp` |
| | `max_iterations` | `10` | Max dev iterations per cycle |
| | `tdd` | `true` | Enforce TDD in prompts |
| `release` | `auto_pr` | `true` | Auto-create Pull Requests |
| | `auto_merge` | `false` | Auto-squash-merge PRs |
| | `auto_tag` | `false` | Auto-create semantic version tags |
| | `auto_release` | `false` | Auto-create GitHub Releases |

## Project Constraints

You can optionally create a `constraints.md` file in your project root (alongside `ralph-config.yaml`) to define project-level restrictions. Ralph injects these constraints into both PRD generation and development prompts, so the AI agent respects your tech stack, coding conventions, and forbidden patterns.

Copy the example to get started:

```bash
cp constraints.md.example constraints.md
```

Then edit it to match your project. A typical `constraints.md` looks like:

```markdown
## Tech Stack
- Frontend: React 18 + Tailwind CSS
- Backend: Node.js with Express
- Language: TypeScript (strict mode)

## Coding Rules
- Use functional components only, no class components
- All API routes must validate input with zod schemas

## Forbidden
- Do not introduce jQuery, Lodash, or Moment.js
- Do not write CSS-in-JS — use Tailwind utility classes only
```

This file is entirely optional — Ralph works fine without it. When present, constraints are automatically picked up by the PRD generation and development phases.

## Skills (PRD Workflow)

Ralph includes skills for generating PRDs interactively — useful when you want to manually define what to build rather than relying on autonomous research.

### Install skills

**Claude Code Marketplace:**
```bash
/plugin marketplace add snarktank/ralph
/plugin install ralph-skills@ralph-marketplace
```

**Manual (Amp):**
```bash
cp -r skills/prd ~/.config/amp/skills/
cp -r skills/ralph ~/.config/amp/skills/
```

**Manual (Claude Code):**
```bash
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

### Use skills

- `/prd` — Generate a Product Requirements Document interactively
- `/ralph` — Convert a markdown PRD to `prd.json` format

Then run the development loop:
```bash
./ralph.sh --legacy --tool claude
```

## Reports

Each phase generates reports to `reports/YYYY-MM-DD/`:

| File | Phase | Content |
|------|-------|---------|
| `research-report.md` | Research | Competitor analysis findings |
| `gaps.json` | Research | Machine-readable feature gaps |
| `prd-generated.md` | PRD Gen | Generated stories summary |
| `dev-progress.md` | Develop | Stories completed, iterations used |
| `review-report.md` | Review | AI code review findings |
| `release-summary.md` | Release | PR/CI/merge/tag/release status |
| `ralph.log` | All | Unified log for the entire run |

## State Management

Ralph tracks state in `.ralph-state/`:

| File | Purpose |
|------|---------|
| `lock.d/` | Process lock (prevents concurrent runs) |
| `last-run.json` | Last run checkpoint (cycle, phase, status) |
| `cycle-count` | Cumulative cycle counter |
| `gaps.json` | Latest research gaps (bridge between phases) |

## Error Handling

| Exit Code | Meaning | Behavior |
|-----------|---------|----------|
| `0` | Success | Continue to next phase |
| `1` | Recoverable error | Log and skip remaining phases in this cycle |
| `2` | Fatal error | Stop the daemon |

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `progress.txt` (learnings and context)
- `prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"

### Feedback Loops

Ralph only works if there are feedback loops:
- Build command catches compilation errors
- Tests verify behavior
- Lint catches style issues
- CI must stay green (broken code compounds across iterations)

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Testing

```bash
bash tests/smoke-test.sh
```

Runs 36 checks: syntax validation, module loading, function availability, utility tests, config validation, and CLI tests.

## Debugging

```bash
# See which stories are done
jq '.userStories[] | {id, title, passes}' prd.json

# See learnings from previous iterations
cat progress.txt

# Check latest reports
ls reports/$(date +%Y-%m-%d)/

# Check daemon state
cat .ralph-state/last-run.json

# View unified log
tail -f reports/$(date +%Y-%m-%d)/ralph.log
```

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** — see each step with animations.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
