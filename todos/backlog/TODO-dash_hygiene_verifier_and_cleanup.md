# TODO-dash_hygiene_verifier_and_cleanup.md -- Dash hygiene: verifier + cleanup (Unicode dashes and ASCII "--" in comments)

> **Status: BACKLOG / PLAN ONLY.** No code cleanup has been executed. This file
> is the plan. Date it and move to active/ when started (per the dated-active
> TODO lifecycle).

## Motivation
We already have a rule (CRITICAL-RULES.md + STYLEGUIDE.md) saying "never use
Unicode em/en dashes; use a single ASCII hyphen". Yet an audit on 2026-06-15
found the rule has silently drifted, and a related LLM habit has crept in:

- **139 Unicode em/en dashes** (U+2014 / U+2013) across 37 OspreySharp files.
- **235 ASCII " -- "** (double hyphen used as an em-dash substitute) in comments
  across 59 OspreySharp files.

Neither is caught by any verifier: ReSharper inspection passes clean and
`fix-crlf.ps1` only normalizes line endings. This is the exact failure CRITICAL-
RULES.md warns about ("when a rule's verifier is weak, the rule will drift;
strengthen the verifier rather than the wording"). It surfaced when a literal
" -- " inside an XML comment in Directory.Build.props broke the OspreySharp build
(a `--` is a parse error inside `<!-- -->`). The "--" habit is an LLM tell;
humans write a single "-".

STYLEGUIDE.md was clarified on 2026-06-15 to ban both forms (the edit is in the
ai/ working tree, currently UNCOMMITTED -- commit it alongside this work).

## CRITICAL design constraint: "--" is heavily used in legitimate code
Any verifier or cleanup MUST NOT touch legitimate `--`. False-positive sources:
1. **CLI flag references** in comments AND in error/help strings: `--task`,
   `--library`, `--decoys-in-library`, `--work-dir`, etc. e.g. an error message
   `"expected --library"` or a comment `// see --task FirstJoin` is correct and
   must be left alone. **(Brendan flagged this explicitly.)**
2. **C# decrement operator**: `i--`, `--count`.
3. **Bare POSIX argument separator** `--` if ever referenced in help text.
4. **Domain-required Unicode**: .resx, translation files, and test data may carry
   legitimate non-ASCII (including dashes) on purpose -- exclude those paths from
   the Unicode-dash auto-fix.

Distinguishing feature for the em-dash-substitute habit: it is **" -- "
space-padded on both sides**, used as prose punctuation, NOT `--word` (a flag) and
NOT `x--` (operator). The audit's 235 count used the space-padded ` -- ` pattern in
comment lines, so it already excludes `--flag` and the operator -- but the
verifier/cleanup must still re-confirm per occurrence (e.g. CLI help text could
contain a space-padded `--`, and a comment could legitimately quote `foo -- bar`
POSIX usage).

## Proposed approach (verifier-first)
1. **Verifier** -- extend the existing `fix-crlf.ps1` (already runs in the build
   gate and already scans modified files) OR add a sibling check script:
   - **Unicode em/en dashes**: auto-replace with `-` in .cs (and .ps1/.jam/.props
     comments), EXCLUDING domain-exception paths (.resx, translation TSVs, test
     data dirs). Deterministic and safe; spot-check the diff.
   - **ASCII " -- " in comments**: **FLAG, do not auto-fix.** Emit a file:line
     list for manual review, because distinguishing prose-dash from a CLI-help /
     operator / separator occurrence needs human eyes (the constraint above).
     Auto-fix here would risk corrupting flag references.
   - Wire it into `Build-OspreySharp.ps1` / `build.ps1` and TeamCity so the rule
     stops drifting. Decide: warn-only first, or hard-fail once clean.
2. **Cleanup** -- only after the verifier exists, sweep until green:
   - Unicode: apply the auto-fix, review the diff.
   - " -- ": fix each by hand (usually -> single "-" or restructure the sentence;
     leave CLI-flag/operator/separator occurrences untouched).
   - Gate the cleanup the normal OspreySharp way (Build + RunInspection + RunTests;
     regression is unaffected -- comment/string-punctuation-only changes, but run
     it if any error-message string text changes).

## Scope (decide when started)
- **OspreySharp first** (the Claude-heaviest tree; 374 known violations; where this
  surfaced).
- **Full pwiz (Skyline) as a follow-on** -- run a full-repo audit first (delegate a
  background agent to count Unicode dashes + space-padded " -- " in comments across
  pwiz, excluding the domain-exception paths) to size it before committing.
- Design the verifier reusable so it can extend to the whole repo.

## Open questions
- Auto-fix vs flag-only for " -- " (plan says flag-only; confirm).
- Build gate: warn-only initially, or hard-fail once the tree is clean?
- Exact domain-exception path list for the Unicode auto-fix (.resx, translations,
  test data -- enumerate).
- Where the STYLEGUIDE.md clarification (already edited, uncommitted) lands -- fold
  into this work's PR, or commit separately to ai/ now.

## Related
- Memory: [[feedback_tests_assert_whole_constants]] (substring-vs-constant test
  assertions; same family of "don't hardcode fragile strings" hygiene).
- CRITICAL-RULES.md "Trust comes from verifiers" principle.
