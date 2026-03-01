# Research Phase — Competitive Analysis & Gap Discovery

You are performing competitive research for **{{PROJECT_NAME}}**.

## Project Context

**Description:** {{PROJECT_DESC}}

## User Requirements (TOP PRIORITY)

The following requirements were specified by the project owner. These are
**highest priority** and MUST appear first in `gaps.json`.

{{REQUIREMENTS}}

### Handling User Requirements in Output

- Every user requirement MUST appear in `gaps.json` — never omit one.
- User requirements always rank **above** research-discovered gaps in the output ordering.
- If a user requirement overlaps with a competitive research finding, **merge** them
  into one entry with `"source": "user+research"` and combine the rationale.
- User-only items (no competitive overlap) get `"source": "user"`.
- Research-only items get `"source": "research"`.
- User requirement priority values are preserved as-is (never downgraded by research).

## Objectives

1. Analyze each competitor listed below across the specified dimensions.
2. If auto-discovery is enabled, search the web for **up to 3 additional competitors** that are not listed below but are relevant to this project. Include them in your analysis.
3. Cross-compare competitor capabilities against the current project codebase.
4. Identify gaps where competitors offer functionality that {{PROJECT_NAME}} lacks or could improve.

## Known Competitors

{{COMPETITORS}}

## Analysis Dimensions

Evaluate each competitor along these dimensions:

{{DIMENSIONS}}

For each dimension, provide a brief assessment (2-3 sentences) per competitor.

## Auto-Discovery

**Enabled:** {{AUTO_DISCOVER}}

If enabled (`true`):
- Use web search to find additional competitors in the same space as {{PROJECT_NAME}}.
- Limit discovery to **3 additional competitors** maximum.
- Include discovered competitors in the same analysis as the known ones.
- Clearly mark discovered competitors as "[Discovered]" in the report.

## Research Methods

For each competitor:
1. **Web Search** — Search for the competitor's website, documentation, blog posts, and recent announcements.
2. **GitHub Analysis** — If a GitHub URL is provided, analyze the repository for: stars, recent activity, release cadence, key features, architecture patterns, and documentation quality.
3. **Feature Comparison** — Compare capabilities against {{PROJECT_NAME}} to identify gaps.

## Required Output

You MUST produce exactly TWO files in the current working directory:

### 1. `research-report.md`

A human-readable markdown report with the following structure:

```
# Competitive Research Report — {{PROJECT_NAME}}

## Executive Summary
(3-5 sentence overview of findings)

## Competitor Profiles
### [Competitor Name]
- **Website:** ...
- **GitHub:** ...
- **Summary:** ...
(Repeat for each competitor, including discovered ones)

## Dimension Analysis
### [Dimension Name]
| Competitor | Assessment | Rating |
|------------|------------|--------|
| ...        | ...        | ...    |
(Repeat for each dimension)

## Gap Analysis
| Gap | Source | Priority | Competitors With Feature | Effort | Rationale |
|-----|--------|----------|--------------------------|--------|-----------|
| ... | ...    | ...      | ...                      | ...    | ...       |

## Recommendations
(Prioritised list of actionable next steps)
```

### 2. `gaps.json`

A machine-readable JSON file containing an array of gap objects:

```json
[
  {
    "gap": "Short description of the missing capability",
    "priority": "high",
    "source": "user",
    "competitors": ["competitor-one", "competitor-two"],
    "effort": "medium",
    "rationale": "Why this gap matters and how competitors address it"
  }
]
```

Field definitions:
- **gap** (string): Concise name of the missing feature or capability.
- **priority** (string): One of `"high"`, `"medium"`, or `"low"`.
- **competitors** (array of strings): Names of competitors that have this capability.
- **effort** (string): Estimated implementation effort — one of `"small"`, `"medium"`, or `"large"`.
- **rationale** (string): Explanation of why this gap is important and how competitors solve it.
- **source** (string): One of `"user"`, `"research"`, or `"user+research"`. Indicates whether the gap came from user requirements, competitive research, or both.

## Important

- Write BOTH files to the current working directory.
- `gaps.json` MUST be a valid JSON array (parse-check it before writing).
- Be thorough but concise — focus on actionable insights.
- Do NOT fabricate data. If information is unavailable, say so explicitly.
