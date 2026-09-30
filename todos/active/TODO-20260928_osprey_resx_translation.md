# TODO-20260928_osprey_resx_translation.md - Claude-drafted ja / zh-Hans translations of Osprey, straight to expert review

## Branch Information
- **Branch**: `Skyline/work/20260928_osprey_resx_translation` (checkout `C:\proj\pwiz-work1`;
  created at `de1bbf1e33`, the port-branch tip, and pushed 2026-09-28)
- **Base**: `Skyline/work/20260612_net8_port` (the RESX PR #4721 merged into it 2026-09-28)
- **Module**: `osprey`
- **Created**: 2026-09-26 (Brendan's request at the end of the RESX session); started 2026-09-28
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: (pending)

## The question this answers
Skyline's translations came out of a rigorous process: glossary generated from source material,
professional translation, then expert review by native-speaker practitioners, with the translation
company mediating feedback for consistency. Can Claude produce the first draft AND hold overall
consistency itself, so Osprey goes straight to the expert review phase with no translation company?
The work is only half the deliverable; the other half is evidence for or against that claim.

## Decisions (Brendan, 2026-09-28)
- Glossary + style guide location: `pwiz_tools/Shared/Translation/` (shared with Skyline).
- The translation company's original glossary / style guide exists outside the repo; Brendan
  will provide it (location pending). Use it as an input to step 1, not a replacement for the
  corpus evidence - reviewer edits in the RESX outrank it.
- Reviewers review in the translation company's CSV format (`localization.ja.csv` /
  `localization.zh-CHS.csv`), not a new Artifact. Step 8 extends that CSV (notes / confidence /
  glossary-term columns) rather than inventing a new surface.

## Inputs (all in the pwiz tree)
1. **Skyline RESX pairs** - every `X.resx` with `X.ja.resx` / `X.zh-Hans.resx` beside it. Measured
   2026-09-26: 7,225 ja and 7,236 zh-Hans English->translation pairs (script:
   `ai/.tmp/sessions/20260926-resx/seed_translations.py` builds the map; exact matches were already
   seeded into Osprey). These are post-review FINAL values.
2. **Tutorial HTML** - `pwiz_tools/Skyline/Documentation/Tutorials/<Name>/{en,ja,zh-CHS}/index.html`;
   16 of 33 tutorials are translated. Paragraph-aligned domain prose - the richest source of how
   practitioners render proteomics / MS terms in running text (not just UI labels). Note the
   tutorials still use `zh-CHS`; the port-branch RESX uses `zh-Hans`.
3. **`pwiz_tools/Skyline/Translation/LastReleaseResources.db`** and the ResourcesOrganizer
   (`pwiz_tools/Skyline/Executables/DevTools/ResourcesOrganizer`) - the pipeline the translation
   company's CSVs go through; `ai/docs/translation-guide.md` documents it, including "Reviewing
   translated CSVs: reviewer term changes are deliberate" (e.g. the zh-CHS reviewer's non-literal
   term for "imputation") - the glossary must record the REVIEWER's choice, not the literal one.
3a. **Nick Shulman's DevTools in `pwiz_tools/Skyline/Executables/DevTools` - learn from and reuse
   them before writing anything (Brendan, 2026-09-26).** They already reduced the translation
   company's job from RESX files to CSVs of English + translation:
   - `ResourcesOrganizer` (README.md there; Jamfile targets `GenerateLocalizationCsvFiles`,
     `ImportLocalizationCsvFiles`, `FinalizeResxFiles`): reads every .resx into a SQLite db, emits
     `localization.ja.csv` / `localization.zh-CHS.csv` with columns Name, English, Translation,
     Issue ("English text changed", "Inconsistent translation" - its own consistency checks), and
     FileCount/File, consolidating identical English across files into one row. Claude's output
     should be exactly these CSVs filled in, imported with `ImportLocalizationCsvFiles`; the
     `Issue` column and the consolidation are free consistency signals. Its db
     (`LastReleaseResources.db`) also answers "what was added since the last release" for the
     holdout evaluation in step 7.
   - `TutorialLocalization` (`TutorialLocalizer.cs`, `LocalizationRecord.cs`): aligns each
     tutorial's English and localized HTML element by element (XPath, via the `invariant.html`
     in each language folder) into records of TutorialName, XPath, English, Localized,
     OriginalEnglish. That is the tutorial parallel corpus for input 2, already aligned - use its
     output rather than re-aligning HTML.
   - Also there: `NormalizeResxWhitespace`, `SortRESX`, `AssortResources` - check before writing
     any resx post-processing.
4. **Git history of the `.ja.resx` / `.zh-*.resx` files** - translation-import commits followed by
   reviewer-edit commits may separate the translator's draft from the expert's final. If they do,
   that is the ground truth for the evaluation below.
5. Ask Brendan: does the translation company's original glossary / style guide exist outside the
   repo? Who are the ja and zh expert reviewers, and in what form do they want to review?

## Plan
1. **Glossary / term base.** Mine the English side of Osprey's 797 resources (and Skyline's) for
   domain terms and n-grams (precursor, precursor candidate, fragment, transition, peak, peak
   boundary, retention time, isolation window, spectral library, decoy, target, FDR, q-value, PEP,
   calibration, cross-run reconciliation, imputation, chromatogram, run, replicate, ...). For each,
   find its renderings in inputs 1-2, choose the dominant reviewed form, and record the evidence.
   Output a checked-in TSV: `en | ja | zh-Hans | evidence (resource keys / tutorial + section) |
   conflicts | note`. Flag terms Osprey introduces that Skyline never translated ("intermediate
   file", "precursor candidate peaks", task names) - those need the reviewers' first decision.
   Location to decide with Brendan (proposal: `pwiz_tools/Shared/Translation/glossary.tsv`, so
   Skyline's next round can use it too).
2. **Style guide, derived not invented.** From the same corpus: punctuation (full-width colon
   after the `エラー：` / `错误：` prefixes, sentence-final 。), spacing between CJK and Latin text,
   katakana vs kanji preferences, how UI verbs and button names are rendered, how `{0}` placeholders
   sit in sentences. Checked in beside the glossary.
3. **Translation memory.** Exact matches are seeded already; add fuzzy matches (same sentence with
   a different number or file name) as starting points.
4. **Before translating, finish the deferred RESX item**: CLI flags, `--task` values and file
   extensions still inline in some English resources (`--decoys-in-library`, `--parallel-files`,
   `--task PerFileScoring`, `.spectra.bin`) must become `{N}` arguments, or translators - human or
   Claude - may translate a token the user has to type. Measured in Skyline: of 76 translated resources
   that name a flag, 4 ja and 25 zh-Hans lost or translated it (`TODO-skyline_resx_argument_text.md`).
   In the same step, replace the 11 `"--flag"` literals in 2 Osprey.Test files with the typed
   `OspreyCommandArgs.ARG_*` instances and add a CodeInspectionTest guard for them.
5. **Translate** all Osprey resources to ja and zh-Hans with glossary + style guide + TM in
   context, batched by file so related messages stay consistent. Keep placeholders, format
   specifiers and verbatim tokens identical. Emit in the translation company's CSV format
   (`localization.ja.csv`, `localization.zh-CHS.csv` - check the import script's expected names)
   and import through `ImportLocalizationCsvFiles`, so the reviewers' step is unchanged. Mark
   low-confidence strings for the reviewer rather than guessing silently.
6. **Mechanical validation**: an Osprey test (Skyline's `LocalizedResourcesTest` analog) that
   every translated value has the same placeholder set as the English and no English left in it
   by accident; the translated `Error:` prefix still matches `CommandStatusWriter.ERROR_PREFIXES`
   (test exists); a glossary-conformance check (every glossary term in an English value appears
   in its required rendering); unit tests under ja-JP; a Stellar run with `--culture ja` and
   `--culture zh-Hans`, reading the whole log and `--help`.
7. **Evaluation - the actual question.** Hold out the strings added to Skyline in the last
   release (their reviewed translations exist), rebuild the glossary without them, have Claude
   translate them, and compare with the reviewed finals: exact-match rate, glossary conformance,
   and - if git history gives the translator's pre-review draft - how many reviewer edits Claude's
   draft would have needed versus the professional draft. Offer the reviewers a blind sample
   (Claude vs professional draft) to grade. Report the numbers, not an impression.
8. **Reviewer package**: English, proposed ja/zh, glossary terms used, confidence and notes per
   string, in a form the reviewers can comment on (an Artifact with shared state is a candidate) -
   and a way to fold their changes back into both the RESX and the glossary, so the glossary
   becomes the consistency authority the translation company used to be.

## Acceptance
- Glossary + style guide checked in with evidence per term; Osprey `.ja.resx` / `.zh-Hans.resx`
  complete; placeholder / conformance tests green; unit tests green under ja-JP; Stellar logs in ja
  and zh-Hans read end to end.
- An evaluation write-up with the holdout numbers, sent to Brendan with the reviewer package.

## Progress

**2026-09-28** (Brendan away for the afternoon; autonomous, decisions recorded here)
- Branch created in `C:\proj\pwiz-work1` at `de1bbf1e33` (port-branch tip, #4721 merged) and pushed.
- **Correction to this TODO**: the "exact matches were already seeded" claim is stale - `42586e94f2`
  removed the sparse seed files (Brendan: first Osprey translation is its own PR with full files).
  Osprey now has 812 resources in 8 `.resx` (the 797/6 figure predates `OspreyCommandArgUsage.resx`);
  only ~10 of them have an exact reviewed match anywhere in Skyline, so the TM contributes terms
  and phrasing, not whole strings.
- **Inputs gathered** (session folder `ai/.tmp/sessions/20260928-resxtr/`, not committed):
  - Brendan's two glossaries (ja 72177 2014-01, zh summary 2014-05) plus, from `G:\My Drive\Localization`:
    the ja Term Base 2016-04 (latest + Yasushi's edits), the zh glossary 2014-05-23 final-reviewed and
    2014-06-03, three zh reviewer-marked glossaries, the Acclaro zh style guide (a tutorial template;
    only its numerals / spacing rules survive text recovery), LS and Dynamic Language review
    instructions, ja/zh `.tmx` TMs, and the translator-draft vs reviewed rounds for 24.1 and 25.1.
    `archive/` + `extract_archive.py` (xlsx/xls/docx -> tsv/txt).
  - RESX corpus: every Skyline `X.resx` / `.ja.resx` / `.zh-Hans.resx` pair, including form text
    members: 9,888 ja and 10,058 zh reviewed pairs (`corpus.py` -> `corpus-resx.tsv`).
  - Tutorial corpus: 3,923 ja / 3,894 zh aligned paragraphs (`tutorial_corpus.py`), aligned exactly
    as `DevTools/TutorialLocalization` does (`<lang>/invariant.html` vs `<lang>/index.html` by XPath).
- **Port-branch pipeline defects found** (the translation tooling had not been run since the .NET 10
  retarget):
  - `TutorialLocalization/Jamfile.jam`: `msbuild` without `/restore` fails NETSDK1004 since the project
    gained a PackageReference - FIXED (added `/restore`). The tool then still dies at run time:
    `lib\CsvHelper.dll` needs `Microsoft.Bcl.HashCode`, absent from the net10 output - NOT fixed here
    (DevTools packaging; the aligner was re-implemented in the session script instead).
  - ResourcesOrganizer `GenerateLocalizationCsvFiles.bat` / `ImportLocalizationCsvFiles.bat` hardcode
    `zh-CHS`; the tool names output files after that string, so on the port branch the import would
    create new `*.zh-CHS.resx` beside the real `*.zh-Hans.resx` - FIXED to `zh-Hans` (CSV name becomes
    `localization.zh-Hans.csv`). `UpdateResxFiles.bat` and `LastReleaseResources.db` (whose Chinese
    rows are keyed `zh-CHS`) are NOT changed: migrating the release baseline belongs to the next
    Skyline translation round - follow-up for Brendan.
  - Five non-Skyline tool resx still named `.zh-CHS.resx` (SkylineBatch, MPPExport, SProCoP, SkyGadget,
    Turnover); untouched.
- **Glossary + style guide drafted** in `pwiz_tools/Shared/Translation/` (`glossary.tsv`,
  `style-guide.md`): ~150 terms, each with ja / zh-Hans, `reviewed` (Skyline's reviewers settled it,
  with counts) or `new` (first proposal for an Osprey-only term), conflicts and notes. Derived rules
  with measured shares (e.g. ja `「{0}」` 93%, zh `“{0}”` 85%; zh spaces CJK<->Latin 3,367:58, ja does
  not 3,784:32; `エラー：`/`错误：` 163/163). Reviewer choices kept even where non-literal: zh
  `耐受性` for tolerance (24/24), `划定` for imputation, `编号` for accession; ja `単離ウィンドウ`,
  `繰り返し測定`, `Q値`. Decision: acquisition "run" = ja `ラン` (tutorial usage), Osprey invocation =
  `実行`; zh `运行` for both. Osprey-only terms flagged low-confidence for the reviewers:
  reconciliation, peak co-assignment, entrapment, calibrator, fold.
- **Step 4 delegated** to a subagent in this checkout (CLI flags / task names / extensions -> `{N}`
  arguments, test literals -> typed args, CodeInspectionTest guard). In progress.
- **Step 7 evaluation set up**: holdout = the Skyline 24.1 + 25.1 translation rounds, 520 ja / 521 zh
  strings with the professional pre-review draft (archive `*-LS.csv`, 24.1 reviewer sheets) and the
  reviewed final (checked-in RESX). Reviewers changed 116/520 ja drafts but only 24/521 zh drafts
  (zh 25.1 final == LS draft for all 193 strings). Two blind subagents (session model, Opus 5.5)
  translate it with only the glossary, style guide and a TM that excludes every holdout string;
  `eval_score.py` scores exact match, similarity, placeholders, glossary and style conformance,
  and confidence calibration. Caveats to report with the numbers: the finals were edited FROM the
  professional draft (anchoring favors it on exact match), and the glossary was built from a corpus
  that included the 526 holdout English strings (~5%).
- **Pipeline plan for the Osprey drafts**: write Claude's translations as the standard CSV with
  `Issue = New resource`, import with `ImportLocalizationCsvFiles` (creates `Osprey*.ja.resx` /
  `.zh-Hans.resx` with `Needs Review:New resource` comments - the same state as any unreviewed
  Skyline string), then `GenerateLocalizationCsvFiles` hands the reviewers their usual CSV with the
  drafts pre-filled. Verified by reading `ResourcesFile.ImportLocalizationRecords`,
  `ResourcesDatabase.ExportResx` / `ExportLocalizationCsv`.
- **Step 4 done** (subagent) `e051007f6a`: 104 English values now take CLI flags, `--task` names,
  file extensions/patterns, stored column/metadata names, cvParam accessions and build commands as
  `{N}` arguments from constants (new `Osprey.Core/OspreyTaskNames.cs`; `OspreyArgNames` gained
  OUTPUT_DIR/CACHE_DIR/PARALLEL_FILES/VERBOSE); keys unchanged. New guard
  `CodeInspectionTest.TestArgumentTextComesFromArguments` (no `--flag` literal naming a declared
  argument in any Osprey .cs; no flag or known extension in an English resx value) - its first run
  found 22 violations, all fixed. Gates: 609/609 en/ja-JP/fr-FR, inspection 0, Stellar regression PASSED.
- `e472274c39`: glossary + style guide + the two tool fixes committed.
- **Evaluation results** (`ai/.tmp/sessions/20260928-resxtr/eval/NOTES.md`, `score.ja.md`, `score.zh.md`):
  | | ja Claude | ja pro | zh Claude | zh pro |
  |---|---|---|---|---|
  | exact match with reviewed final | 23.8% | 77.7% | 28.0% | 95.4% |
  | char similarity to final | 0.792 | 0.957 | 0.765 | 0.990 |
  | glossary conformance (final ja 93.5%, zh 93.2%) | 95.8% | 94.0% | 95.4% | 93.0% |
  | style checks (final ja 99.0%, zh 97.7%) | 99.9% | 98.1% | 100% | 98.1% |
  | reviewer-changed strings: Claude == final | 3/116 | - | 9/24 | - |
  | reviewer-changed strings: Claude closer than pro | 18/116 | - | 11/24 | - |
  Reading: exact match is anchored to the professional draft (finals were edited FROM it; zh reviewers
  changed 24/521). Claude is more consistent than both the professional draft AND the reviewed final
  on glossary and style, and pre-empts the mechanical class of reviewer edits (zh: 9/24 exact). Its
  clearest systematic miss is expanding terse labels/column names; the finals also contain errors
  Claude avoided (ja "standard error" -> 標準エラー). Acceptability itself is unmeasured until the
  reviewers grade the blind A/B sample (`eval/blind-grading.{ja,zh-Hans}.csv`, 40 pairs each, half
  from reviewer-changed strings; key in `blind-grading-key.*.csv`). The blind zh translator also
  corrected the style guide: zh renders m/z as 质荷比 (181/181), ja keeps m/z (161/181).
- **Osprey drafts**: two subagents (Opus 5.5, full TM + Osprey source read-only + brief + glossary),
  812 strings each. ja 719 high / 92 medium / 1 low; zh 684 / 102 / 26 (all 26 low are the three
  low-confidence `new` terms: entrapment, peak co-assignment, calibrator). Consistency pass
  (`validate_translations.py`): 0 hard failures, 0 inconsistent, glossary ja 96.0% / zh 98.2%
  (Skyline's own reviewed finals: ~95%); every remaining glossary miss was read - all legitimate
  senses the checker cannot tell apart (verb "run" / Osprey invocation -> 実行; verb "score" -> 评分;
  "failed" -> 无法). One real fix applied: "Reading {0}" -> `{0}を読み取り中`. The validator run on the
  reviewed Skyline corpus found 125 same-English-different-translation cases in Skyline itself.
- **Imported through the real pipeline**: `to_localization_csv.py` -> `ImportLocalizationCsvFiles`
  (812/812 matched per language) -> 16 new `Osprey*.ja.resx` / `.zh-Hans.resx`, each entry commented
  `Needs Review:New resource`. Two pipeline facts learned: (1) `ExportResx` drops a "New resource"
  entry whose value equals the English, so the 9 deliberately identical strings (Mokapot, Percolator,
  ppm, `Osprey v{0}`...) import with an empty Issue; (2) the import re-serializes 8 unrelated Skyline
  localized files (character entities -> literal characters) - reverted each time.
- **New test** `Osprey.Test/OspreyLocalizedResourcesTest.cs` (Skyline's LocalizedResourcesTest for
  Osprey): every Osprey resource class found by scan; ja and zh-Hans satellites complete; format-item
  sets identical; `CommandStatusWriter.IsErrorLine` agrees with the English.
- **Two test defects exposed by the first real ja/zh run** (invisible while no satellites existed):
  `IOTest.TestReconciliationFileFormatVersionMismatchRejected` asserted an English literal (now the
  formatted resource); `TestProgressReporterHeartbeat` looked for ASCII `(` (now the marker read from
  the resource - ja/zh write a full-width parenthesis). Gates: 610/610 in en-US (inspection 0),
  ja-JP and zh-CN; fr-FR 610/610 before the test-only fix.
- **Reviewer package** (`ai/.tmp/sessions/20260928-resxtr/reviewer-package/`): the stock
  `GenerateLocalizationCsvFiles` output filtered to Osprey (768 ja / 769 zh rows - identical English
  across files consolidates), standard columns first so a returned file imports unchanged, plus
  `Claude confidence`, `Claude note`, `Glossary terms`; sorted low -> medium -> high.
- Open for Brendan: (1) zh flags arriving as `{N}` are bare, not in “ ” as Skyline's zh CLI help
  does - one global decision; (2) the long corrupt-charge IO error still says "stage" (docs/21 bans
  it) - English fix; (3) zh tolerance unit label `m/z` -> 质荷比 per the reviewed glossary, printed
  after a number; (4) `UpdateResxFiles.bat` + `LastReleaseResources.db` still key zh as zh-CHS.
- **Read both Stellar logs end to end** (`regression.ps1 -Dataset Stellar -Culture ja` / `zh-Hans`, both
  PASSED every mode = no translated text reaches an output file). Found what a table check cannot:
  `Generating {0} decoys...` where `{0}` is the decoy METHOD (both languages had put a counter on it;
  scanned all bare-placeholder counters - the only such case); a dangling ", {0} files" clause; ja space
  before FDR after a localized `{3}`; and a code gap - `ProgressReporter` appended a hardcoded `...` to
  every heading, so zh could not use `…`. New resource `ProgressReporter_ProgressReporter__0____`
  (`{0}...`; zh `{0}…`); 5 test assertions now format through it. zh re-run PASSED with the fixes visible.
- `Documentation/Help/ja` and `zh-Hans/CommandLine.html` now generated beside `en` (as Skyline does);
  `TestCommandLineHelpDocumentation` loops the three languages. The page intro/title are still
  hardcoded English in `GenerateUsageHtml` (open item).
- `d0a29a6b0c` (pushed): 16 localized resx, the new test, the two test fixes, the heading resource, help
  pages. Gates on the final tree: 610/610 en-US (inspection 0), ja-JP, zh-CN, fr-FR.
- Satellites confirmed in `Osprey/bin/x64/Release/net10.0/{ja,zh-Hans}/` (Osprey has no ZIP/MSI step;
  the SDK output is the distribution).
- Reviewer CSVs regenerated from the committed resx with the stock tool: 768 ja / 770 zh rows, 100%
  coverage (`check_coverage.py`).
- **Report for Brendan**: https://claude.ai/artifact/CLEeB1GSpGt2EpuDKxuRVn (answer, evaluation table,
  examples, Osprey results, reviewer package, open decisions, file map).
- **Status**: drafts complete and gated; waiting on Brendan for the open decisions, for sending the
  reviewer CSVs + blind grading sheets to the ja/zh reviewers, and for PR timing (no PR opened;
  `/code-review` and the TeamCity Perf/Regression gate not yet run - both belong at PR time).

**2026-09-29** - Brendan's decisions on the open items
1. zh flags: follow Skyline (quote them). `flag_args.py` parses every call site for placeholders filled
   from `OspreyArgNames` / `ARG_*` / `TaskText` / `ArgumentText`, plus the `--help` `DescriptionArgs`;
   56 zh values now wrap those `{N}` in “ ” (group titles and the appended-sentence `{3}` of
   ProcessFile_Loaded excluded as false positives; RequiresError `{1}` left bare because its value can
   be the already-quoted "--library and --output"). Help-page prose passes flags inside `<code>`, so no
   quotes there.
2. New terms: wait until the review round.
3. The "stage" message (`ParquetScoreCache_RequireCharge...`) reworded to one sentence + remedy:
   "{0} is damaged: row {1} ({3} {2}) has a charge of 0, which is not a possible precursor charge.
   Delete the file and run {4} again to rewrite it." - `{4}` = `--task PerFileRescoring` for a
   `.scores-reconciled.parquet`, else `--task PerFileScoring`; the mechanism (write race, 2026-09-17)
   moved to a code comment. Key unchanged (RESX PR convention).
4. CommandLine.html: all prose (title, meta description, intro, HPC section, example comments, closing
   paragraph) moved to 13 `OspreyResources` entries with markup/flags/file names as arguments, like
   Skyline's translated page; intro now "a peptide-centric DIA search tool from the MacCoss lab", the
   C#/.NET 8/Rust sentence dropped; the `--help` banner "(.NET port of Osprey)" dropped for the same
   reason (flagged to Brendan); possessives removed from the closing paragraph (docs/21). ja/zh drafted
   by the coordinator, imported "Needs Review".
5. Issue for Nick: [#4737](https://github.com/ProteoWizard/pwiz/issues/4737) (LastReleaseResources.db
   zh-CHS rows - verified 36,892 ja / 36,892 zh-CHS, UpdateResxFiles.bat, TutorialLocalization
   Microsoft.Bcl.HashCode crash, import re-serialization churn, zh-CHS tool stragglers).
- `ff1c1350dd` (pushed). Gates: 610/610 en-US (inspection 0), ja-JP, zh-CN, fr-FR; Stellar regression
  PASSED. Also confirmed on `d0a29a6b0c` before these changes: 610/610 under ja-JP and zh-CN.
- Reviewer CSVs regenerated (826 strings; 100% coverage).
- `fa808438b4` (Brendan: "--library and --output" is not translation-safe): the translated "{0} and {1}"
  fragment resource is gone; `RequiresError` has one- and two-argument overloads with their own
  sentences ("{0} requires {1}." / "{0} requires {1} and {2}."); the three tests assert the whole
  formatted message. Open idea (not done): a guard flagging resources that are only placeholders plus
  a conjunction (the fragment-composition class).
- Help-page test: `TestCommandLineHelpDocumentation` already regenerates en/ja/zh-Hans, overwrites stale
  pages and fails naming them. Differs from Skyline's `HelpDocumentationContentTest`, which fails with
  "Rerun test with IsRecordMode=>true" and only writes in record mode - offered to match it exactly.
- `749bec4ef1` (Brendan: completeness puts a translation requirement on every developer; Skyline lets
  English grow): `OspreyLocalizedResourcesTest` now checks only translations that exist (missing entry or
  missing satellite = skipped, like Skyline's `if (localizedValue == null) return;`); placeholder and
  error-line checks kept; a non-vacuous guard fails if no ja or zh-Hans translation was checked at all.
  Mutation-tested: an English-only resource passes; a ja `{0}` -> `{9}` fails naming the entry.
  Gates 610/610 en-US (inspection 0), ja-JP, zh-CN.
- **BOM audit** (Brendan, 2026-09-30): `validate-bom-compliance.ps1 -PwizRoot C:/proj/pwiz-work1` found 12
  Osprey files with a UTF-8 BOM - the 8 English .resx already had it on the port branch (the RESX PR's
  session `resx.py` wrote `utf-8-sig`), and 4 .cs were added by THIS session's Python patch scripts, also
  `utf-8-sig`. ResourcesOrganizer-written localized .resx have none. Root cause for any future script:
  never write `utf-8-sig` (Python) or `Encoding.UTF8` (.NET) to a source file.
- `344ac4333c`: `CodeInspectionTest.TestNoUtf8Bom` (Skyline's `InspectUtf8Bom` for Osprey) scans the Osprey
  tree (.cs .resx .csproj .sln .props .targets .DotSettings .config .xml .xsd .wxs .manifest .json .md .html
  .tsv .txt .ps1 .bat .sh .py .jam; skips bin/obj/TestResults/.vs), strips each BOM keeping timestamps,
  and fails listing the files. First run fixed exactly the 12 (BOM-only diffs). Gates 611/611 en-US
  (inspection 0), ja-JP, zh-CN, fr-FR. Re-audit: pwiz clean.
- Left for their owners (pwiz-ai, not this branch): `ai/scripts/Invoke-DailyReport.ps1`,
  `Invoke-PRReport.ps1`, and the two `TODO-20260924_osprey_log_readability-*.csv` still carry BOMs
  (a BOM on a CSV may be deliberate - Excel needs it to show CJK).
- Do Osprey output files carry a BOM? No. All 124 files of the last Stellar regression run (every
  intermediate file, JSON, `.osprey.task` stamp, TSV report, log, parquet, blib) start without one; and
  every text writer in product code (49: StreamWriter / File.WriteAllText, incl. FDRBench, PIN,
  model-diagnostics HTML/JSON and the `-d` dumps) uses the .NET default, UTF-8 without BOM. The 7
  `Encoding.UTF8` uses are GetBytes/GetString (hashes, library-cache strings) and one StreamReader - no
  preamble.
- `b4e0de0b01`: `CodeInspectionTest.TestNoBomWritingEncoding` - Skyline's Encoding.UTF8 writer rule plus
  File.Append*, `XmlWriterSettings { Encoding = Encoding.UTF8 }`, `new UTF8Encoding(true)`,
  `Encoding.GetEncoding("utf-8")`; all .cs incl. tests, comments ignored, exemption `// UTF8 BOM OK:`.
  Mutation-tested (a File.WriteAllText with Encoding.UTF8 is reported with file:line; nothing else
  matches). Gates 612/612 en-US (inspection 0), ja-JP, zh-CN, fr-FR.
