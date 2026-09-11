# TODO-osprey_log_readability.md - make Osprey's log read for a mass spectrometrist

## Branch Information
- **Branch**: (pending; suggest `Skyline/work/YYYYMMDD_osprey_log_readability`)
- **Base**: `master`
- **Created**: 2026-09-11
- **Status**: Backlog (spec complete, not started)
- **GitHub Issue**: (pending)
- **Module**: `osprey`
- **PR**: (pending)

**Origin**: Brendan, 2026-09-09, after noticing that log terms such as "projection" come from
class names Claude assigned during development and mean nothing to a user. Reviewed line by
line on 2026-09-09..11 against master `794cb6a5d8` (#4646). Supersedes
`ai/todos/backlog/TODO-osprey_log_lines_are_user_facing_prose.md` (now a stub pointing here).
Related: `ai/todos/backlog/TODO-osprey_env_var_cataloging.md` (env vars named in log lines).

**Companion files beside this TODO** (the spec is the three of them together):

| File | What it is |
|---|---|
| `TODO-osprey_log_readability-spec.html` | The review page: glossary with decisions, Table A (user-facing lines by confusion, with rewrites), B1 (developer lines leaking into the default log), B2 (gated diagnostics inventory), C (warnings written for a developer). Open in a browser. Same content as the published artifact `https://claude.ai/code/artifact/c51944d7-39b3-4208-9432-92160c6a2fca`. |
| `TODO-osprey_log_readability-lines.csv` | One row per emitting call site (583), with priority, the flag that exposes it, current text, flagged terms, why, suggested text and action. Line numbers are for master `794cb6a5d8`. |
| `TODO-osprey_log_readability-terms.csv` | The term sheet with Brendan's decisions in the "Brendan decision so far" column. |

The HTML is the readable form; the CSV is the checklist to work down. Where they disagree,
the HTML is newer.

## Summary

Osprey's console log is its only user interface, and roughly a third of the lines a user sees
in an ordinary run use vocabulary that exists only inside the codebase: sidecar, compaction,
survivors, hydrate, stratum, base_id, fold, bundle, stubs, projection. Some lines print C#
method names (`[PATH] First-pass streaming ingest (RunStreamingFirstPass)`), some announce the
default behaviour by an environment-variable assignment the user never made
(`OSPREY_PASS2_QVALUE=protein-compact: ...`), and the second-pass progress headings narrate the
code structure (seed, collect, stream, patch, reload) rather than what the user is waiting for.

The gating of developer output is in good shape: `[COUNT]`/`[TIMING]`/`[BENCH]`/`[STAGE-WALL]`
are behind `--perf-stats`, `[MEM ...]` behind `OSPREY_LOG_MEMORY`, bisection dumps behind
`-d`/`OSPREY_DUMP_*`, implementer detail behind `--verbose`. The problem is inside the default
tier. The fix has three parts, in this order: **gate** the developer lines that leak (no wording
decisions needed), **rewrite** the user-facing lines with the decided vocabulary, and **move
every script and test that keys off prose onto tagged machine lines**, so the prose can change
now and be translated later without breaking a gate.

## Evidence (master `794cb6a5d8`, tests excluded)

| Tier | Call sites | Exposed by |
|---|---:|---|
| default log | 399 | every run |
| perf stats | 83 | `--perf-stats` (`[COUNT]` `[TIMING]` `[BENCH]` `[STAGE-WALL]`) |
| model diagnostics | 35 | `--model-diagnostics` |
| bisection dumps | 31 | `-d`, `OSPREY_DUMP_*`, `OSPREY_DIAG_*` |
| verbose | 20 | `--verbose` |
| FDRBench / entrapment | 12 | `--fdrbench` |
| memory probes | 3 | `OSPREY_LOG_MEMORY` |

Inside the 399 default lines: 47 contain a C# method, class, task or variable name; 53 say
"sidecar"; 15 name an `OSPREY_*` variable; about 120 use at least one codebase-only term.
Only 3 of 583 sites format a count with a thousands separator.

Two real logs were read end to end: the 3-file Stellar run
`D:\test\osprey-runs\defectb2-stellar.log` and the 82-file Astral run
`D:\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compact-s7offB-20260831_115149\run.log`.
In the 82-file log, 82 of 369 lines are the same developer note repeated once per file
("Loaded N FDR stubs (features not loaded - not read on this path)").

## Decided vocabulary (Brendan, 2026-09-09..11)

Use this as the rename map. The full table with meanings is the glossary on the spec page.

| Never in user text | Say instead |
|---|---|
| sidecar | **intermediate file** ("intermediate" is the key word: not the end result). Name the file where it helps. |
| entry / entries, base_id(s) | **precursor candidates** (targets + decoys); "candidates" replaces "entries" and "library entries" everywhere |
| compaction / compact | say what was kept: "kept N of M precursor candidates for cross-run reconciliation" |
| survivors / survivor pool / retained set | precursor candidates carried forward (no objection recorded; open) |
| stratum, protein-compact stratum | **precursor candidates from proteins with 2 or more detections**; "protein-compact subset" only where the flag itself is named. "Detections" = passed the current cutoff, without saying which. |
| hydrate / rehydrate | load / reload from intermediate files (open) |
| fold (verb) | one run at a time. Not liked even as a developer term. |
| projection | (the last progress heading using it was removed by #4646; the `[PATH]` line moves to perf-stats) |
| bundle / envelope | **cross-run reconciliation files**. "Reconciliation plan" was opaque; "results" is reserved for end results a user looks at. |
| stubs | "Loading FDR values from intermediate files" (one heading, not one line per file) |
| scalars | first-pass scores (open) |
| frozen model / no retrain | **drop**. Records what the code no longer does; diagnostic channel only if a test needs it. |
| use_cwt / forced / gap-fill / action(s) | **peaks re-picked / peak boundaries imputed / missing peaks** (Skyline's peak-boundary-imputation vocabulary; in a count, just "missing peaks") |
| Stage 1-4 / 5 / 6 / 7 | never a stage number. The `--task` names are fine: the CLI help documents them. |
| resident, byproduct, interned, parquet index | diagnostic output if a test needs it, else drop |
| worker / fan-out / join | per-file run / merge (open) |
| boundary file pair | intermediate files (do not add "that the next task needs") |
| `OSPREY_*` on a default path | never. Name a variable only when the user set it; env vars are developer-facing. |
| enum `ToString()` (UnitResolution, DiannTsv, Reverse, percolator) | Skyline's `GetLocalizedString(this Enum)` extension over a `LOCALIZED_VALUES` array of resource strings (`Skyline/Model/Export.cs`), so a later RESX pass finds them in place |

Kept as they are: **coelution** (known DIA term; Skyline has a "coelution score"),
**reconciliation / cross-run reconciliation** ("cross-run" carries the meaning; TRIC is the
nearest published concept), **Percolator**, **`[TASK] Name:starting` markers** (Brendan likes
them; the names are the `--task` values).

Rules that fell out of the review:

1. A noun swap is not a fix for a data-structure word ("stratum" -> "set" is equally opaque).
   The line must state the effect on the results, in one clause: which candidates get new
   q-values, what was kept, what will be imputed.
2. "results" means end results the user looks at. Anything written beside an input for a
   later step is an "intermediate file"; do not stack the two words.
3. Every count carries a thousands separator (`{0:N0}`). Global, not per line.
4. A line whose only purpose is to record which code path ran, or how memory is managed, is
   diagnostic output behind `--verbose`, `--perf-stats` or `OSPREY_LOG_MEMORY`, never user text.
5. No C# identifier, no task name outside the `[TASK]` marker, no environment variable and no
   stage number in a default-tier line.

## The machine channel: what scripts and tests may key off

This is the design decision that makes the rewrite safe now and translation possible later.

Osprey already has two kinds of line. **Prose** is for the person watching the run, may change
in any PR, and will one day be RESX-translated to Japanese and Chinese as Skyline's is. **Tagged
lines** (`[TASK]`, `[COUNT]`, `[TIMING]`, `[BENCH]`, `[STAGE-WALL]`, `[PATH]`, `[MEM ...]`) are
machine-parseable, never localized, and are the contract for every script and test. The rule
to adopt and write into `pwiz_tools/Osprey/docs/20-command-line.md` (a new "Log format"
section) is:

- **A script or test that reads the log keys off tagged lines only.** A prose probe is a
  defect to fix in the consumer, not a reason to freeze the prose.
- **Tagged lines are ASCII, untranslated, and their format is versioned by convention**:
  `[TAG] key: value` or `[TAG] key=value`. Adding a tag or a key is fine; renaming one means
  updating the consumers in the same PR.
- **The tags are gated** (`--perf-stats` for the stat tags, `OSPREY_LOG_MEMORY` for `[MEM]`),
  except `[TASK]`, which is a section header and stays in the default log. `[PATH]` and
  `[TRAIN]` are not in `OspreyOutput.IsStatLine` today and so leak into the default log; add
  them, and have every gate that needs them pass `--perf-stats`.
- **Route assertions get a `[PATH]` line each.** `regression.ps1` currently asserts which
  route a run took by grepping prose ("Second-pass join: folding over N run(s)", "worker's
  written answer for all N file(s)", "folding the report from the completed first pass",
  "ALL-RUNS reconciliation bundle", "a consumer asked for the whole-run survivor pool"). Each
  of those becomes a `[PATH] <route-key>` line emitted where the prose is emitted today, e.g.
  `[PATH] stage7-join: fold-per-run`, `[PATH] pass2-per-file: worker-answers 82/82`,
  `[PATH] mdiag: fold-pass1`, `[PATH] all-runs-bundle: built`. The prose next to it can then
  say whatever a user needs, or nothing.
- **Counts a gate asserts get a `[COUNT]` line.** The library-fragment release count that
  `Test-LibraryFragmentRelease` parses out of prose becomes
  `[COUNT] library-fragments-released: N of M (K retained for rescore+gap-fill)`.

## Coupling inventory: everything that reads log text today

Found by grepping `Osprey.Test`, `pwiz_tools/Osprey/*.ps1`, `ai/scripts`. This is the list the
implementation must walk; every row either moves to the machine channel or is confirmed to be
format-only and unaffected.

### `pwiz_tools/Osprey/regression.ps1` (the correctness gate; runs with `--timestamp --memstamp`, NOT `--perf-stats`)

| Probe (line) | Text it matches | Disposition |
|---|---|---|
| task cache map (1044-1069) | `[TASK] <Name>:starting`, `[TASK] <Name>:skipping (outputs valid)` | keep; `[TASK]` is machine channel and stays as is |
| cold-work probes (1044-1045) | `Scoring file ` / `Re-scoring file ` (case-sensitive prefix of the per-file lines) | these are prose headers a user reads. Keep the words, but add `[PATH] score-file N/M` / `[PATH] rescore-file N/M` and move the probe to them |
| library-fragment release (1051-1054, 1290s) | regex over `Released library fragments for N of M entries (K base_ids retained for <scope>)` | the prose line is a B1 demotion target (memory bookkeeping). Emit `[COUNT] library-fragments-released: ...` under `--perf-stats`; regression passes `--perf-stats`; prose goes behind `OSPREY_LOG_MEMORY` |
| no-all-runs-bundle (1197, 1227-1290) | `ALL-RUNS reconciliation bundle` in the guard's error text; anchor `Threads:` from the banner | `[PATH] all-runs-bundle: refused` / `: built`; banner `Threads:` is fine as an anchor but a `[TASK]`-style start marker is cleaner |
| mode 3 fold split (2132-2205) | `Second-pass worker verification ACTIVE`, `worker's written answer for all \d+ file\(s\)`, `Second-pass join: folding over \d+ run\(s\)`, `Second-pass (worker verification ACTIVE\|fold )` | all four are A20/A22 rewrite or demotion targets. Replace with `[PATH]` lines |
| mode 10 alt arms (2333) | `OSPREY_PASS2_QVALUE=transfer:`, `Experiment aggregation: mean-best-2 ACTIVE` | opt-in env vars, so naming them is allowed (A27); still, assert `[PATH] pass2-qvalue: transfer` and `[PATH] experiment-agg: mean-best-2` rather than prose |
| mode 11 pay-later report (3134-3152) | `folding the report from the completed first pass`, `folding the pass-2 report from the completed second pass`, `[STAGE-WALL] second-pass-fdr`, `Running protein-level FDR`, `Re-scoring file ` | first two are A28 rewrite targets ("fold" is banned). `[PATH] mdiag: fold-pass1` / `fold-pass2`; the forbidden-work probes move to `[STAGE-WALL]`/`[PATH]` |
| pooled-survivor check (2815) | `a consumer asked for the whole-run survivor pool` | C2 (demote). `[PATH] survivor-pool: materialized` |

### `ai/scripts`

| Script | Text it matches | Disposition |
|---|---|---|
| `perfviz.py` | `LINE_RE` (timestamp + memstamp columns), `TASK_RE` `\[TASK\] (\w+):(starting\|done\|skipping)`, `FAIL_RE` `\[ERROR\]\|Unhandled exception\|Pipeline failed` | unaffected; all machine channel. "Pipeline failed" is the `[ERROR] Pipeline failed: ...` line, keep that prefix |
| `Osprey/Test-PerfGate.ps1`, `Osprey/Measure-Pipeline.ps1` | `[STAGE-WALL]` names `stage1to4 stage5 stage6 stage7 second-pass-fdr blib`; `[TIMING] Percolator/Simple FDR`, `[TIMING] First-pass protein FDR` | unaffected (perf-stats channel). Note the stage numbers live in the *machine* keys, which is fine; they are not user text |
| `Osprey/Get-MemoryReport.ps1` | `[MEM <label>]` labels; `[STAGE-WALL]`; **prose** `Coelution analysis complete. N total scored entries across N files`; `Total pipeline: Ns` | the coelution line is A23 (rewrite). Add `[COUNT] scored-candidates: N across M files` and move the probe; `Total pipeline` is already `[TIMING]` |
| `Osprey/SEA-AD/Measure-Stage6Rescore.ps1` | `[MEM reconciliation-resident]`, `[MEM stage7-inherited]` etc. | unaffected |
| `Osprey/Run-Osprey.ps1 -Summary` | a prose pattern list (`calibrated frag`, `Coelution search RT`, `Applying MS2`, `First-pass RT tolerance`, `Refined RT tolerance`, `Wrote feature`, `precursors at`, `Coelution analysis complete`, `MS2 calibration (pass`, `Confident peptides`, `Coelution scored`, `Analysis complete`) | a convenience filter, not a gate. Update the list in the same PR; several of these are already `--verbose` lines |
| `Osprey/Common/OspreyDatasetRun.psm1`, dataset runners | no log-text parsing (the runner writes its own START/DONE lines) | unaffected. The human habit of reading "file NN/NN:" lines (memory) keeps working because the per-file headers keep that shape |

### `Osprey.Test`

| Test | What it asserts | Disposition |
|---|---|---|
| `ProgramTests.cs` (~40 asserts) | CLI validation errors: flag names (`--task PerFileScoring`, `--library and --output`, `2+ files`, `No input files`, `unknown task`), version-guard text (`different daily build`, `incompatible release identity`, `search_hash mismatch`) | flag names are not translated and are the right thing to assert. The version-guard phrases are prose: assert on the shared constant/format string, not a literal (TESTING.md "translation-proof tests") |
| `ResidentPoolGuardTest.cs:342-344` | `O(files x entries)`, `per-run survivor loader`, `cannot admit this path` from `ScoringTaskShared.AllRunsBundleGuardError` (`ScoringTaskShared.cs:805-811`) and `PerFileScoringTask.cs:2257-2260` | these error texts are developer prose (big-O, "survivor loader") and were not on the spec's Table C; add them as C13 and rewrite. The test should assert the guard fired, via the `[PATH] all-runs-bundle: refused` line or a return code, not the wording |
| `MultiProgressReporterTest.cs`, `ProgressReporterTest.cs` | progress *format*: `<activity>...`, `  N%`, `[1] 10%  [2] 20%`, `[TIMING]` filtered from file blocks | format-only, unaffected by wording |
| `FdrTest.cs:1520-1590`, `ModelDiagnosticsDataTest.cs` | model-diagnostics *report* text (`Model sanity check`, `(unexpected direction)`, `Reason` strings), captured through `OspreyOutput.Out` | report content, not the log; out of scope here but the same translation-proof rule will apply |
| `CodeInspectionTest.cs` | no rule about log strings today | add one (below) |

## Implementation plan

Work from the CSV, `Priority` column, in this order. Each step is independently green.

**Step 1: machine channel and gates (no wording decisions).**
- Add `[PATH]` and `[TRAIN]` to `OspreyOutput.IsStatLine`.
- Add the `[PATH]` route lines and the `[COUNT]` lines listed in the coupling inventory,
  next to the prose they replace.
- `regression.ps1`: pass `--perf-stats` (add to `$memStampArgs`), move every probe in the
  table above to the tagged line, keep the `[TASK]` probes. `Get-MemoryReport.ps1`: same for
  the coelution count. `Run-Osprey.ps1 -Summary`: refresh its pattern list.
- Demote the B1 lines (spec page, Table B1) to `--verbose` or `OSPREY_LOG_MEMORY`. This alone
  removes about a third of the default-tier jargon and a quarter of the 82-file log.
- `ProgressReporter`: no change; the heading/percent format is what the tests pin.

**Step 2: the High rows (A1-A13).** Thirteen rows, all in every default run. A1, A2 and A11 are
what a new user hits in the first run that reaches the second pass. Use the decided wording in
the CSV verbatim; it has already been through Brendan's review. A4 is resolved on master by
#4646 and is on the list only to keep "projection" banned.

**Step 3: Medium and Low rows (A14-A31) and Table C.** A14 (`[TASK]`) is decided "keep".
Table C is the warnings written for a developer: keep the one user sentence each already
contains, move mechanism, issue numbers and method names into a code comment beside the call.
Add C13 (`AllRunsBundleGuardError`, `PerFileScoringTask.cs:2257`).

**Step 4: enums and counts.**
- `Resolution: {0}`, `Library: {0} ({1})`, `Generating decoys using {0} method`,
  `Running {0} FDR control`: Skyline's `GetLocalizedString` extension pattern with a
  `LOCALIZED_VALUES` array. Resource strings can live in a plain static class today and move to
  RESX later without touching call sites.
- `{0:N0}` on every count in a default-tier line. A helper is not needed; it is a format
  specifier. Grep `LogInfo|LogWarning|LogError|new ProgressReporter` for `{\d}` placeholders
  bound to `int`/`long` counts.

**Step 5: guard against regrowth.** A `CodeInspectionTest` rule that scans string literals
passed to `LogInfo`, `LogWarning`, `LogError` and `new ProgressReporter(` (not `LogVerbose`, not
tagged lines) for the banned tokens: `sidecar`, `stratum`, `base_id`, `hydrat`, `compaction`,
`survivor`, `stubs`, `scalars`, `frozen`, `projection`, `byproduct`, `interned`, `resident`,
`Stage [1-7]`, `OSPREY_[A-Z_]+` and any `\w+\.cs`/`\w+Task\b`/`Run\w+\(` identifier. The review
found ~120 such lines; without a guard they come back one feature at a time, because the class
name is the nearest word to hand for whoever is inside the class. Put the rule's word list in
one place and reference it from the new docs section.

**Docs.** Add a "Log format" section to `pwiz_tools/Osprey/docs/20-command-line.md`: the two
kinds of line, the tag list, the gating, and the consumer rule. The vocabulary table above goes
in the same section (it is "what the code does", so it lives in pwiz, not ai/).

## Acceptance

- `Build-Osprey.ps1 -RunTests -RunInspection` green, including the new inspection rule.
- `regression-parallel.ps1 -Dataset All` green with `--perf-stats` in the harness args and no
  prose probes left in `regression.ps1` (grep `Select-String -Pattern '[A-Za-z]` for
  non-tagged patterns).
- `Test-PerfGate.ps1 -Dataset Stellar` runs (it only reads `[STAGE-WALL]`).
- Re-read the 3-file Stellar default log and an 82-file second-pass log against the banned
  list: zero hits in the default tier. The 82-file log shrinks by the 82 per-file stub lines.
- Every `Osprey.Test` assert on log prose is either on a flag name, a shared constant, or a
  tagged line.

## Shape of the PR

One PR is the right size (memory: lean bigger on PRs; the small-PR instinct is not free).
Steps 1 and 5 are the mechanical halves and can be reviewed first; steps 2-4 are the wording,
which is already decided. If it must split, split after step 1, because step 1 is what makes
the wording changes safe against the gates.

## Later: RESX and translation (not this TODO)

When Osprey text moves to RESX and is translated to Japanese and Chinese as Skyline's is, the
machine channel above is what keeps the gates and `perfviz.py` working: tagged lines are never
resourced. Prose asserts in tests follow Skyline's translation-proof pattern (assert on the
resource constant, run under the test culture). The `GetLocalizedString` extensions from step 4
are the first strings to move. That effort is its own TODO; this one only avoids making it
harder.
