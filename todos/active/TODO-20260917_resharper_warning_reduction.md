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
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-09-17
- **Status**: In Progress - #4685 and #4697 open, both pushed and current with the base;
  **101 warnings, 0 errors** on #4685 as of 2026-09-25. Wave 3 moved to
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
| #4685 today, after the CA1416 annotation (`8f1527a771`) | 0 | **101** |
| Projected with #4697 (wave 1) merged | 0 | ~154 |
| Projected with wave 4, and wave 3 arriving through the base | 0 | ~139 |

### The 101, in full (measured 2026-09-25 on #4685 at `8f1527a771`)

Every category, nothing collapsed. Regenerate with `pwiz_tools/Skyline/tcinspect.ps1` and
group the report by `TypeId`.

| Inspection | Count | What it is | Route to zero |
|---|---|---|---|
| `CSharpWarnings::CS0618` | 42 | Use of obsolete symbol | wave 1 here; wave 4 here; wave 3's share arrives through the base once the other branch merges |
| `ConditionIsAlwaysTrueOrFalse` | 32 | Expression is always true or false | per-site: dead guard, or a guard the annotations do not believe |
| ~~`LocalizableElement`~~ | ~~25~~ 0 | Element is localizable | **done, wave 5** - see below |
| ~~`ConstantConditionalAccessQualifier`~~ | ~~23~~ 0 | `?.` qualifier known null or non-null | **done** - see below |
| `CSharpWarnings::CS0672` | 20 | Member overrides obsolete member | wave 1 (the `OnClosing`/`OnClosed` pairs) |
| ~~`ConstantNullCoalescingCondition`~~ | ~~13~~ 0 | `??` condition known null or non-null | **done** - see below |
| ~~`InvalidXmlDocComment`~~ | ~~7~~ 0 | Invalid XML doc comment | **done** - see below |
| `HeuristicUnreachableCode` | 7 | Heuristically unreachable code | pairs with the always-false conditions |
| ~~`CheckNamespace`~~ | ~~6~~ 0 | Namespace does not match file location | **done, all 6 suppressed** - the rename it asks for would break every one; see below |
| ~~`CA1416`~~ | ~~4~~ 0 | Platform compatibility | **done** - see below |
| ~~`NotAccessedField.Local`~~ | ~~3~~ 0 | Private field never read | **done** - 2 deleted, 1 kept; see below |
| ~~`Redundant*`, 8 categories~~ | ~~18~~ 0 | Casts, `Cast<T>` calls, default arguments, `#nullable` directives, jumps, `!`, an empty `finally`, a name qualifier | **done, the `Redundant*` sweep** - see below |
| ~~`PartialTypeWithSinglePart`~~ | ~~1~~ 0 | `partial` with one part | **done** - see below |
| ~~`UsingStatementResourceInitialization`~~ | ~~1~~ 0 | Object initializer on a `using` variable | **done** - see below |
| ~~`NullCoalescingConditionIsAlwaysNotNullAccordingToAPIContract`~~ | ~~1~~ 0 | `??` never null per annotations | **done** - see below |

Two notes on getting this to zero rather than to "small":

- **39 of the 111 are what is left of the annotation family** - `ConditionIsAlwaysTrueOrFalse`
  (32) and `HeuristicUnreachableCode` (7); the other two members are now done. These flag our
  own defensive null checks as provably unnecessary, on the strength of .NET 10 annotations
  net472 never had. Each one is either dead code to delete or a guard to keep with a
  suppression; they cannot be swept. **The measured split from the 36 already worked is
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

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260918_inspection_in_build.md` before starting work.
