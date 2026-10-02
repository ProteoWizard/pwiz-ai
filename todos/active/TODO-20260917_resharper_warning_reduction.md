# TODO-20260917_resharper_warning_reduction.md

Get the Skyline ReSharper inspection back to zero errors and zero warnings on the net10 line,
the way it already runs on net472.

## Branch Information
- **Checkout**: `C:\dev\pwiz-inspect`
- **Branches**:
  - `Skyline/work/20260918_inspection_in_build` - [#4685](https://github.com/ProteoWizard/pwiz/pull/4685),
    based on `Skyline/work/20260612_net8_port`. Carries the in-build inspection AND the
    severity/sweep/clipboard work below.
  - `Skyline/work/20260922_form_close_obsolete_apis` - [#4697](https://github.com/ProteoWizard/pwiz/pull/4697),
    **stacked on #4685**. Obsolete Form close methods, ServicePointManager, Assembly.CodeBase.
  - `Skyline/work/20260930_owned_form_close_cascade` - [#4750](https://github.com/ProteoWizard/pwiz/pull/4750),
    **stacked on #4685** (`d5bed42226`). The owned-form close cascade (item 3 below). Stacked
    because the defect exists ONLY on #4685: it arrived with #4697's `OnClosing` ->
    `OnFormClosing` rename and has not reached the base.
  - `Skyline/work/20260925_dda_search_fixes` - [#4712](https://github.com/ProteoWizard/pwiz/pull/4712),
    **also stacked on #4685** (two of its commits edit lines #4685 introduced). The three product
    and test defects the `NotAccessedField.Local` findings exposed, combined from the three
    single-fix branches below, which are now superseded and can be deleted:
    `20260925_msamanda_max_variable_mods`, `20260925_diaumpire_fragment_tolerance`,
    `20260925_diaumpire_persistent_cleanup_glob`.
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-09-17
- **Status**: In Progress - #4685 and #4697 open, both pushed and current with the base;
  **0 warnings, 0 errors** on #4685 as of 2026-09-29 - the goal is met. Wave 3 moved to
  `TODO-20260924_httpclient_to_progress_continued.md`; wave 4 not started.
- **Module**: `skyline`
- **PR**: [#4685](https://github.com/ProteoWizard/pwiz/pull/4685),
  [#4697](https://github.com/ProteoWizard/pwiz/pull/4697)
- **Related**:
  - `TODO-20260823_resharper_cleanup.md` - **the same goal, reached from the other side**
    (Skyline + SkylineBatch + AutoQC, 12 commits on `Skyline/work/20260823_resharper_cleanup`,
    idle since 2026-08-24). Reconcile before either lands; see "Overlap" below.
  - `TODO-20260924_httpclient_to_progress_continued.md` - **owns wave 3 as of 2026-09-24**,
    on its own branch off master. See "Wave 3 moved out" below
  - `completed/2025/10/TODO-20251010_webclient_replacement.md` - the 2025 WebClient migration,
    whose deferred Phase 2 was wave 3 here
  - `TODO-20260612_net8_port.md` - the port this rides on

## Goal

Zero errors and zero warnings. net472 runs at zero today; the net10 line should too.

## Why

The inspection reported 2,412 findings, of which 403 were errors on a tree that compiles
clean. A check in that state is not a gate - nobody reads it, and a real regression lands
invisibly. The errors were not code problems at all (see below), and two inspection categories
supplied 1,833 of the warnings.

## Measured state

Counts from `pwiz_tools/Skyline/tcinspect.ps1` over `Skyline.sln`, severity >= WARNING, using
the team `Skyline.sln.DotSettings` profile.

| State | Errors | Warnings |
|---|---|---|
| CI build #285, before any of this | 403 (338 hidden by an exclusion) | 2,347 |
| After the pre-build fix (errors resolved) | 0 | 2,369 |
| After severity tuning | 0 | 536 |
| After the mechanical sweep | 0 | 211 |
| #4685 after wave 2 (clipboard) | 0 | 201 |
| #4685 after wave 5 (non-UI literals) | 0 | 176 |
| #4685 after merging the base forward (`316e234536`) | 0 | 178 |
| #4685 after the `Redundant*` sweep (`0be13270fb`) | 0 | 160 |
| #4685 after the doc-comment and namespace fixes (`ac6a36a17c`) | 0 | 147 |
| #4685 after the constant `?.` / `??` fixes (`7049b83324`) | 0 | 111 |
| #4685 after the unread fields and singletons (`79b26ba191`) | 0 | 105 |
| #4685 after the CA1416 annotation (`8f1527a771`) | 0 | 101 |
| #4685 after merging the base forward (`ba5bb9e763`, 17 commits) | 0 | 90 |
| #4685 after the first annotation-family pass (`37e39d0700`) | 0 | 72 |
| #4685 after the rest of the annotation family (`159a0bd27b`) | 0 | 53 (projected) |
| #4685 after **#4697 merged in** (`17fa34a5da`) - CI-measured | 0 | 20 |
| #4685 after the orphaned usings and wave 4 (`96a874fa0f`) | 0 | 5 |
| #4685 today, after the dead TLS pinning and the Ardia pragma (`c01385e72a`) | 0 | **0** |
| Projected with #4697 (wave 1) merged | 0 | ~154 |
| Projected with wave 4, and wave 3 arriving through the base | 0 | ~139 |

### The red `Skyline code inspection` check on #4685 is ONE BAD AGENT, not a regression and not a flake (2026-09-30)

`gh pr checks 4685` shows `Skyline code inspection  fail - inspectcode exited with code 4` at
`f54676b6b6`, which reads like the zero has been lost. It has not: **`inspectcode` never gets as far
as analyzing.** Its own solution build fails, and `tcinspect.ps1` treats any non-zero `inspectcode`
exit as `error` before it ever reads the report.

**Called a flake at first, and that was wrong** - the developer re-ran it and it failed again.
Re-running will keep failing, because the cause is persistent state on one build agent:

| Build | Commit | Agent | Inspection |
|---|---|---|---|
| #389 (4195218) | `f54676b6b6` | **-0adf59cd4d8f84520** | **error, exit 4** |
| #386 (4195026) | `f54676b6b6` | **-0adf59cd4d8f84520** | **error, exit 4** |
| #374 (4193726) | `f4946afc18` | -09d014c1d20635833 | success, 0 inspections |
| #372 (4193636) | `c01385e72a` | -081fe6d4d689fdb5f | success, 0 inspections |
| #371 (4193605) | `96a874fa0f` | -09d014c1d20635833 | ran fine, reported 5 real warnings |
| #366 (4193222) | `17fa34a5da` | -0e12417989960283e | success, 20 warnings |

**2 of 2 failures on `pwiz-windows-i-0adf59cd4d8f84520`; 4 of 4 clean runs on three other agents.**
The two failures have *different* proximate errors, which is the tell - it is not one stuck file but
a dirty output tree:

- #386: `MSB3021: Unable to copy file "...IoModuleGCMSRawDataRepository.dll" to
  "bin\x64\Release\net10.0-windows\..." Access to the path ... is denied.`
- #389: `CS0579: Duplicate 'System.Reflection.AssemblyCompanyAttribute' attribute` in
  `SkylineTester\obj\x64\Release\net10.0-windows\SkylineTester.AssemblyInfo.cs` - the SDK's
  generated `AssemblyInfo.cs` colliding with a stale one left in `obj`.

Both are under `x64\Release\net10.0-windows`. **That is the part worth keeping**: those directories
belong to projects the inspection's solution build is the ONLY thing that compiles - `SkylineTester`
above all, which `build.bat` deliberately does not build (see the Copilot-round notes below). So
nothing else on the agent ever cleans them, and once one goes stale it stays stale.

The code is fine, on three independent measurements: #374 on another agent, a local `tcinspect.ps1`
run over `f54676b6b6` **plus** the cascade fix (`success`, **0 `<Issue>` elements**), and #389's own
test steps passing.

**Two ways to fix it, developer's call:**
1. Clean that agent - delete `pwiz_tools/Skyline/SkylineTester/{obj,bin}` in its `C:\pwiz` checkout,
   or turn on "Clean all files before build" for the config once and let it run there.
2. Make the check not care which agent it lands on - have `tcinspect.ps1` remove
   `SkylineTester/obj` and `SkylineTester/bin/x64` before the solution build. Costs seconds and
   removes a whole class of red checks that look exactly like losing the zero.

### Nothing left (measured 2026-09-29 on #4685 at `c01385e72a`)

`tcinspect.ps1` reports `Code inspection: success - No inspections at WARNING or above`, which is
the FIRST time the script has taken its success path, so the GitHub check goes green rather than
red. Regenerate with `pwiz_tools/Skyline/tcinspect.ps1`.

The last 5 were both `CS0618`, and neither was a cleanup decision:

| Site | Count | Resolution |
|---|---|---|
| `SkylineNightly/TeamCityNightlyAuth.cs:152,156` | 4 | **Deleted.** `ConfigureSecurityProtocol`'s only consumer was the `HttpClient` created three lines below its call, and `ServicePointManager` does not affect `HttpClient` - so wave 3's migration of these projects to `HttpClient` had already made the pinning inert. #4697's caveat ("NOT inert for the legacy stack, 7 files still on WebRequest/WebClient") no longer applied: a grep for `WebRequest`/`WebClient`/`ServicePointManager` across `SkylineNightly` and `SkylineNightlyShim` returns nothing outside the deleted method. It was also the last consumer of `using System.Net;` in that file - checked BEFORE editing this time, instead of discovering it on the re-inspect. #4697 had missed this fourth call site, in a different project from the three its body named |
| `Shared/CommonMsData/RemoteApi/Ardia/ArdiaClient.cs:204` | 1 | **`#pragma warning disable SYSLIB0014`.** Stays on purpose, for the reason the file already documents at lines 188-190: `HttpClient` adds `charset=utf-8` to Content-Type and the delete API answers 400. The comment records what retiring it takes - an `HttpContent` with a `CharSet`-less `MediaTypeHeaderValue`, verified against the endpoint with `TestArdia*` credentials - against a component frozen pending Thermo funding |

Both pragmas (these plus the two `SYSLIB0013` ones) clear the **build** warning as well as the
inspection: `SYSLIB0013` and `SYSLIB0014` are now absent from the build log entirely.

| Inspection | Count | What it is | Route to zero |
|---|---|---|---|
| ~~`ConditionIsAlwaysTrueOrFalse`~~ | ~~32~~ 0 | Expression is always true or false | **done** - see below |
| ~~`CSharpWarnings::CS0672`~~ | ~~20~~ 0 | Member overrides obsolete member | **done, #4697** (the `OnClosing`/`OnClosed` pairs) |
| ~~`RedundantUsingDirective`~~ | ~~8~~ 0 | Using not required | **done** - regressed from 0 when #4697 orphaned them; see below |
| ~~`LocalizableElement`~~ | ~~25~~ 0 | Element is localizable | **done, wave 5** - see below |
| ~~`ConstantConditionalAccessQualifier`~~ | ~~23~~ 0 | `?.` qualifier known null or non-null | **done** - see below |
| ~~`CSharpWarnings::CS0618`~~ | ~~42~~ 0 | Use of obsolete symbol | **done** - waves 3 and 4, #4697, the dead TLS pinning, and one pragma |
| ~~`ConstantNullCoalescingCondition`~~ | ~~13~~ 0 | `??` condition known null or non-null | **done** - see below |
| ~~`InvalidXmlDocComment`~~ | ~~7~~ 0 | Invalid XML doc comment | **done** - see below |
| ~~`HeuristicUnreachableCode`~~ | ~~7~~ 0 | Heuristically unreachable code | **done** - always paired with the always-false conditions |
| ~~`CheckNamespace`~~ | ~~6~~ 0 | Namespace does not match file location | **done, all 6 suppressed** - the rename it asks for would break every one; see below |
| ~~`CA1416`~~ | ~~4~~ 0 | Platform compatibility | **done** - see below |
| ~~`NotAccessedField.Local`~~ | ~~3~~ 0 | Private field never read | **done** - 2 deleted, 1 kept; see below |
| ~~`Redundant*`, 8 categories~~ | ~~18~~ 0 | Casts, `Cast<T>` calls, default arguments, `#nullable` directives, jumps, `!`, an empty `finally`, a name qualifier | **done, the `Redundant*` sweep** - see below |
| ~~`PartialTypeWithSinglePart`~~ | ~~1~~ 0 | `partial` with one part | **done** - see below |
| ~~`UsingStatementResourceInitialization`~~ | ~~1~~ 0 | Object initializer on a `using` variable | **done** - see below |
| ~~`NullCoalescingConditionIsAlwaysNotNullAccordingToAPIContract`~~ | ~~1~~ 0 | `??` never null per annotations | **done** - see below |

Two notes on getting this to zero rather than to "small":

- **The annotation family is fully cleared.** All four members are at zero. These flagged our
  own defensive null checks as provably unnecessary, on the strength of .NET 10 annotations
  net472 never had. Each one was either dead code to delete or a guard to keep with a
  suppression; they could not be swept. **The measured split from the 36 worked in the first
  pass is
  32 delete / 2 real bug / 2 keep**, so expect the bulk to be genuine and a real minority
  not to be.
- The 1,833 warnings the `.editorconfig` severities removed are **demoted, not fixed**. If
  the zero-warning bar is meant to include them, that is a much larger body of work and the
  severity rules are the wrong instrument.

## What landed, and why

### The 403 errors were an inspection artifact, not code

ReSharper resolves a project reference pointing outside the solution through the referenced
project's output assembly, evaluated under the properties the inspection runs with. Under
`Platform=x64` it looks in `bin\x64\Release`, which is empty on a cold agent, so every
pwiz-sharp type went unresolved and the project model kept that state for the whole run.

Building `Skyline.csproj` first - **the csproj, not the solution** - fixes it.
`AssignOutOfSolutionProjectReferenceConfiguration` in `pwiz_tools/Directory.Build.targets`
fires only for a SOLUTION build and pins out-of-solution references to AnyCPU on purpose, so
a solution pre-build fills `bin\Release` and the inspection still finds nothing. Measured on a
cold x64 tree: 442 unresolved references and 403 errors before, 0 and 0 after.

Three wrong theories were tested and discarded first (build ordering alone, renaming
assemblies to match project names, `--properties:ReferencePath`). The repro that made it
tractable is deleting `pwiz-sharp/pwiz/src/*/bin/x64` and re-running the inspection; that
reproduces CI exactly on a developer machine.

### Severity tuning: -1,833 warnings (`.editorconfig`)

- `dotnet_diagnostic.WFO1000.severity = none` - 805. Wants
  `[DesignerSerializationVisibility]` on every public property of a Form; ours are
  hand-written test accessors.
- `resharper_possible_null_reference_exception_highlighting = suggestion` - 865
- `resharper_assign_null_to_not_null_attribute_highlighting = suggestion` - 163
- Both of the above `= none` under
  `pwiz_tools/Skyline/{CommonTest,Test,TestConnected,TestData,TestFunctional,TestPerf,TestTutorial,TestUtil}/**.cs`

Verified on a probe project: in a `<Nullable>disable</Nullable>` tree these two inspections
fire ONLY on symbols carrying nullability annotations, which in practice means .NET 10
framework members. Un-annotated Skyline code that genuinely returns null is not flagged at
all, so the warning was never the signal it looked like.

**Severities live in `.editorconfig`, not `Skyline.sln.DotSettings`, deliberately**: an
`InspectionSeverities` entry in that file OVERRIDES the `.editorconfig` value for the same
inspection, which silently un-did the test-tree rule when it was tried there (measured
2026-09-17 on TestFunctional).

### Mechanical sweep: -334 findings, 155 files

174 redundant casts, 83 `new Action(...)` wrappers, 49 unused usings, 28 redundant name
qualifiers. Two passes: dropping the delegate wrappers orphaned nine more usings. Two casts
were deliberately left - `null as double?` in `AlignmentForm` types the conditional, which
`LangVersion 8` cannot infer without it.

### Obsolete APIs, by wave

| Wave | Sites | State |
|---|---|---|
| 1 - Form close methods (WFDEV004), ServicePointManager, Assembly.CodeBase | 47 | [#4697](https://github.com/ProteoWizard/pwiz/pull/4697) |
| 2 - Clipboard/DataObject `GetData` to `TryGetData<T>` (WFDEV005) | 10 | merged into #4685 |
| 3 - `WebRequest.Create` / `WebClient` | 10 in-solution + 2 outside | **moved out** to `TODO-20260924_httpclient_to_progress_continued.md` - see below |
| 4 - `Uri.EscapeUriString` (SYSLIB0013) | 5 | not started, blocked on a question |
| 5 - non-UI string literals (`LocalizableElement`) | 25 | merged into #4685 (`a593268c93`) |

### Wave 5: none of those 25 belonged in a resource file

Every one was an exe name, path fragment, extension, URL scheme, serialization key or
separator - `"BlibBuild.exe"`, `"crux-output"`, `".pin"`, `"https"`, `"schema2"`, the `"_"`
that builds a resource KEY in `MzTolerance.UnitText`. Localizing any of them would be a bug.
`ai/STYLEGUIDE.md` already names the fix: a verbatim string is how this codebase marks text
that must not be localized ("Use `$@""` format ... to avoid ReSharper localization
warnings"). 22 became `@"..."`; the three whose literal contains escapes
(`MSAmandaSearchWrapper.cs` x2, `ResourceAssorter.cs`) took
`// ReSharper disable once LocalizableElement` instead, because `@"..."` would change what
the string holds.

Two things to know if this recurs: ReSharper reports the string's CONTENT for a plain literal
(quotes excluded) but the WHOLE expression for an interpolated one, so an offset-driven fix
has to find the opening quote both ways; and `MzTolerance` is a good specimen of both
idioms - `$@"..."` on `ToString()`, `[Localizable(false)]` on `AuditLogText`, the latter
because its literal needs `\"` escapes.

## Wave 3 moved out, to its own branch off master (2026-09-24)

`TODO-20260924_httpclient_to_progress_continued.md` owns it now, on
`Skyline/work/20260924_httpclient_to_progress_continued`, based on **master** rather than on
the port branch - so master and the port both get the fix instead of it riding here and
arriving only when #4619 merges. Its inventory is this one's, re-taken from `origin/master`
on 2026-09-23 and widened to `HttpWebRequest`/`WebRequest.Create` and bare `HttpClient`.
Phase 1 (SkylineNightly, SkylineNightlyShim, and lowering the inspection tolerance) is
already done there; Skyline's own `Program.cs` analytics pings and `ReportErrorDlg` are its
Phase 2, and it makes the same "leave Ardia alone" call this TODO did.

**Do not migrate any of these call sites here.** The only thing this branch still owes wave 3
is that #4697 deletes `ServicePointManager`, and the legacy stack is what still uses it - see
"Open items" below.

**The open question this TODO raised is answered, and its premise was wrong.** The surviving
`new WebClient()` calls in `SkylineNightly/Nightly.cs` and `SkylineNightlyShim/Program.cs`
DO trip the `CodeInspectionTest` rule. Nothing excludes them: the rule passes `null` for
exemptions, commented "notably not Executables, which NonSkylineDirectories would have
skipped, and which is where the migration was missed". They are absorbed by the rule's
**tolerance argument of 3** - the third is `Executables/Installer/SetupDeployProject.cs` -
which tolerates known survivors as warnings so no NEW one can be added, and which the
comment calls "the only thing tracking them". So the file scope needed no fix; the number is
what gets lowered as each site migrates, which is exactly what the other branch's Phase 1
did. Nothing here drifted.

## Wave 4 is blocked on a compatibility answer

`Uri.EscapeUriString` at `Model/GroupComparison/NormalizationMethod.cs:251,287`,
`SkylineFiles.cs:4193`, `Util/PanoramaPublishUtil.cs:377`.

`EscapeDataString` is the documented replacement and there is in-repo precedent -
`Shared/PanoramaClient/PanoramaClient.cs:175` already switched, commenting *"The latter will
not escape characters such as '+' or '#'"*. But it escapes MORE characters, so the encoded
output changes. `NormalizationMethod`'s strings look like persisted identifiers; somebody has
to confirm what is already written into existing `.sky` documents before the encoding moves,
or round-tripping breaks for any name containing a reserved character.

## Open items on the branches

1. ~~**#4685's description is stale**~~ **DONE 2026-09-24.** Rewritten: the
   `ProteowizardWrapper.PwizSharp` exclusion and the "about 14 of the 65 errors" DotSettings
   plan are gone (both died with the pre-build fix), the severity tuning, sweep and waves 2
   and 5 are described, and the forbidden `Generated with [Claude Code]` line and session URL
   are removed. The missing `skyline` module label was added at the same time.
2. ~~**`.editorconfig` scope**~~ **DONE 2026-09-29** (`f4946afc18`). The repo-root `[*.cs]` is now
   `[pwiz_tools/{Skyline,Shared,SeeMS,MSConvertGUI}/**.cs]`.
   - **`Shared` has to be in scope, and a `pwiz_tools/Skyline/.editorconfig` would NOT have
     worked**: 11 of `Skyline.sln`'s 28 projects live in `pwiz_tools/Shared` (including the
     vendored `zedgraph` the `WFO1000` note names), and EditorConfig matches on the file's path
     on disk, not on which project compiles it. Scoping to the Skyline directory alone would
     have reopened a large share of the 1,833 demotions. Nesting at `pwiz_tools/` instead would
     have swept Osprey and Bumbershoot straight back in.
   - `SeeMS` and `MSConvertGUI` are included on purpose - they are not in `Skyline.sln`, so they
     do not affect this check, but they hit the same WinForms noise for the same reasons.
   - Out of scope, deliberately: `pwiz_tools/Osprey` (252 `.cs`) and `pwiz_tools/Bumbershoot`
     (234). Those are the ONLY C# trees the narrowing drops - every other `pwiz_tools`
     subdirectory has no `.cs` at all.
   - **The other half of the review finding was simply wrong, and it is worth knowing why.**
     It claimed `WFO1000 = none` contradicted `pwiz-sharp/.editorconfig`'s `= warning`. It never
     did: **`pwiz-sharp/.editorconfig` line 1 is `root = true`**, so EditorConfig stops walking
     up there and the repo-root file has never reached anything under `pwiz-sharp`. The two
     values govern disjoint trees. The near-identical prose is not duplication of a conflict -
     pwiz-sharp has its OWN ported SeeMS and MsConvertGUI, so the same rule is documented once
     per copy. pwiz-sharp's `= warning` is also load-bearing: WFO1000 ships at Error in the
     .NET 9+ WinForms SDK, so without the demotion its WinForms builds would fail.
   - Verified: `tcinspect` still `success - No inspections at WARNING or above`, so nothing
     inside `Skyline.sln` reopened.
3. **The owned-form close cascade - MEASURED, and 2 of the 4 sites are real. Fixed in
   [#4750](https://github.com/ProteoWizard/pwiz/pull/4750) (2026-09-30).** #4697 raised this in its PR
   body as an open question and Copilot's review of #4685 found three sites independently. Rather
   than reason about WinForms semantics again, they were **measured** with a 5-case net10 WinForms
   repro (`ai/.tmp/sessions/20260930-c6440483/cascade/`). What it establishes:
   - An owned form's `OnFormClosing` fires with `reason=FormOwnerClosing` **BEFORE the owner's
     own `OnFormClosing`**, so its teardown has already run when the owner cancels. The form is
     left open (`IsDisposed=False`) with the teardown applied.
   - **The legacy `OnClosing` override is NOT called by the cascade** - only `OnFormClosing` is.
     So #4697's rename genuinely introduced this on the net10 line; it is **not** a master bug,
     which is why the fix branch stacks on #4685 rather than going to master.
   - `Show(someChildControl)` does resolve `Owner` to that control's top-level form, so
     `UndoRedoList` really is in `SkylineWindow.OwnedForms`.
   - An owned form that cancels propagates `e.Cancel = true` into the owner's `OnFormClosing`,
     **and the owner can clear it** - after which the close proceeds normally.

   The enumeration matters more than the three sites Copilot happened to find: the cascade reaches
   EVERY owned form, so all of `SkylineWindow`'s modeless owned forms were checked.

   | Owned form | Teardown reached by the cascade | Verdict |
   |---|---|---|
   | `AlignmentForm` (`SkylineGraphs.cs:2948`) | cancels `_cancellationTokenSource` | **REAL - worst** |
   | `ViewLibraryDlg` (`Skyline.cs:1849`, `PeptideSettingsUI.cs:1304`) | unsubscribes the ion/loss handlers | **REAL** |
   | `UndoRedoList` (via `Show(dropDownButton.Owner)`) | `DenyListClosing` cancels unconditionally | **NOT a defect** - see below |
   | `AllChromatogramsGraph` (`Skyline.cs:4006`) | `OnFormClosed` only, which a cancelled close never raises | safe |
   | `DocumentationViewer` (`Skyline.cs:2984`) | none | safe |
   | DigitalRune `FloatingWindow` (floating dock panes) | the docking library never references `FormClosing` at all, and `FloatingWindow` does not forward it, so a floating `DockableFormEx` never sees the cascade | safe |
   | `SkylineWindow` itself | it is the owner, not an owned form | safe - see below |

   **`SkylineWindow` is not the only owner, so the other owners were checked too.** The cascade is
   a general hazard, and `DockableFormEx.OnFormClosing` sets `_isClosingOrDisposing` (which
   `SafeBeginInvoke` consults, so a stuck `true` silently stops background UI updates) - its
   `if (!e.Cancel)` guard cannot see a cancel that happens after it. It turns out not to matter:
   every form that owns another one here has **no cancel path at all**. `EditGroupComparisonDlg`
   (owner of `foldChangeGrid`) and `FoldChangeForm` (owner of `foldChangeSettings`) have no
   `OnFormClosing` and never set `e.Cancel`; `CreateMatchExpressionDlg` (owner of
   `MatchExpressionListDlg`) has none either - its `_cancellationTokenSource.Cancel()` is in
   `FilterRows`, not a close handler; `VolcanoPlotFormattingDlg` and `EditCustomThemeDlg` have
   none. `VolcanoPlotPropertiesDlg` is the one form with a `FormClosing` handler that could have
   cancelled, and it does not - it restores settings - and it owns nothing. So `DockableFormEx`
   needs no change today, but the guard there is weaker than it looks and is worth remembering if
   an owner ever gains a cancel.

   **Correction 1: `AlignmentForm`'s mechanism was recorded wrongly here, and the wrong mechanism
   leads to the wrong fix.** The note above said the token is left "permanently cancelled". It is
   not: `UpdateRows` calls `Cancel()` and then **replaces** the token on every call where the row
   set differs, and `AlignedRetentionTimes` participates in `DataRow.Equals`, so a completed
   alignment guarantees the rows differ next time. Every `AlignDataRow` therefore gets a FRESH
   token. The real mechanism is one level down: `AlignDataRowAsync` **rethrows**
   `OperationCanceledException`, `ProducerConsumerWorker.Consume` catches it and calls
   `SetException` -> `Abort()` -> `Clear()` + `DoneAdding()`, which pushes a `null` per consumer
   thread and **ends every consumer thread permanently**. `_exception` is never cleared and only
   the constructor calls `RunAsync`, so `_rowUpdateQueue` is dead for the life of the form: later
   `Add()` calls enqueue work nothing will ever run, and the grid sits on "Waiting for retention
   time alignment" forever. Anyone "fixing" this by recreating the token would have changed
   nothing. The window is narrower than the old note implies (cancellation must catch alignment
   in flight) but the damage is total and permanent.

   **Correction 2: `UndoRedoButtons` is NOT a defect - Copilot's finding is refuted.** The claim
   was that Skyline "refuses to close" while an undo/redo dropdown is open. It does not:
   `SkylineWindow.OnFormClosing` **starts with `e.Cancel = false`** (`Skyline.cs:1145`), which
   discards the owned form's cancel, and the repro's case F confirms the close then proceeds and
   both forms dispose. That line is not new - it is on master at `Skyline.cs:1150`, so it predates
   #4697 - and `UndoRedoButtons` is constructed in exactly one place (`Skyline.cs:148`), so
   `SkylineWindow` is its only owner. Net behaviour versus master is identical, because on master
   the legacy `Closing` event was never raised by the cascade at all. It was still **hardened**,
   because the non-bug is accidental rather than designed: `DenyListClosing` now skips
   `CloseReason.FormOwnerClosing`, so it no longer depends on `Skyline.cs:1145` staying there, and
   no longer truncates the cascade (a cancel makes WinForms `break` out of the owned-forms loop,
   silently skipping the remaining owned forms' `OnFormClosing`).

   **`SkylineWindow` - #4697's fourth site - examined and clean.** Copilot did not flag it and it
   needed checking anyway. Both of its cancel paths return **before** any teardown:
   `CheckSaveDocument()` failing does `e.Cancel = true; return;`, and the
   `Settings.Default.SaveException` path cancels and then throws. The teardown that follows
   (`_closing = true`, the eight `ProgressUpdateEvent` unsubscribes, `DestroyAllChromatogramsGraph`,
   `DestroyFilesTreeForm`) is only reached once no cancel is possible. `base.OnFormClosing(e)` does
   raise the `FormClosing` event after that teardown, which WOULD strand it if a subscriber
   cancelled - but a grep shows **nothing subscribes to `SkylineWindow.FormClosing`**; all eight
   `FormClosing +=` sites in the tree are dialogs subscribing to their own. No change needed.

   **The fix, and why two shapes rather than one.** The invariant is that teardown must not run on
   a `FormClosing` that may still be cancelled, and there are two honest ways to honour it:
   - `ViewLibraryDlg`: move the teardown to `OnFormClosed`, which runs only on a close that
     actually happened. It also covers a direct close cancelled by a `FormClosing` subscriber,
     which the `CloseReason` shape below does not.
   - `UndoRedoButtons`: skip on `CloseReason.FormOwnerClosing`. The whole purpose of the handler is
     to veto closes, so it cannot move.
   - `AlignmentForm`: **both** - skip the early cancel on `FormOwnerClosing`, and cancel in
     `OnFormClosed` for the case that skips.

   **Two drafts were written and backed out, and both mistakes are worth keeping:**
   - *Moving `AlignmentForm`'s cancel wholesale out of `OnFormClosing`* would have changed the
     NORMAL close path too, letting in-flight alignment call `Invoke` and touch the grid mid-close
     where the early cancel used to stop it. Same hazard class as the `base.OnFormClosed` omission
     under "Hazards" below. The normal path is now left byte-for-byte as it was; only the cascade
     path changes.
   - *`OnHandleDestroyed` as the replacement hook* - which is what both #4697's note and Copilot
     suggested, on the strength of `ViewLibraryDlg` already unsubscribing
     `SpectralLibraryList.ListChanged` there. It is the wrong hook for this: **`OnHandleDestroyed`
     also fires when WinForms recreates a handle** (`RightToLeft`, `FormBorderStyle`,
     `ShowInTaskbar` and friends), which would have torn down a form that is staying open - the
     very bug being fixed, arrived at from the other direction. `OnFormClosed` fires only on a real
     close and never on handle recreation. The existing `SpectralLibraryList` unsubscribe is left
     where it is: that one points from a GLOBAL object at the dialog, so it must run on a hook that
     always runs or the dialog leaks. The ion/loss handlers point from the dialog's own hosted panel
     at the dialog, so they leak nothing and can use the stricter hook.

   **Test**: `RetentionTimeAlignmentTest` gained
   `VerifyCancelledShutdownLeavesOwnedFormsWorking`, reusing that test's existing fixture (results
   + a .blib + a populated `AlignmentForm`) instead of standing up a second one. It opens the
   library explorer, builds the ion type menu, asserts the document is dirty (without unsaved
   changes the close would not stop to ask and would SUCCEED, which would wreck the test), drives
   `SkylineWindow.Close` into the save prompt and clicks Cancel, then asserts both forms are still
   alive and still functional. Both assertions are deterministic:
   - `AlignmentForm.IsAlignmentActive`, a new `internal` property (`InternalsVisibleTo("TestFunctional")`
     already exists, so no reflection) reporting `!IsCancellationRequested && Exception == null`.
     A behavioural assertion could not work here: the token is refreshed on every `UpdateRows`, so
     with no work in flight there is nothing observable to catch.
   - For `ViewLibraryDlg`, toggling the `a`-ion checkbox in the hosted `IonTypeSelectionPanel` and
     checking `GraphSettings.ShowAIons` followed it - a real end-to-end check of the subscription.
     It toggles relative to the checkbox's own state so it does not depend on the panel starting in
     sync, and restores `Settings.Default.ShowAIons` afterwards since that setting is global.
     **First attempt failed, and the reason is the point of the whole item**: `UpdateIonTypeMenu()`
     alone leaves `GetHostedControl<IonTypeSelectionPanel>()` returning null, because the selector
     hangs off `ionTypesContextMenuItem`, which only enters `GraphControl.ContextMenuStrip` when
     `BuildSpectrumMenu` runs from ZedGraph's `ContextMenuBuilder` event - i.e. on a right-click.
     The test now calls `BuildSpectrumMenu` then `UpdateIonTypeMenu`, the two public methods that
     right-click-then-hover drives, reaching the private `graphControl` the way
     `LibraryExplorerTest` already does (`Controls.Find(@"graphControl", true)`). **This also bounds
     the real-world defect**: the ion/loss handlers do not exist until the user has opened that
     context menu, so the `ViewLibraryDlg` half only bites someone who did.

   **Both assertions were verified to have teeth, by negative control.** A test that passes before
   and after the fix is worthless, so each fix was reverted in turn (keeping the `IsAlignmentActive`
   property so the test still compiled) and the test re-run. Two runs were needed, because the
   first failure short-circuits the second assertion:

   | Product state | `TestRetentionTimeAlignment` | Failing line |
   |---|---|---|
   | both fixes reverted | **FAILED** | 180, `AssertEx.IsTrue(alignmentForm.IsAlignmentActive)` |
   | `AlignmentForm` fixed, `ViewLibraryDlg` reverted | **FAILED** | 184, `AssertEx.AreEqual(..., GraphSettings.ShowAIons)` |
   | both fixed | **PASSED** | - |

   The three `IsDisposed` assertions just above passed in both failing runs, which is itself the
   proof of the scenario: the cancelled close left both forms **open**, with teardown applied.

   **Why no existing test caught any of this**, which is the part worth remembering: a grep for
   `SkylineWindow.Close` across `TestFunctional`, `TestTutorial` and `TestUtil` finds exactly one
   caller - the framework's own teardown in `TestFunctional.cs` - and it calls
   `CloseOpenForms(typeof(SkylineWindow))` FIRST, so by the time it closes the main window there are
   no owned forms left and the cascade never runs. Nothing in the suite had ever closed
   `SkylineWindow` mid-test, let alone cancelled it with owned forms open, so this was not a gap in
   assertions - the code path had zero coverage. The new helper is the first test to enter it.
4. **`ServicePointManager` is NOT inert on net10 for the legacy stack** - was #4697's other open
   question. Now moot for the nightly projects: wave 3 moved them to `HttpClient`, so the pinning
   in `TeamCityNightlyAuth` was dead and is deleted (`c01385e72a`).
5. **CI cleaning, the test-project set and the x64 build - pushed to #4685 (2026-10-01) as
   `51573fe525` (clean slate, CleanSkyline sweep, every test project built, tutorial skip, dead
   dotnet steps removed) and `d4643f36c5` (x64 `build.bat` reusing the inspection's build).**
   **CI confirmed green**: build #414 (`732ae80769`) - 1802 tests, `Skyline code inspection`
   PASS (first green inspection check since the bad-agent failures), Core Windows .NET 650 tests.
   **Then `f994f9b8a0`: removed package references the framework provides, and stopped
   suppressing `NU1510`.** The warning only showed for `Common.csproj` on the command line because
   `Shared/Common` has its own `Directory.Build.props`, which stops MSBuild walking up to the global
   `NoWarn`. Removed `System.Resources.Extensions` from the 27 WinForms projects (Windows Desktop
   ships it; kept in plain-`net10.0` `CommonUtil`, `ProteowizardWrapper`, `SkylineRunner`), then the
   14 more references that unsuppressing exposed. **Two were security pins**
   (`System.Security.Cryptography.Xml 8.0.4` in `SkylineNightly`/`TestData`, against GHSA advisories
   via `System.ServiceModel`): NuGet audit could not prove them safe to drop (`NuGetAuditMode=direct`,
   and `TestData` suppresses `NU1903`), so the restore graph was checked instead - after removal,
   `Cryptography.Xml` and `Pkcs` are absent entirely; pruning removed the vulnerable transitive copy
   too. Verified: zero `NU1510` and no `MSB3822/3823` across the inspection, `tcbuild.bat` and all 15
   `Executables` builds; UI tests with embedded bitmaps pass in en and ja. Gotchas found: building
   `SkylineAiConnector` needs `SkylineMcpServer` restored first (pre-existing), and rewrites the
   TRACKED `SkylineAiConnector.zip` - restore it before committing.
   Next: watch the first CI build of `d4643f36c5` - it is the first real run of the new Clean step,
   the patch with four steps removed, and the x64 build. If `TestLibraryBuild` leaves a `.ses`
   temp file there, see the x64 notes below (1 failure in 6 local runs, 0 on AnyCPU CI).
   **Follow-up (2026-10-01, `732ae80769`): `pwiz-sharp` added to the clean.** Perf/Tutorial build
   4196611 (#4750) failed with `MSB3030` copying `CommunityToolkit.HighPerformance.dll` and
   `K4os.Compression.LZ4.dll` from BlibBuild/BlibFilter output. `Skyline.csproj`'s wildcard over
   BlibBuild's `bin` is expanded at project LOAD; it listed DLLs a pre-`ff622113da` build left on
   the agent (that commit moved Parquet.Net to the 6.1.0 fork and dropped both packages), and
   BlibBuild's own `IncrementalClean` deleted them before Skyline copied. Root `clean.bat` now
   calls `pwiz-sharp\clean.bat` (proven by pwiz-sharp's own CI; also clears the native CMake trees
   and generated vendor pins; keeps its caches), and the Perf/Tutorial `.kts` gets the same Clean
   step - it never cleaned, which is why it was exposed. Verified cold: clean exits 0, pwiz-sharp
   52 bin/obj -> 0, tracked `vendor-archives/` and `build/` untouched; main config inspection
   `success` 0 issues in 579s (~100s more than with pwiz-sharp warm), `tcbuild.bat` unchanged at
   296s, `TestLibraryBuild` passed; Perf/Tutorial clean 10s + build/test 136s, tutorial test passed.
   The fix for the bad-agent inspection failure, as directed by the developer:
   - `.kts`: new `Skyline_Clean` step running root `clean.bat`, ordered BEFORE the inspection, so
     the inspection starts from a clean slate. It is the build's only clean.
   - `tcbuild.bat`: no longer cleans. It used to call `CleanSkyline.bat` directly, which bypassed
     `clean-apps.bat`'s `for /d /r` bin/obj sweep - **that bypass is why `SkylineTester\obj` was
     never cleaned**. The sweep lived in `clean-apps.bat` all along; `CleanSkyline.bat` was never an
     enumeration, even in its 2009 first version. The chain the old build used is
     `clean.bat` -> `clean-apps.bat` (sweep) -> `CleanSkyline.bat` (generated-file extras).
   - `CleanSkyline.bat`: its 24 hand-listed bin/obj lines replaced by a copy of `clean-apps.bat`'s
     `:CleanBinaries` sweep over its own tree, so running it alone cleans Skyline completely;
     `clean-apps.bat` sweeps every app except Skyline and still calls it. It ends `exit /b 0`
     because the sweep leaves errorlevel 1 behind (`git ls-files --error-unmatch`) and the TC Clean
     step fails on a nonzero `clean.bat` exit. Verified: alone it took Skyline from 37 bin/obj dirs
     to 1 and left `Shared` alone; via `clean.bat`, `Shared` 22 -> 0; both exit 0; nothing tracked
     deleted. The one survivor is `Executables\DevTools\DocumentConverter\bin`, **a git submodule
     with a tracked `bin\mammoth`** - the sweep's tracked-file guard keeping it is correct, and a
     blind `rmdir` (or a parent-repo `git ls-files` check) would have deleted it.
   - `build.bat`: always builds and stages every test project (TestTutorial and TestPerf included),
     so `SkylineTester.zip` carries every test DLL. New `--skip-tutorial-tests`
     (`skip=TestTutorial.dll`, applied in `:run_tests` so every pass honours it);
     `--with-tutorial-perf` now means "include tutorial and perf tests in the run" and adds
     `perftests=on` to the full-suite pass only (the ja/zh pass selects by regex and would pick up
     `TestImportHundredsOfReplicates`/`TestImportMassOnlyMolecules` in two more languages).
   - `tcbuild.bat`: passes `--skip-tutorial-tests` unless given `--with-tutorial-perf`.
   - Found on the way: **CI was already staging - and zipping - the inspection's x64 `TestPerf`**
     (#374: `Staging TestPerf (...\bin\x64\...)`), because `CleanSkyline.bat` listed `TestTutorial\bin`
     but not `TestPerf\bin`. Its tests did not run only because perf tests are gated on
     `perftests=on`.
   - Verified end to end in the new CI order (`clean.bat` -> `tcinspect.ps1` -> `tcbuild.bat`):
     clean exits 0 (no errorlevel leak from `git ls-files --error-unmatch`) and deletes nothing
     tracked; inspection `success`, 0 issues, from the clean slate; staging took `build.bat`'s
     AnyCPU output for every project even with the inspection's x64 trees present (the stager takes
     the newer directory); default run appended `skip=TestTutorial.dll` and ran only the ordinary
     test; `--with-tutorial-perf` run appended `perftests=on`, no skip, and ran
     `TestAuditLogTutorial` (pass); `SkylineTester.zip` contains all seven test DLLs; the hygiene
     check listed only the uncommitted edits.
   - **Then made `build.bat` x64 so the inspection's build IS the build (developer's design: the
     inspection still runs first and builds; `build.bat` picks up after it).** Measured with
     alternating solution / `build.bat --build-only` builds: **0 recompiles in either direction**,
     `build.bat` on top of an inspected tree ~2 min instead of a full build. Five things had to
     change, and three of them would have failed SILENTLY:
     - `build.bat`: `-p:Platform=x64` in `MSBUILD_PROPS`.
     - `Directory.Build.targets`: the out-of-solution pin passes the solution's own `$(Platform)`
       (was a fixed AnyCPU, chosen only to match the old `build.bat`).
     - **`Skyline.csproj` bundles BlibBuild/BlibFilter/msconvert/Bullseye/SkylineProcessRunner/
       SkylineCmd output from hard-coded `bin\$(Configuration)` paths, every one behind
       `Exists()`** - under x64 they would simply have vanished from Skyline with no error. New
       `BundledProjectPlatformDir` (beside the pin) used in all 17 places, plus `Test.csproj` and
       SkylineTester's `_PrereqOut`. **`_PrereqOut` was also quietly zipping STALE AnyCPU
       `BlibToMs2` binaries** (pwiz-sharp is never swept). Staged file list verified identical to
       the AnyCPU baseline: 1,386 files, all 34 bundled-tool files.
     - **`SkylineTool` is deliberately AnyCPU** (external tools link it and may be 32-bit; master's
       sln maps it the same) - so `BuildSkylineToolAsAnyCPU` pins it centrally. It has to be a
       target, not reference metadata: test projects reach it TRANSITIVELY, the SDK adds those
       references without metadata, and every reference PATH is hashed into
       `CoreCompileInputs.cache`. First version broke `Hardklor.vcxproj` (native, imports the same
       file, no `ResolvePackageDependenciesForBuild`) - fixed with a `UsingMicrosoftNETSdk` condition.
     - **Pre-existing, independent of all this: `Net8Version.g.cs` made Skyline and every dependent
       recompile on EVERY build** (`WriteCodeFragment` writes unconditionally). Now gated on an
       inputs cache written `WriteOnlyWhenDifferent`, like the SDK's own `GenerateAssemblyInfo`.
       Diagnosed with `-v:d`: CoreCompile prints which input is newer than which output.
     - `tcinspect.ps1 -AutomatedBuild` (passed by the `.kts`): `AutomatedBuild` changes every
       assembly's version stamp, so any property mismatch with `build.bat` means a full rebuild.
   - **Superseded design question: the inspection should reuse `build.bat`'s artifacts and does not.**
     `Skyline.sln` has only x64/x86 platforms, so solution-based tools build `bin\x64`; `build.bat`
     builds per-csproj AnyCPU into `bin\<Config>` (since `90db5edf4e`, no recorded reason); and
     ReSharper resolves out-of-solution `pwiz-sharp` references with `Platform=x64`, ignoring the
     `Directory.Build.targets` AnyCPU pin, which is the sole reason for `tcinspect.ps1`'s x64
     pre-build. Cost on #374 (warm): ~3 min of the 11.5-min step is building; more cold. Proposed:
     build x64 in `build.bat`, run the inspection with `--no-build` after it. Not started.

## Hazards found the hard way

- **A rename is not always a rename.** Five `OnClosed` overrides never called base. That was
  harmless while they overrode the legacy method, but after renaming they swallowed
  `FormClosed`, DigitalRune never released its `DockPane`, and five graph tests failed on the
  NEXT test's `ShowGraph`. Restoring `base.OnFormClosed(e)` fixed it. A warning-count check
  would have called that sweep clean; the test suite is what caught it.
- **Staging keeps stale test assemblies.** `CleanSkyline.bat` and `build.bat` do not touch
  `TestPerf` (it is outside the per-commit build), so a `TestPerf.dll` referencing a type that
  no longer exists kept getting re-staged by `Run-Tests.ps1`, and TestRunner died while
  ENUMERATING tests with a message naming `TestUtil`. Deleting `TestPerf/bin` and
  `TestPerf/obj` clears it.
- **Run the baseline before the change, not after.** The full suite was run with the changes
  already in, so separating new failures from pre-existing ones meant reading each stack.

## Overlap with TODO-20260823_resharper_cleanup (measured 2026-09-23)

Same goal, different entry point, and neither knew about the other until 2026-09-23. The two
are mostly complementary: that branch works the projects OUTSIDE `Skyline.sln` - SkylineBatch,
AutoQC, SharedBatch - which the inspection measured here never sees.

**`Skyline/work/20260823_resharper_cleanup` has no PR and never has.** 12 commits on origin,
idle since 2026-08-24, merge base `2cb66ee39d`, now **179 commits behind** the port branch.

Its sibling DID land: [#4648](https://github.com/ProteoWizard/pwiz/pull/4648) (merged
2026-09-10) carried the WebClient migration and the prohibition rule to master, and the net8
line has it. Verified on `origin/Skyline/work/20260612_net8_port`: `DownloadDlg.cs` uses
`HttpClientWithProgress`, the `CodeInspectionTest` WebClient rule is present, and the only
`new WebClient` left under `Executables` is `Installer/SetupDeployProject.cs`. So **4 of the
12 commits are already in by content** (`3d1e03b3b3`, `a7ba7007f6`, `54c3d374c1`,
`f6180de116`); `git cherry` still reports them as unmerged because #4648 was squash-merged.

What is actually stranded on that branch is 8 commits over ~41 files:

| Commit | What |
|---|---|
| `d75c9b1b8a` | net472 build + test prerequisites for SkylineBatch and AutoQC (13 files) |
| `e03778809f` | 12 ReSharper warnings in the batch tools |
| `bb760ed8d0` | 20 warnings in the shared assemblies |
| `38eb21a434` | 8 warnings in AutoQC and CommonUtil |
| `7d55c6b316` | 4 null-analysis warnings in CommonUtil |
| `50ff57ef89` | 6 warnings, plus two documented as unfixable |
| `47513caf32` | **Fix**: AutoQC suite hanging on a modal Skyline error dialog |
| `1a99335fa3` | **Fix**: DNS failures reported as connection failures on net8 |

The last two are real bug fixes, not warning cleanup, and are the strongest argument for not
letting the branch rot.

**Collision set with the sweep commit `d99bae0e24`** - five files both branches change, so a
rebase forward will conflict here and nowhere else:

```
Shared/CommonBaseUI/Controls/ControlUtil.cs
Shared/CommonUtil/Collections/ImmutableList.cs
Shared/CommonUtil/Spectra/SpectrumMetadata.cs
Shared/CommonUtil/SystemUtil/FileEx.cs
Skyline/TestPerf/DiannSearchLFQbenchTest.cs
```

Three of those are cast/using removals from the sweep on the same lines the cleanup branch
edited for the same reason, so the conflicts should resolve to "both did it" rather than to a
real disagreement. Whoever moves that branch forward should also decide which branch owns the
`.editorconfig` severity policy before both edit it.

## Progress log

### 2026-09-24

- Wave 5 landed (`a593268c93`): 25 `LocalizableElement` findings to 0, branch total 201 -> 176.
- #4685 pushed and current: inspection mechanics, severities, mechanical sweep, wave 2, wave 5.
- #4697 rebased onto #4685 with `--onto` so its diff is the 25 wave-1 files alone, then the
  base merged forward into it (`44d88d839c`). No review or comment existed when it was
  force-pushed, which is the only window the repo's rules allow for that.
- The former `Skyline/work/20260917_resharper_inspection_noise` branch is **gone**: its two
  commits were cherry-picked onto #4685 (`f621e178f3`, `d99bae0e24`) and the branch deleted
  local and remote. Do not look for it.
- Measured the overlap with `TODO-20260823_resharper_cleanup`: 4 of its 12 commits are already
  in by content via #4648; 8 are stranded; 5 files collide with the sweep.

### 2026-09-24, later session

- Merged the base forward into #4685 (`316e234536`, 12 commits, no conflicts) and pushed.
  TeamCity build 4186456 picked it up, so the inspection step this PR ADDS is what verifies
  the merge.
- **Re-measured after the merge: 178 warnings, 0 errors** (was 176). The base brought two new
  findings, both in the mechanical sweep's own categories, neither swept:
  - `Shared/CommonBaseUI/SystemUtil/PInvoke/User32.cs:420` - `RedundantCast` on `(IntPtr)(-1)`.
    (Flagged here mid-session as "needs a suppression, the cast is load-bearing on net472".
    **That was wrong** - see the LangVersion note in the sweep entry below. It was deleted.)
  - `SkylineTester/CreateZipInstallerWindow.cs:214` - `RedundantNameQualifier` on
    `System.Text.Encoding.UTF8`. Safe to delete.
  - The lesson generalises: the base branch will keep adding a finding or two per merge in
    exactly the categories the sweep already cleared, so the count drifts UP between sessions
    without anyone writing new bad code. Re-measure after every merge-forward.
- **#4685's description rewritten** (open item 1, closed). It no longer claims the
  `ProteowizardWrapper.PwizSharp` exclusion or the "about 14 of the 65 errors" DotSettings
  plan, both dead since the pre-build fix; it now covers the severity tuning, the sweep and
  waves 2 and 5; the `Generated with [Claude Code]` line and session URL are gone; and the
  `.editorconfig` scope question is stated in the body as an open question for review rather
  than left for a reviewer to find.
- **#4685 had no module label.** Added `skyline`. #4697 already had it. Worth checking on any
  PR this TODO opens - neither `gh pr create` nor the description edit adds it.
- Wave 3 handed off to `TODO-20260924_httpclient_to_progress_continued.md`, and its open
  question answered from `CodeInspectionTest.cs`: the rule's scope was never the problem, the
  tolerance count of 3 is what tracks the survivors. See "Wave 3 moved out" above.

**Still open on #4697's description**: it says it is "Stacked on
`Skyline/work/20260917_resharper_inspection_noise` ... which is the base of this PR". That
branch no longer exists and its base is now `Skyline/work/20260918_inspection_in_build`.
(Moot since #4697 merged into #4685 as `17fa34a5da`, but the body is still wrong if read.)

### 2026-09-28 to 09-30: 101 -> 0, and the Copilot round

Detail for each step is in its own section below; this is the sequence.

- **09-28** Merged the base forward (`ba5bb9e763`, 17 commits): 101 -> 90 on the merge alone,
  and it MOVED the composition - the 4 findings triaged as wave 3's vanished, and
  `LocalizableElement` regressed 0 -> 2. Then the first annotation-family pass
  (`37e39d0700`), 90 -> 72.
- **09-28** Second annotation pass (`159a0bd27b`), the last 19 worked site by site: 16
  deletions, 3 intent-preserving fixes. 72 -> 53 projected.
- **09-29** #4697 merged into #4685 (`17fa34a5da`) while away, which is why the projection was
  wrong: CI measured **20**, not 53. #4697 cleared all 20 `CS0672` but put 8
  `RedundantUsingDirective` and 2 `??` BACK from zero.
- **09-29** Those 10 plus wave 4 (`96a874fa0f`), 20 -> 5. Then the dead TLS pinning and the
  Ardia pragma (`c01385e72a`): **5 -> 0.** `tcinspect` returns `success` for the first time.
- **09-29** `.editorconfig` scope narrowed (`f4946afc18`) - the last open `/code-review max`
  finding, and half of it turned out not to be a defect (pwiz-sharp has `root = true`).
- **09-30** Copilot review of #4685, 13 comments: **2 fixed, 8 refuted, 3 confirmed-deferred**
  (`f54676b6b6`). Inspection still `success` afterwards.

### 2026-09-30, later session: the owned-form close cascade

Picked up the largest remaining item (item 3 under "Open items") on its own branch,
`Skyline/work/20260930_owned_form_close_cascade`, stacked on #4685.

- **Measured the WinForms semantics instead of reasoning about them.** A 5-case net10 WinForms
  repro settled the ordering, the legacy-`OnClosing` question, the `Show(childControl)` owner
  resolution and the owner-clears-cancel case in one run. The legacy-`OnClosing` result is what
  pinned the defect to the net10 line rather than master, and the owner-clears-cancel result is
  what refuted one of the three Copilot findings.
- **2 of 4 sites real, not 3.** `AlignmentForm` and `ViewLibraryDlg` are genuine and permanent.
  `UndoRedoButtons` is not a defect (`SkylineWindow.OnFormClosing` clears `e.Cancel` on its first
  line, and that line predates #4697); hardened anyway. `SkylineWindow` examined for the first time
  and clean.
- **Enumerated all of `SkylineWindow`'s owned forms rather than working from the review's list**,
  since the cascade reaches every one. That added `AllChromatogramsGraph`, `DocumentationViewer`
  and the DigitalRune floating-window path to the checked set - all three safe, the last because
  the docking library never references `FormClosing` at all.
- **The recorded `AlignmentForm` mechanism was wrong** and would have produced a fix that changed
  nothing. Corrected in item 3: the token is refreshed on every `UpdateRows`; what actually dies
  is `_rowUpdateQueue`, permanently, via `ProducerConsumerWorker.SetException` -> `Abort()`.
- **Backed out the first version of the `AlignmentForm` fix.** Moving the cancel wholesale to
  `OnHandleDestroyed` would also have changed the normal close path, letting in-flight alignment
  reach the grid mid-close. Now it skips only `FormOwnerClosing` and cancels in
  `OnHandleDestroyed` for that case, leaving the normal path unchanged.
- `build.bat` run through `cmd /c` from the Bash tool **silently did not run** and **exited 0**:
  Git Bash's MSYS path conversion rewrites `/c` to `C:/`, so `cmd` never saw the switch and
  started an interactive shell (banner plus a clink prompt, then EOF). First blamed on clink;
  `cmd /c echo X` vs `cmd //c echo X` settled it. Ran it through the PowerShell tool instead. This is the same shape as the LF-`.bat` label-skip note in MEMORY -
  a 0 exit from a build wrapper proves nothing on its own, so check the log for the compile lines.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260918_inspection_in_build.md` before starting work.

### The `Redundant*` sweep: 178 -> 160, all 8 categories to zero

18 findings over 13 files, worked per site. 16 deleted, 2 kept.

**`LangVersion 8` was the wrong premise, and it had been recorded twice.** This TODO said the
`AlignmentForm` casts must stay because "LangVersion 8 cannot infer" the conditional, and this
session then repeated the same reasoning for `(IntPtr)(-1)`. Both were wrong:
`pwiz_tools/Directory.Build.props` sets `LangVersion 8.0`, but **`Skyline.csproj`,
`CommonUtil.csproj` and `CommonBaseUI.csproj` each override it to `latest`**, unconditionally,
on a single `net10.0[-windows]` target. So C# 9 target-typed conditionals and the C# 11 numeric
`IntPtr` are both available, the net472 legs those arguments assumed are not built at all, and
all three casts were plain deletions. **Check the project's effective `LangVersion` before
accepting a "the old compiler needs it" argument** - the repo-wide default is not what Skyline
compiles with.

**The two kept, and why:**
- `MSAmandaSearchWrapper.cs:104` - `MzTolerance.Units.mz` equals the default, but it sits one
  line under `new MzTolerance(5, MzTolerance.Units.ppm)`. Making the fragment tolerance's unit
  implicit next to an explicit ppm sibling invites exactly the unit confusion this domain
  punishes. Kept under `// ReSharper disable once RedundantArgumentDefaultValue`.
- Nothing else. The other 16 were provably equivalent.

**Two that needed checking rather than sweeping:**
- `MsDataFileImpl` `GetSpectrum(0, false)` -> `GetSpectrum(0)`: optional-argument defaults bind
  from the **static** type, not the overrides. `_spectrumList` is an `ISpectrumList` and
  `IonMobilitySpectrumList` is a `SpectrumListWrapper`; both declare `getBinaryData = false`,
  so the calls are identical. Had either differed, this would have silently changed whether
  binary data loads on a file-open hot path.
- Removing the dead `Thread.CurrentThread.Name` guard in `ConcurrencyVisualizer` orphaned
  `using System.Threading;`. Same two-pass effect the original mechanical sweep hit: a
  deletion can create the next finding, so re-inspect rather than assuming a clean subtraction.

**Also found**: all three `AssortResources` files carried `#nullable enable` **twice**, once
before the usings and once after. And `build.bat` does not build `SkylineTester` or
`Executables/DevTools/AssortResources` at all - only the inspection's solution build compiles
them, so a code change there is not covered by a `build.bat --no-tests` green.

Same for `TestPerf`, with a flag that changes it: the default target set omits `TestPerf`, and
a plain `build.bat` only **stages** it out of whatever is already in `TestPerf\bin` (which is
the stale-`TestPerf.dll` trap above). **`build.bat --with-tutorial-perf --build-only` pulls it
into `BUILD_TARGET` and really compiles it** - look for `TestPerf -> ...TestPerf.dll` in the
log, and do not accept `Staging TestPerf` as evidence that it built.

Verified: `build.bat --no-tests` 0 errors; `tcinspect` 160/0 with every `Redundant*` category
absent and no new category and no other count moved; `Test.dll` 421 tests (incl.
`CodeInspection`), `TestData.dll` 178 tests, `TestRetentionTimeAlignment` - all 0 failures.
CI build 4186465 then measured 160 independently, matching exactly.

### Doc comments and namespaces: 160 -> 147 (`ac6a36a17c`)

13 findings, 13 files, **all comment-only** - a scripted check over `git diff -U0` confirmed no
changed line was anything but a comment, so no IL could move and the suites could not be
affected. Build and inspection were the whole gate; re-running tests would have proved nothing.

**`InvalidXmlDocComment` (7)** - three were `cref`s made ambiguous by net10 adding overloads
(`Path.GetFileNameWithoutExtension`, `File.GetAttributes`,
`MSAmandaSearchWrapper.HasPercolatorQValues`), fixed by naming the overload. One was
`MathNet.Numerics.Providers.LinearAlgebra.ManagedLinearAlgebraProvider`, which is **internal in
MathNet 4.15** (the version `Common.csproj` deliberately pins), so it can never resolve - it is
a provenance note and became a `<c>` span. One was a `<param name="forward">` for a parameter
`Util.GetEnumerator` no longer has. One was a `cref` to an inherited `protected` member across
projects, which ReSharper would not bind until qualified as `AbstractUnitTestEx.CheckRecordMode`.

**The seventh was a real documentation bug**, not a formatting nit. `SkylineTesterWindow` had
**three `<summary>` blocks stacked with no members between them**: the docs for
`AddStagingCommand(string buildDir)` and `GetStagingTargetDir()` had been left behind when the
methods moved, so `GetRunBuildDir()` carried all three and a `<param name="buildDir">` described
a method that has no such parameter. Reattached each block to its own method; the text is
byte-identical, only relocated. Worth knowing the inspection catches this class of drift at all.

**`CheckNamespace` (6)** - **the rename it demands would break all six**, so all six are
suppressed with the reason inline:
- `SkylineNet8Stubs.cs` declares `namespace System.Deployment.Application` on purpose: it stands
  in for the BCL namespace ClickOnce lost on net10, so the existing `using` directives still
  compile. ReSharper wants `pwiz.Skyline`, which would defeat the file's entire reason to exist.
- The five `Executables/DevTools/AssortResources/*.cs` are **compiled into two projects**: their
  own `AssortResources.csproj`, and `Test.csproj`, which `Compile`-links them so
  `CodeInspectionTest` can use `AssortResources.ResourceAssorter` without building the tool.
  ReSharper judges them by the Test project's root namespace and asks for `pwiz.SkylineTest`;
  `AssortResources` is the correct namespace for the tool, and `CodeInspectionTest` refers to it
  by that name.

This is the first category where the honest answer was "the inspection is wrong about intent"
for every instance. The remaining 147 still contain more of these - a count reaching zero is not
the same as every finding being a defect.

### Constant `?.` and `??`: 147 -> 111 (`7049b83324`)

36 findings, 17 files, the first two members of the annotation family. **32 removed, 2 kept
under a suppression, and 2 turned out to be real defects.** Use `Offset` in the inspection XML
to locate the exact operator - several lines carry two findings and the message alone will not
say which.

**Why 32 were safe to remove.** Three distinct guarantees, not one:
- **Our own pwiz-sharp types**: `Chromatogram.Precursor`, `Precursor.Activation` and
  `BinaryDataArray.Data` are `= new()` field initializers on non-nullable properties, and
  `GetChromatogram` returns non-nullable. `CVParam.Value`/`UserParam.Value` are
  `= string.Empty`. Those are real guarantees in code we own. The `?.` came from the legacy
  C++/CLI wrapper, where the same members were pointers - another mechanical-port artifact.
- **WinForms**: `Control.Text` and `DataGridViewCell.ToolTipText` return `string.Empty`, never
  null; the grid indexers throw rather than return null.
- **BCL contracts**: `HttpResponseMessage.Content`, `HttpContent.Headers`,
  `HttpRequestMessage.Headers`/`Method`, `Exception.Message`, `Task<T>.Result`,
  `ToolStripDropDownItem.DropDown`, `Path.GetExtension`/`GetFileName` of a non-null argument.

**The two real defects are the same shape, and worth recognising again.** A `??` whose left
operand returns `string.Empty` rather than null **can never fire**, so the fallback is dead:
- `EditPeakScoringModelDlg.cs:1007` -
  `cell.ToolTipText = cell.ToolTipText ?? <unexpected coefficient sign>` assigned the empty
  string back to itself, so **the wrong-sign warning tooltip never appeared at all**. Now
  guarded with `string.IsNullOrEmpty`.
- `HangDetection.cs:238` - `dialog.Text ?? "<no text>"` reported an empty string instead of
  the placeholder in hang diagnostics.

If another `?? <fallback>` on a WinForms string property shows up, check it for this before
deleting the `??`: deleting it preserves the bug, it does not fix it.

**The two kept** are ClrMD (`Microsoft.Diagnostics.Runtime`) stack walks in `HangDetection`
and `LogFileMonitor`. ClrMD annotates `ClrMethod.Type` non-null, but this code runs against a
process that is already wedged, which is exactly when a library's happy-path annotation is
least trustworthy, and an NRE there costs the diagnostic the code exists to produce.

**One ReSharper conclusion was simply wrong** and is worth remembering: at
`FormulaBox.cs:455` it claimed the parameter `text` was non-null, having inferred that from
the preceding `textFormula.Text = text` - i.e. from the assumption that the assignment was
valid, which is the very thing `assign_null_to_not_null` (demoted to `suggestion` in our
`.editorconfig`) would have questioned. `text` reaches that line from `DisplayFormula` and
other nullable sources. Rewritten as `textFormula.Text.Length`, which is what the line
actually wants and cannot be null.

Verified: `build.bat --no-tests` 0 errors; `tcinspect` 111/0 with both categories absent, no
new category and no other count moved; `Test.dll` 421, `TestData.dll` 178, and
`TestPeakScoringModel` + `TestEditCustomMoleculeDlg` + `TestIonMobility` (the dialogs touched,
including the tooltip behaviour change) - all 0 failures. CI builds #326 and #328 then ran the
full Skyline suite on this commit: SUCCESS.

### Unread fields and the singletons: 111 -> 105 (`79b26ba191`)

6 findings, 5 files. **One of the three unread fields is a dead product setting** - the same
defect shape as the dead `??` in the batch before, a value the user sets that never reaches the
thing it configures. A second one LOOKED like it and was not; see the correction below, which
is the more useful lesson of the two.

**`MSAmandaSearchWrapper._maxVariableMods`** - `SetModifications(mods, maxVariableMods_)` is an
`AbstractDdaSearchEngine` override, and **Comet and MSFragger both write their captured value
into the params file** (`max_variable_mods_in_peptide`, `max_variable_mods_per_peptide`).
MS Amanda stores it and never reads it; the `MaxNoDynModifs` written to its settings XML comes
from `AdditionalSettings[MAX_NO_DYN_MODIFS]`, default 4. **So the DDA search UI's max-variable-
mods value has no effect on an MS Amanda search.** The field is deleted and the gap recorded at
the call site.

**Fixed on `Skyline/work/20260925_msamanda_max_variable_mods` (`63892957d0`, pushed, no PR).**
The duplicate `MaxNoDynModifs` additional setting is removed and the page's value drives it, the
same resolution Comet's `max_variable_mods_in_peptide` already got - `CometSearchEngine.cs:83`
still carries that commented-out `AddAdditionalSetting`. MS Amanda's own bundled `settings.xml`
documents `MaxNoDynModifs` with the identical `(min 0, max 10)` range, so the two controls were
one parameter. Effective default moves 4 -> 3 (the document default) for users; no baseline
moved, because no PSM in the test sets needed a 4th variable modification. `MSAmandaSearchSettingsTest`
was added as the verifier the defect lacked - a value stored and never read is invisible to
every other test. **Two product calls for review**: it removes a user-visible setting, and it
changes the effective default.

`TestDiaUmpireWiffFile` was the one flagged-but-unverified risk, and it is now **closed**: the
test has **no** document-count assertions at all (it asserts wizard state and `searchSucceeded`,
then cancels), so there was never a count for 4 -> 3 to move, and the search succeeded under the
new value. It did fail, on something unrelated - see below.

**`DiaUmpireTutorialTest...FragmentTolerance` - I CALLED THIS THE SAME DEFECT AND I WAS WRONG.**
Recorded because the reasoning error is the reusable part. I saw `SetupPage` assign
`SearchSettingsControl.PrecursorTolerance` with no matching line for the fragment tolerance,
concluded the assignment had been forgotten, and kept the field under a suppression "because
deleting it erases the recorded intent". Investigation on
`Skyline/work/20260925_diaumpire_fragment_tolerance` (`4b9394703f`) showed the line was
**deliberately deleted**: commit `48e069d673`, "POC: search DiaUmpire TTOF tutorial with Comet",
removed it and says so in its own body - *"high-res MS2 analyzer, no fragment tol"*.

**Comet has no fragment tolerance.** `SearchSettingsControl` disables and clears the MS2
tolerance box for Comet; `ValidateEntries` guards the apply with `if (txtMS2Tolerance.Enabled)`
so `SetFragmentIonMassTolerance` is never called; and `CometSearchEngine`'s override is an
explicit empty no-op commented "controlled by MS2 Analyzer selection". The knob that exists is
`Ms2Analyzer`, which the test already sets to high-resolution for both instruments. The field
was removed, not wired up.

Wiring it would NOT have moved a search result - it would have written a bogus `40 m/z` into a
disabled box (Comet offers no ppm unit, and the setter silently coerces an unsupported unit to
index 0) and changed the `[Track]`ed audit log from `Fragment tolerance is "0" m/z` to `"40"`,
breaking `AuditLogCompareLogs`. So the "fix" would have introduced the defect.

**Separate defect found while running `TestDiaUmpireWiffFile`** - fixed on
`Skyline/work/20260925_diaumpire_persistent_cleanup_glob` (`65c4286479`, pushed, no PR).
`DiaUmpireVendorFormatTest.RemoveDiaUmpireFiles` globs `"*-diaumpire.*"` - with a dot - so it
misses `<file>-diaumpire_pin.tsv`, which the search leaves in the PERSISTENT dir. One orphan is
enough to fail `CheckForModifiedPersistentFilesDir` ("New files: ...-diaumpire_pin.tsv"), after
the test body has otherwise passed. Dropping the dot (`"*-diaumpire*"`) covers both. This never
fires in CI because the test is `NoNightlyTesting(EXCESSIVE_TIME)`, which is also why it has
gone unnoticed. Note the orphan then poisons the NEXT run's opening snapshot, so a naive re-run
can pass and tell you nothing - delete it from the cache before re-testing.

Verified from a **pristine** cache (orphan removed first, so the pass is not the masking effect
above): `TestDiaUmpireWiffFile` 0 failures in 268 s, and the persistent dir has no `-diaumpire*`
left afterwards, which is the behaviour the fix is actually for. The zip is now cached on this
machine at `C:\test\Skyline\downloads\Perftests\` - it was only ever in the stale D: tree, which
is why this test looked like it needed an 11 GB download.

**The lesson**: an unread field next to a used sibling looks like a forgotten assignment, and
`git log -S` on the removed line settles it in one command. Check whether the value was removed
on purpose BEFORE concluding it was dropped by accident. Two more things that made this quiet
and are worth their own look: the `FragmentTolerance` setter coerces an unsupported unit
instead of rejecting it, and assigning while the box is disabled is accepted silently.

The other four were straightforward: a static `Control` field in the no-op
`ConcurrencyVisualizer` that was only ever assigned (a GC root for nothing, had its one caller
not been commented out); `partial` on `MsDataFileImpl` with no second part (`MsDataFileImpl.-
Vendors.cs` declares `VendorReaderRegistration`, a different class); a `StreamWriter` object
initializer moved inside its `using` (the `LocalizableElement` suppression moves with the
`"\n"` it guards); and a `??` over a `HashSet<string>` element in a nullable-enabled file.

Verified: `build.bat --no-tests` 0 errors; `tcinspect` **105/0**, all four categories absent and
no other count moved; `Test.dll` 421, `TestData.dll` 178, `TestDdaSearchSettingsPreset` +
`TestDdaSearchDependencyErrors` (the MS Amanda path) - all 0 failures.

### CA1416: 105 -> 101 (`8f1527a771`)

All 4 were one file and one API: `CommonTextUtil.EncryptString`/`DecryptString` call DPAPI
(`ProtectedData.Protect`/`Unprotect`, `DataProtectionScope.CurrentUser`) to store credentials,
and **`CommonUtil.csproj` targets plain `net10.0` rather than `net10.0-windows`**, on purpose,
so Osprey can consume it on Linux. DPAPI has no cross-platform equivalent, so the honest fix is
`[SupportedOSPlatform("windows")]` on the two methods - not a guard with a fallback, because
any fallback that still returned a value would be a security regression.

**The thing to check before annotating, and the reason it was free here**: an annotation
normally cascades CA1416 to every caller. It did not, because a `net10.0-windows` project gets
`[assembly: SupportedOSPlatform("Windows7.0")]` implicitly, and every caller is one -
`CommonMsData` (Ardia, UNIFI, waters_connect, `RemoteAccount`), Skyline, and `Test`. Verified
by building and grepping the log for `CA1416`: zero. Annotate only the two methods, never the
class: the rest of `CommonTextUtil` is platform-neutral and is what Linux actually uses.

Verified: 0 errors and no CA1416 anywhere in the build log; `tcinspect` **101/0** with nothing
else moved; `Test.dll` 421 incl. `TestEncryptString` - 0 failures.

### Annotation family, first pass: 101 -> 90 -> 72 (`37e39d0700`, 2026-09-28)

**Merge the base forward and RE-MEASURE before working a finding list.** The 17-commit base
merge alone took 101 -> 90, and it moved the composition, not just the total:

- **The 4 findings I had triaged as "wave 3's, do not touch" disappeared on their own**, because
  wave 3's `HttpWebRequest` migration landed on the port branch. They were
  `WebResponse.GetResponseStream()` null checks in `Program.cs` (535/586/592) and
  `Nightly.cs:1424`. Triaging by OWNER rather than by category is what kept that from being
  wasted work and a merge conflict.
- `CS0618` fell 42 -> 33 for the same reason.
- **`LocalizableElement` came BACK from 0 to 2** - a category this branch had already cleared.
  `CommandStatusWriter.ERROR_PREFIXES` gained escaped `ja`/`zh-CHS` error prefixes. They are
  deliberately literals, not resources (PortableUtil has no `.resx`, and a log reader must
  recognise an error from ANY language, not the current UI culture), and `@"..."` is not
  available because the `\uXXXX` escapes ARE the content. Suppressed with disable/restore.
  **A cleared category can regress from the base; check the whole list, not just your targets.**

Of the 35 annotation findings then remaining, 16 were decided on evidence and are done here.

**The `SortDescriptions` cluster (6)** - `RowFilter.GetListSortDescriptionCollection` returns
`new ListSortDescriptionCollection()` when empty, never null. For the three that go through
WinForms `BindingSource.SortDescriptions` (which returns the underlying list's only when it is
an `IBindingListView`, so NOT a free guarantee), every public `BindingListSource` constructor
funnels through one private ctor that does `base.DataSource = new BindingListView(...)`. Chased
that before deleting rather than trusting the annotation.

**pwiz-sharp guards (9)** - dead `chromatogram == null` checks plus their unreachable
`return null` bodies (non-nullable `GetChromatogram`), and a `SelectedIons == null` half
(`{ get; } = new()`).

**Two of those were NOT deletes, and this is the third time this shape has appeared.**
`MsDataFileImpl` 1550/1560 guarded `window.CvParam(...) != null`, but `ParamContainer.CvParam`
returns `new CVParam()` when the term is absent - never null - and `implicit operator double`
maps an empty value to **0.0**. So a missing scan-window limit was not skipped: it recorded
**0**, won the `<` comparison, and gave the spectrum a scan window of **(0, 0)**. Fixed to
`!IsEmpty`, the idiom the same file already uses three frames down. Deleting the guard would
have cleared the warning and KEPT the bug. Mitigating: `ScanWindows` elements carry both limits
in well-formed mzML, so it needs malformed input; and **the legacy wrapper has the identical
`!= null` check**, so the port copied it faithfully and the idiom changed underneath it.

Fixing 1550/1560 also resolved 1571 (`scanWindowUpperLimit.HasValue`), which had followed from
the dead guards - a reminder that this family's findings are not independent.

**Kept (1)**: `GcRootReporter:189` ClrMD `method.Type`, suppressed for the same reason as the
two in `HangDetection`/`LogFileMonitor` - it walks a process being dumped for a leak.

Verified: `build.bat --no-tests` 0 errors; `tcinspect` **72/0**, `ConditionIsAlwaysTrueOrFalse`
29->16, `HeuristicUnreachableCode` 6->3, `LocalizableElement` 2->0, `CS0618`/`CS0672` unmoved;
`Test.dll` 421, `TestData.dll` 178, and `TestDocumentGridExport` + `TestClusteredHeatMap` +
`TestCandidatePeaks` for the sort paths - all 0 failures.

### Annotation family, second pass: 72 -> 53 (`159a0bd27b`, 2026-09-28)

The last 19, worked site by site. **16 deletions, 3 intent-preserving fixes** - and the three
are the same shape that has now appeared five times: a guard that can never fire, so a
degenerate value flows on instead of being skipped.

- `AuditLogEntry:361` - `loggedSkylineDocumentHash != null`, where the value comes from
  `ReadElementString`, which returns `""` for an empty element. An empty `<document_hash/>` set
  `DocumentHash` from `Convert.FromBase64String("")` and fed it to `VerifyHashValues()`. **The
  same file already used the right idiom 30 lines earlier** (`!string.IsNullOrEmpty`).
- `PanoramaFilePicker:461` - `SubItems[1] != null` **throws** when there is no second subitem,
  i.e. in exactly the case it meant to skip; the body does not even read it. -> `Count > 1`.
- `BoundComboBoxColumn:119` - `null == DataPropertyName`, which returns `string.Empty`, so an
  unbound column was not caught. -> `string.IsNullOrEmpty`.

Two gates the developer set were worth setting. `DataSourceUtil.IsDataSource(string)` does NOT
tolerate null (`new FileInfo(path)` throws), so the two `entry != null` deletions were safe only
because the CALLER (`Directory.EnumerateFileSystemEntries`) never yields null - a caller
guarantee, not a callee one. And `BoundDataGridView` re-indexed `Columns[e.ColumnIndex]` on the
next line, so deleting its dead guard alone would have orphaned `column` and traded one warning
for another.

### Wave 4 was never a uniform swap, which is why it stalled (`96a874fa0f`, 2026-09-29)

The five `EscapeUriString` sites split two ways and the right answer is OPPOSITE for each half.

**The two `NormalizationMethod` sites -> `EscapeDataString`.** The blocker ("is the encoding
persisted in .sky?") is answered by the round-trip, not by inspecting documents: write is
`surrogate_` + escape(name) + `?label=` + escape(label); read is `Split('?', 2)` ->
**`Uri.UnescapeDataString`** -> `HttpUtility.ParseQueryString`. **The read side has ALWAYS used
`UnescapeDataString`**, which decodes `%XX` whichever escaper wrote it, so old documents (fewer
escapes, nothing to decode) and new ones both parse - and an older Skyline reads a new document
too, since its read side is the same. Loading always re-derives `Name` through the constructor,
so `Equals` (which compares `Name`) never straddles encodings. It also **fixes a latent bug**:
that name is built like a query string, and `EscapeUriString` leaves `?` and `=` unescaped, so a
surrogate name containing either broke the delimiters `ParseRatioToSurrogate` splits on.

**`SkylineFiles:4175` and `PanoramaPublishUtil:377` must NOT be swapped.** Both escape a WHOLE
URI or path: `folderPath` is `panoramaSavedUri.AbsolutePath`, so `EscapeDataString` would encode
its `/` and the `Contains` match could never succeed; the other escapes a full absolute URI,
where encoding `://` would fail the `IsWellFormedUriString(..., Absolute)` check on the next
line. Swapping either is a silent functional break that compiles and passes inspection. Both now
carry `#pragma warning disable SYSLIB0013` with the reason; retiring them properly means
composing the `Uri` from parts, which needs real Panorama testing.

### The `RedundantUsingDirective` regression, and what it says

#4697 took the count down but put 8 findings BACK in a category the mechanical sweep had
cleared, plus 2 in another. All ten are second-order effects of its three migrations:
5 `System.ComponentModel` (the `CancelEventArgs` -> `FormClosingEventArgs` change), 2
`System.Net` (the `ServicePointManager` removal), and 2 dead `nightlyDirectory ?? throw` guards
(`Assembly.CodeBase`, nullable, -> `AppContext.BaseDirectory`, never null). **A merge can
reopen a category you closed; re-measure the whole list, never just your targets.**

Verified: `build.bat --no-tests` 0 errors and **no SYSLIB0013 anywhere in the build log** (the
pragmas clean the build warning too, not just the inspection); `tcinspect` **5/0**; `Test.dll`
421, `TestData.dll` 178, `TestSurrogateStandards` + `TestUpdateGlobalStandard` (the direct
`RatioToSurrogate` coverage) - all 0 failures.

## Done: 2,412 findings and 403 errors, down to ZERO of each

The goal in the title is met on #4685. `tcinspect` returns `success`, so the check is green.

**What the count never showed, and is the real return on this work**: the annotation family and
the dead-guard hunt turned up **six genuine defects**, every one of which had been invisible
because the guard or fallback that hid it could never execute:

1. `EditPeakScoringModelDlg` - the wrong-sign coefficient tooltip **never appeared**, because
   `ToolTipText` reads back as empty rather than null, so `??` kept the empty string.
2. `HangDetection` - the `<no text>` placeholder never appeared in a hang report, same cause.
3. `MsDataFileImpl` scan windows - a missing CV param recorded a scan window of **(0, 0)**
   instead of being skipped, because `CvParam` returns an empty `CVParam`, never null, and an
   empty one converts to `0.0`.
4. `AuditLogEntry` - an empty `<document_hash/>` set a hash of zero bytes and fed it to
   `VerifyHashValues()`.
5. `PanoramaFilePicker` - a `SubItems[1] != null` guard **threw** in exactly the case it was
   written to skip.
6. MS Amanda ignored the DDA search page's max-variable-mods entirely (PR #4712).

Plus two test defects: the DiaUmpire vendor test could not pass twice (its cleanup glob missed
`-diaumpire_pin.tsv`), and `DiaUmpireTutorialTest` carried a dead field that LOOKED like a
seventh defect and was not - see the correction above, which is the more useful lesson.

**Nothing is open on #4685 any more.** The `.editorconfig` scope question - the last outstanding
`/code-review max` finding - is closed (item 2 under "Open items"), and half of it turned out not
to be a defect at all. The branch is ready for a human review request.

### Copilot review of #4685, 2026-09-30 (`f54676b6b6`)

13 inline comments: **2 fixed, 8 refuted, 3 confirmed-and-deferred** (item 3 under "Open items").

**8 of the 13 rested on one false premise** - seven "this cast removal prevents compilation" and
one "this test fails even for a correct layout". All were evaluated as if `IntPtr` were not
`nint`, i.e. .NET Framework semantics. On this target (`LangVersion latest`, single
`net10.0-windows`) the C# 11 numeric-`IntPtr` feature makes `int` -> `IntPtr` implicit. Refuted
with evidence, not argument: the branch builds with 0 errors, CI build 4193222 ran the full suite
green (1802 tests), and `TestChromPeakOffsets` - the exact test named - passes with 0 failures.
**This is the same mistake made earlier in this work and corrected by checking `LangVersion`;**
8 of the 8 trace to the mechanical sweep commit `d99bae0e24`, only `User32:420` to the later pass.

**Nearly mis-refuted one of them.** The `StructSizeTest` claim was first checked against
`TestCurrentStructSizes`, but line 45 is inside `TestChromPeakOffsets` - a different
`[TestMethod]`. Both pass, but only the second is evidence. Check WHICH test covers the flagged
line before citing a green run.

**`build.bat` did not compile either file this round** - `SkylineNightlyShim` and `SkylineTester`
are both outside its target set, so its 0-error result said nothing about the two fixes. A bare
`dotnet build` of `SkylineTester` is no good either: it drags in `Skyline.csproj` and fails with
~395 `MSB3030` copy errors for native/vendor artifacts only the staged build produces (0
`error CS` among them). **The inspection's solution build is the gate for these projects** - it
compiles both, and `tcinspect` stayed at `success` after the fixes.

The two fixes: `Path.TrimEndingDirectorySeparator` for the drive-root path bug #4697 introduced
(`C:\` -> the drive-relative `C:`), and the `GetFrames()` null check restored under a suppression
for consistency with the ClrMD guards in `HangDetection`/`GcRootReporter` - a fair catch on my own
inconsistency, since I had argued elsewhere that a framework annotation is not our guarantee and a
diagnostic path deserves the guard.
