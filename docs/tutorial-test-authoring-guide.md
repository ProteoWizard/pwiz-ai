# Authoring Skyline Tutorials and Their Tests

How a Skyline tutorial goes from an idea (often a webinar) to a published, translated tutorial on
skyline.ms, and what its test must do at each stage. Read this before you create or rename a
tutorial test, add a tutorial folder under `Documentation`, or help someone else do either.

**This is a team-wide process with shared costs.** A tutorial test runs on every developer's
nightly machine, on TeamCity, and in every full screenshot retake. A test that is named, placed,
or guarded wrong costs everyone hours. The rules below exist because of real incidents
(see "Why these rules exist").

## Why tutorials work the way they do

Until early 2025 tutorials were Word documents with hand-taken screenshots. Each Skyline release
meant re-taking hundreds of screenshots in three languages by hand, and each translation was a
paid, months-long project with an outside company.

Now:

- **Every tutorial is an HTML page** (`index.html`) in the pwiz repository, in a standard format.
- **Every screenshot is produced by the tutorial's test**, fully automated, in English, Japanese
  and Chinese. A retake of all tutorials is an overnight SkylineTester run, and ImageComparer
  shows exactly what changed.

That leaves **text translation as the main barrier** to a translated tutorial. Screenshots in
`ja` and `zh-CHS` cost nothing extra once the test is localized; the prose is what has to be
written. Modern LLMs may shorten that a lot (see "Translation"), but only for tutorials whose
HTML is clean and standard. A tutorial that is not in the standard format, or whose screenshots
are not fully reproduced by its test, cannot enter this pipeline at all.

## The three stages

| Stage | HTML and screenshots | Test method name | Test guards |
|---|---|---|---|
| **Draft** | `Documentation/Tutorial-Drafts/<Name>/en/` | `Test<Name>TutorialDraft` | `TutorialDocumentationFolder => "Tutorial-Drafts"` and the `IsTranslationRequired` return |
| **Published, English only** | `Documentation/Tutorials/<Name>/en/` | `Test<Name>Tutorial` | the `IsTranslationRequired` return |
| **Published and translated** | `Documentation/Tutorials/<Name>/{en,ja,zh-CHS}/` | `Test<Name>Tutorial` | none |

A tutorial moves down this table, never skips a row, and its test changes as it moves.

## Rule 1: only a published tutorial's test ends in `Tutorial`

**A test method name may end in `Tutorial` only if the tutorial is (or is about to be) published
on skyline.ms.** Everything else is a draft and ends in `TutorialDraft`.

The suffix is not cosmetic. SkylineTester's **"Tutorial tests"** test set is built from exactly
the methods whose name ends in `Tutorial` (`SkylineTesterWindow.cs`,
`test.TestMethod.Name.EndsWith("Tutorial")`), and so is the list on its Tutorials tab. A full
screenshot retake is: choose "Tutorial tests", select all, Run, and leave it for the night. Every
`...Tutorial` test is in that run, in every language.

Signs that a test is a draft and must be named `...TutorialDraft`:

- There is **no `index.html`** for it, or the HTML is not in the standard format
  (`tutorial-doc-style-guide.md`). A test with no written tutorial is not a tutorial yet, however
  complete the test is. Example: `TestDiannSearchTutorial` had no `index.html` and was renamed
  `TestDiannSearchTutorialDraft`.
- It has no tutorial page, ZIP and PDF links on skyline.ms, and no `TutorialCatalog` entry
  (see "Publishing").
- Its screenshots live in `Tutorial-Drafts`.

What does **not** change when you add `Draft`:

- The test still produces screenshots. The framework's `IsTutorial` check is
  `TestContext.TestName.Contains("Tutorial")` (`TestFunctional.cs`), so `PauseForScreenShot` calls
  in a `...TutorialDraft` test write PNGs in auto-screenshot mode, the same as in a published one.
  You can still run it with `Run-Tests.ps1 -TakeScreenshots`, and you can still commit the
  screenshots to have a baseline to test reproducibility against.
- It still runs in the nightly and TeamCity runs of its test project. `Draft` keeps it out of
  the *tutorial* set, not out of testing. That is also why its run time matters (Rule 4).

Other suffixes in use: `...TutorialLegacy` for a tutorial retired from the website,
`...TutorialExtra` / `...TutorialFullFileset` for heavier variants of a published tutorial's test.
None of them end in `Tutorial`, which is the point: they are not part of the tutorial set.

## Rule 2: drafts keep their screenshots in `Tutorial-Drafts`

A draft overrides the screenshot folder:

```csharp
        // While this tutorial is a draft, its screenshots live under Documentation\Tutorial-Drafts.
        protected override string TutorialDocumentationFolder => "Tutorial-Drafts";
```

`TutorialDocumentationFolder` is a virtual on `AbstractFunctionalTest` that returns `"Tutorials"`.
Screenshots go to `Documentation\<TutorialDocumentationFolder>\<CoverShotName>\<lang>\`.
Without the override, a draft's first screenshot run creates a folder under
`Documentation/Tutorials/`, which looks like a published tutorial to everyone who sees it. That
happened with `DIA-NN-Search`.

`CoverShotName` must equal the tutorial folder name, so the screenshots land next to the HTML.

Remove the override when the tutorial is published, in the same commit that moves the folder.

## Rule 3: no screenshots in languages that are not translated

Every tutorial test whose tutorial does not have fully translated `ja` and `zh-CHS` `index.html`
files starts with these lines, including every draft and every tutorial out for translation:

```csharp
        [TestMethod]
        public void TestDiannSearchTutorialDraft()
        {
            // Not yet translated
            if (IsTranslationRequired)
                return;
```

`IsTranslationRequired` is true only in auto-screenshot or cover-shot mode, in a language other
than English (`TestFunctional.cs`). So the test still runs in ja and zh as an ordinary functional
test, which keeps it honest about localization. It just takes no screenshots that no page
would show. Without the guard, every full retake runs the test twice more for nothing. For a
long test that is hours.

Published tutorials that already use this guard include AuditLog, LiveReports, PeakPicking,
LibraryExplorer, CEOptimization, HiResMetabolomics, DriftTimePredictor, OrbiPrm and
AcquisitionComparison. Remove the guard in the commit that adds the translated HTML.

## Rule 4: respect the test-time budget

Tutorial tests run nightly on many machines, on TeamCity per PR, and in every retake.

- Put a tutorial whose data takes minutes to load in **TestPerf**; it only runs with perf tests
  enabled. Quick ones go in **TestTutorial**.
- Shrink the data before you shrink the tutorial. Repackage the download into one ZIP laid out
  the way the test reads it, and leave out anything the tutorial never opens. Mark big files
  `TestFilesPersistent` so they extract once. See "Step 1" in
  `webinar-to-tutorial-draft-guide.md` for the DIAtoSRM example, which removed a 35 GB copy
  from every run.
- Report the run time when you add the test. A test that takes over ~15 minutes needs a
  conversation with the team, not just a commit. One that cannot fit on the PR perf agent
  (disk, memory) goes in `pwiz_tools/Skyline/tc-perftests-skiplist.txt` with a comment saying why.
  It still runs on nightly machines, so the skiplist does not make a long test free.
- Mark a test that exhausts memory beside other workers
  `NoParallelTesting(TestExclusionReason.RESOURCE_INTENSIVE)`.

## Rule 5: everything a test writes stays in its test directories

Keep inputs in `TestFilesDir` (persistent files where needed) and outputs in the test's
`TestResults` folder. Do not create a "stable" working folder in `%LOCALAPPDATA%`, the user
profile, or anywhere else outside them. Such a folder outlives the run and is shared by every
branch built on that machine. A long-lived agent like a nightly machine or MacCoss TeamCity
Agent 1 then runs each branch against state left by another branch, while a fresh cloud agent
never does. The test passes or fails depending on where it ran and what ran before it.

## Writing the test

### Choose a base class

| Base class | Use for | Read |
|---|---|---|
| `AbstractFunctionalTestEx` | Classic tutorial tests: drive forms with `RunUI`, `ShowDialog`, `OkDialog` | `testing-patterns.md` ("Functional Tests"); any test in `TestTutorial/` |
| `McpConnectorTest` | New drafts driven through the in-process AI connector (`IJsonToolService`), as an MCP client would. Doubles as proof the connector can run the whole tutorial | `webinar-to-tutorial-draft-guide.md` |

### Screenshots

- One `PauseForScreenShot*` call per `s-NN.png`, **in the order the HTML numbers them**. Number
  `s-01` upward with no gaps; shared boilerplate images (`proteomics-interface.png`, etc.) are
  not numbered.
- Use the narrowest capture that shows what the text discusses: `PauseForScreenShot(form)` for a
  dialog, `PauseForGraphScreenShot`, `PauseForChromGraphScreenShot`,
  `PauseForPeakAreaGraphScreenShot`, `PauseForRetentionTimeGraphScreenShot`,
  `PauseForFullScanGraphScreenShot` for graphs. In connector tests, `PauseForMcpScreenShot(formId)`.
  See "Screenshot Capture Methods" in `tutorial-doc-style-guide.md`.
- Give each call a description; it is shown when paused and is how a maintainer finds the call.
- Make screenshots reproducible. Wait for asynchronous work (library loads, imports, wizard page
  changes) before capturing. Hide or close floating windows the screenshot should not show. Set
  window and graph sizes explicitly. Anything that depends on timing or on the previous step's
  leftovers shows up as a changed screenshot in the next retake, in all three languages.
- Set `CoverShotName` and take the cover shot (`TakeCoverShot()`), which produces `cover.png`
  for the website.

### Localization

A tutorial test runs in en, ja and zh-CHS, so never match a control, menu item, or list item by
an English literal. Take captions from the control's resources (`GetLocalizedText<T>`,
`MenuPath<T>`), or from the existing localized string. The rules and the table of where list text
comes from are in "Localization" in `webinar-to-tutorial-draft-guide.md`; they apply to classic
tests too. A test that only passes in English is not finished.

### Conventions

- One file per tutorial test, named for the class (`<Name>TutorialTest.cs`). A file named
  `...PerfTest.cs` holding a tutorial test is hard to find.
- Define the step methods in the order `DoTest()` calls them, so the file reads as the tutorial.
- Match the comment density of the existing tutorial tests: a short summary of the tutorial on
  the class, a line where a step is not obvious. Do not narrate every action.
- Keep `IsPauseForScreenShots = true;` commented out, and remove `PauseTest()`, before committing.

## Tools

| Task | Tool |
|---|---|
| Run one test, offscreen | `pwsh -File ai/scripts/Skyline/Run-Tests.ps1 -TestName <Test>` |
| Watch it on screen | add `-ShowUI` |
| Generate screenshots | add `-TakeScreenshots`; add `-Language ja` or `-Language zh` for the localized set |
| Work out the next step against a live, paused Skyline | `PauseTest()` plus the Skyline MCP tools; see "Write the test one step at a time, over MCP" in `webinar-to-tutorial-draft-guide.md` |
| Retake many tutorials | SkylineTester, "Tutorial tests" set; `skylinetester-guide.md` |
| Review changed screenshots | ImageComparer GUI or MCP server (list, diff, accept, revert); `tutorial-workflow-guide.md`, `screenshot-update-workflow.md`, `mcp/image-comparer.md` |
| Check translated HTML structure | `Run-Tests.ps1 -TestName TestLocalizedTutorialHtml` (compares each `ja`/`zh-CHS` `index.html` with its `invariant.html`; covers `Tutorials` and `Tutorial-Drafts`) |
| Check catalog entries | `TestTutorialCatalogResources`, `TestTutorialCatalogFormat` |
| Build the localized tutorial bundle | `Executables/DevTools/TutorialLocalization` |

A screenshot run takes over the desktop: do not use the machine, or run other on-screen tests,
while it runs.

## Publishing

A draft is ready to publish when:

1. **`en/index.html` is clean and in the standard format** (`tutorial-doc-style-guide.md`):
   standard head and `skylineOnload()`, the "Getting Started" section, action bullets, menu
   patterns, an introduction and a conclusion. This is a precondition for translation, not a
   nicety: translators, `TestLocalizedTutorialHtml` and `TutorialLocalization` all work on its
   structure.
2. **The test reproduces every screenshot**, fully automated, with none hand-edited or
   hand-captured, and a second run changes nothing in ImageComparer.
3. **The website pieces exist**: data ZIP on skyline.ms, abstract, version line, cover image,
   PDF. See "Website Publication Requirements" in `tutorial-doc-style-guide.md`.
4. **The catalog knows about it**: an entry in `Controls/Startup/TutorialCatalog.cs` plus
   `<Prefix>_Caption` and `<Prefix>_Description` in `TutorialTextResources`, `<Prefix>_zip` and
   `<Prefix>_pdf` in `TutorialLinkResources`, and `<Prefix>_start` in `TutorialImageResources`.
   `TestTutorialCatalogResources` fails if any is missing.

Then, in one commit:

- Move `Documentation/Tutorial-Drafts/<Name>` to `Documentation/Tutorials/<Name>` and fix the
  shared-asset paths in the HTML (`../../../Tutorials/shared/...` becomes `../../shared/...`).
- Remove the `TutorialDocumentationFolder` override.
- Rename the test method from `...TutorialDraft` to `...Tutorial`.
- Keep the `IsTranslationRequired` guard until the translations land.
- Set `LinkPdf` if the test checks it, and turn the audit-log comparison back on
  (`AuditLogCompareLogs`) once a recorded log exists.

## Translation

A translated tutorial needs `ja/index.html` and `zh-CHS/index.html` with the **same tag skeleton**
as English: translate the text inside each tag; keep every element and attribute. Put a copy of
`en/index.html` in each language folder as `invariant.html`; `TestLocalizedTutorialHtml` compares
the two by XPath and fails on any structural difference. Point the shared boilerplate images at
the language's folder (`shared/ja/...`, `shared/zh-CHS/...`). Then generate the localized
screenshots with `-Language ja` / `-Language zh` `-TakeScreenshots`, review them, and remove the
`IsTranslationRequired` guard.

The prose has historically been translated by an outside company, at real cost and with
months of delay, so few tutorials have been translated. Claude can draft translations for
native-speaker review, using the glossary and the ~3,900 already-reviewed aligned tutorial
paragraphs per language as evidence. Whether reviewers accept those drafts is still an open
question. See `translation-drafting-guide.md` and the `proteowizard-translation` skill. Either way,
a draft translation is only as good as the English: clean, standard, consistently worded HTML is
what makes a tutorial cheap to translate.

## Why these rules exist

- **October 2026**: an overnight "Tutorial tests" retake did not finish. About five hours of
  unfinished tutorial tests had joined the tutorial set under `...Tutorial` names: DIA-NN Search,
  which had no `index.html`, and DIAtoSRM and DiaFragPipe from the webinar-to-draft process.
  DIAtoSRM alone takes ~1.5 hours per pass and, without the `IsTranslationRequired` guard, ran
  in all three languages. The DIA-NN Search draft wrote its screenshots under
  `Documentation/Tutorials`.

## Checklists

**New draft**

- [ ] `Documentation/Tutorial-Drafts/<Name>/en/index.html` in the standard format, `s-NN` numbered
- [ ] Test method `Test<Name>TutorialDraft`, in TestTutorial or TestPerf by run time
- [ ] `TutorialDocumentationFolder => "Tutorial-Drafts"` and `CoverShotName = "<Name>"`
- [ ] `IsTranslationRequired` return at the top of the test method
- [ ] Captions and menu paths localized; test passes offscreen in en, ja and zh
- [ ] Run time measured and reported; skiplist entry if it cannot run on the PR perf agent
- [ ] Nothing written outside the test's directories
- [ ] Screenshots generated, reviewed in ImageComparer, and a second run reproduces them

**Publish**: the five steps under "Publishing".

**Translate**: the steps under "Translation".

## Related docs

- `tutorial-doc-style-guide.md`: HTML format, publication requirements, screenshot methods
- `webinar-to-tutorial-draft-guide.md`: drafting a tutorial from a webinar with an `McpConnectorTest`
- `tutorial-workflow-guide.md`: the edit, run, diff, decide loop for an existing tutorial
- `screenshot-update-workflow.md`: ImageComparer, triage, cover shots, machine setup
- `skylinetester-guide.md`: test sets and screenshot runs in SkylineTester
- `testing-patterns.md`: functional-test mechanics
- `translation-drafting-guide.md`, `translation-guide.md`: translation pipeline
