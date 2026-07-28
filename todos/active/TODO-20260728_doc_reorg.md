# Documentation reorganization - pwiz-ai corpus cleanup

## Branch Information
- **Branch**: `master` (pwiz-ai - commits directly, no feature branch)
- **Base**: `master`
- **Created**: 2026-07-28
- **Status**: In Progress
- **PR**: (none - pwiz-ai commits directly to master)

## Objective

Bring the pwiz-ai documentation corpus back into compliance with
`ai/docs/documentation-maintenance.md`, whose governing rule is that skills and
commands are thin pointers into `ai/docs`, and whose test is: a non-Claude-Code
LLM handed the `ai/docs` file alone must be able to perform the task.

Audit run 2026-07-28 by a 13-agent review (6 parallel reviewers -> 6 adversarial
verifiers -> synthesis). 83 findings survived verification (53 CONFIRMED,
30 ADJUSTED, 0 rejected). Full analysis below.

## Baseline at audit time

| Layer | Measure | Status |
|---|---|---|
| Core five `ai/*.md` | 1,056 lines vs <1000 | 2 of 5 within per-file limit |
| Skills (15) | 74,378 chars | 4 OK, 6 REVIEW, 5 REFACTOR |
| Commands (41) | 167,651 chars | 18 OK, 12 REVIEW, 11 REFACTOR |
| Skills + commands | 242,029 chars | 22/56 (39%) in the "Good" <2,000 band |

Regression vs. the last reorg (`todos/completed/2025/11/TODO-20251105_reorg_md_docs.md`,
PR #3666, 2025-11-05): core files 707 -> 1,056 lines (+49%) in ~9 months.

## Tasks

### P0 - actively wrong instructions (no owner decision needed)
- [x] WI-1 - contradictory/destructive instructions (DONE 2026-07-28; 2 of 3 real,
      the third was a false positive - see Progress Log)
- [x] WI-2 - fix the measuring stick (DONE 2026-07-28)
- [x] WI-3 - add the 5 missing content verifiers to `audit-docs.ps1` (DONE 2026-07-28)
- [x] WI-4 - repo-wide `&` call-operator sweep (DONE 2026-07-28; 47 -> 0)
- [ ] WI-5 - relative-link normalization

### P1 - knowledge existing ONLY in ai/claude (fails the owner's test)
- [ ] WI-6 - create `docs/pr-report-guide.md`
- [ ] WI-7 - create `docs/code-review-guide.md`
- [ ] WI-8 - rehome orphan knowledge from skills/commands

### P2 - duplication that is actively drifting
- [ ] WI-9 - `workflow-guide.md` as single source for workflows/TODO lifecycle
- [ ] WI-10 - `version-control-guide.md` as single source for commits/PRs/labels
- [ ] WI-11 - slim `version-control/SKILL.md` + re-scope injection hook (ONE commit)
- [ ] WI-12 - daily-report pipeline: 3 copies -> 1 guide + 2 thin phases
- [ ] WI-13 - slim the PR-report commands
- [ ] WI-14 - slim the review commands
- [ ] WI-15 - slim remaining REFACTOR/REVIEW skills
- [ ] WI-16 - core five back under hard limits

### P3 - reachability and index accuracy
- [ ] WI-17 - make existing `ai/docs` content reachable
- [ ] WI-18 - MCP docs: remove deleted-tool instructions
- [ ] WI-19 - MCP docs: consolidate duplication, fix reference accuracy

### P4
- [ ] WI-20 - stale-fact sweep

## Owner decisions (2026-07-28)

Answers to §5 of the audit plan. Recorded here so later sessions do not re-ask.

1. **New docs vs. reuse** -> **create all four**: `docs/pr-report-guide.md`,
   `docs/code-review-guide.md`, `docs/autonomous-session-guide.md`,
   `docs/mcp/computers.md`. The version-control reuse precedent held because genuine
   homes already existed; these have none.
3. **night-session** -> **split doctrine from mechanism.** Investigative posture and
   evidence bar move to `docs/autonomous-session-guide.md` (passes the
   non-Claude-Code test); context budget, MCP calls and task chips stay in the skill.
   NOT an exemption.
4. **`ai/` root policy** -> **limit CLAUDE.md (<250); exempt TOC.md (generated),
   root-CLAUDE.md (mirror), README.md (navigation).** Root is a closed set of nine.
   CLAUDE.md is the one platform file that is hand-maintained prose, so it alone
   carries a limit. It is NOT part of the core-five <1000 budget.
5. **C# member ordering** -> the **"interface" variant** (`docs/style-guide.md:35`)
   is canonical: item 2 is "static public **interface** methods", item 5 is
   "public **interface (instance)** methods and properties". WI-16 collapses the
   five copies to this wording.

10. **`scheduled-tasks-guide.md`'s 13 `-Command "&"` occurrences** -> **RESOLVED by
    inspection, no exemption needed.** The guide contains no
    `New-ScheduledTaskAction` / `Register-ScheduledTask` / `-Argument` / `schtasks`
    at all; all 13 are plain CLI invocations a developer would type. The real
    Task Scheduler action is built in `scripts/Invoke-DailyReport.ps1:170`, and it
    already uses `-Execute "pwsh" -Argument "... -File `"$ScriptPath`" ..."`. So the
    WI-4 sweep converts all 13 to `-File` with no whitelist.

Still open: decisions 2, 6, 7, 8, 9, 11, 12.

## Content-check baseline (2026-07-28, after WI-3)

`pwsh -File ./ai/scripts/audit-docs.ps1 -Section checks` - 301 files, **84 violations**.
This is the WI-4/WI-5 work list; re-run to measure progress.

| Check | At WI-3 | Now | Work item |
|---|---:|---:|---|
| call-operator (`-Command "&"` → `-File`) | 47 | **0** | WI-4 DONE |
| broken-link | 22 | 22 | WI-5 |
| dangling-command (`/pw-*` with no file) | 9 | 9 | WI-5 |
| docs-to-skill | 3 | 3 | WI-17 |
| banned-phrase | 3 | 3 | WI-20 |
| **Total** | **84** | **37** | |

## Progress Log

### 2026-07-28 - Audit complete; P0 WI-1 applied

Ran the 13-agent audit. Separately fixed `scripts/audit-docs.ps1` first so the
corpus could be measured at all: it previously checked only Claude Code platform
limits (20k/30k chars) and never the project's own limits, which is why 16
REFACTOR-tier files and 3 over-limit core files went unreported for ~9 months.
It now reports platform and project tiers separately, checks core-file line
limits, counts lines the way `wc -l` does (was over by one per file), and exits
non-zero on hard breaches only.

Applied WI-1, three actively-wrong instructions:

1. `claude/commands/pw-complete.md:46` ordered STOP on an `OPEN` PR, contradicting
   its own frontmatter, its "recurring mistake" warning, its state table 27 lines
   later, and the 150 lines of Step 1b that exist solely to handle OPEN.
2. `docs/project-context.md` said "Remove TODO file before merging to master" -
   destructive. TODOs move to `todos/completed/`; the squash commit references the
   TODO path, and the TODO is the durable engineering record.
3. `claude/commands/pw-daily-review.md` hardcoded `--label bug --label skyline`.
   **This one was a FALSE POSITIVE - the audit finding was wrong, and so was the
   first fix.** The daily report is a *Skyline* report, not a ProteoWizard-wide one:
   its three sources (`get_daily_test_summary`, `save_exceptions_report`,
   `get_support_summary`) are all skyline.ms - Skyline nightly tests, Skyline user
   exception reports, the Skyline support board. `skyline` is therefore the correct
   default for effectively everything it surfaces. Confirming evidence: before the
   2026-07-28 edit, the string "osprey" appeared nowhere in the daily pipeline.
   The default was restored, with a note explaining *why* it is right and when to
   override, which the original bare "always include both by default" lacked.

   **Implication for this audit's reliability:** the adversarial pass rejected 0 of
   83 findings, and this is at least one it should have rejected. The reviewer
   spotted a hardcoded label and inferred a defect without checking what feeds the
   pipeline. Treat remaining findings as needing domain confirmation before acting -
   especially any that claim a default or convention is "wrong" without evidence
   about the workflow's actual scope.

Full audit plan retained below (was written to `ai/.tmp/`, which is gitignored).

### 2026-07-28 - WI-4 applied (call-operator sweep)

47 -> 0 across 15 files. `pwsh -Command "& '<path>' <args>"` -> `pwsh -File '<path>' <args>`.
Safe as a single regex because the inner content is single-quoted throughout, so the
closing double quote is unambiguous: `-Command "&[[:space:]]*\([^"]*\)"` -> `-File \1`.

Edge cases verified by hand after the sweep: trailing comments preserved
(`scripts/README.md:80` keeps `# Fix line endings`), Windows paths with backslashes
(`build-and-test-guide.md:49`, `-SourceRoot 'C:\other\location\pwiz'`), and the
no-leading-`./` variant (`release-guide.md:645`). Both modified `.ps1` files re-parsed
clean via `[Parser]::ParseFile`; the only `.ps1` hits were in comment-based help, so no
behavior changed.

`claude/commands/pw-auditdocs.md` was added to `$RuleDefiningFiles` rather than swept -
it documents these checks and necessarily shows the WRONG form, exactly like
`ai/CLAUDE.md`.

Content violations now 84 -> 37.

### 2026-07-28 - WI-3 applied (content verifiers)

Added `-Section checks` to `audit-docs.ps1` with the five verifiers. Content
violations are fatal (exit 1) - unlike REFACTOR/REVIEW, they are correctness bugs,
not size debt.

**Writing the checks was mostly writing the exemptions.** Naive versions reported
128 violations; 44 of those were the checker's fault, and each false-positive class
had to be understood before the number meant anything:

- **The junction.** `ai/claude/` is surfaced as `<repoRoot>/.claude/` and command
  authors write links relative to THAT path, so `../../ai/docs/x.md` from
  `.claude/commands/` is correct for the primary consumer but resolves to
  `ai/ai/docs/x.md` physically. **19 false positives.** Links now resolve
  lexically against three views (own dir, repo root, junction) and fail only if
  none work.
- **Repo-root-relative paths** like `[Wiki MCP](ai/docs/mcp/wiki.md)` from
  `claude/commands/` are the project's documented convention, not errors.
- **Template placeholders** - `**Issue**: [#NNN](url)` in `pw-handoff.md` is a
  fill-in-the-blank form, not a broken link.
- **Self-reference.** `audit-docs.ps1` flagged ITSELF, because `$BannedPhrases`
  spells the phrases out. The whitelist existed for exactly this and I had not
  applied it to my own file. Same for `documentation-maintenance.md`.
- **Frozen records.** `todos/` and `docs/archive/` excluded - an archived doc is
  kept *because* it is superseded, so its stale links are the record working as
  intended. 16 violations, all of which would have made the check cry wolf forever.

The surviving 84 are the WI-4/WI-5 work list (table above). Spot-checked several
against the files by hand; e.g. `docs/mcp/exceptions.md:207` links
`../mcp/LabKeyMcp/README.md`, which really is wrong - the file is at
`ai/mcp/LabKeyMcp/README.md`, so the link needs `../../`.

### 2026-07-28 - WI-2 applied (measuring stick)

The theme: **every hand-maintained count in the corpus had rotted, and the fix is
to delete the number, not refresh it.**

- `documentation-maintenance.md` - removed the "Current" column (read 707 vs an
  actual 1,056) and the budget arithmetic that consumed it (offered 293 lines of
  headroom against a budget 56 over). Both now point at `audit-docs.ps1`.
  Enumerated `ai/` root as a closed set of nine per decision 4. Corrected the
  `pwiz_tools/Skyline/ai/` directory - which does not exist - to
  `ai/scripts/<Project>/`.
- `Generate-TOC.ps1` - three bugs. (a) `Measure-Object -Line` counts NON-BLANK
  lines, reading ~25% under (WORKFLOW.md 231 vs 307), so over-limit core files
  looked compliant in the very index used to check them; now `(Get-Content).Count`,
  matching `wc -l` and `audit-docs.ps1`. (b) The subdomain list was hardcoded to
  `labkey/` only, so TOC reported "Subdomains 1" while `callgraph/` and
  `labkey-setup/` had READMEs for months - now discovered from disk. (c) A fenced
  code block inside a double-quoted here-string collapsed ``` to `p (backtick is
  PowerShell's escape char), rendering the block as inline code - now a
  single-quoted here-string.
- `audit-docs.ps1` - added the CLAUDE.md 250-line limit, kept OUT of the core-five
  <1000 budget via a new `-BudgetFiles` parameter (folding it in would have
  silently raised the bar the five are measured against).
- `README.md` / `CLAUDE.md` - replaced stale counts ("all 58 documents", "~170
  lines", "Total: <500") with limits and a pointer to generated metrics.
- `pw-auditdocs.md` - documented BOTH tiers; it previously described only the
  platform limits, so a reader concluded an 18,962-char command was fine.
- `ai-repository-strategy.md` - phantom `helpers/` dir corrected to
  `scripts/Skyline/scripts/`; 3 of 8 script dirs listed -> all 8.
- Beyond the audit's list: `skylinetester-guide.md` had two *runnable* commands
  using the phantom path, and `scripts/AutoQC/README.md` +
  `scripts/SkylineBatch/README.md` cited it as the pattern to follow.

---

## Full audit plan (2026-07-28)

Synthesized from 83 verified findings (6 review sections, 0 rejected). Read-only audit;
nothing below has been applied.

Governing design doc: `ai/docs/documentation-maintenance.md`.
Governing principle (owner, 2026-07-28): *skills and commands are thin pointers into
`ai/docs`; a non-Claude-Code LLM handed the `ai/docs` file alone must be able to perform
the task.*

---

## 1. State of the corpus

### Measured 2026-07-28

| Layer | Files | Size | Compliance |
|---|---|---|---|
| Core files (`ai/*.md`, the five limited) | 5 | **1,056 lines** vs `<1000` budget | 2 of 5 within limit |
| `ai/` root total | 9 `.md` | — | rule says 6 max |
| `ai/docs/**` | 88 `.md` (36 top-level + mcp/ + labkey/ + labkey-setup/ + archive/ + callgraph/) | unlimited by design | n/a |
| `ai/claude/skills/*/SKILL.md` | 15 | 74,378 chars | 4 OK, 6 REVIEW, **5 REFACTOR** |
| `ai/claude/commands/*.md` | 41 | 167,651 chars | 18 OK, 12 REVIEW, **11 REFACTOR** |
| Skills + commands combined | 56 | **242,029 chars** | **22/56 (39%) in the "Good" `<2,000` band** |

Total `.md` under `ai/` excluding `todos/`: 198.

### Core-file limits (hard, `documentation-maintenance.md:18-25`)

| File | Limit | Actual (`wc -l`) | Over by |
|---|---|---|---|
| CRITICAL-RULES.md | <100 | 138 | +38 |
| MEMORY.md | <200 | 156 | ok |
| WORKFLOW.md | <200 | **307** | +107 |
| STYLEGUIDE.md | <200 | **295** | +95 |
| TESTING.md | <200 | 160 | ok |
| **Total** | **<1000** | **1,056** | **+56** |

### Worst offenders

**Skills** (>5,000 = REFACTOR): night-session 14,588 · version-control 11,858 ·
osprey-development 9,883 · labkey-development 7,836 · debugging 6,989.

**Commands** (>5,000 = REFACTOR): pw-complete 18,962 · pw-daily-research 16,247 ·
pw-pr-research 15,826 · pw-pr-email 11,556 · pw-startissue 11,461 · pw-issue 8,866 ·
pw-daily-email 8,630 · pw-test-review 8,581 · pw-oop-review 7,864 · pw-daily 6,449 ·
pw-review 5,432.

### The dominant structural problem

**Two of them, and they compound.**

1. **Procedures are being authored directly into `ai/claude/` and never given an
   `ai/docs` home.** Entire pipelines — the PR activity report (27,382 chars across
   `pw-pr-research.md` + `pw-pr-email.md`), the code/test review rubrics (16,445 chars),
   the handoff protocol, the PR review-thread resolution procedure, the autonomous
   session doctrine — exist *only* as slash commands. `ai/docs/` has no `pr-report-guide.md`
   and no `code-review-guide.md` at all. These fail the owner's test outright: hand a
   non-Claude-Code LLM the knowledge base and the task cannot be performed.

2. **Where an `ai/docs` home does exist, the command/skill duplicates it instead of
   pointing at it, and the copies drift.** `pw-daily.md` is a third copy of a workflow it
   declares it only sequences — and it is the copy that went stale on the 2026-01-30
   `ai/.tmp/daily/` reorg while the two it duplicates were updated. Same pattern in
   `debugging/SKILL.md` vs `debugging-principles.md`, `leak-debugging/SKILL.md` vs
   `leak-debugging-guide.md`, `pw-pcommit`/`pw-pcommitfull` vs `version-control-guide.md`.

A third, quieter problem: **the measuring stick itself is stale.**
`documentation-maintenance.md` still reports the 707-line total from November 2025 and
budgets 293 lines of headroom against a budget that is already 56 over. `TOC.md` counts
non-blank lines while the limits are written in `wc -l`, understating every core file by
~25%. `README.md` promises "<500 lines for essential context" against an actual 601 for
the three files it names.

---

## 2. Regression signal vs. the last audit

**Prior audit: `ai/todos/completed/2025/11/TODO-20251105_reorg_md_docs.md` (PR #3666,
merged 2025-11-05)** — ~9 months ago. It created the `ai/` + `ai/docs/` split, extracted
`CRITICAL-RULES.md`, and slimmed the four core files, moving detail into
`project-context.md`, `style-guide.md`, `workflow-guide.md`, `testing-patterns.md`.

### What it achieved vs. today

| File | Nov 2025 (post-reorg) | 2026-07-28 | Change |
|---|---|---|---|
| CRITICAL-RULES.md | 81 | 138 | **+70%** |
| MEMORY.md | 144 | 156 | +8% (held) |
| WORKFLOW.md | 166 | **307** | **+85%** |
| STYLEGUIDE.md | 162 | **295** | **+82%** |
| TESTING.md | 154 | 160 | +4% (held) |
| **Total** | **707** ✅ | **1,056** ❌ | **+49%** |

### The regression is real and its mechanism is identifiable

- **The reorg's own stated failure mode came true.** The TODO wrote: *"Agents add new
  information that 'floods' existing documents"* and *"Core files should be
  append-hostile."* Nine months later WORKFLOW.md and STYLEGUIDE.md have re-absorbed the
  exact content classes the reorg extracted — WORKFLOW.md:137-140, :179-192 and :213-224
  are **byte-identical** to `workflow-guide.md`, and STYLEGUIDE.md:139-152 and :230-239
  are byte-identical to `style-guide.md`. The extraction happened; the pointer discipline
  did not hold.
- **The two files that held (MEMORY, TESTING) are the two nobody edits.** The regression
  tracks edit frequency, not category.
- **A whole new layer was built with no size governance.** `ai/claude/` (15 skills +
  41 commands, 242,029 chars) did not exist in the Nov 2025 plan. `audit-docs.ps1` only
  gained the project REFACTOR/REVIEW thresholds **today (2026-07-28)** — before that it
  reported only the Claude Code platform limits (20k/30k), which nothing was close to.
  Nine months of unmeasured growth is precisely how 16 REFACTOR-tier files accumulated.
- **The `ai/` root rule was quietly abandoned.** The reorg's structure had 6 `.md` files;
  `documentation-maintenance.md:71` says *"NEVER create new .md files in ai/ root"*.
  There are now 9 (CLAUDE.md, TOC.md, root-CLAUDE.md added), and
  `ai-repository-strategy.md:185-188` already lists two of them as legitimate — the two
  docs contradict each other.

**Conclusion for this pass:** a one-time cleanup will regress again on the same 9-month
clock unless the verifiers land with it. Work items **WI-2** (fix the measuring stick)
and **WI-3** (add the missing checks to `audit-docs.ps1`) are therefore scheduled early
and should not be deferred as "cosmetic".

---

## 3. How to read this plan

- Findings were **merged across sections**. Where three reviewers reported the same
  underlying defect (the `&` call operator appeared in the skills, commands-a, commands-b,
  core, docs and mcp-docs sections with counts of 19 / 16 / 51 / 36 / 3), it is **one**
  work item with the widest verified scope.
- Each work item is sized to be **one coherent commit**.
- Reductions are estimates from the measured char/line counts in the findings.
- **Risk** names what can break: hooks, cross-references, TOC regeneration, published
  wiki pages.

### Dependency graph (must-precede relationships)

```
WI-2 (fix measuring stick) ──────────────► all size-target work (WI-9..WI-16)
WI-3 (add audit verifiers) ──────────────► WI-4, WI-5 (sweeps stay fixed)
WI-6 (create pr-report-guide.md) ────────► WI-13 (slim pw-pr-* commands)
WI-7 (create code-review-guide.md) ──────► WI-14 (slim pw-oop/test/review)
WI-8 (rehome orphan knowledge) ──────────► WI-11, WI-12, WI-15 (slim skills)
WI-10 (version-control-guide absorbs) ───► WI-11 (slim version-control skill + hook)
WI-9  (workflow-guide absorbs) ──────────► WI-16 (slim WORKFLOW.md)
```

**The single most important sequencing rule:** *create the `ai/docs` home before slimming
the file that currently holds the content.* Every "slim X" item below is blocked on its
corresponding "move to docs" item. Doing them in the wrong order deletes knowledge that
exists in exactly one place.

---

## 4. Work items, in priority order

### P0 — Instructions that are actively wrong today

These make an agent take a wrong action *now*. Small, mechanical, no dependencies.
Do these first regardless of the rest of the plan.

---

#### WI-1 — Contradictory and destructive instructions

| | |
|---|---|
| **Files** | `claude/commands/pw-complete.md`, `docs/project-context.md`, `claude/commands/pw-daily-review.md`, `docs/daily-report-guide.md` |
| **Reduction** | ~10 lines (correctness, not size) |
| **Risk** | Low. `pw-complete.md:46` edit must not disturb the state table at :73-76. |

1. **`pw-complete.md:46`** orders STOP on an `OPEN` PR — contradicting the frontmatter,
   the intro's explicit "recurring mistake" warning at :8-12, the state table at :73-76,
   and all 150 lines of Step 1b which exist solely to handle OPEN. It is read 26 lines
   before the table that corrects it. Replace the stop clause with
   *"`MERGED`, `OPEN`, or `CLOSED` — branch per the table below."*
2. **`docs/project-context.md:250`** says *"Remove TODO file before merging to master"* —
   the **only** such instruction in the repo, contradicting `WORKFLOW.md:152-158`,
   `README.md:82` and `workflow-guide.md:360-367`, all of which `git mv` it to
   `todos/completed/`. An LLM following it **destroys the engineering record.** Delete.
3. **`pw-daily-review.md:47-49`** hardcodes `--label bug --label skyline` as the default
   for every issue, conflicting with `pw-issue.md` (stated 4×) which requires exactly one
   of `skyline`/`pwiz`/`osprey`. `osprey` and `pwiz` are live labels
   (`gh label list` confirmed). A daily-report finding in pwiz code gets mislabelled, and
   the module label is the head of the chain into the PR title and squash-merge subject
   (`pw-issue.md:217` → `pw-complete.md:412-417`, unrecoverable once squashed).
   Replace with *"create per `/pw-issue`"*.
4. **Section Order contradiction**: `pw-daily-email.md:97-102` lists six email sections;
   `daily-report-guide.md:868-874` still says three. Update the guide to the post-split
   six-section order.

---

#### WI-2 — Fix the measuring stick

| | |
|---|---|
| **Files** | `docs/documentation-maintenance.md`, `TOC.md`, `scripts/Generate-TOC.ps1`, `README.md`, `CLAUDE.md`, `claude/commands/pw-auditdocs.md`, `docs/ai-repository-strategy.md` |
| **Reduction** | none (accuracy) |
| **Risk** | Medium. `Generate-TOC.ps1` change alters every row in TOC.md — regenerate and eyeball the diff. Do not renumber limits, only the "Current" column. |

Everything downstream depends on these numbers being true.

- `documentation-maintenance.md:18-25` reports **707 total** (81/144/166/162/154);
  actual is **1,056** (138/156/307/295/160). :242-243 then computes *"Remaining budget:
  293 lines"* against a budget already 56 **over**. Replace the "Current" column with a
  pointer to generated metrics rather than hand-maintained numbers.
- `documentation-maintenance.md:210-216`, :321-335, :381-385 and the example at :130
  prescribe a **`pwiz_tools/Skyline/ai/` directory that does not exist**
  (`Test-Path` → False). The scripts live in `ai/scripts/Skyline/`. Correct the section
  (spans :205-225) and the diagram.
- `documentation-maintenance.md:14`/:71/:341 forbid new `ai/` root `.md` files; there are
  9, and `ai-repository-strategy.md:185-188` already sanctions two of them. Reconcile:
  document the root as *5 limited core files + README.md + 3 enumerated Claude Code
  platform files*, and **state whether CLAUDE.md / TOC.md / root-CLAUDE.md have line
  limits or are exempt and why** (owner decision — see §5).
- `Generate-TOC.ps1:98-104` counts **non-blank** lines; the limits are `wc -l`. Every core
  file reads ~25% under. Change to `(Get-Content $FilePath).Count`, regenerate.
  Also fix the collapsed code fence at `Generate-TOC.ps1:366-368` (renders as inline code
  at TOC.md:195-197) and the subdomain count (`TOC.md:14` says 1, actual 4).
  TOC.md is 3 days stale and omits `docs/osprey-large-datasets.md`.
- `README.md:8-13` claims CRITICAL-RULES "<100" (138), WORKFLOW "~170" (307), and
  "Total: <500" (actual 601); `:19` claims "<200 lines each". `README.md:15` and
  `CLAUDE.md:165` both say "58 documents"; TOC sums to 115, actual 117+.
  Restate from `wc -l`, or emit the total from `Generate-TOC.ps1`.
- `pw-auditdocs.md:35-44` documents **only** the platform limits (20k/30k) and omits the
  project 2k/5k bands its own script now prints — so a reader concludes an 18,962-char
  command is fine. Add both tiers; replace the "Fixing Size Issues" paraphrase with a
  pointer to `documentation-maintenance.md` §"Commands and Skills: Reference, Don't Embed".
- `ai-repository-strategy.md:179` shows a `helpers/` directory under `ai/scripts/Skyline/`
  that does not exist (actual: `scripts/`), and omits 5 of 8 `ai/scripts/` subdirectories.

> **Note for the record:** the audit brief's premise 3 ("`audit-docs.ps1` only checks
> platform limits") is itself out of date — the script was extended 2026-07-28 and now
> reports REFACTOR/REVIEW and core-file line violations. Only the command doc lags.

---

#### WI-3 — Add the missing verifiers to `audit-docs.ps1`

| | |
|---|---|
| **Files** | `scripts/audit-docs.ps1` |
| **Reduction** | none (prevention) |
| **Risk** | Low, but the checks must not fire on deliberate counter-examples (see whitelist). |

Per `CRITICAL-RULES.md:10`, a rule without a verifier drifts. Every sweep below
(WI-4, WI-5) will re-rot in 9 months without these. Add:

1. `pwsh -Command "&` grep — **whitelist `ai/CLAUDE.md:77` and `:89`** (those two *are*
   the prohibition's WRONG examples) and hand-review `docs/scheduled-tasks-guide.md`
   (Task Scheduler action strings may legitimately require `-Command`).
2. Relative-link resolution check over `ai/docs/**` and `ai/claude/**`.
3. Every `/pw-*` token in a skill or command has a matching `claude/commands/<name>.md`.
4. No `docs/**/*.md` links to `claude/skills/**/SKILL.md` outside a declared
   "skills that auto-load" table.
5. Banned phrases (`load-bearing`, `smoking gun`) per `C:\proj\CLAUDE.md`.

---

#### WI-4 — Repo-wide `&` call-operator sweep

| | |
|---|---|
| **Files** | ~10-12 files; verified occurrences reported as 19 / 36 / 51 by three reviewers using different scopes — **re-count at execution time** |
| **Reduction** | none (correctness) |
| **Risk** | Low. Do not "fix" `ai/CLAUDE.md:77`/`:89`. Hand-check the 13 `scheduled-tasks-guide.md` occurrences. |
| **Depends on** | WI-3 (land the verifier in the same or prior commit) |

`ai/CLAUDE.md:71-82` bans `pwsh -Command "& './script.ps1'"` because the `&` breaks
allowed-tools permission matching. Confirmed prescriptive occurrences span, at minimum:

- **Core files** (highest impact): `WORKFLOW.md:247,250,253`; `README.md:170`
- **Executed commands**: `pw-archivetodos.md:9`; `pw-pcommitfull.md:45`
- **Onboarding docs** (the copy-paste propagation source):
  `docs/build-and-test-guide.md:37,40,49,52`; `docs/developer-setup-guide.md:83,122,123`
  (**:122-123 sit inside the "Generic Prompt for Other Tools" block that is published to
  the public AIDevSetup wiki**); `docs/new-machine-setup.md:71,883,892,922,933`
- **Others**: `docs/scheduled-tasks-guide.md` (13), `docs/translation-guide.md:78,81,107,110`,
  `docs/debugging-principles.md:158`, `docs/release-guide.md:645`,
  `docs/mcp/image-comparer.md:72`, `scripts/README.md:80,81,87,93`, `scripts/audit-loc.ps1:16,19`,
  `mcp/ImageComparerMcp/README.md:8,62,83`

Convert to `pwsh -File './path.ps1' -Arg value`.

---

#### WI-5 — Relative-link normalization

| | |
|---|---|
| **Files** | 3 skills, 8 commands, 2 mcp docs, `README.md`, `docs/mcp/team-city.md` |
| **Reduction** | none (correctness) |
| **Risk** | Low. Verify each rewritten link resolves both in-repo and on github.com/ProteoWizard/pwiz-ai. |
| **Depends on** | WI-3 |

Four mutually incompatible conventions are in use, and `.claude` being a junction to
`ai/claude` means each is broken under at least one access path.

- **Skills** — standardize on the plain text form `ai/docs/<file>.md` already used by
  12 of 15 skills; drop markdown link syntax in skills entirely. Fix 4 sites:
  `skyline-tester:42`, `debugging:8` **and `:79`**, `leak-debugging:13`.
- **Commands** — standardize on `../../docs/...` (repo root is `ai/`, so this resolves
  in-repo and on GitHub). Convert the 17 `../../ai/docs/` links in `pw-daily.md`,
  `pw-daily-email.md`, `pw-daily-research.md`, `pw-daily-review.md`, `pw-release.md`;
  4 files already use the correct form. Fix the 3 bare `ai/docs/` links at
  `pw-upconfig.md:60-62`.
- **MCP docs** — `exceptions.md:207-208` and `nightly-tests.md:472-473` use `../mcp/`;
  correct is `../../mcp/` (as `issues.md:172-173` and `README.md:101-102` already do).
- **Dead links** — `README.md:179-181` (`../README.md`, `../.cursorrules`, `../doc/`)
  resolve nowhere in the recommended sibling layout; relabel as `pwiz/` paths
  (`pwiz/README.md` and `pwiz/.cursorrules` both exist).
  `docs/mcp/team-city.md:146` links to a TODO now in `todos/completed/2026/02/` — drop it
  (an `ai/docs` file must not depend on a path that moves when a TODO is archived).

---

### P1 — Knowledge that exists ONLY in `ai/claude/` (fails the owner's test)

Highest value after correctness. Each is *create the docs home first*, then slim.

---

#### WI-6 — Create `docs/pr-report-guide.md`; the PR-report pipeline has no `ai/docs` home at all

| | |
|---|---|
| **Files** | **new** `docs/pr-report-guide.md`; `claude/commands/pw-pr-research.md` (15,826), `pw-pr-email.md` (11,556), `pw-pr-reporting.md` (4,046); `scripts/PRReport/README.md` |
| **Moves** | threshold table, all `gh` invocations with `--json` field lists, TODO classification table, `todos-inventory.json` / `manifest.json` / per-subscriber slice schemas, HTML/section-order/link-convention/badge spec, fan-out loop, reporting-level definitions, the `>= 3` pile-up threshold |
| **Reduction** | ~24,000 chars out of `ai/claude/`; the two commands target **<2,000 each** |
| **Risk** | Medium. `pw-pr-research.md` computes `in_pileup` from the `>= 3` threshold and `pw-pr-email.md` renders a callout keyed to it — the threshold must survive as a single stated value, not be lost in the move. Scheduled task consumes this pipeline. |
| **Blocks** | WI-13 |

`ls docs/` confirms no PR-report guide exists; the only `ai/docs` mentions of the pipeline
are 5 scheduling pointers in `scheduled-tasks-guide.md`. Mirror the `daily-report-guide.md`
precedent. **Do not model the resulting command size on `pw-daily-research.md`** — that
file is 16,247 chars and is itself a REFACTOR violation; it demonstrates the *pointer
convention* only. Model on `documentation-maintenance.md:468-488`.

Also fold in the reporting-level duplication: the levels are defined independently in
`PRReport/README.md:64-67`, `pw-pr-reporting.md:28-31` and `pw-pr-email.md:204-205` with
drifting wording, and the `>= 3` threshold is restated in **seven** places. Delete the
expanded Drive-sharing prose at `pw-pr-reporting.md:47-51` (the README it already links
at :12 and :79 owns it).

---

#### WI-7 — Create `docs/code-review-guide.md`; the review rubrics have no `ai/docs` home

| | |
|---|---|
| **Files** | **new** `docs/code-review-guide.md`; `claude/commands/pw-oop-review.md` (7,864), `pw-test-review.md` (8,581), `pw-review.md` (5,432); plus `docs/testing-patterns.md` |
| **Moves** | shared "be honest, even uncomfortable" posture (`pw-oop-review.md:15-28` ≡ `pw-test-review.md:16-29`); OOP five lenses + survey heuristics + the monolithic-vs-spaghetti calibration; generic review criteria from `pw-review.md:102-130`. **Test-coverage lenses go to `docs/testing-patterns.md`** as an "Assessing test coverage by reading" subsection next to the existing tool-based "Code Coverage Validation" (:1824) — `pw-test-review.md:11-14` already frames itself as the by-eye complement to dotCover. |
| **Reduction** | ~14,000 chars out of `ai/claude/` |
| **Risk** | Low — no hooks, no scheduled consumers. `pw-test-review.md:18` currently reads *"Same as /pw-oop-review"*: a command-to-command dependency that this item removes. |
| **Blocks** | WI-14 |

**Do NOT put the OOP rubric in `docs/style-guide.md`** — that file (35,565 chars) is
exclusively C# micro-conventions (control flow, member ordering, using-directive ordering,
naming, whitespace, resource strings, file headers). An architecture-assessment rubric
there would be misfiled.

While here: `pw-review.md:116-121` attributes five rules to `CRITICAL-RULES.md`; two are
not there — the `MessageBox.Show`/`MessageDlg` and `System.Windows.Forms`-in-Model rules
actually live at `docs/architecture-error-handling.md:427`. Point at the real sources
rather than restating rules that drift.

---

#### WI-8 — Rehome orphan knowledge from skills and commands into `ai/docs`

| | |
|---|---|
| **Files** | 8 sources → 6 existing docs + 1 new |
| **Reduction** | ~8,000 chars moved (net zero repo-wide; the point is *reachability*, not size) |
| **Risk** | **Highest deletion risk in the plan.** Each item below is verified to exist in exactly one place. Nothing here may be deleted before it is written elsewhere. |
| **Blocks** | WI-11, WI-12, WI-15 |

| Knowledge | Currently only in | Destination |
|---|---|---|
| PR review-thread procedure: GraphQL `reviewThreads` query, `databaseId`→REST id join, `in_reply_to` POST, `resolveReviewThread` mutation | `pw-respond.md:52-89` — and **`version-control-guide.md:375` points *into* the command**, inverting the architecture | `docs/version-control-guide.md` new §"Addressing and resolving PR review threads"; :375 becomes a section reference naming `/pw-respond` as the entry point |
| "pwiz-ai — rebase, never merge" push-rejection policy; deliberately overrides the machine-global `pull.rebase false` | `version-control/SKILL.md:124-146` (1,069 chars). Not in `WORKFLOW.md`, `workflow-guide.md`, `version-control-guide.md` or `ai-repository-strategy.md` — none contains the word "rebase" in this context | `docs/version-control-guide.md` (FORMAT+POLICY, matching the established split). Cross-link from `docs/new-machine-setup.md:258`, where the global it overrides is set |
| Bug-fix commit gate (3 verification questions, "stop and ask the developer why", acceptable-rationale carve-out) — **byte-identical** md5 `01c1ce33…` in two commands | `pw-pcommit.md:34-44` ≡ `pw-pcommitfull.md:29-39` | `docs/version-control-guide.md` §"Checklist Before Commit" (:439) |
| Handoff-file protocol: naming rule, temporal-vs-durable split, gitignore constraint, full template, TODO pointer-line contract | Split across `pw-handoff.md:14-68` (producer) and `pw-continue.md:53-63` (consumer) — one contract, two owners, no source of truth | `docs/workflow-guide.md` (already owns TODO lifecycle; :72 already frames handoff as switching between *LLM* sessions generally, so this is not Claude Code-specific) |
| Numerical-divergence heuristics: Welford vs sum/n non-associativity under SIMD, Kahan summation, `cargo rustc -- --emit=asm`, `/p:JitDisasm`, `black_box`/`NoInlining`; plus first-divergent-row/ULP-boundary/tie-break triage | `night-session/SKILL.md:261-294`. Grep for Welford, Kahan, `black_box`, JitDisasm, non-associat, vectoriz across `docs/` returns **zero** | `docs/debugging-principles.md` §"Cross-Implementation Bisection" (:355), next to "Bit-Preserving Number Formats". **`skill:287-294` has no counterpart and must be moved, not dropped.** `skill:283-286` *contradicts* `doc:527` (skill says ryu default in Rust; doc prescribes `{:.17}`) — resolve before deleting |
| Autonomous overnight session doctrine (posture, worked bad/better/high-definition example at :124-144) | `night-session/SKILL.md` — grep for `night.session`/`autonomous overnight` across `docs/` returns **zero** | **new** `docs/autonomous-session-guide.md` (owner decision — see §5) |
| Save-path convergence: SkylineCmd args are LLM-driven through in-process MCP and save via `SkylineFiles.SaveDocument`, not `CommandLine`'s; use a scoped ambient override set in `CommandLine.RunInner` read at `DocumentWriter`→`CompactFormatOption.Effective`; PR #4288 | `skyline-development/SKILL.md:60` + one archived TODO. Grep for `DocumentWriter`/`SaveDocument`/`CompactFormatOption` across `docs/` returns **zero** | `docs/architecture-files.md` §6 (FileSaver/atomic writes) as "Save paths: GUI, CommandLine and MCP converge at DocumentWriter" — **or a new `architecture-save-paths.md`** (owner decision). **Do NOT add to `CRITICAL-RULES.md`** — it is already 38 lines over its hard limit |
| Win11 corner rendering: `CleanupBorder11()`, `GraphicsPath.AddArc` 8px forms / 4px tool windows, the tested-and-rejected `Gdi32.CreateRoundRectRgn()` note | `skyline-screenshots/SKILL.md:50-52`. Grep across `docs/` returns **zero** | `docs/screenshot-update-workflow.md` next to the Cover Shot material (:271-275) |
| LabKey repo-selection rule ("branch only the repo(s) that actually have changes; do NOT reflexively branch the enlistment root") + 2-repo gradle example | `labkey-development/SKILL.md:64-80` | `docs/labkey/labkey-feature-branch-workflow.md` new §"Which repository do I branch?" next to the cross-repo naming rule (:13) |
| Build-before-commit rule + "JSP files are compiled at build time" rationale | `labkey-development/SKILL.md:113-120`. Grep returns **zero** | `docs/labkey-setup/reference/gradle-commands.md`, next to the command table it depends on |
| Daily research manifest JSON schema | `pw-daily-research.md:354-388` | `docs/daily-report-guide.md` §Manifest File (currently ~5 lines of prose at :43-48) |
| Email-phase delta: consolidated-vs-fallback file resolution order, Investigation Findings section spec + content rules, email-side leak-deference prohibition | `pw-daily-email.md`. Grep for "Investigation Findings" across `docs/` returns **zero** | `docs/daily-report-guide.md` new §"Email Phase" under §Email Format |
| Team-usage-store `TEAM-STORE-ID.txt` marker check, private-duplicate failure mode, "do NOT create by hand" warning | `pw-usage-reporting.md:23-43` | `scripts/Usage/README.md` §Per-machine setup, matching `scripts/PRReport/README.md:33,51-53` |
| Canonical assignee roster (the two existing lists disagree: `pw-daily-review.md:47` has `chambm`, lacks `rita-gwen`/`bconn-proteinms`; `pw-issue.md:236` the inverse) | two commands | `docs/project-context.md`, one list feeding both |

**Not orphaned — do not "fix" these:** `debugging/SKILL.md:55-64` is already a compliant
thin pointer, and `validation-cycle-principles.md:80`'s link to the debugging SKILL is
already framed as auto-load navigation, not as a content source.

---

### P2 — Duplication that is actively drifting

---

#### WI-9 — `docs/workflow-guide.md` becomes the single source for workflows and TODO lifecycle

| | |
|---|---|
| **Files** | `docs/workflow-guide.md`, `WORKFLOW.md`, `docs/version-control-guide.md` |
| **Reduction** | ~160 lines out of `WORKFLOW.md` (in WI-16); ~20 lines out of the guide |
| **Risk** | Medium — workflow renumbering touches every inbound anchor. Grep for `Workflow N` references before renumbering. |
| **Blocks** | WI-16 |

- **`workflow-guide.md` has zero references to `version-control-guide.md`** across all
  578 lines. That is the root of the commit-format drift. Delete its third commit-message
  copy at :497-517 (missing the conditional `Reported by <First>.` line that
  `version-control-guide.md:148,155-158` requires) and point at
  `version-control-guide.md#commit-message-format`.
- **`workflow-guide.md:436`** issues `--title "Brief description"` with **no module
  prefix**, contradicting `version-control-guide.md:65-72` which marks the prefix Required
  on both the PR title and the squash-merge subject.
- **Workflow numbering conflicts**: `workflow-guide.md` Workflow 3 = "Early Pull Request
  for TeamCity Validation" and 4 = "Completing Work and Merging"; `WORKFLOW.md` Workflow
  3 = "Complete Work and Merge" and 4 = "Create GitHub Issue". Both 3 and 4 name different
  procedures across the two files. Renumber or de-number (owner decision — see §5).
- **Emergency Procedures (`workflow-guide.md:532-548`)** prescribes
  `Skyline/hotfix/…` and `Skyline/rollback/…` branches — neither exists in
  `version-control-guide.md:397-405`, which gives `Skyline/work/YYYYMMDD_feature_name`
  as *the* format — and :539 says "Merge directly to master" against its own :22
  "Direct pushes require review". Delete or rewrite (owner decision).
- **TODO template is missing the `Module` field**: `workflow-guide.md:129-139` lacks it
  while `WORKFLOW.md:81` has it and explains (`:87-93`) it is the only record of the
  module that survives into master's history. `version-control-guide.md:100-105` shows a
  third, complete template. Add `Module` to the workflow-guide template and cross-link
  the two so they cannot drift again.
- Also absorb from `WORKFLOW.md` (per WI-16): Key Workflows :97-225, TODO header template
  :73-83.

---

#### WI-10 — `docs/version-control-guide.md` becomes the single source for commits, PRs, labels

| | |
|---|---|
| **Files** | `docs/version-control-guide.md`, `pw-issue.md` (8,866), `pw-complete.md` (18,962), `pw-pcommit.md`, `pw-pcommitfull.md`, `pw-daily-review.md` |
| **Reduction** | ~4,000 chars from `pw-issue.md`, ~1,500 from `pw-complete.md`, ~1,200 across the two pcommit commands |
| **Risk** | Medium. `pw-complete.md` is the highest-traffic command; the squash-message rules being moved are cited as unrecoverable-once-merged. Land WI-1 item 1 first or in the same commit. |
| **Depends on** | WI-8 (rebase policy, review-thread procedure, bug-fix gate land here first) |
| **Blocks** | WI-11 |

- `pw-issue.md:221-232` "Available Labels" omits **`osprey`** — required by the same file
  4× (:39, :91, :143, :217) and consumed by `pw-complete.md:57,142-143` — and is also
  missing the live `vendor` and `tech-debt` labels. Delete the table; point at
  `version-control-guide.md` §Module Tagging (:5, table at :14), which `pw-issue.md:217`
  already cites.
- `pw-issue.md` triplicates its "Determine labels" + "Ask about assignee" blocks
  near-verbatim at :38-46, :90-98 and :142-150 — one policy maintained three times inside
  one file. Collapsing this is most of the path from 8,866 to target.
- `pw-complete.md:118-150` restates squash-message format rules and **labels itself**
  ("also in version-control-guide.md" at :130) — duplicated at
  `version-control-guide.md:46-60` and :111-119. Delete.
- `pw-pcommit.md:7-19` / `pw-pcommitfull.md:11-23` both reproduce the commit template from
  `version-control-guide.md:139-152`, with *drifted placeholder wording*, and both files
  **open by telling the reader to read that guide** (:4 / :5). Delete both copies and the
  checklist restatement at `pw-pcommit.md:21-32`.

---

#### WI-11 — Slim `version-control/SKILL.md` and re-scope the injection hook

| | |
|---|---|
| **Files** | `claude/skills/version-control/SKILL.md` (11,858), `claude/hooks/Inject-VersionControlSkill.ps1`, `docs/version-control-guide.md` |
| **Reduction** | ~9,000 chars |
| **Risk** | **Highest hook risk in the plan.** The hook currently injects the **entire** 11,858-char SKILL.md on every `gh` command. If the skill is slimmed to a pointer without changing the hook, deterministic rule injection silently stops working. |
| **Depends on** | WI-8 (rebase policy rehomed), WI-10 |

Per the precedent already established: mark an `<!-- INJECT:START -->` / `<!-- INJECT:END -->`
region in `docs/version-control-guide.md`, change the hook to extract *that* region, and
reduce the skill to a thin pointer. **The hook change and the skill slimming must be one
commit** — they cannot be separated without a window where `gh` commands get no rules.

The ~85% verbatim duplication against `version-control-guide.md` is already in the audit
baseline; the only *new* content is the rebase policy handled in WI-8.

---

#### WI-12 — Daily-report pipeline: collapse three copies to one guide + two thin phases

| | |
|---|---|
| **Files** | `pw-daily.md` (6,449), `pw-daily-research.md` (16,247), `pw-daily-email.md` (8,630), `docs/daily-report-guide.md`, `docs/scheduled-tasks-guide.md` |
| **Reduction** | ~24,000 chars out of `ai/claude/`; all three commands target <2,000 |
| **Risk** | **Medium-high.** This pipeline runs on a schedule. Verify a full `/pw-daily` cycle after the change. The two phase commands have phase-boundary rules ("Do NOT send email" at research :8; "Do NOT archive emails" at :57) that are genuinely command-shaped and must survive. |
| **Depends on** | WI-8 (manifest schema + email-phase delta land in the guide first) |

1. **Stale `ai/.tmp/` paths from the 2026-01-30 reorg** — `pw-daily.md:46` and `:188`
   still use the flat `ai/.tmp/history/` and `ai/.tmp/daily-summary-*.json`; the MCP server
   uses `daily/history/` and `daily/summaries/` (`common.py:240,253`, `computers.py:52-54`).
   **The doc side is contaminated too**: `daily-report-guide.md:151,233,237,307,308,1062`
   and `scheduled-tasks-guide.md:135`. Fix all in one pass or the command gets re-broken
   from the docs.
2. **`pw-daily.md` is a third copy of a workflow it declares (`:18`) it only sequences.**
   Lines 38-98 restate the research MCP sequence; :99-173 restate
   `daily-report-guide.md:428-687`; :175-181 restate the validation rules. Reduce to a
   dispatcher: keep the two-phase architecture summary (:11-22) and "run
   /pw-daily-research, then /pw-daily-email". **The delete subsumes the path fixes at
   :188 — land both in the same commit.**
3. **`pw-daily-research.md`** duplicates `daily-report-guide.md` at the same granularity,
   including a **byte-identical** paragraph (command :108-110 ≡ guide :341-343). Replace
   Phase 1.5 and the leak/regression-echo block (:242-332) with section pointers. Keep the
   required-reading list, the ordered MCP call sequence, and the phase-boundary rules.
4. Reconcile the two error-email subject lines (`daily-report-guide.md:139` "Data
   Unavailable" vs `pw-daily-email.md:168` "Research Phase Incomplete").

---

#### WI-13 — Slim the PR-report commands

| **Depends on** | WI-6 |
|---|---|
| **Files** | `pw-pr-research.md`, `pw-pr-email.md`, `pw-pr-reporting.md` |
| **Reduction** | ~24,000 chars → three files under 2,000 |
| **Risk** | Scheduled pipeline; verify one full run. |

Mechanical once WI-6 exists. Keep in each command: description, arguments, prerequisite
file list, output paths, the ordered step list, and one `**Read**: ai/docs/pr-report-guide.md`
line.

---

#### WI-14 — Slim the review commands

| **Depends on** | WI-7 |
|---|---|
| **Files** | `pw-oop-review.md`, `pw-test-review.md`, `pw-review.md` |
| **Reduction** | ~14,000 chars |
| **Risk** | Low. No hooks, no schedules, no other consumers. |

Keep posture pointer + output structure in each. Also in this pass:
`pw-review.md:31-34` asserts three pwiz checkouts exist (`pwiz/`, `pwiz-work1/`,
`pwiz-work2/`); only `pwiz/` exists. The very next lines already say to call
`mcp__status__get_project_status()` and apply selection criteria, so delete the roster.
And `pw-oop-review.md:115` uses **"load-bearing"**, banned by `C:\proj\CLAUDE.md`, in a
line instructing Claude how to phrase its output — reword to "essential"; same fix at
`night-session/SKILL.md:17`.

---

#### WI-15 — Slim the remaining REFACTOR/REVIEW skills

| **Depends on** | WI-8 |
|---|---|
| **Files** | `debugging` (6,989), `labkey-development` (7,836), `night-session` (14,588), `leak-debugging` (4,062), `skyline-screenshots` (2,478), `skyline-development` (3,998) |
| **Reduction** | ~18,000 chars |
| **Risk** | Low-medium. `osprey-development` (9,883) was not individually reviewed in this audit — treat as unassessed, not as compliant. |

- **debugging** — reduce `:35-53`, `:81-122`, `:131-141` (2,778 chars of verified
  duplication, incl. three verbatim sentences and the `BISECT:` code block) to section
  pointers into `debugging-principles.md`. Keep frontmatter, the validation-cycle quote,
  "The First Questions", the existing thin pointer at :55-64, and "Related Skills".
  **Note:** the sub-2,000 target is only reachable if "Write the Failing Test First"
  (:65-79, 2,192 chars) is *first* merged into the doc's "Permanent Verifier Pattern";
  leave it and the floor is ~2,800.
- **labkey-development** — after WI-8 moves the two genuinely unhoused blocks, delete the
  deployModule/deployApp commands (:89-111, already at
  `docs/labkey-setup/reference/gradle-commands.md:10-28`) and reduce the module block
  (:82-87, already at `docs/labkey-setup/reference/modules.md:20-60`) to the
  ownership/maintainer sentences moved into that doc. Target <3,000.
- **night-session** — after WI-8, leave only Claude Code mechanism.
- **leak-debugging** — trim `:36-61` and `:63-70` to pointers into
  `leak-debugging-guide.md` (§Investigation Methodology, §Memory Profiling with dotMemory,
  §Common GC Leak Patterns; the 4-row pattern table at guide :852-858 is near-verbatim).
  **Keep** the leak-vs-scaling triage callout (:8-13) and the "Which Leak Type?" routing
  table (:28-34) — genuinely unique routing.
- **skyline-screenshots** — after WI-8, reduce to frontmatter, the `ai\.tmp` diff-lookup
  behavior, and pointers; :14, :16, :22-25 already exist at
  `screenshot-update-workflow.md:38-57` and :95-137.
- **skyline-development** — reduce :60 to a one-line pointer once WI-8 lands the rule.

---

#### WI-16 — Bring the five core files back under their hard limits

| | |
|---|---|
| **Files** | `WORKFLOW.md` (307→~185), `STYLEGUIDE.md` (295→~195), `CRITICAL-RULES.md` (138→<100), `MEMORY.md`, `docs/project-context.md`, `docs/style-guide.md` |
| **Reduction** | ~1,056 → ~840 lines total |
| **Risk** | Medium. Core files are auto-loaded every session; an over-aggressive cut removes context agents rely on. Re-run `wc -l` (not TOC.md's non-blank count) to verify. |
| **Depends on** | WI-2 (correct measurement), WI-9 (workflow-guide ready to receive) |

**WORKFLOW.md (307 → ~185).** Move "Key Workflows" :97-225 into `workflow-guide.md`
(where Workflows 1-7 already live), leaving a table of workflow → slash command → anchor.
Move the TODO header template :73-83 (carrying the `Module` field). Replace "Commit
Messages" :264-287 with a pointer. Verified byte-identical blocks that can go outright:
:137-140 ≡ `workflow-guide.md:295-298`; :179-192 ≡ :378-397; :213-224 ≡ ~:434-446.
**Do NOT strip the build block at :241-256** — `documentation-maintenance.md:118-131`
explicitly sanctions "brief quick command + pointer" as the *correct* pattern, and :256
already carries the pointer.

**STYLEGUIDE.md (295 → ~195).** **First MOVE** :70-104 (the multi-line braceless-body rule
with its 24-line `using`/`Parallel.ForEach` example) into `docs/style-guide.md`'s
control-flow section — a repo-wide grep confirms it exists *nowhere else*, so this is a
WI-8-class rehoming, not a trim. Then replace with pointers: :137-164 (array literals,
verbatim ≡ `style-guide.md:91-104`), :226-246 (Apache header ≡ :689-708), :282-288
(executables ≡ :638-644), :29-35 (naming ≡ :561-570 and `CRITICAL-RULES.md:32-37`).

**CRITICAL-RULES.md (138 → <100).** Delete the trailing NEVER block :129-138 — 8 of its
9 bullets restate rules stated above in the same file (:130≡:20, :131≡:40, :133≡:48,
:134≡:26, :135≡:67, :136≡:14, :137≡:16-17, :138≡:112); fold the one unique bullet
("Parse exception messages for status codes", :132) upward. Merge the two adjacent
`ai/.tmp` sections (:109-127, 19 lines) into ~4 lines. Reduce the member-ordering block
:76-86 to one bullet + pointer (it carries a checkmark/cross explanation against the
file's own charter at :3, "Bare constraints only — no explanations"). Reduce :31-37 to a
pointer. **Keep the `ai/.tmp` rule IN CRITICAL-RULES.md** — do not hand ownership to
`ai/CLAUDE.md`, which is the one file a non-Claude-Code tool never loads.

**MEMORY.md / project-context.md.** MEMORY.md is within budget at 156 — do not gut it; the
brief-core/detailed-docs split is the *designed* structure. Replace only the two
byte-identical blocks: MEMORY.md:102-106 ≡ `project-context.md:227-231`, and
MEMORY.md:133-137 ≡ :254-258. On the docs side delete `project-context.md`'s seven
duplicated sections (~82 of 271 lines) but **preserve :42-52** ("Choosing the right
RunAsync", the ActionUtil vs CommonActionUtil split) — unique detail absent from MEMORY.md.
Sync the localization lists: `project-context.md:25`, `:69` and `:157` list 3 languages;
MEMORY.md:18, `testing-patterns.md:1668` and `build-and-test-guide.md:236` say 5
(English, Chinese, Japanese, Turkish, French).

**Member ordering, 5 copies.** The six-item list exists at `CRITICAL-RULES.md:77`,
`MEMORY.md:83`, `STYLEGUIDE.md:110`, `docs/style-guide.md:34`, `docs/project-context.md:208`
— **and items 2 and 5 disagree** ("static public methods" / "public methods/properties"
vs "static public *interface* methods" / "public *interface (instance)* methods and
properties"). Make `docs/style-guide.md:32-43` the single source; resolve the wording once
there (owner decision — see §5).

---

### P3 — Reachability and index accuracy

---

#### WI-17 — Make existing `ai/docs` content reachable

| | |
|---|---|
| **Files** | `docs/README.md`, `claude/skills/skyline-development/SKILL.md`, `tutorial-documentation/SKILL.md`, `ai-context-documentation/SKILL.md`, `docs/tutorial-workflow-guide.md`, `docs/osprey-development-guide.md` |
| **Reduction** | none — this *adds* ~20 pointer lines |
| **Risk** | Low. Adding to `tutorial-documentation` (963 chars, ~1,000 of headroom) and `skyline-development` (3,998, REVIEW band) is fine; keep additions to one line each. |

Highest-leverage item in this section: **all four `architecture-*.md` guides — 2,409 lines
of the deepest subsystem documentation in the repo — have zero inbound references from any
skill or command.** A 726-file scan confirms only `TOC.md` and `docs/README.md` link them.
Meanwhile `skyline-development/SKILL.md`, whose description says *"ALWAYS load when working
in pwiz_tools/Skyline"*, references four other docs and none of these. Add an
"Architecture deep-dives" block with a one-line "read this when" trigger per guide.

Also:
- **`docs/README.md` omits 8 of 35 guides** (memory-band-guide, native-file-dialog-automation,
  osprey-crossimpl-validation-guide, **osprey-development-guide — 1,448 lines, the
  third-largest guide in the repo**, osprey-large-datasets, tutorial-workflow-guide,
  validation-cycle-principles, webinar-to-tutorial-draft-guide). No Osprey category exists
  despite four Osprey guides totalling 1,893 lines.
- **Tutorial island**: `tutorial-workflow-guide.md` and `webinar-to-tutorial-draft-guide.md`
  reference each other and nothing else references either — yet
  `tutorial-workflow-guide.md:91-97` names `tutorial-documentation` as the auto-loading
  entry point. The skill (`:12-13`) routes to only 2 of 5 tutorial docs and mentions
  `ja`/`zh-CHS` (`:21`) while pointing nowhere for `translation-guide.md`. Add three lines.
- **`ai-context-documentation/SKILL.md`** — the skill that gates `ai/` and `.claude/` edits
  — never mentions `documentation-maintenance.md`
  (grep across `claude/` returns **zero**). Add it as item 1 under "Core Documentation
  Files" with a "read before creating or growing any .md" instruction, and replace the
  frontmatter templates at :27-61 with the size-band table + pointer. While there: its
  write paths at :31, :44 and :67-68 say `.claude/skills/`; normalize to `ai/claude/`; and
  the commit-policy sentence is duplicated at :20 and :75.
- **`osprey-large-datasets.md`** has exactly two inbound references, both in
  `scripts/Osprey/Get-PanoramaFiles.ps1`. Add to `osprey-development-guide.md`'s "See also"
  (:1326-1352) and to `docs/README.md`. *(Its absence from TOC.md is ordinary 3-day
  staleness, not a defect — WI-2's regeneration fixes it.)*
- **Inverted references** — `tutorial-workflow-guide.md:76-78` and `:88-89` send readers
  into a SKILL.md for content details. After WI-8 moves the Win11 content, repoint both at
  `screenshot-update-workflow.md`. Leave `validation-cycle-principles.md:80` alone — it is
  already framed as navigation.

**Durable fix worth considering:** have `Generate-TOC.ps1` emit `docs/README.md`, or
delete `docs/README.md` in favor of `TOC.md`. A hand-maintained second index will drift
again (owner decision — see §5).

---

#### WI-18 — MCP docs: remove the deleted-tool instructions

| | |
|---|---|
| **Files** | `docs/mcp/exceptions.md`, `nightly-tests.md`, `development-guide.md`, `claude/skills/skyline-exceptions/SKILL.md`, `mcp/LabKeyMcp/README.md` |
| **Reduction** | ~60 lines |
| **Risk** | Low — these instructions cannot work today, so nothing regresses. |

`list_schemas`, `list_containers` and `query_table` were **deliberately removed**
(`TODO-20251227_mcp_context_optimization.md:111`; `tool-hierarchy.md:68`; confirmed by
enumerating all 50 registered tools in `mcp/LabKeyMcp/tools/*.py`). They are still
advertised as available in:

- `exceptions.md:60,62,63` (tool table) and the "Explore data" example at `:165-166`
- `nightly-tests.md:160-165, 199-206, 252-258, 417, 422` — **all three server-side-query
  walkthroughs are non-executable**, and the copies disagree on calling convention
  (`parameters={...}` at :203 vs flat `param_name`/`param_value` at :422).
  Replacements exist and are correctly named: `get_daily_test_summary`,
  `save_run_comparison`, `save_run_metrics_csv`, `save_test_leak_history`.
- `development-guide.md:166,167,200,215,284-291,310-315` — and this is **circular**:
  `tool-hierarchy.md:81` routes readers *into* this section as the sanctioned replacement
  workflow, ten lines below its own removal notice at :68 and thirteen above the rationale
  at :83-86. A reader following the sanctioned path lands on the forbidden instructions.
- Downstream copies: `skyline-exceptions/SKILL.md:32-33`;
  `mcp/LabKeyMcp/README.md:69-70,72,74-77,106-108,196-199`.

Note `nightly-tests.md`'s §"Custom Queries" should be *reframed* as documentation of the
server-side SQL that MCP tools consume, not deleted — the SQL is still real.

---

#### WI-19 — MCP docs: consolidate duplication and fix reference accuracy

| | |
|---|---|
| **Files** | `docs/mcp/README.md`, `setup.md`, `exceptions.md`, `issues.md`, `files.md`, `nightly-tests.md`, `status.md`, `gmail.md`, `development-guide.md`, `image-comparer.md`, `support.md` |
| **Reduction** | ~120 lines |
| **Risk** | Low. `setup.md` is referenced from `new-machine-setup.md:940` as the Phase 7 target — keep that anchor valid. |

**Consolidation:**
- The `+claude` account / `~/.netrc` credential setup appears in **five** locations across
  four peer files (`README.md:55-69`, `exceptions.md:65-82` **and** `:133-144`,
  `setup.md:117-146`, `files.md:116-126`) and has drifted (only `setup.md:131` names the
  `Site:Agents` group; only `exceptions.md:71` mentions wiki edit access). Make
  `setup.md#labkey-api-credentials` the single source — **merge `exceptions.md:71` and
  `:73-77` into it first**, then reduce the rest to pointers. `issues.md:67` and
  `files.md:126` already use the pointer pattern but aim at `exceptions.md`; repoint.
- LabKeyMcp repo-layout table is identical (bar one row) at `exceptions.md:38-47` and
  `issues.md:40-49`, with a fuller third copy at `development-guide.md:407-421`. Keep the
  `development-guide.md` copy; pointer the other two.
- `README.md:104-106` delegates setup to `setup.md` and then supplies a **competing**
  32-line registration section (:108-139) — which omits `setup.md:96`'s warning that
  `claude mcp add` strips backslashes. Move the mechanics into `setup.md`; keep only
  "Context Impact" (:141-153) and "Separate Directories" (:155-172) in the README.
- Four architecture diagrams (`README.md:37-53`, `exceptions.md:17-30`, `issues.md:19-32`,
  `nightly-tests.md:68-81`) disagree on the SDK name. Lower priority — each is ~14 lines of
  per-document orientation; if kept, make them agree.

**Accuracy (mechanical):**
- `development-guide.md:409` annotates `server.py` as "one `@mcp.tool()` per public tool";
  the file is 55 lines with **zero** decorators — it calls `register_all_tools(mcp)`.
- `status.md:23` says "three tools" then lists four, and omits **three of seven** —
  including `get_project_status` and `get_context_usage`, which `C:\proj\CLAUDE.md`
  makes mandatory. Fix the count and add all three to the bullet list and "When to Use".
  Do **not** copy the full usage blocks — `:215` already delegates to
  `mcp/StatusMcp/README.md`, which documents them.
- `gmail.md:147-160` — 4 of 12 tool names are wrong (`create_draft`→`draft_email`,
  `list_labels`→`list_email_labels`, `batch_delete`→`batch_delete_emails`), `send_draft`
  has no counterpart, and 8 registered tools are missing. Add a note that this table
  tracks the upstream npx package and must be re-verified on update.
- `README.md:147` says "LabKey MCP (42 tools)"; actual is 50. `README.md:33` lists
  `status.md` inside the LabKey **Data Sources** table; it is already at `:14`.
- `setup.md` omits **MailChimpMcp** entirely (one of five servers). Registration command
  exists at `mcp/MailChimpMcp/README.md:44` — reuse it, but rewrite to the relative-path
  form `setup.md:96` mandates. Config step at `mailchimp.md:46-55`.
- `setup.md:85-90` and `image-comparer.md:43-66` both give a manual build+register path
  superseded by `mcp/ImageComparerMcp/Setup-ImageComparerMcp.ps1`. Point at the script
  (keep manual as fallback). Note `ImageComparerMcp/README.md:88` links *back* to
  `image-comparer.md` as "full architecture" — a bounce to break.
- `issues.md:147` and `support.md:82` call `list_attachments(entity_id=…)`; the parameter
  is `parent_entity_id` (`attachments.py:29-33`). **Both** are wrong — do not point one at
  the other.
- **7 LabKey tools are documented nowhere in `ai/docs`**: `save_daily_failures`,
  `save_run_metrics_csv`, `save_leakcheck_stats`, `get_run_toolsets`,
  `deactivate_computer`, `reactivate_computer`, `current_target`. Add the four nightly ones
  to `nightly-tests.md:291-305`; add a Computer Fleet section (or `docs/mcp/computers.md`,
  matching the `tools/computers.py` boundary) for the other three.
  A further 5 (`analyze_daily_patterns`, `save_daily_summary`, `check_computer_alarms`,
  `list_computer_status`, `save_run_comparison`) *are* documented — in
  `daily-report-guide.md`, not the MCP reference. Add one-line index entries pointing
  there rather than authoring a second copy.
  `docs/skylinetester-guide.md:104` points at `nightly-tests.md` for `save_run_comparison`,
  which does not mention it — repoint.

---

### P4 — Remaining stale facts (low effort, low risk, batchable)

---

#### WI-20 — Stale-fact sweep

| | |
|---|---|
| **Reduction** | ~30 lines |
| **Risk** | Low, with one exception: `developer-setup-guide.md` is **published to the public AIDevSetup wiki** via `/pw-upconfig`, so its errors reach external Cursor/Copilot users. Re-run `/pw-upconfig` after fixing. |

| Defect | Fix |
|---|---|
| `pw-cover.md:21` invokes `pwiz_tools\Skyline\ai\Run-Tests.ps1` — **the whole directory is absent**; :26 of the same file already uses the correct form | `pwsh -File './ai/scripts/Skyline/Run-Tests.ps1' -UseTestList -Coverage` |
| `skylinetester-guide.md:141,144` — same nonexistent path | Drop the code block :139-145; keep the prose and the existing pointer at :152 (`build-and-test-guide.md:224-278` covers it more completely) |
| `skyline-development/SKILL.md:66` advertises `/pw-rcrw` — no such command | `/pw-rules` (**not** `pw-checkrules.md`, a near-miss with different intent) |
| `developer-setup-guide.md:105` advertises `/pw-commit` — no such command (there are 41 commands; the commit ones are `pw-pcommit` / `pw-pcommitfull`) | `/pw-pcommit`. Add a command-name validation step to `/pw-upconfig` |
| `release-management/SKILL.md:75-81` says `/pw-release` is "**Planned**", omits the `daily` type, and points at a "Future Automation" section of `release-guide.md` **that no longer exists** (renamed to §"/pw-release Command" at :1561) | `/pw-release <daily\|complete\|rc\|major\|patch>` + pointer to :1561 |
| `release-guide.md:220-225` shows master's `SKYLINE_YEAR : 25`; live `Jamfile.jam:62` says 26, and the same file says 26 at :43 and documents the bump at :663 | Replace the hardcoded block with a pointer to §"Jamfile.jam Constants" (:40-46) + a note that master's YEAR advances during MAJOR Phase 1 |
| `testing-patterns.md:2118-2120` anchors to "WORKFLOW.md **Workflow 3**: Before Creating PR (Coverage Validation)" — WORKFLOW.md:145 Workflow 3 is "Complete Work and Merge"; workflow-guide.md:307 Workflow 3 is TeamCity validation. Neither concerns coverage | Repoint at `/pw-cover`. **Do NOT collapse `testing-patterns.md:1824-2182` into `build-and-test-guide.md`** — they document different tools (VS dotCover GUI vs `Run-Tests.ps1`/`Analyze-Coverage.ps1`) and :1837 already routes correctly |
| `style-guide.md:811-818` attributes a 7-topic list to `ai/TESTING.md`; those topics are `testing-patterns.md`'s TOC (:4-14) | Repoint to `testing-patterns.md`; delete the duplicated 6-project quick reference at :820-845. **Do not touch `CRITICAL-RULES.md:50-52` or `STYLEGUIDE.md:266-273`** — both are already correct core-brief pointers |
| `pw-leakcheck.md:29-30` labels 10/20 as "default"; script defaults are 5/10 (`Run-Tests.ps1:130,133`). But 10/20 **are** the guide's recommended values (`leak-debugging-guide.md:441,444,475`) | Reword to "(suggested 10)"/"(suggested 20)". **Do NOT renumber to 5/10** — that would downgrade the recommended profiling run |
| `pw-leakcheck.md:54-58` is a truncated 3-row copy of the 4-row table at `leak-debugging-guide.md:509-514` | Delete; point at :504-514 |
| `osprey-development-guide.md:1253-1261` and `:1279-1293` restate the same three Skyline-vs-Osprey deltas (CRLF/LF, Co-Authored-By, 10-line cap); `:1330` routes to `WORKFLOW.md` for commit conventions that now live in `version-control-guide.md` | Merge the three overlapping bullets into the table; repoint :1330 |
| `architecture-data-model.md:446-523` never links `architecture-reporting-layer.md` though that doc links back 3× | Add one bidirectional link. **Do NOT move :454-513** — it is the only documentation of ClusterRole, ClusteredProperties, Clusterer, PCA and ReportColorScheme in the repo |
| `release-cycle-guide.md:156-223` duplicates `release-guide.md` version/tag tables **byte-identically** (:169-174 ≡ :69-74; :202-206 ≡ :1027-1031); :5 and :262 already point at release-guide | Replace with the Quick Reference table (:186-194) + link. **Preserve the Jan-4 worked example at :184** — it exists only there |

---

## 5. Requires the owner's decision

These are not mechanical. Each has a defensible answer either way; picking wrong costs a
second migration.

1. **New docs vs. reuse.** The plan proposes creating four files:
   `docs/pr-report-guide.md` (WI-6), `docs/code-review-guide.md` (WI-7),
   `docs/autonomous-session-guide.md` (WI-8), and possibly `docs/mcp/computers.md` (WI-19).
   The version-control precedent says *reuse existing docs rather than creating new ones* —
   but none of these has a plausible existing home. Confirm all four, or name reuse targets.
2. **Where the save-path rule lives.** `architecture-files.md` is titled *"File Handle
   Architecture: ConnectionPool, Pooled Streams, and FileSaver"* and its nine sections are
   about file handles, not save paths. It is the least-bad existing home, but a new
   `architecture-save-paths.md` may be the honest one. `ai/docs/` has no MCP-integration
   or CommandLine doc today. **Ambiguous — your call.**
3. **Is the night-session doctrine model-agnostic?** Roughly half of
   `night-session/SKILL.md` is posture and investigative doctrine that any LLM could use;
   the other half is Claude Code mechanism (context budget, MCP calls, task chips). If the
   doctrine is genuinely Claude Code-specific, the skill stays large and the >5,000 rule
   gets a documented exemption instead. **This is the one skill where "thin pointer" may
   be the wrong answer.**
4. **`ai/` root policy.** There are 9 `.md` files against a rule saying 6, and two docs
   already contradict each other about it. Decide: do `CLAUDE.md` (226 lines),
   `TOC.md` (205, generated) and `root-CLAUDE.md` (71) get line limits, or are they
   documented exemptions as Claude Code platform files? WI-2 cannot be written without
   this answer.
5. **Member-ordering wording.** The five copies disagree on items 2 and 5: "static public
   methods" / "public methods/properties" vs "static public **interface** methods" /
   "public **interface (instance)** methods and properties". Which is the rule? WI-16
   collapses to one copy and needs the answer.
6. **Workflow numbering.** `WORKFLOW.md` and `workflow-guide.md` both define Workflows 3
   and 4 as *different procedures*. Renumber the guide to match the core file, renumber
   both to a shared scheme, or drop numbers and use names? Numbers are load-free but
   anchors point at them.
7. **Emergency Procedures** (`workflow-guide.md:532-548`) prescribes `hotfix/` and
   `rollback/` branch prefixes that exist in no branch-convention doc, and "merge directly
   to master" against its own protection rule. Is this a real escape hatch to document
   properly, or dead text to delete?
8. **`docs/README.md`'s future.** It is missing 8 of 35 guides and will drift again.
   Generate it from `Generate-TOC.ps1`, or delete it in favor of `TOC.md`?
9. **ryu vs `{:.17}`.** `night-session/SKILL.md:283-286` prescribes "ryu default in Rust";
   `debugging-principles.md:527` prescribes `{:.17}`. A technical contradiction, not a
   documentation one — resolve before WI-8 merges the block.
10. **`scheduled-tasks-guide.md`'s 13 `-Command "&"` occurrences.** Windows Task Scheduler
    action strings may legitimately require `-Command` rather than `-File`. Confirm before
    the WI-4 sweep touches them.
11. **Assignee roster.** Two commands carry disagreeing lists. Confirm the canonical roster
    before WI-8 writes it into `project-context.md`.
12. **`osprey-development/SKILL.md` (9,883 chars, REFACTOR)** was not individually reviewed
    in this audit. It should get the WI-15 treatment, but nobody has verified what in it is
    duplicated vs. unhoused. Schedule a review pass or accept it as-is for now.

---

## 6. Suggested commit sequence

```
1.  WI-1   contradictory/destructive instructions        (P0, no deps)
2.  WI-2   fix the measuring stick                       (needs owner decision 4)
3.  WI-3   add audit-docs.ps1 verifiers
4.  WI-4   & call-operator sweep                         (after WI-3)
5.  WI-5   relative-link normalization                   (after WI-3)
6.  WI-8   rehome orphan knowledge into ai/docs          (needs owner decisions 1,2,3,9,11)
7.  WI-6   create docs/pr-report-guide.md
8.  WI-7   create docs/code-review-guide.md
9.  WI-9   workflow-guide absorbs workflows              (needs owner decisions 6,7)
10. WI-10  version-control-guide absorbs commits/labels
11. WI-11  slim version-control skill + re-scope hook    ** hook + skill in ONE commit **
12. WI-12  daily pipeline: 3 copies -> 1 guide           ** verify a full scheduled run **
13. WI-13  slim pw-pr-* commands
14. WI-14  slim review commands
15. WI-15  slim remaining skills
16. WI-16  core files back under limits                  (needs owner decision 5)
17. WI-17  reachability / index fixes                    (needs owner decision 8)
18. WI-18  MCP: remove deleted-tool instructions
19. WI-19  MCP: consolidate + accuracy
20. WI-20  stale-fact sweep                              ** re-run /pw-upconfig **
```

**Projected end state:** core files ~840/1000 lines (all five under limit); skills+commands
down from 242,029 to roughly 130,000 chars with REFACTOR-tier files reduced from 16 to 1-2;
four new `ai/docs` guides closing the "knowledge only in `ai/claude`" gap; and five new
checks in `audit-docs.ps1` so the next 9 months are measured.
