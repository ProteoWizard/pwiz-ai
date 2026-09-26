# TODO-osprey_resx_translation.md - Claude-drafted ja / zh-Hans translations of Osprey, straight to expert review

## Branch Information
- **Branch**: (not started) - `Skyline/work/YYYYMMDD_osprey_resx_translation`
- **Base**: `Skyline/work/20260612_net8_port` (after the RESX PR from `TODO-20260926_osprey_resx.md`
  merges; stack on it if it has not)
- **Module**: `osprey`
- **Created**: 2026-09-26 (Brendan's request at the end of the RESX session)

## The question this answers
Skyline's translations came out of a rigorous process: glossary generated from source material,
professional translation, then expert review by native-speaker practitioners, with the translation
company mediating feedback for consistency. Can Claude produce the first draft AND hold overall
consistency itself, so Osprey goes straight to the expert review phase with no translation company?
The work is only half the deliverable; the other half is evidence for or against that claim.

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
