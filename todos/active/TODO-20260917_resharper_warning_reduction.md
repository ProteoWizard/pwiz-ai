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
  **178 warnings, 0 errors** on #4685 as of 2026-09-24. Wave 3 moved to
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
| #4685 today, after merging the base forward (`316e234536`) | 0 | **178** |
| Projected with #4697 (wave 1) merged | 0 | ~154 |
| Projected with wave 4, and wave 3 arriving through the base | 0 | ~139 |

### The 178, in full (measured 2026-09-24 on #4685 at `316e234536`)

Every category, nothing collapsed. Regenerate with `pwiz_tools/Skyline/tcinspect.ps1` and
group the report by `TypeId`.

| Inspection | Count | What it is | Route to zero |
|---|---|---|---|
| `CSharpWarnings::CS0618` | 42 | Use of obsolete symbol | wave 1 here; wave 4 here; wave 3's share arrives through the base once the other branch merges |
| `ConditionIsAlwaysTrueOrFalse` | 32 | Expression is always true or false | per-site: dead guard, or a guard the annotations do not believe |
| ~~`LocalizableElement`~~ | ~~25~~ 0 | Element is localizable | **done, wave 5** - see below |
| `ConstantConditionalAccessQualifier` | 23 | `?.` qualifier known null or non-null | per-site, same family as the above |
| `CSharpWarnings::CS0672` | 20 | Member overrides obsolete member | wave 1 (the `OnClosing`/`OnClosed` pairs) |
| `ConstantNullCoalescingCondition` | 13 | `??` condition known null or non-null | per-site, same family |
| `InvalidXmlDocComment` | 7 | Invalid XML doc comment | fix the `cref` targets |
| `HeuristicUnreachableCode` | 7 | Heuristically unreachable code | pairs with the always-false conditions |
| `CheckNamespace` | 6 | Namespace does not match file location | rename namespace or move file |
| `CA1416` | 4 | Platform compatibility | annotate or guard the Windows-only calls |
| `NotAccessedField.Local` | 3 | Private field never read | delete |
| `RedundantEnumerableCastCall` | 3 | Redundant `Cast<T>`/`OfType<T>` | delete |
| `RedundantArgumentDefaultValue` | 3 | Argument equals the default | delete |
| `RedundantNullableDirective` | 3 | Redundant `#nullable` directive | delete |
| `RedundantJumpStatement` | 2 | Redundant control flow jump | delete |
| `RedundantCast` | 3 | Redundant cast | **all three need a suppression, not a deletion**: 2 are `null as double?` in `AlignmentForm`, typing the conditional in a way LangVersion 8 cannot infer; the third is `(IntPtr)(-1)` in `PInvoke/User32.cs`, redundant only because `IntPtr` IS `nint` on net10 |
| `RedundantSuppressNullableWarningExpression` | 2 | Redundant `!` | delete |
| `PartialTypeWithSinglePart` | 1 | `partial` with one part | delete the modifier |
| `RedundantEmptyFinallyBlock` | 1 | Empty `finally` | delete (leftover from the mechanical port) |
| `RedundantNameQualifier` | 1 | Redundant name qualifier | delete - `System.Text.Encoding.UTF8` in `SkylineTester/CreateZipInstallerWindow.cs:214`, arrived with the base |
| `UsingStatementResourceInitialization` | 1 | Object initializer on a `using` variable | restructure |
| `NullCoalescingConditionIsAlwaysNotNullAccordingToAPIContract` | 1 | `??` never null per annotations | per-site |

Two notes on getting this to zero rather than to "small":

- **75 of the 178 are the annotation family** - `ConditionIsAlwaysTrueOrFalse`,
  `ConstantConditionalAccessQualifier`, `ConstantNullCoalescingCondition`,
  `HeuristicUnreachableCode`. These flag our own defensive null checks as provably
  unnecessary, on the strength of .NET 10 annotations net472 never had. Each one is either
  dead code to delete or a guard to keep with a suppression; they cannot be swept.
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
    **Do not just delete it.** It is redundant only because `IntPtr` IS `nint` on net10 and
    takes an implicit `int` conversion; on a net472 leg that cast is load-bearing. This one
    needs a suppression or a multi-target check, not a deletion.
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

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260918_inspection_in_build.md` before starting work.
