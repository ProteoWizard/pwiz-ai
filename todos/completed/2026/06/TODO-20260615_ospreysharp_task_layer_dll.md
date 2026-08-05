# TODO-20260615_ospreysharp_task_layer_dll.md -- Lift the OspreySharp task layer into the OspreySharp.Tasks DLL

> PR 2 of the OspreySharp debt-paydown arc (PR 1 = #4302, the diagnostics seam,
> merged 2026-06-15). Move the ~7,900-LOC task bodies out of the exe project
> (`OspreySharp\Tasks\`) into the `OspreySharp.Tasks` DLL so the pipeline layer
> becomes unit-testable. **Pure relocation, output-identical, regression-gated --
> no new tests** (those are PR 3). Unblocked by PR 1: the task bodies no longer
> reach the exe-only OspreyDiagnostics static facade. See
> [[project_ospreysharp_debt_paydown_arc]].

## Branch Information
- **Branch**: `Skyline/work/20260615_ospreysharp_task_layer_dll`
- **Base**: `master` (cut from post-#4302 master, 6752500b)
- **Created**: 2026-06-15
- **Status**: Completed
- **PR**: [#4304](https://github.com/ProteoWizard/pwiz/pull/4304) (merged 2026-06-16)

## Decisions (Brendan, 2026-06-15)
1. **Fold into the existing `OspreySharp.Tasks` DLL** (not a new OspreySharp.Pipeline
   project). Tasks becomes the full pipeline layer; resolves the confusing "two
   folders named Tasks" (exe `OspreySharp\Tasks\` vs the Tasks DLL).
2. **Task-bodies-first scope.** Move the task bodies only; leave AnalysisPipeline
   (driver), RescoreWorker, Program, and the diagnostics sink in the exe. The
   full thin-exe (moving AnalysisPipeline + the 2076-line OspreyFileDiagnostics +
   the OspreyDiagnostics bootstrap) is a deliberate follow-on, not this PR.

## Versioning decisions (Brendan, 2026-06-15) -- supersedes the old "move VERSION to a Core const" plan
Context: OspreySharp is becoming the official released tool, shipped with Skyline
like SkylineBatch; Rust Osprey is being discontinued (see memory
project_ospreysharp_official_rust_retired). So OspreySharp adopts the **Skyline
versioning scheme** (`YEAR.ORDINAL.BRANCH.DOY` from Jamfile constants) and drops
the old Rust-release number ("26.6.1") that `Program.VERSION` carried.

There are TWO distinct version concepts; do NOT conflate them:
- **Assembly/file version** (currently the `1.0.0.0` placeholder in
  `Directory.Build.props`): the build identity. Follows the Skyline scheme.
- **Logical "osprey version"** (currently `Program.VERSION = "26.6.1"`): stamped
  into the blib (`osprey_version`), parquet/sidecar (`osprey.version`), and read by
  `ParquetScoreCache.CheckParquetMetadata` to gate cache reuse. Also moves to the
  Skyline scheme, derived from the build version.

Design (agreed):
1. **Version is build-derived in ALL real builds.** Jamfile injects
   `YEAR.ORDINAL.BRANCH.DOY` for Boost/official; **`build.ps1` computes + injects
   the same** for standalone/dev (so dev binaries report their true version --
   no static "dev version" fork, no second source of truth). Duplicate the small
   DOY calc from Skyline's Jamfile for now; consolidate to a shared Jamfile later.
2. **`OspreyVersion.Current` in OspreySharp.Core** replaces `Program.VERSION`:
   returns the assembly version by default, **overridable via a diagnostic env var
   `OSPREY_VERSION_OVERRIDE`**. This one accessor feeds all three consumers (blib
   stamp, parquet/sidecar stamp, cache-compat read).
3. **Bit-parity determinism via the override, not a frozen version.** The version
   is daily-changing, which WOULD break the mode-1 golden (the `OspreyMetadata`
   table compares `osprey_version` as an Exact column -- BlibGolden.ps1; written
   at MergeNodeTask:1079). `regression.ps1` sets `OSPREY_VERSION_OVERRIDE` to a
   canonical constant for every invocation in the run, so the stamped value is
   deterministic. **No comparator change** -- the golden still compares the field,
   we just make the input deterministic at the source (so this does NOT touch the
   bit-parity-tolerance sign-off rule; we are not skip-listing a compared field).
   Keep the assembly `AssemblyVersion`/`FileVersion` as the real build value -- they
   are never stamped into the blib, so they are not bit-parity-sensitive and need
   no override.
4. **`ParquetScoreCache` cache-compat reworked to 4 components.** Old semantics:
   `major.minor` mismatch -> abort, `patch` drift -> warn+proceed. New mapping:
   `YEAR.ORDINAL.BRANCH` = release identity (mismatch -> abort, the old
   major/minor rule); `DOY` = daily drift (differ -> warn+proceed, the old patch
   rule). So daily builds within a release line still reuse caches; crossing an
   official-release boundary aborts. Update `TryParseVersion` (now 4 ints),
   `CheckParquetMetadata`, the `ProgramTests` drift tests, and `IOTest`'s
   `TASK_VERSION` constant.

## Exe-only coupling to resolve (scoped 2026-06-15)
The task bodies are nearly DLL-ready already (PR 1 removed the diagnostics-facade
reach). Remaining exe-only deps:
- **`Program.VERSION` / `Program.VERSION_STRING`** -- used by MergeNodeTask (389,
  1079), PerFileRescoreTask (563, 877), PerFileScoringTask (195, 822, 1021), and
  AnalysisPipeline (230). **Replaced by `OspreyVersion.Current` in OspreySharp.Core**
  (see Versioning decisions above); update all refs. This is now commit 1's
  versioning rework, not a simple const move.
- **`ProfilerHooks`** -- used by AbstractScoringTask. **Move ProfilerHooks.cs into
  the Tasks DLL**; move the `JetBrains.Profiler.Api` PackageReference from the exe
  csproj to the Tasks csproj.
- **Two stale comments** naming OspreyDiagnostics (no code impact): PerFileRescoreTask:788,
  PerFileScoringTask:1455 -- tidy while here.
- **AnalysisPipeline stays in exe** but constructs the (now-DLL-internal) tasks via
  `CanonicalPipeline()` -- works because the Tasks DLL already grants
  `InternalsVisibleTo("OspreySharp")`. Verify it still resolves after the move
  (or move `CanonicalPipeline()` into the DLL as a factory).

## Move set (into OspreySharp.Tasks DLL)
- `OspreySharp\Tasks\AbstractScoringTask.cs`, `Calibrator.cs`, `FirstJoinTask.cs`,
  `MergeNodeTask.cs`, `PerFileRescoreTask.cs`, `PerFileScoringTask.cs`,
  `PipelineByproducts.cs` -- already in namespace `pwiz.OspreySharp.Tasks`, so
  **no namespace change** (just `git mv` into the DLL folder).
- `RescoreHydration.cs` / `RescoreCompaction.cs` -- **verify**: if the task bodies
  reference them (likely -- hydration/compaction are part of rescore), move them
  too; if only AnalysisPipeline uses them, they can stay in the exe. Determine by
  build error during the move.
- `ProfilerHooks.cs`.

## csproj changes
- **OspreySharp.Tasks.csproj**: add ProjectReferences to IO, ML, Chromatography,
  Scoring, FDR (the bodies call ParquetScoreCache, PercolatorFdr, CoelutionScorer,
  etc.); add the `JetBrains.Profiler.Api` PackageReference. Keep Core + Diagnostics
  refs + the two InternalsVisibleTo (OspreySharp, OspreySharp.Test).
- **OspreySharp.csproj** (exe): drop the JetBrains.Profiler.Api package (moved);
  keep all ProjectReferences (still references Tasks DLL).
- **OspreySharp.Core.csproj**: gains `OspreyVersion` (no ref changes).
- Confirm no dependency cycle: Tasks -> {Core, Diagnostics, IO, ML, Chromatography,
  Scoring, FDR}; nothing below references Tasks. Exe -> Tasks (+ all). Acyclic.

## Commit plan (one PR, parity-gated each commit -- the PR-1 cadence)
Each commit: `Build-OspreySharp.ps1 -RunTests -RunInspection`, then
`regression.ps1 -Dataset Stellar`. Commits 2-4 are pure relocation (output stays
byte-identical); commit 1 is the versioning rework (changes the version *value*
but, via the override, keeps the golden green -- a deliberate behavior change to
the version string, not a relocation).
1. **Versioning rework** (see Versioning decisions above):
   - `OspreyVersion.Current` in OspreySharp.Core (assembly version + `OSPREY_VERSION_OVERRIDE`).
   - Jamfile: add `OSPREY_YEAR/ORDINAL/BRANCH` + DOY calc; inject `/p:Version=...`
     into the `do_osprey_sharp` msbuild action.
   - `build.ps1`: compute the Skyline-scheme version + inject `/p:Version=...`.
   - `Directory.Build.props`: set the version properties (real default; the build
     scripts override).
   - Repoint all `Program.VERSION`/`VERSION_STRING` refs to `OspreyVersion.Current`.
   - Rework `ParquetScoreCache.TryParseVersion`/`CheckParquetMetadata` to 4 comps;
     update `ProgramTests` drift tests + `IOTest` `TASK_VERSION`.
   - `regression.ps1`: set `OSPREY_VERSION_OVERRIDE` to a canonical constant for
     every invocation; confirm mode-1 golden stays green with the new version.
2. Move `ProfilerHooks.cs` into Tasks DLL; shift the JetBrains package ref.
3. `git mv` the task bodies + PipelineByproducts (+ RescoreHydration/Compaction if
   needed) into the Tasks DLL; add the csproj ProjectReferences; fix
   `CanonicalPipeline()` resolution; tidy the 2 stale comments.
4. (If split needed) repoint OspreySharp.Test references; confirm tests still bind.

## Pre-merge gate
`regression.ps1 -Dataset All` (Stellar + Astral) + `Test-PerfGate.ps1 -Dataset Stellar`
(relocation -> expect perf-neutral) + zero-warning inspection + `/pw-self-review`.
A dumps-on run is NOT needed (no diagnostics code changes this PR).

## Out of scope (future)
- Full thin-exe: move AnalysisPipeline + OspreyFileDiagnostics + OspreyDiagnostics
  bootstrap out of the exe.
- PR 3: extract collaborators (per-file resume driver, PercolatorRunner, reconciliation
  I/O) + the unit tests that migrate coverage off the 41-min nightly regression.
- The `IOspreyDiagnostics : IScoringDiagnostics` / gate-flags-vs-writes interface split.

## Progress Log

### 2026-06-15 -- Created
Scoped the exe-only coupling (above) after #4302 merged. Decisions captured. Branch
cut from post-#4302 master. **Implementation deferred to a fresh context** -- the
~8,000-LOC cross-DLL move plus per-commit build/regression cycles needs more
headroom than remained in the session that planned it. Next session: execute the
commit plan above; it is a pure `git mv` + csproj-wiring relocation, so the Stellar
regression after each commit is the proof it stayed output-identical.

### 2026-06-15 -- Versioning rework folded into commit 1
On resuming, Brendan noted OspreySharp versioning should follow the Skyline scheme
(AssemblyInfo from Jamfile constants) rather than the hardcoded `Program.VERSION`.
Investigation found `Program.VERSION = "26.6.1"` is a 3-part cache-compatibility
version tracking the (now-discontinued) Rust release, consumed semantically by
`ParquetScoreCache.CheckParquetMetadata` and stamped into the blib's compared
`OspreyMetadata` table -- so a naive swap to the daily-changing Skyline version
would break the mode-1 golden. Decision: unify onto the Skyline scheme (Rust is
being retired, so its versioning has no claim) and keep the regression deterministic
via a diagnostic `OSPREY_VERSION_OVERRIDE` env var that `regression.ps1` pins, NOT a
frozen dev version and NOT a comparator skip-list. Full design under "Versioning
decisions" above; commit plan updated (commit 1 is now the versioning rework).
Starting commit 1 implementation now.

### 2026-06-15 -- Commit 1 (versioning rework) implemented + gated GREEN
Implemented and verified the versioning rework:
- `OspreySharp.Core/OspreyVersion.cs` -- new `OspreyVersion.Current` (assembly
  version by default, `OSPREY_VERSION_OVERRIDE` diagnostic override).
- Repointed all `Program.VERSION`/`VERSION_STRING` refs (Program, AnalysisPipeline,
  MergeNodeTask, PerFileRescoreTask, PerFileScoringTask) to `OspreyVersion.Current`;
  removed the const + its obsolete Rust-release-tracking comment (kept the
  --decoys-in-library limitation note).
- `ParquetScoreCache.TryParseVersion`/`CheckParquetMetadata` -> 4 components
  (YEAR.ORDINAL.BRANCH = release identity -> abort; DOY = daily drift -> warn).
- `ProgramTests` drift tests reworked to 4 comps (Daily/Branch/Ordinal/Year);
  `IOTest` needed NO change (its version fixtures are opaque -- ValidateMetadata
  does dict equality, TaskValiditySidecar.IsValid ignores version; verified).
- `Directory.Build.props` version -> 26.1.1.0 (was placeholder 1.0.0.0).
- `build.ps1` computes + injects `/p:Version=YEAR.ORDINAL.BRANCH.DOY` (git-date DOY).
- `Jamfile.jam` adds OSPREY_YEAR/ORDINAL/BRANCH + DOY calc, injects
  `;Version=$(OSPREY_VERSION)` into the msbuild action. **NOTE: the Jamfile path is
  only exercised by the official `bjam OspreySharp` Boost build -> verified by
  TeamCity, NOT the local gates.**
- `regression.ps1` pins `OSPREY_VERSION_OVERRIDE=26.1.1.0`; both golden
  `OspreyMetadata.tsv` (stellar+astral) updated 26.6.1 -> 26.1.1.0.

Gates (all GREEN): Build-OspreySharp.ps1 -RunTests -RunInspection = build clean,
**0 inspection warnings**, **383 tests pass** (2 cross-impl skips). `regression.ps1
-Dataset Stellar` = build stamped v26.1.1.166 (DOY 166 = 2026-06-15), **mode 1 (vs
golden) PASS** + **mode 2 (resume) PASS** -- proves the daily build version +
override keeps the golden deterministic. Ready to commit. Next: commits 2-4 (the
task-layer DLL move).

### 2026-06-15 -- Commits 1-3 landed; task-layer move complete
All three commits on the branch, each gated green:
- **a042b0a0f4** (commit 1) -- versioning rework (above).
- **4fb2f44a1b** (commit 2) -- ProfilerHooks -> OspreySharp.Tasks; JetBrains.Profiler.Api
  package ref shifted exe -> Tasks. Build+test+inspect green.
- **b651b7938e** (commit 3) -- the 7 Stage task bodies + RescoreHydration/RescoreCompaction
  git mv'd into OspreySharp.Tasks (SDK auto-include, no <Compile> edits); added
  IO/ML/Chromatography/Scoring/FDR ProjectReferences; Rescore* namespaces ->
  pwiz.OspreySharp.Tasks; tidied the 2 stale comments + a now-cross-assembly
  AnalysisPipeline cref. **Build clean, 0 warnings, 383 tests pass, Stellar
  regression mode 1 + mode 2 PASS (blib byte-identical, 52,514,816 bytes).**
**Commit 4 (repoint OspreySharp.Test) was NOT needed** -- the tests bind the task
types through the Tasks DLL's InternalsVisibleTo and pass unchanged.
CanonicalPipeline() in the exe still resolves (IVT("OspreySharp")), no change.

Remaining pre-merge gate: `regression.ps1 -Dataset All` (add Astral) +
`Test-PerfGate.ps1 -Dataset Stellar` (expect perf-neutral) + `/pw-self-review`,
then open the PR.

### 2026-06-15 -- Pre-merge gate green; commit 4 (hardening) added; opening PR
Pre-merge gate all green:
- **Astral regression** (mode 1 + mode 2) PASS at b651b7938e (blib byte-identical
  136,622,080 bytes); Stellar already PASS at that HEAD = `-Dataset All` covered.
- **Perf gate** (Stellar 3-rep A/B vs pwiz-perfbase) PASSED -- median total -1.4%,
  perf-neutral (run-1 cold-cache outlier washed out by the median).
- **`/pw-self-review`** (fresh-context agent): no critical/high/medium; 3 LOW notes.
  Finding 1 (legacy 3-component caches bypassed the version gate) -> addressed by
  commit 4. Findings 2-3 (DOY cross-check reasoned-not-tested; tests read stamped
  version) deferred/no-action.

**Commit 4 -- 5fc76879e6** -- on Brendan's call (project principle: hard fail over
warn-and-proceed; see memory feedback_hard_fail_over_warn_proceed): CheckParquetMetadata
now HARD-FAILS on ANY osprey.version mismatch (release/daily/unrecognized) instead of
warn+proceed; removed the now-dead warning/logWarning plumbing; flipped the daily +
unparseable unit tests to assert abort. **Verified it does NOT increase regression
workload**: re-ran Stellar with the hardening -> mode 2 (resume) PASS with the fast
1:18 resume (caches reused by exact match, NOT recomputed); golden stays deterministic
via OSPREY_VERSION_OVERRIDE, so no new snapshot per build.

Final commit stack: a042b0a0f4 (versioning) / 4fb2f44a1b (ProfilerHooks) /
b651b7938e (task bodies) / 5fc76879e6 (hardening). Opening the PR.

### 2026-06-15 -- PR #4304 opened; Copilot round addressed (commit 238221847d)
PR #4304 opened. Copilot left 9 inline comments. Addressed 3, pushed back on 6:
- **REAL BUG (Copilot #9)**: Directory.Build.props pinned <AssemblyVersion>/<FileVersion>
  explicitly, which BLOCKED the /p:Version override -- OspreyVersion.Current (reads
  Assembly.GetName().Version) always returned the static 26.1.1.0; the daily build
  version never flowed through. The regression masked it (override sets the value
  directly). Fixed: dropped the explicit AssemblyVersion/FileVersion so they derive
  from <Version>. Verified: Release build now reports `OspreySharp v26.1.1.166` from
  --version (was 26.1.1.0). [commit 238221847d]
- Two stale-doc fixes (OspreyVersion XML doc + a ProgramTests comment still said the
  old "warn but proceed").
- 6 translation-proof nits on internal diagnostic-string assertions: pushed back
  (non-localized internal strings; matches existing convention; one is pre-existing).
  Threads left open for the human reviewer. See memory feedback_tests_assert_whole_constants.

**Side finding (Brendan flagged):** the ` -- ` double-hyphen in an XML comment broke
the build, surfacing an LLM habit. Audit of OspreySharp: 139 Unicode em/en-dashes +
235 ASCII ` -- `-in-comments, none caught by any verifier (inspection passes clean).
STYLEGUIDE.md updated to ban both. Verifier + cleanup = separate effort (TBD scope).

### 2026-06-16 - Merged
PR #4304 merged as commit 6ee60e4e43 (squash). Shipped all four planned commits:
the Skyline version scheme + OspreyVersion.Current with the OSPREY_VERSION_OVERRIDE
bit-parity seam, the cache-version hard-fail hardening, the ProfilerHooks move, and
the lift of the seven task bodies + RescoreHydration/RescoreCompaction into the
OspreySharp.Tasks DLL (pipeline layer now a unit-testable DLL). Gated green
throughout: build + 0-warning inspection + 383 tests, Stellar + Astral regression
(mode 1 + mode 2), perf-neutral (-1.4% Stellar), fresh-context self-review, and the
Copilot round (a real AssemblyVersion-pinning bug caught and fixed + verified; six
translation-proof nits pushed back and resolved). Out of scope / deferred: the full
thin-exe (AnalysisPipeline + OspreyFileDiagnostics + the diagnostics bootstrap stay
in the exe), PR 3 (extract collaborators + migrate coverage off the nightly), and the
IOspreyDiagnostics interface split. Follow-up filed: the dash-hygiene verifier +
cleanup backlog plan (ai/todos/backlog/TODO-dash_hygiene_verifier_and_cleanup.md).
