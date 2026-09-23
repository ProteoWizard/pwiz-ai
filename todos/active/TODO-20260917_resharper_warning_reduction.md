# TODO-20260917_resharper_warning_reduction.md

Get the Skyline ReSharper inspection to a number that means something: zero errors, and a
warning count low enough that a new finding is visible rather than lost in four figures.

## Branch Information
- **Checkout**: `C:\dev\pwiz-inspect`
- **Branches**:
  - `Skyline/work/20260918_inspection_in_build` - [#4685](https://github.com/ProteoWizard/pwiz/pull/4685),
    based on `Skyline/work/20260612_net8_port`. Carries the in-build inspection AND the
    severity/sweep/clipboard work below.
  - `Skyline/work/20260922_form_close_obsolete_apis` - [#4697](https://github.com/ProteoWizard/pwiz/pull/4697),
    **stacked on #4685**. Obsolete Form close methods, ServicePointManager, Assembly.CodeBase.
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-09-17
- **Status**: In Progress - #4685 and #4697 open; waves 3 and 4 not started
- **Module**: `skyline`
- **PR**: [#4685](https://github.com/ProteoWizard/pwiz/pull/4685),
  [#4697](https://github.com/ProteoWizard/pwiz/pull/4697)
- **Related**:
  - `TODO-20260823_resharper_cleanup.md` - **the same goal, reached from the other side**
    (Skyline + SkylineBatch + AutoQC, 12 commits on `Skyline/work/20260823_resharper_cleanup`,
    idle since 2026-08-24). Reconcile before either lands; see "Overlap" below.
  - `completed/2025/10/TODO-20251010_webclient_replacement.md` - the 2025 WebClient migration,
    whose deferred Phase 2 IS wave 3 here
  - `TODO-20260612_net8_port.md` - the port this rides on

## Goal

Zero `CSharpErrors`, and the warning count down to the point where the remaining findings are
ones a human would choose to argue about. Not literally zero warnings: several categories are
artifacts of .NET 10 annotating framework members that net472 left unannotated, and "fixing"
them would mean editing working code to satisfy an annotation.

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
| #4685 today (+ wave 2 clipboard) | 0 | **201** |
| Projected with #4697 (wave 1) merged | 0 | ~154 |
| Projected with waves 3 and 4 | 0 | ~139 |

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
| 3 - `WebRequest.Create` / `WebClient` | 10 in-solution + 2 outside | **not started - see below** |
| 4 - `Uri.EscapeUriString` (SYSLIB0013) | 5 | not started, blocked on a question |

## Wave 3 is the WebClient replacement's missing Phase 2

Do not design this fresh. `completed/2025/10/TODO-20251010_webclient_replacement.md` deferred
exactly these call sites under "Deferred to Future Branches (Out of Scope for Phase 1)":

> **Tools Migration** - Executables (AutoQC, SkylineBatch, Installer); Nightly build tools
> (SkylineNightly, SkylineNightlyShim)

It pointed at `todos/backlog/TODO-tools_webclient_replacement.md`, **which was never written** -
the only deferral from that list with no successor. `TODO-20260823_resharper_cleanup.md`
diagnoses this at length.

The target is already decided and enforced: `CodeInspectionTest.cs` forbids
`new\s+(System\.Net\.)?WebClient\s*[({]` at `Level.Error` with no inline opt-out, naming
`pwiz.Common.SystemUtil.HttpClientWithProgress` as the project standard (progress reporting,
cancellation, and a `TestBehavior` seam for tests). That rule shipped as
[#4648](https://github.com/ProteoWizard/pwiz/pull/4648), merged to master 2026-09-10.

**Open question for whoever starts it**: the surviving `new WebClient()` calls in
`SkylineNightly/Nightly.cs` and `SkylineNightlyShim/Program.cs` apparently do not trip that
rule today. Find out why before migrating - if the rule's file scope excludes those projects,
the scope is the first fix, or the migration will drift again the same way.

Sites, grouped by blast radius:

- **3a** `SkylineNightly/Nightly.cs:767,1287,1354,1547` and `SkylineNightlyShim/Program.cs:141`.
  Out-of-process; failures are visible and harmless to users. Forces
  `TeamCityNightlyAuth.ConfigureClient(WebClient, string)` to change shape.
- **3b** `Program.cs:523,578` - Google Analytics pings, fire-and-forget, on the startup path.
- **3c** `Alerts/ReportErrorDlg.cs:257,324` - crash reporting. Highest risk: runs when Skyline
  is already failing, synchronously, from the UI thread, where `.Result` deadlocks.
- **Leave alone**: `ArdiaClient.cs:204` documents why it is `HttpWebRequest` - `HttpClient`
  adds `charset=utf-8` to Content-Type and the Ardia delete API answers 400. Migrating it
  means building the `HttpContent` with a `MediaTypeHeaderValue` that has no `CharSet`, and
  verifying against the endpoint, which needs the `TestArdia*` credentials.
- Outside `Skyline.sln` (never inspected, still warn in their own builds):
  `Executables/SkylineBatch/SkylineBatch/Program.cs:286`,
  `Executables/Installer/SetupDeployProject.cs:109`.

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

1. **#4685's description is stale** - it still describes the `ProteowizardWrapper.PwizSharp`
   exclusion and a plan to add `DotSettings` entries for "about 14 of the 65 errors". Both
   went away when the pre-build fixed resolution. It also ends with a
   `Generated with [Claude Code]` line and a session URL, which
   `ai/docs/version-control-guide.md` forbids.
2. **`.editorconfig` scope, raised by `/code-review max` and not yet addressed** - the blanket
   `[*.cs]` at repo root reaches `pwiz_tools/Osprey`, `Bumbershoot`, `MSConvertGUI`, `SeeMS`
   and `Skyline/Executables`, each of which keeps its own `.sln.DotSettings` that does not
   suppress these inspections. `WFO1000 = none` also contradicts `pwiz-sharp/.editorconfig`'s
   `= warning` with near-identical prose. Narrowing the scope to the Skyline tree is the
   smaller claim and the easier review.
3. **#4697 carries two documented open questions** (both in its PR body): the owned-forms
   close cascade calls only `OnFormClosing`, never the legacy `OnClosing`, so four sites -
   `ViewLibraryDlg`, `AlignmentForm`, `UndoRedoButtons`, `SkylineWindow` - may want an
   `e.CloseReason` guard; and `ServicePointManager` is NOT inert on net10 for the legacy
   stack, which wave 3 is what actually retires.

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
