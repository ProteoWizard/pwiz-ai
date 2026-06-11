# TODO-20260610_osprey_regression_testperf.md -- OspreySharp CI regression (TestPerf-style download + no-copy run)

> Build the fully-supported OspreySharp regression test a TeamCity agent can run
> overnight. It behaves like a Skyline `TestPerf` test: it **downloads a data zip**
> from panoramaweb into the shared Perftests download folder, **unzips it there**,
> **skips the download when the files are already present**, then runs OspreySharp
> against the extracted files **as read-only inputs** (no copies -- enabled by the
> just-merged `--work-dir`/`--output-dir`/`--cache-dir` feature) and writes all
> output + cache files to `pwiz_tools/OspreySharp/TestResults`. This is the nightly
> "Osprey Windows .NET Regression" config we have discussed, now unblocked.

## Branch Information

- **Branch**: `Skyline/work/20260610_osprey_regression_testperf` (to be created;
  default to `C:\proj\pwiz` per the plain-worktree preference)
- **Base**: `master`
- **Created**: 2026-06-10
- **Status**: **IN PROGRESS.** Branch created; harness implemented + unit-validated
  against blib fixtures; end-to-end run + golden commit in progress. See Progress Log.
- **Next session handoff**: For the startup protocol, read
  `ai/.tmp/handoff-20260610_osprey_regression_testperf.md` before starting work.
- **Predecessor TODO**:
  [`TODO-20260609_osprey_output_cache_dir.md`](../completed/TODO-20260609_osprey_output_cache_dir.md)
  -- the `--work-dir`/`--output-dir`/`--cache-dir` decoupling (pwiz #4278 `c5f4d9c`,
  maccoss/osprey #47 `696c938`) that lets a run read read-only inputs and write only
  to a work dir. That capability is the foundation this builds on.
- **GitHub Issue**: (none)
- **PR**: (planned)

## Mission

Stand up an overnight TeamCity regression for OspreySharp that needs no manual data
staging: it acquires its test data the way Skyline perf tests do (download + unzip +
skip-if-present), runs the full pipeline on real data with **zero input copies**, and
flags any regression -- so OspreySharp (now the primary implementation) has a real
end-to-end gate, not just per-commit unit tests.

## Context (what exists now)

- **Per-commit config** `ProteoWizard_OspreyWindowsNet` ("OspreySharp Windows .NET")
  runs `pwiz_tools/OspreySharp/tcbuild.bat` -> `build.ps1 -TeamCity -Coverage`
  (build + unit tests under dotCover + TeamCity service messages). `build.ps1` is
  deliberately **pwiz-standalone** (no `ai/` dependency) -- the CI design constraint
  this work must respect.
- **Overnight config** "Osprey Windows .NET Regression" -- Matt will create it on
  TeamCity; our job is the self-contained entry point + the config spec (schedule
  trigger, agent requirements, data acquisition, expected duration).
- **The `--work-dir` feature just merged**: input mzML + library can be referenced
  in place (read-only); every per-file artifact (scores parquet, calibration JSON,
  FDR/reconciliation sidecars, `.spectra.bin`, library `.libcache`) and the blib go
  to the work dir. Verified end-to-end no-copy on both impls.

## Data acquisition -- model on Skyline TestPerf

Two zips are staged on panoramaweb (beside the existing Skyline/TestPerf data):

- mzML (use this until Osprey reads raw):
  `https://panoramaweb.org/_webdav/MacCoss/software/%40files/perftests/osprey-testfiles-mzML.zip`
- raw (for later, once `pwiz_data_cli` is wired in):
  `https://panoramaweb.org/_webdav/MacCoss/software/%40files/perftests/osprey-testfiles.zip`

They download + unzip into the shared Skyline perf-test downloads folder
(`D:\Users\brendanx\Downloads\Perftests` on this machine -- i.e.
`<Downloads>\Perftests`), alongside the many Dario-Amodei mProphet datasets already
there. Extracted layout (from the earlier local staging): `osprey-testfiles-mzML\`
with `stellar\` and `astral\` subfolders (each `*.mzML` + a `*.tsv` library +
`*.fasta`).

Mirror Skyline's mechanism (read for reference, don't necessarily reuse the types):
- `pwiz_tools/Skyline/TestUtil/AbstractUnitTest.cs` -- `DownloadZipFile`
  (`HttpClientWithProgress.DownloadFile`, `SKYLINE_DOWNLOAD_FROM_S3` -> `ci.skyline.ms`
  toggle).
- `GetTargetZipFilePath` -- targets `PathEx.GetDownloadsPath()\<UrlFolder>` (the URL's
  `.../perftests/...` segment -> `Perftests`).
- `ExtensionTestContext.ExtractTestFiles` -- extracts with `DoNotOverwrite`, so a
  present file set is left alone (this IS the skip-if-present behavior).

**Skip-if-present**: if the extracted `osprey-testfiles-mzML\` tree is already in the
downloads folder, skip the download entirely. TeamCity agents start clean and always
download (fast AWS/panorama pipe); developer machines reuse the existing copy.

## The run -- no copies, output to TestResults

For each dataset (Stellar, Astral):
- Reference the extracted `*.mzML` and `*.tsv` library **in place** from the
  read-only downloads folder (`-i`/`-l` absolute paths). Do **not** modify that
  folder.
- Pass `--work-dir <pwiz_tools/OspreySharp/TestResults/<dated-run>>`. All derived
  artifacts + the `.spectra.bin` and `.libcache` caches land there; the downloads
  folder stays byte-for-byte untouched (verified pattern from the predecessor).
- Date-stamp the run dir under `TestResults` (like Skyline's `TestFilesDir`), so
  parallel/repeat runs don't collide and cleanup is trivial.

## What the regression asserts (from the earlier design)

Two complementary modes (no Rust required for the nightly):
1. **Straight-through vs golden** -- one end-to-end run per file; compare the final
   Stage 7 protein-FDR TSV + `output.blib` to a small golden (refreshed only on an
   intentional, reviewed behavior change). The user-facing correctness gate.
2. **Resume vs straight-through self-consistency** -- run the same build in
   two-invocation resume mode (`--task PerFileScoring` then `--task MergeNode` from
   the produced parquets, sharing one `--cache-dir`) and assert its final blib/TSV
   **equals** mode 1's output. The build is its own oracle, so **no baseline** is
   needed for the resume dimension -- this is what the predecessor's no-copy parity
   run already exercised manually.

Reuse the existing tolerance comparators (`Compare-Blib-Crossimpl.ps1` row+column
1e-9, `Compare-Stage7-Crossimpl.ps1`); decide whether to port slim copies into pwiz
for the standalone constraint or call them from `ai/` (see decisions). The heavy
stage-isolated snapshot harness (`Test-Snapshot.ps1`) stays in `ai/` as the
developer bisection tool -- not the nightly.

## Entry point + TeamCity config

- Self-contained pwiz entry point mirroring the per-commit one, e.g.
  `pwiz_tools/OspreySharp/tctest.bat` -> `regression.ps1` (or a `-Regression` mode on
  the existing `build.ps1`), emitting TeamCity service messages and a `buildProblem`
  on any mismatch. No `ai/` dependency.
- The new config is **schedule-triggered** (overnight), separate from the per-commit
  smart trigger; likely needs no entry in
  `scripts/misc/vcs_trigger_and_paths_config.py`.
- Deliverable for Matt: the entry-point script + a short config spec (VCS root, agent
  prereqs -- pwsh/VS Build Tools/.NET 8, the download step, schedule, expected
  duration, where the golden lives).

## Open decisions

1. **Harness language**: pure PowerShell harness (matches `build.ps1` standalone
   precedent and the "keep it in .ps1" steer) vs a C# `OspreySharp.Test` test that
   reuses/ports Skyline's `TestFilesDir` download. Leaning **PowerShell**.
2. **Downloads path**: derive `<Downloads>\Perftests` (Skyline convention) with an
   override (env var / `-TestBaseDir`) for agents whose downloads dir differs.
3. **Golden**: ship it inside the data zip, a separate small `osprey-golden.zip`, or
   checked into pwiz? And who refreshes it on an intentional behavior change.
4. **Comparators**: port slim copies into `pwiz_tools/OspreySharp/` (true
   standalone) vs invoke the `ai/` ones (simpler, but breaks pwiz-standalone).
5. **Scope per night**: Stellar + Astral, straight-through + resume = 4 full runs;
   confirm the wall-time budget (measure modern cost first -- the stale ~70 min
   figure was for the stage-isolated harness, not straight-through).

## Out of scope / future

- Raw-data path: `osprey-testfiles.zip` + `pwiz_data_cli.dll` wired into OspreySharp
  so the nightly reads `.raw` directly (drops the mzML-conversion layer).
- A `.libcache` source size+mtime fingerprint to match the `.spectra.bin` one
  (deferred from the predecessor; Rust already does an mtime check).

## Acceptance criteria

- On a clean agent, the harness downloads `osprey-testfiles-mzML.zip`, unzips into
  `<Downloads>\Perftests`, and on a second run skips the download.
- Runs Stellar + Astral with inputs referenced in place; the downloads folder is
  unchanged after the run; all output + caches are under `OspreySharp/TestResults`.
- Straight-through vs golden and resume vs straight-through both pass at 1e-9; a
  seeded regression makes the harness emit a TeamCity `buildProblem` and non-zero exit.
- The entry point is pwiz-standalone (no `ai/` checkout required on the agent).

## Open decisions — RESOLVED (2026-06-10, with Brendan)

1. **Harness language** → **PowerShell** (`regression.ps1`), matching the
   `build.ps1` standalone precedent.
2. **Downloads path** → derive `<Downloads>\Perftests` via the Windows
   known-folder rule (honours a relocated Downloads, e.g. D:) with
   `SKYLINE_DOWNLOAD_PATH` + `-DownloadsPath` overrides. Mirrors
   `PathEx.GetDownloadsPath` + `GetTargetZipFilePath`.
3. **Golden** → **small committed text** in `osprey-regression.data/<dataset>/`.
   The full-fidelity blib is ~50 MB (Stellar) / ~135 MB (Astral) — too big to
   commit — so the golden is `protein_fdr.tsv` (full) + a deterministic
   ~500-precursor subset of per-table projections + a full-set `blib_summary`
   (counts + aggregates). Measured Stellar golden = **0.61 MB**. Versioned with
   the code so an older tag runs against its own baseline; refreshed only via
   `-CreateGolden` on a reviewed behavior change.
4. **Comparators** → **ported slim into pwiz** (`Regression/BlibGolden.ps1`), no
   `ai/` dependency. Same projection schema + 1e-9 tolerance as the cross-impl
   `Compare-Blib-Crossimpl.ps1`.
5. **Scope per night** → Stellar + Astral, each straight-through (mode 1) +
   resume (mode 2). Wall time TBD from the first agent run; comparison overhead
   is minutes (mode-2 full blib compare ~164s Stellar; see perf note).

## Progress Log

### 2026-06-10 — Harness built + unit-validated; end-to-end in progress
Branch `Skyline/work/20260610_osprey_regression_testperf` created off master.

**Risk cleared first (per verify-before-assuming):** the resume leg depends on a
resume path that was RED by design until recently. Confirmed the 1st-pass-RT
resume bug was **fixed + merged** as PR #4270 (`6d6db7dd`, 2026-06-05) and the
resume parity gate is green; the "FAILS today" comment still in
`ai/scripts/.../Compare-StraightThroughResume-CSharp.ps1` is stale doc-lag.
Mode 2 is therefore viable; empirically re-confirmed below.

**Implemented (pwiz_tools/OspreySharp/, all pwiz-standalone):**
- `Regression/RegressionData.ps1` — `Get-RegressionData`: download (HttpClient) +
  DoNotOverwrite extract + skip-if-present. Path derivation validated → resolves
  to `D:\Users\brendanx\Downloads\Perftests\osprey-testfiles-mzML`.
- `Regression/BlibGolden.ps1` — blib projection schema (single source of truth)
  + SQLite access (System.Data.SQLite from the build output) + `Save-BlibGolden`
  (capture), `Compare-BlibGolden` (mode 1 vs committed text golden),
  `Compare-BlibFull` (mode 2 full blib-vs-blib).
- `regression.ps1` — orchestrator: build → acquire data → per dataset
  straight-through (no-copy, `--work-dir`, `OSPREY_DUMP_STAGE7_PROTEIN_FDR`) →
  no-copy assertion (data dir fingerprint unchanged) → mode 1 vs golden → mode 2
  resume (invalidate FirstJoin sidecars + blib, re-run, compare). TeamCity
  service messages + `buildProblem` mirror `build.ps1`.
- `tctest.bat` — scheduled TeamCity entry point.
- `Regression/README.md`, `Regression/TEAMCITY-CONFIG.md` (spec for Matt).

**Validated against blib fixtures (no run needed):**
- Golden capture: Stellar **0.61 MB** text, ~516-precursor subset.
- mode 1: cold-vs-own-golden **PASS** (0 issues); buggy-resume-vs-golden
  **FAIL** (36 issues) correctly localized to RetentionTimes/RefSpectra RT.
- mode 2: cold-vs-cold **PASS**; cold-vs-buggy **FAIL** (18 issues,
  11058/59768 RefSpectra RT rows) — catches the exact historical bug.

**Perf note:** `Compare-BlibFull` (mode 2, full blib) ~165s/Stellar in pure
PowerShell (per-cell rendering of 180K rows dominates); ~2-3x for Astral.
Acceptable for an overnight (one mode-2 compare/dataset). A SQL-ATTACH diff or
raw-value compare would cut this materially — deferred follow-up.

**End-to-end VALIDATED on real data (Stellar):**
- Data acquisition: downloaded osprey-testfiles-mzML.zip = **~14 GB** (these are
  real DIA mzML, ~1.5 GB each; extracts to ~25 GB) in ~130s; second run printed
  "data present, skipping download" → **skip-if-present works**.
- Cold straight-through 4:10, blib 52,514,816 bytes; **no-copy assertion PASS**
  (caches/.spectra.bin/.libcache to work-dir; read-only data dir untouched).
- Golden captured = **1.1 MB** text (0.45 MB protein_fdr + 0.6 MB blib
  projections), committed to `osprey-regression.data/stellar/`.
- **mode 1 (cold vs golden): PASS** at 1e-9.
- Resume 1:38 (loads, not recomputes); **mode 2 (resume==straight): PASS** at
  1e-9 — the empirical re-confirmation that PR #4270's resume fix holds.

Two bugs found + fixed during real runs: `"$name:"` PS interpolation (→
`${name}:`); and `-o output.blib` / Stage 7 dump are CWD-relative not
`--work-dir`-relative, so `Invoke-OspreyRun` now `Push-Location $WorkDir`. Also a
SQLite file-lock on the mode-2 invalidation (pooled handle from the mode-1
compare) → `Pooling=False` + `Dispose` in `Invoke-BlibQuery`.

**Astral also VALIDATED end-to-end (hram):** golden captured = **2.4 MB**;
cold straight-through 15:28, blib 136,622,080 bytes; **mode 1 (vs golden) PASS**
(committed golden reproducible by a fresh cold run); resume 2:16; **mode 2
(resume==straight) PASS**. Both goldens committed-ready (stellar 1.1 MB + astral
2.4 MB = 3.5 MB text under `osprey-regression.data/`). Repo root verified clean
(two first-run leftover output files removed; `Push-Location` prevents
recurrence).

**Status: feature complete + validated; PR [#4280](https://github.com/ProteoWizard/pwiz/pull/4280)
open (3 commits, squash-merge pending).**

Review rounds done:
- **Copilot** (3 comments, all fixed + threads resolved, `61ad1b14f0`): zip-slip
  guard in `Expand-ZipNoOverwrite`; corrected README golden size; fixed a
  `BlibGolden` header path comment.
- **`/pw-self-review`** fresh-context agent (`47a1a29b34`): found 1 HIGH + 3 LOW.
  HIGH = same-day re-run left `$straightDir` un-wiped, so the "straight-through"
  leg resumed against leftover mode-2 invalidation state and mode 1 silently
  compared a mislabeled resume blib to the golden. Fixed by wiping `$straightDir`
  before each leg; **validated** (same-day re-run now cold 03:42, not 00:00, both
  modes PASS). LOWs: hoisted subset modulus to one `$script:DefaultModulus`;
  documented mode 1's out-of-subset blind spot + SUM order-dependence; corrected
  the TEAMCITY-CONFIG trigger section to the per-PR-overnight smart-trigger model.

**Remaining:**
- Commit the harness + both goldens (`/pw-pcommit`).
- Hand Matt the `Regression/TEAMCITY-CONFIG.md` spec to create the scheduled
  "Osprey Windows .NET Regression" config; fill its Astral wall-time from the
  first real agent run.
- (Deferred) faster mode-2 compare (SQL-ATTACH / raw-value) if nightly wall-time
  matters; raw-data path (`osprey-testfiles.zip` + `pwiz_data_cli`).
