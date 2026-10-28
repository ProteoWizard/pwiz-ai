# Translation scripts (ja / zh-Hans)

Scripts for translating ProteoWizard `.resx` text into Japanese and Chinese. Most come from the
first Claude-drafted round (Osprey, PR #4752, `todos/completed/2026/09/TODO-20260928_osprey_resx_translation.md`).
They were written during that session and made into parameterized scripts afterwards. Read
`ai/docs/translation-drafting-guide.md` for the process and `ai/docs/translation-guide.md` for the
ResourcesOrganizer pipeline. This README only says which script does which step.

**Requirements**: Python 3.12+ on the PATH. `extract_archive.py` also needs `openpyxl`, `xlrd`
and `python-docx` to read the archive's spreadsheets and Word files.

**Work directory**: most scripts read and write TSVs in one work folder, conventionally
`ai/.tmp/sessions/<YYYYMMDD>-<id>/`. Scripts that take `<session dir>` expect this layout:

```
corpus-resx.tsv          corpus.py
corpus-tutorials.tsv     tutorial_corpus.py
inventory.tsv            resx_inventory.py
archive/                 extract_archive.py (only the holdout evaluation needs it)
eval/                    holdout.py, blind_sample.py, eval_score.py output
eval-blind/              claude.<lang>.tsv from the blind subagents + the glossary they used
```

TSV cells escape `\n`, `\t` and `\\`. Output CSVs meant for Excel are written with a UTF-8 BOM
(Excel needs it to show CJK). Source files are never written with one.

**Keep the data out of this repository.** pwiz-ai is public. The archive (the translation
company's glossaries, translation memories and pre-review drafts) and anything derived from it
(holdout sets, blind grading sheets) stay in the shared Localization drive folder.

## Evidence: corpus, inventory, glossary, style

| Script | Purpose |
|---|---|
| `corpus.py <pwiz root> <out.tsv>` | Reviewed English->ja/zh pairs from every localized `.resx` pair. It skips Osprey because those drafts have not been reviewed; skip any other unreviewed project the same way |
| `tutorial_corpus.py <Tutorials dir> <out.tsv>` | Tutorial paragraphs aligned by XPath (`<lang>/invariant.html` vs `<lang>/index.html`), as `DevTools/TutorialLocalization` aligns them |
| `resx_inventory.py <pwiz root> <project dir> <corpus.tsv> <out.tsv>` | The project's English resources, with any exact reviewed translation from the corpus as translation memory |
| `ngrams.py <inventory.tsv> <min count>` | Frequent 1-4 word n-grams, used to pick glossary candidates |
| `term_evidence.py <session dir> <terms.txt> <out.md>` | For each term, how often each candidate rendering appears in the corpora and archive glossaries. This is the evidence column of `glossary.tsv` |
| `style_stats.py <corpus-resx.tsv>` | Punctuation and spacing shares behind `style-guide.md` |
| `grep_pairs.py <regex> [max] [ja\|zh\|both]` | Reviewed pairs whose English matches a regex. Run it from the work directory |

## Drafting, checking, import

| Script | Purpose |
|---|---|
| `templates/translator-brief-osprey.md` | The Osprey translator brief. Copy it and adapt it for a new project |
| `templates/drafting-subagent-prompt.md` | The prompt given to each per-language drafting subagent |
| `validate_translations.py <table.tsv> <glossary.tsv> [report.md]` | Consistency pass. Hard failures (exit 1): placeholder set, `Error:`/`Warning:` prefix, empty value. Also reports style, glossary, inconsistency and leaked-English findings |
| `to_localization_csv.py <ja.tsv> <zh.tsv> <Scratch dir>` | Turns drafts into `localization.ja.csv` / `localization.zh-Hans.csv` with `Issue = New resource`, ready for `ImportLocalizationCsvFiles.bat` |
| `Validate-TranslationCsvSync.ps1 -CsvPath <csv> -Language ja\|zh-Hans` | Checks that every CSV entry exists in the localized `.resx` files. Run it before sending CSVs to translators or reviewers |

## Reviewer package

| Script | Purpose |
|---|---|
| `reviewer_package.py <Scratch dir> <both.tsv> <glossary.tsv> <out dir> [project]` | Filters the stock `GenerateLocalizationCsvFiles` output to one project. Keeps the standard columns, adds Claude confidence, note and glossary terms, and sorts low confidence first |
| `check_coverage.py <both.tsv> <package dir> [project]` | Checks that every drafted string differing from the English is in the package |

## Evaluation (blind holdout)

| Script | Purpose |
|---|---|
| `extract_archive.py <archive dir> <out dir> [downloads dir]` | Copies the archive files used (glossaries, term bases, `.tmx`, pre-review vs reviewed sheets) and converts them to text |
| `doc_strings.py <in.doc> <out.txt>` | Rough text recovery from a Word 97 `.doc` (the old zh style guide) |
| `holdout.py <session dir>` | Holdout of the 24.1 + 25.1 rounds: professional pre-review draft, reviewed final, blind input, and a translation memory with the holdout removed |
| `eval_score.py <session dir> <ja\|zh> [out.md]` | Scores Claude and professional drafts against the reviewed finals |
| `blind_sample.py <session dir> <n>` | Unlabeled A/B grading sheet for the reviewers, with its answer key kept separately |

## Osprey-specific (examples to adapt)

| Script | Purpose |
|---|---|
| `osprey/flag_args.py <osprey dir> <out.tsv>` | Finds which `{N}` placeholders carry command-line text, by parsing call sites for `OspreyArgNames` / `ARG_*` |
| `osprey/apply_zh_quotes.py` | Wraps those placeholders in `“ ”` in the zh drafts, following Skyline's zh CLI help. Uses the session's relative paths |

The one-off code patches from that session (adding the test guards, the help-page generator and
the console table) were applied to pwiz in #4752 and are not kept here.
