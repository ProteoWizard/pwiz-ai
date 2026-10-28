# Translation Drafting Guide (Claude-drafted ja / zh-Hans)

How a Claude session drafts Japanese and Chinese (Simplified) translations of ProteoWizard
`.resx` text so that it can go straight to the native-speaker expert reviewers, without a
translation company. The process was established on Osprey's first translation (PR #4752,
`ai/todos/completed/2026/09/TODO-20260928_osprey_resx_translation.md`), and the steps below are written
to apply to any ProteoWizard project.

**Companion guide**: `ai/docs/translation-guide.md` covers the ResourcesOrganizer pipeline
(RESX sync, localization CSVs, import, `LastReleaseResources.db`). That pipeline did not change.
Claude's drafts go into it at the same point a translation company's CSVs used to, so the
reviewers keep the review step they already know.

## Background: what a translation company did

Skyline's translations came from a three-part process: a glossary built from source material,
professional translation, and then review by native-speaker proteomics practitioners. The company
also mediated the reviewers' feedback so that terminology stayed consistent across rounds.
Claude's drafting replaces two parts of that, the draft and the consistency role. Expert review
stays. Every Claude draft is imported marked `Needs Review:` and has not been reviewed until a
native speaker has looked at it.

## Why there is more to translate now

For most of ProteoWizard's history, only the C# applications were localized: Skyline and its
satellite tools. The rest of pwiz was C++ (the msconvert family, the vendor-reader layer, and
BiblioSpec), and we chose not to localize C++. BiblioSpec is mostly a Skyline tool, yet its
error messages reached Skyline users in English, because there was no RESX layer to put them in.

The move to .NET 10 changed that. PR #4658 (2026-10-07) retired the C++ tree; `pwiz/` and the
`pwiz_tools` command-line tools are now C#. Text that could not be localized before can now use
the same RESX / ResourcesOrganizer / satellite-assembly pipeline as Skyline. Projects that are
now in C# but have no RESX yet, as of 2026-10-16:

| Project | Notes |
|---|---|
| `pwiz_tools/BiblioSpec` (BlibBuild, BlibFilter, BlibSearch, BlibToMs2) | 0 `.resx`. Its errors surface in Skyline's library build, so it is the most visible gap for ja / zh users |
| `pwiz_tools/Commandline` (msconvert, msdiff, ...) and the `pwiz/` library | 0 `.resx` |
| `pwiz_tools/CarafeSharp`, `pwiz_tools/BullseyeSharp` | New C# ports; CarafeSharp has 1 `.resx`, BullseyeSharp has none |

Osprey is the first of these to be translated (RESX in PR #4721, ja / zh-Hans drafts in #4752).
Its two TODOs (listed under Related) are the record for moving a project's text into RESX and
then translating it.

Each newly translated project takes two pieces of work, in this order:

1. **Move the text to RESX** and decide what stays English. Text for a person is resourced: log
   lines, errors a user can fix, help. Text for a program stays English: file contents, column
   names, machine-parsed log tags, developer diagnostics. This step also splits the culture:
   person-facing text formats numbers in the current culture, file output in the invariant
   culture. Follow `TODO-20260926_osprey_resx.md`, which copies Skyline's patterns.
2. **Draft the translations** with the procedure below.

Before translating a library such as `pwiz/` or BiblioSpec, check where its messages are read.
Text that only reaches Skyline through an exception message is a different case from a
command-line tool's own console output.

**The tooling is still Skyline-shaped.** ResourcesOrganizer scans `pwiz_tools` minus a hardcoded
exclude list (MSConvertGUI and SeeMS are excluded, and the `pwiz/` library is never scanned). Its
single baseline db follows Skyline's release, and its quickbuild entry points were removed with
the Jamfiles. Generalizing it to an opt-in set of projects is tracked in
`ai/todos/backlog/TODO-pwiz_translation_expansion.md`.

## Open question: will reviewers accept Claude drafts?

The answer is not known yet. Skyline's reviewers have always started from a professional
translation company's draft, and they may push back on Claude drafts and want the company back.
The measurements in "Evidence so far" cover consistency and closeness to past finals. They do not
measure whether a reviewer would accept a Claude draft. The first real test is the Osprey reviewer CSVs
and the blind A/B grading sheets. Record the outcome in the expansion TODO.

Either answer leaves the pipeline as it is. The company's deliverable and Claude's are the same
localization CSVs, and the glossary, style guide, consistency checks and gates apply to both. The
answer (possibly different for ja and zh) decides who writes the first draft. Do not describe
Claude drafting as the settled process until the reviewers have answered.

## Evidence so far (2026-09-28 Osprey session)

These are the first measurements, taken before any reviewer has seen a Claude draft. They inform
the open question above but do not answer it.

### What the past rounds say about the reviewers

The translation archive holds both the professional company's pre-review draft and the reviewed
final for Skyline's 24.1 and 25.1 rounds:

| | ja | zh |
|---|---|---|
| holdout strings (24.1 + 25.1) | 520 | 521 |
| professional drafts the reviewers changed | 116 (22%) | 24 (5%); none of 193 in 25.1 |
| kind of change | mostly terminology (`カウント` for "Count" columns, `保持時間アラインメント`) | mostly mechanical (full-width `：`, `…`, the measure word `个`, an English word left in) |

The two reviewers work differently. The ja reviewer rewrites terms. The zh reviewer mostly
accepts the draft and fixes punctuation. An answer to the open question may differ by language.

### Blind holdout evaluation

Two blind subagents (Opus 5.5, one per language) translated the holdout English. They had only
the glossary, the style guide and a translation memory with every holdout string removed. Each
draft was scored against the reviewed final, and the professional draft was scored the same
way. Session record: `TODO-20260928_osprey_resx_translation.md`, "Evaluation results".

| measure | ja Claude | ja pro | ja final | zh Claude | zh pro | zh final |
|---|---|---|---|---|---|---|
| exact match with reviewed final | 124/520 (23.8%) | 404/520 (77.7%) | - | 146/521 (28.0%) | 497/521 (95.4%) | - |
| mean character similarity to final | 0.792 | 0.957 | 1.000 | 0.765 | 0.990 | 1.000 |
| placeholder set differs from English | 0 | 0 | 0 | 0 | 0 | 0 |
| glossary term rendered as in glossary | 95.8% | 94.0% | 93.5% | 95.4% | 93.0% | 93.2% |
| style-guide checks passed | 99.9% | 98.1% | 99.0% | 100% | 98.1% | 97.7% |

On the strings the reviewers changed, did Claude anticipate the reviewer's edit?

| | ja (116 changed) | zh (24 changed) |
|---|---|---|
| Claude draft == reviewed final | 3 | 9 |
| Claude closer to the final than the professional draft was | 18 | 11 |

Claude's confidence ratings tracked the outcome:

| confidence | ja exact / similarity | zh exact / similarity |
|---|---|---|
| high | 26.8% / 0.819 (426 strings) | 32.6% / 0.799 (411 strings) |
| medium | 10.6% / 0.670 (94) | 9.5% / 0.640 (105) |

How to read these numbers:

- **Exact match favors the professional draft by construction.** Each final was produced by
  editing that draft, so any acceptable professional wording survives word for word, and an
  equally acceptable Claude wording counts as a miss. For zh, where reviewers changed 5% of
  drafts, the 95% professional score mostly reflects that the reviewers accepted the drafts.
- **On consistency, Claude beat both the professional draft and the reviewed final.** That is the
  job the company's project management used to do.
- **Claude anticipated the mechanical edits** (zh: 9 of 24 exact) but rarely the terminology
  edits (ja: 3 of 116).
- **The finals contain errors that Claude avoided**: ja "standard error" rendered `標準エラー`
  ("error message") where `標準誤差` is the statistical term; stray spaces after `エラー：`;
  the product name Carafe transliterated `カラフ`.
- **Claude's systematic miss**: it expands terse labels and column names into descriptions
  ("Apex Analyte Ion Count" -> `ピーク頂点時のアナライトイオン数`, where the final is
  `頂点アナライトイオンカウント`). The brief rule in "Drafting procedure" came from this.
- The glossary was built from a corpus that included the holdout English (about 5% of it), which
  slightly favors Claude on glossary conformance.

### The Osprey drafts (not yet reviewed)

| | ja | zh-Hans |
|---|---|---|
| strings drafted | 812 | 812 |
| confidence high / medium / low | 719 / 92 / 1 | 684 / 102 / 26 |
| glossary conformance after the consistency pass | 96.0% | 98.2% |
| hard failures (placeholders, prefixes, leaked English) | 0 | 0 |

All 26 low-confidence zh strings involve three Osprey-only terms with no reviewed precedent
(entrapment, peak co-assignment, calibrator). For comparison, the same consistency checker run
over Skyline's reviewed corpus found 125 cases of one English string with different
translations.

### What would answer the question

The blind A/B grading sheets: 40 holdout pairs per language, half of them from strings the
reviewers changed. Claude and professional drafts are shown unlabeled, graded "accept / minor
edit / wrong", with a preference column. Add the reviewers' edit rate on the Osprey drafts once
they review them. Until those results exist, Claude drafts are first drafts that need expert
review, and the company remains a live option.

## Languages

Japanese (`ja`) and Chinese Simplified (`zh-Hans`) only. ProteoWizard never translates to a
European language. `fr-FR` and `tr-TR` are **test cultures**: tests run under them to catch
culture-sensitive number formatting while the UI stays English.

RESX satellites on master are `.ja.resx` / `.zh-Hans.resx`. The `zh-CHS` to `zh-Hans` rename
reached the RESX files, ResourcesOrganizer and `LastReleaseResources.db` in PR #4758. Tutorial
HTML folders are still `zh-CHS` (`Documentation/Tutorials/<Name>/zh-CHS/`).

## Shared assets (checked into pwiz)

`pwiz_tools/Shared/Translation/` serves all projects:

- **`glossary.tsv`**: `en | ja | zh-Hans | status | evidence | conflicts | note`.
  `status = reviewed` records what Skyline's reviewers settled on, with counts. Follow those
  rows even where the term is not literal (for example zh `划定` for "imputation", `耐受性` for
  "tolerance", `编号` for "accession"; ja `単離ウィンドウ`, `Q値`). `status = new` marks a first
  proposal for a term Skyline never translated. Use it for consistency, and flag it to the
  reviewers for a decision.
- **`style-guide.md`**: punctuation, spacing, quoting and sentence patterns, each with the share
  of reviewed Skyline values that follow it. It is derived from the corpus, not invented. Where
  reviewers split, it names the minority so that a reviewer can overturn a rule knowingly.

Treat both files as living documents. When reviewers change a term, record their choice in the
glossary in the same change that imports their edits. That keeps the glossary the authority on
consistency, the role the translation company used to fill.

## Evidence sources

| Source | What it gives | How to read it |
|---|---|---|
| Every `X.resx` with `X.ja.resx` / `X.zh-Hans.resx`, form text members included | ~9,900 ja / ~10,000 zh reviewed English->translation pairs (UI labels, messages) | Parse each resx pair by key; skip values equal to the English |
| Tutorial HTML `Tutorials/<Name>/{en,ja,zh-CHS}/index.html` | ~3,900 aligned paragraphs per language of domain prose: how practitioners write MS terms in running text | Align by XPath, as `DevTools/TutorialLocalization` does (`<lang>/invariant.html` vs `<lang>/index.html`); use its output, do not re-align HTML |
| `pwiz_tools/Skyline/Translation/LastReleaseResources.db` | What changed since the last release | ResourcesOrganizer, see translation-guide.md |
| Translation archive (outside the repo; ask Brendan) | The company's original glossaries, term bases, `.tmx` TMs, style-guide fragments, and translator-draft vs reviewed sheets for past rounds | Reviewed RESX values outrank the archive glossaries, because they are newer and reviewer-edited |

Skyline's reviewed values still contain inconsistencies: a consistency check found 125 cases of
one English string with different translations. Use majority evidence, and do not copy a single
match without checking it.

## Before translating: make the English safe to translate

Do these first. A translation of English that is not safe to translate has to be redone.

1. **Anything the user types goes in as a `{N}` argument**: command-line flags, `--task` values,
   file extensions and patterns, column and metadata names, cvParam accessions, build commands.
   Translators, human or Claude, cannot tell that a token is literal. In Skyline, 4 of 76 ja
   and 25 of 76 zh values that name a flag lost the flag or translated it (backlog:
   `ai/todos/backlog/TODO-skyline_resx_argument_text.md`). Take the text from the declaration
   (`ARG_X.ArgumentText`, task-name constants, `EXT` constants). Osprey enforces this with
   `CodeInspectionTest.TestArgumentTextComesFromArguments`.
2. **No sentence assembled from fragments.** A resource such as `"{0} and {1}"` that joins
   other values cannot be translated correctly. Write one whole-sentence resource per shape
   instead (`"{0} requires {1}."` and `"{0} requires {1} and {2}."`).
3. **Placeholders must mean one thing.** A count, a name and a method in the same `{0}` position
   lead translators to attach a counter word to a name (Osprey: `Generating {0} decoys...`, where
   `{0}` was the decoy method). Read the call site.
4. **Singular and plural are separate resources** (`CountText`). Translate both, even where
   ja/zh give them the same form.
5. **No hardcoded punctuation appended in code.** Osprey's `ProgressReporter` appended `...`, so
   zh could not use `…`. Put the ellipsis in a `{0}...` resource.
6. **HTML or help-page prose comes from resources too**, with markup, flags and file names
   passed as arguments (Osprey `CommandLine.html`, following Skyline's translated help page).

## Drafting procedure

1. **Inventory** the resources to translate: file, key, English, comment, and any exact reviewed
   translation of the identical English already in the corpus (translation memory). Usually only
   a few strings match exactly. The corpus mostly contributes terms and phrasing.
2. **Extend the glossary** with the project's domain n-grams that are not yet covered. For each
   term, find its renderings in the corpus and tutorials, choose the dominant reviewed form, and
   record the counts as evidence. Mark the project's own terms `new`.
3. **Write a translator brief** (one page): what the product is, who reads the text and where
   (console log scanned by eye, dialog, help), the kinds of strings (progress lines, summaries,
   errors with a remedy, enum labels, help descriptions), domain vocabulary with meanings, and
   a "never translate" list. Include this lesson from the evaluation: **keep labels, column
   names, enum and feature names terse and noun-stacked like the English, and never expand them
   into descriptions.**
4. **One drafting subagent per language**, both working from the same inputs (inventory, brief,
   glossary, style guide, the project's user-facing-text rules, and the corpus TSV to search).
   Give each subagent read-only access to the source, so it can look up a key's call site to see
   what fills each `{N}` and whether the string is a heading, a log line or a fragment. Ask for
   output as a TSV `file | key | en | <lang> | confidence | note`, written in batches of about 50,
   with `confidence` = high / medium / low. Read confidence as "would a native-speaker reviewer
   accept this unchanged?". A note is required when confidence is not high or when a `new`
   glossary term carries the meaning. Rules to state in the prompt:
   - Every placeholder and format item (`{1:N0}`, `{2:P1}`) is kept exactly. The order may change;
     the set may not. Literal text such as the `%` in `{2:F1}%` stays.
   - Leading and trailing whitespace and the number of line breaks match the English, because
     column-aligned help depends on them.
   - Leading `Error:` / `Warning:` becomes exactly `エラー：` / `警告：` (ja) or `错误：` / `警告：`
     (zh). Code matches these prefixes (`CommandStatusWriter.ERROR_PREFIXES`).
   - The same English gets the same translation everywhere, unless the note explains why not.
   - The subagent verifies its own output with a script before finishing: row count, key/English
     identical to the inventory, placeholder sets, line-break counts, no empty values.
5. **Consistency pass (coordinator)**, the job the translation company used to do: hard failures
   (placeholders, prefixes, leaked English), the same English translated differently, and glossary
   conformance per term. Read every remaining glossary miss. Most are legitimate other senses of
   a word (verb "run" vs an acquisition "run"; "score" as a verb), and only some are errors.
6. **Import through the real pipeline.** Convert the TSVs to `localization.ja.csv` /
   `localization.zh-Hans.csv` with `Issue = New resource` and run `ImportLocalizationCsvFiles`
   (translation-guide.md). Every entry then carries `Needs Review:New resource`, the same state
   as any unreviewed Skyline string. Do not hand-write `.ja.resx` files.
7. **Read the product's output in each language**, end to end (Osprey: `regression.ps1 -Culture ja`
   and `-Culture zh-Hans`, then the whole log and `--help`). This finds problems a table check
   cannot, such as wrong placeholder semantics, a dangling clause, or a space next to a localized
   value.

## Gates and guards

- **A localized-resources test** in the style of Skyline's `TestData/LocalizedResourcesTest.cs`
  (Osprey: `Osprey.Test/OspreyLocalizedResourcesTest.cs`). It checks only translations that exist:
  - format-item sets match the English;
  - error/warning prefix detection agrees with the English;
  - **orphans fail**: a ja/zh key whose English key is gone. A developer who removes or renames a
    key deletes its translations in the same change;
  - a non-vacuous guard fails if no translation was checked at all.

  **Missing translations do not fail** (Brendan): requiring completeness would put a translation
  burden on every developer, and Skyline lets the English grow ahead of translation.
- **Unit tests under `ja-JP`, `zh-CN` and `fr-FR`** as well as `en-US`. The first real satellites
  expose every test that asserts English text (see "Translation-Proof Testing" in
  `ai/MEMORY.md`). Osprey: `Build-Osprey.ps1 -RunTests -Culture ja-JP`.
- **No UTF-8 BOM in source files.** Python scripts that patch source must not write
  `utf-8-sig`, and .NET writers must not use `Encoding.UTF8` for source files. Osprey's
  `CodeInspectionTest.TestNoUtf8Bom` / `TestNoBomWritingEncoding` mirror Skyline's inspection.
- **Console output**: CJK text needs UTF-8 console encoding, and help-text wrapping must measure
  East Asian wide characters as two columns (Osprey `ConsoleTable.DisplayWidth`).

## Reviewer package

Reviewers work in the translation company's CSV format, not a new tool. Run the stock
`GenerateLocalizationCsvFiles` and filter it to the project. Keep the standard columns
(Name, English, Translation, Issue, FileCount/File) first, so that a returned file imports
unchanged. After them, add `Claude confidence`, `Claude note` and `Glossary terms`, and sort
low -> medium -> high. Check coverage before sending: every resource whose draft differs from the
English appears in the CSV.

## Pipeline facts learned the hard way

- `ExportResx` drops a "New resource" entry whose value equals the English, so deliberately
  identical strings (product names, `ppm`) import with an empty Issue.
- `IncrementalUpdateResxFiles` / `FinalizeResxFiles` revert any translation that is not in
  `LastReleaseResources.db`. Osprey is therefore excluded from them (`EXTRA_EXCLUDE` in
  `UpdateResxFiles.bat`) until a release adds Osprey to the baseline. Exclude a new project the
  same way before its first drafted round.
- Until a project is in `LastReleaseResources.db`, nothing flags a translation whose English has
  changed. When the English under an already-translated key changes, re-draft that key in the
  same change.
- After a merge that moves or renames keys, carry the drafts to the new keys through the pipeline
  import. Never edit satellites by hand.
- Run the import on a clean tree and check `git status`: anything outside the expected
  satellites is churn to revert.

## Scripts

`ai/scripts/Translation/` holds the scripts for every step above: corpus and tutorial
alignment, inventory, term evidence, style statistics, the consistency validator, the CSV
converter, the reviewer package, the blind evaluation, and the translator brief and drafting
prompt templates. See its README.md. Archive-derived data is not kept in pwiz-ai, because the
repo is public.

## Related

- `ai/docs/translation-guide.md`: ResourcesOrganizer pipeline
- `pwiz_tools/Shared/Translation/`: glossary and style guide
- `pwiz_tools/Osprey/docs/21-user-facing-text.md` ("Resources"): rules for writing
  English that is safe to translate, with Osprey's guards
- `ai/todos/completed/2026/09/TODO-20260926_osprey_resx.md`: moving a project's text to RESX
  (scope, culture split, enforcement), following Skyline
- `ai/todos/completed/2026/09/TODO-20260928_osprey_resx_translation.md`: the full record of the first round
- `ai/todos/completed/2026/09/TODO-20260929_translation_tooling_zh_hans.md`: the zh-Hans tooling migration
- `ai/todos/backlog/TODO-pwiz_translation_expansion.md`: tooling for all of pwiz, target projects,
  and where the reviewer-acceptance result gets recorded
