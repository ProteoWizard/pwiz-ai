# Drafting subagent prompt (template)

The prompt the Osprey round (2026-09-28) gave each drafting subagent, one per language. Replace
`<...>`, and swap `ja` for `zh` (and the style examples) for the Chinese agent. See "Drafting
procedure" in `ai/docs/translation-drafting-guide.md`.

---

You are translating the user-facing text of <Project> (<one-line description>) into <Japanese>.
Your drafts go straight to native-speaker expert reviewers - there is no translation company in
between - so quality AND consistency matter. Work autonomously.

## Inputs (folder `<work dir>`)
- `inventory.tsv` - the <N> strings: columns `file`, `key`, `en`, `comment`, `tm_ja`, `tm_zh`
  (`\n` = line break, `\t` = tab, `\\` = backslash). `tm_ja` is an exact reviewed Skyline
  translation of the identical English when one exists - use it.
- `<project>-brief.md` - READ FIRST: what the product is, who reads the text, domain vocabulary,
  what never to translate, and the evaluation lesson (keep labels terse).
- `glossary.tsv` - term base; use the `ja` column. `reviewed` rows are settled by Skyline's
  reviewers - follow them. `new` rows are proposals for project-only terms - follow them too
  (consistency), and mention in the note when a `new` term carries the meaning of a string.
- `style-guide.md` - punctuation/spacing rules measured from reviewed translations.
- `<user-facing text rules, e.g. Osprey docs/21-user-facing-text.md>` - the project's English
  vocabulary rules (what each term means to the user).
- `corpus-resx.tsv` - ~10,000 reviewed Skyline English->ja/zh pairs (columns `file`, `key`, `en`,
  `ja`, `zh`). Too large to read whole - Grep it for phrases to match Skyline's established wording.

You may also READ (never edit) the source under `<checkout>\<project dir>` to see how a resource is
used (grep the key name to find its call site: what fills each `{N}`, whether the string is a
fragment joined to others, whether it is a column heading or a log line). Do not modify anything
outside your output files.

## Rules
- Every placeholder / format item (`{0}`, `{1:N0}`, `{2:P1}`, `{3:F1}`) must appear exactly as in
  the English; order may change for grammar; the set may not. Literal text around them (e.g. the
  `%` in `{2:F1}%`) stays.
- Keep the whitespace shape: leading/trailing spaces and the number of line breaks as in the
  English (column-aligned help text and indented report lines depend on it).
- Keep product/algorithm/format names, acronyms, and anything the brief lists under "Never
  translate", in English.
- A leading `Error:` / `Warning:` -> `エラー：` / `警告：` exactly (zh: `错误：` / `警告：`).
- Singular/plural pairs are separate resources: translate both.
- Same English -> same translation everywhere unless the context truly differs (then say why in
  the note).
- Enum display values are short labels shown in the log and help; keep them short.

## Output
Write `<work dir>\<project>.ja.tsv`, UTF-8, header `file\tkey\ten\tja\tconfidence\tnote`, one row
per inventory row in the same order, `file`/`key`/`en` copied verbatim from the inventory (keep the
escaping), `ja` escaped the same way, `confidence` = `high` | `medium` | `low` (would a
native-speaker proteomics reviewer accept it unchanged?), `note` = short English note for the
reviewer whenever confidence is not high or a `new` glossary term carries the meaning. Work in
batches of ~50 rows and write incrementally; scratch files only in that folder named `scratch-ja-*`.

Before finishing, verify with a script: <N> rows, file/key/en identical to the inventory,
placeholder sets identical, line-break counts identical, no empty `ja`. Then report: counts by
confidence, the choices you applied repeatedly that a reviewer should confirm once, and the
hardest strings.
