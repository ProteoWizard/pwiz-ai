---
name: proteowizard-translation
description: Load when working on Japanese / Chinese translation of ProteoWizard text - drafting ja / zh-Hans RESX translations, the glossary or style guide, ResourcesOrganizer localization CSVs, reviewer packages, making English resources safe to translate, or moving the text of a project now in C# (BiblioSpec, msconvert, pwiz/) into RESX.
---

# ProteoWizard Translation (ja / zh-Hans)

## Read first

1. **ai/docs/translation-drafting-guide.md**: how Claude drafts translations for expert review
   (evidence, glossary, brief, drafting subagents, consistency pass, gates, reviewer CSVs,
   evaluation results)
2. **ai/docs/translation-guide.md**: the ResourcesOrganizer pipeline (RESX sync, localization
   CSVs, import, `LastReleaseResources.db`)

## Key facts

- Until the .NET 10 move, the C++ parts of pwiz (msconvert, the `pwiz/` library, BiblioSpec) were
  never localized. Now that they are C#, they can be translated, starting with moving their text
  into RESX. See "Why there is more to translate now" in the drafting guide.

- **Open question**: we do not yet know whether reviewers will accept Claude drafts or want the
  translation company back. Do not present Claude drafting as settled.
- **Tooling gaps on master**: the quickbuild targets were removed with the Jamfiles (#4658). Use the
  ResourcesOrganizer `.bat` files directly. Coverage is `pwiz_tools` minus a hardcoded exclude list.
  See `ai/todos/backlog/TODO-pwiz_translation_expansion.md`.
- Target languages are **ja and zh-Hans only**. fr-FR / tr-TR are test cultures, not translations.
- Satellites: `.ja.resx` / `.zh-Hans.resx`. Tutorial HTML folders are still `zh-CHS`.
- Glossary and style guide: `pwiz_tools/Shared/Translation/` (`glossary.tsv`, `style-guide.md`).
  Reviewer choices outrank literal renderings. Record reviewer changes back into the glossary.
- Claude's drafts are imported through `ImportLocalizationCsvFiles` as `Needs Review:` and are
  first drafts for native-speaker review. Never hand-edit satellite `.resx` files.
- Before translating, make the English safe: user-typed tokens as `{N}` arguments, no sentences
  assembled from fragments, separate singular and plural resources.
- Gates: a localized-resources test (placeholders, error prefixes, orphans; missing translations
  are allowed), and unit tests under ja-JP / zh-CN / fr-FR. Then read the product's output in
  each language end to end.

## Scripts

`ai/scripts/Translation/` (README.md): corpus, inventory, glossary evidence, consistency validator,
localization CSV conversion, reviewer package, blind evaluation, brief and prompt templates.

## Reference implementations

- Skyline: `pwiz_tools/Skyline/TestData/LocalizedResourcesTest.cs`, `DevTools/ResourcesOrganizer`,
  `DevTools/TutorialLocalization`
- Osprey: `Osprey.Test/OspreyLocalizedResourcesTest.cs`, `docs/21-user-facing-text.md`
  ("Resources"), `CodeInspectionTest.TestArgumentTextComesFromArguments`
- First Claude-drafted round: `ai/todos/completed/2026/09/TODO-20260928_osprey_resx_translation.md`

## Related skills

- **skyline-development** / **osprey-development** for the code being translated
- **tutorial-documentation** for translated tutorial HTML
