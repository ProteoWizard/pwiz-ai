# Osprey pipeline architecture document and sidecar file contract

## Branch Information
- **Branch**: `Skyline/work/20260902_osprey_pipeline_architecture_docs`
- **Base**: `master`
- **Created**: 2026-09-02
- **Status**: In progress - WI-1..WI-10 and R1-R11 done; needs /code-review + PR. WI-11 waits on the resume branch.
- **PR**: (none yet)
- **Module**: `osprey`
- **Worktree**: `C:\proj\pwiz-work2` (branch created there from `origin/master` at
  `08a02b9e2e`; `C:\proj\pwiz` holds the net8 branch and `pwiz-work1` holds the
  in-flight resume branch, so neither is used). Start the session with
  `/pw-continue C:\proj\pwiz-work2`.
- **Model**: Opus 5 is sufficient. This is documentation writing plus one SVG reflow;
  the survey and design were done on 2026-09-02 and are recorded below, so no
  re-survey is needed.
- **Skills to load**: `/osprey-development`, `/ai-context-documentation` (for the
  `ai/` side), `/version-control` before any commit.

## Objective

Give Osprey one authoritative statement of its pipeline architecture and its sidecar
file contract, reflect that contract in `Osprey-workflow.html`, and reconcile the
existing docs so nothing is stated twice. The principles that make 500-run and HPC
operation possible (atomic + immutable writes, per-file vs experiment-wide sidecars,
forward-scan resume, validity keys, PerFile-vs-Join responsibilities) exist today only
in TODO prose, code comments and buried subsections of a 1876-line guide. They were
underspecified when the port was made and are being settled on branch
`Skyline/work/20260901_osprey_firstpass_resume`; this TODO writes them down.

## Decisions (2026-09-02, with Brendan)

1. **Classify docs by SUBJECT, not by reader.** "What the code does" (algorithm
   reference, architecture, file contract, CLI, diagram) lives with the code in
   `pwiz_tools/Osprey/docs`, reviewed in the same PR as code. "How we work on it"
   (gates, traps, env vars, datasets, run layout, machine paths) lives in `ai/docs`.
   Evidence: Mike's Rust repo classified `docs/` as "algorithm reference" with
   `CLAUDE.md` as the LLM layer; `package.ps1` ships `README.md`, `CommandLine.html`
   and `Osprey-workflow.html` in the release bundle. The `docs/` tree stays in pwiz.
2. **New doc**: `pwiz_tools/Osprey/docs/00-pipeline-architecture.md`, ONE document
   (principles + file contract together so they cannot drift). `00-` sorts first and
   marks it C#-native: no "C# port of Rust docs/NN" header, no Divergences section.
3. **HTML**: add a File-scope legend; KEEP the Port-status legend and the footer parity
   tables (they go with the later parity-removal sprint, not this PR).
4. **Sequencing**: docs-only branch off `master` now. Everything not yet merged from the
   resume branch is marked in ONE contiguous `## In flight` block plus marked table
   rows, so finalization after that merge is a single block edit (WI-11).
5. **Out of scope**: stripping the port-of-Rust framing and `DIVERGENCES.md`; moving
   `docs/` to `ai/docs/osprey/`; an end-user troubleshooting doc.

## The ownership rule (state it once in each of the three docs)

- **00** owns scope, contract, principles, relay: which file, whose, when, who may read it.
- **14** owns bytes: headers, versions, schemas, hashing, invalidation mechanics.
- **15** owns operations: CLI flags, `--input-scores` ordering, orchestration recipes.

Guard rail: if 00 passes ~900 lines, split DOWNWARD (move leaked byte formats back to
14), never sideways into a second architecture doc.

## Survey findings (2026-09-02)

**Pool A, `pwiz_tools/Osprey/docs` (24 files) + `README.md` + `Osprey-workflow.html`.**
Healthy but pre-dates the principles. All agree on the 4-task / 7-stage model. No
TODO/WIP markers. Spot-checks against `ArtifactPaths.cs`, `FdrScoresSidecar.cs`,
`ReconciledParquetWriter.cs` and the `HpcTask` enum found no staleness. Gaps:
`-LinkFrom` is documented nowhere (only XML comments in
`Osprey.Core/OspreyEnvironment.cs`); `README.md` never links `docs/`; only
`Calibrator.cs` and `CalibrationTest.cs` cite a numbered doc. The HTML is 885 lines,
self-contained inline SVG + CSS, no JS; one `h1`; SVG groups in order: Title, Legend
(Port status), Inputs, Task 1/4 PerFileScoring (Stages 1+2), Stage 3, Stage 4, Task 2/4
FirstPassFDR (Stage 5), Task 3/4 PerFileRescoring (Stage 6), Task 4/4 SecondPassFDR
(Stage 7), footer prose. Each task banner has `in` / `out` lines naming files.

**Pool B, `ai/docs`.** No architecture doc; never routes to Pool A. The principles live
at these `osprey-development-guide.md` headings: `## Osprey project layering` (~81),
`### Atomic file writes: FileSaver` (~129), `## Do the work in the PerFile* tasks, not
the JOIN tasks` (~780), `## HPC split CLI flags` (~816), `## Never conditionally write
an output artifact` (~1663). `osprey-development/SKILL.md` and every `ai/docs` guide
omit `pwiz_tools/Osprey/docs`; only 29 TODOs cite it. `ai/MEMORY.md` has zero Osprey
mentions. `TODO-20260728_doc_reorg.md` enforces hard core-file size limits, so the dev
guide must shrink, not grow.

**Pool C, the in-flight TODOs.** Settled (document now):
- Atomic write via `FileSaver` temp + same-dir rename; presence proves completeness
  (PR #4366; `completed/TODO-20260704_osprey_filesaver_atomic_writes.md`).
- Write-once immutability: each phase writes its product once at phase end; a new
  column is a NEW file written by the phase that computes it (agreed 2026-09-01;
  `active/TODO-20260901_osprey_firstpassfdr_resume.md` "(e3) THE TARGET DESIGN").
- Per-file vs experiment-wide taxonomy: a `PerFile*` iteration reads only its own
  run's artifacts plus experiment-wide summaries from earlier phases, and builds
  nothing spanning runs (`active/TODO-20260901_osprey_stage5_reload_materialization.md`
  "THE TARGET SHAPE for --task PerFileRescoring").
- `.osprey.task` validity key = search hash + reconciliation params + run FDR + sorted
  file STEMS, not paths, so `-LinkFrom` survives moves; `PerFileScoring`'s key omits
  stems. Build stamp = commit-date DOY + git hash (PR #4352).
- Resume is a forward scan by stage; a stage that Runs invalidates everything
  downstream ("(d) Resume is a FORWARD SCAN" in the resume TODO).
- `--work-dir` (scratch + `.spectra.bin` cache) vs `--output-dir` (products)
  (`completed/TODO-20260826_osprey_run_from_cache.md`).
- Only the `FirstPassFDR` barrier and `SecondPassFDR` may hold whole-experiment
  structures; aggregate O(entries), never O(files x entries)
  (`active/TODO-20260823_osprey_chs_large_scale.md`).

In flux (mark "in flight, see TODO-20260901_*"):
- Protein-q split of the experiment-scope FDR sidecar.
- Final bounded-loop shape of `PerFileRescoring` (`perFileEntries`,
  `reconciliationActions`).
- Deletion of the fat pre-compaction path.
- Whether 500 / 64 GB is met: Stage 5 fixed at 446 files; Stage 7 bundle hydration is
  the next wall.

**Sidecar inventory from the TODOs** (seed for the contract table; `?` = verify in code):

| File | Scope | Writer | Reader | Notes |
|---|---|---|---|---|
| `<stem>.spectra.bin` | per-file cache | PerFileScoring (SpectraCache) | PerFileScoring, PerFileRescoring | magic + VERSION + size/mtime; now "data, not intermediate" |
| library cache (`.libcache`) | shared | library load | all tasks | not HPC-splittable |
| `<stem>.calibration.json` | per-file | Stage 3 | rescoring | |
| `<stem>.scores.parquet` | per-file | PerFileScoring | FirstPassFDR, PerFileRescoring | key omits stems; bitwise identical 1-file vs N-file |
| `<output>.<Task>.osprey.task` | per-file per-task | each task via PerFileResumeDriver | resume | task + build + validity key; stamped only after Run |
| `<stem>.1st-pass.fdr_scores.bin` | per-file | FirstPassFDR pass 1 (moved 09-01) | PerFileRescoring | ~78 MB/file |
| `out.1st-pass.fdr_experiment.bin` | experiment | FirstPassFDR | SecondPassFDR, PerFileRescoring | relay to every node; silent mis-compute if missing |
| `out.1st-pass.protein_q.bin` | experiment | FirstPassFDR protein-FDR end | SecondPassFDR | IN FLIGHT (protein-q split) |
| `.1st-pass.model.json` | experiment | FirstPassFDR training | FirstPassFDR pass 1/2 | relay together with `.stratum.json` or fail-fast |
| `.1st-pass.stratum.json` | experiment | FirstPassFDR protein-FDR end | Pass2FdrSidecar, PerFileRescoring | |
| `.1st-pass.retained_base_ids.bin` | experiment | FirstPassFDR.PlanStage6 | PerFileRescoring | IN FLIGHT; library-bounded; write failure fatal |
| `<stem>.reconciliation.json` | per-file | FirstPassFDR Stage-6 planning | PerFileRescoring | duplicated experiment-wide array being split out |
| `<stem>.scores-reconciled.parquet` | per-file | PerFileRescoring | SecondPassFDR | byte-identical per node in regression mode 3 |
| `<stem>.2nd-pass.fdr_scores.bin` | per-file | SecondPassFDR | ? | |
| `<output>.blib` | experiment (terminal) | SecondPassFDR | Skyline | |

## Outline of `docs/00-pipeline-architecture.md`

Marker key: NOW = writable from settled principles; FLIGHT = carries
`> **In flight** - see ai/todos/active/TODO-20260901_*`.

| Section | Content | State |
|---|---|---|
| Title + 10-line abstract, link to `docs/README.md` | | NOW |
| `## Scope of this document` | the ownership rule | NOW |
| `## Scale targets and the deployment model` | `### 500 runs on 64 GB` (memory, not wall clock, binds); `### Single-process, HPC-split, resumed-run modes`; `### What "bounded" means` (O(entries) / O(library), never O(files x entries)) | NOW |
| `## The task graph` | `### Four tasks over seven stages` (table: task, stages, scatter/barrier, node count); `### Scatter vs barrier: what a join may hold` (experiment competition, parsimony, blib, nothing else) with the per-run-loop figure re-derived as ASCII or SVG (the one lost in a non-durable `ai/.tmp` handoff, see the stage5 TODO "Process finding"); `### Phase boundaries inside a task` (training / pass 1 / barrier / pass 2 / protein FDR / planning inside FirstPassFDR) | NOW |
| `## Principles` P1-P11 | list below | NOW |
| `## The sidecar file contract` | master table (file, scope, writer task+stage, reader, validity key, relay) + one paragraph per non-obvious row; `### Reading the table`; `### Experiment-wide artifacts that must relay together` | NOW + FLIGHT rows |
| `## Directory resolution` | `### --work-dir vs --output-dir`; `### Cache placement` (`ArtifactPaths.ResolveCacheDir`); `### -LinkFrom: hard-link adoption of a prior run` (first prose home; source `Osprey.Core/OspreyEnvironment.cs`) | NOW |
| `## Validity and resume` | `### The validity key`; `### The build stamp`; `### Resume is a forward scan`; `### Per-file guards inside a stage` (adopt by FEEDING both passes from the sidecar, never by skipping the file) | NOW |
| `## HPC relay checklist` | one subsection per boundary 1->2, 2->3, 3->4: the exact file list a node must be shipped | NOW + FLIGHT rows |
| `## In flight` | the four in-flux items, contiguous | FLIGHT |
| `## Cross-references` | docs 01-20 by stage; `ai/docs/osprey-*` guides by topic | NOW |

**Principles** (one sentence each in the doc, plus a one-line rationale):

| # | Statement |
|---|---|
| P1 | Every durable artifact commits through `FileSaver`; a file is absent or complete, so presence proves completeness. |
| P2 | Artifacts are write-once: a new column means a new file, never a revisit. |
| P3 | A column lives in the file written by the phase that computes it. |
| P4 | Never conditionally write an output artifact; write the header-only / 0-record file. |
| P5 | Every artifact is per-file or experiment-wide; a `PerFile*` iteration reads only its own run's artifacts plus experiment-wide summaries written by an earlier phase, and builds nothing spanning runs. |
| P6 | Work goes in the `PerFile*` tasks; a join holds O(distinct), never O(files x entries). |
| P7 | Persist at phase end, not task end; crash exposure is one in-flight file, independent of cohort size. |
| P8 | Guards are per-file, not per-phase; adoption feeds both passes from the sidecar so output stays byte-identical. |
| P9 | Resume is a forward scan; a stage that Runs invalidates all downstream validity, so a non-exhaustive key costs a recompute, never a wrong answer. |
| P10 | The validity key names file stems, not paths, so `-LinkFrom` and directory moves do not invalidate. |
| P11 | `--work-dir` holds scratch and caches; `--output-dir` holds what the user keeps. |

## Reconciliation of existing docs

| File | Action |
|---|---|
| `docs/14-intermediate-files.md` | Trim + keep. Move section 0 (`ArtifactPaths` redirection, FileSaver) and section 8 (`.osprey.task`) into 00; leave one-line pointers. Keep sections 1-7 formats verbatim. Add the new sidecars' FORMATS only. Tag each section heading with scope (per-file / experiment-wide). |
| `docs/15-hpc-scoring-split.md` | Trim + keep. Replace "Persistent files per input" and per-task in/out prose with a pointer to 00's table; keep task-name mapping, membership truth table, `--input-scores` resolution, footer-hash validation, concurrency. Add a Relay pointer per task section. |
| `docs/12-second-pass-fdr.md` | Add "Inputs from the first pass": which experiment-wide artifacts the frozen-model modes read (`.1st-pass.model.json`, `.stratum.json`, experiment sidecar) and why they relay together. 5-10 lines + pointer. |
| `docs/README.md` | Add the `00` row at the top of the ordered index; one sentence that 00 has no Rust counterpart and no Divergences section; state the ownership rule. |
| `pwiz_tools/Osprey/README.md` | ROUTING FIX: add a "Documentation" pointer block (`docs/README.md`, `docs/00`, `Osprey-workflow.html`). Under HPC distribution, after the worked example, point at 00's relay checklist. Verify stage/task names match 00 exactly. |
| `docs/20-command-line.md` | Add a `-LinkFrom` row (currently CLI-invisible). |
| `ai/docs/osprey-development-guide.md` | Shrink ~250 lines. MOVE OUT `### Atomic file writes: FileSaver`, `## Do the work in the PerFile* tasks`, `## Never conditionally write an output artifact` (they become P1 / P6 / P4 in 00; 3-line stubs with links remain). `## HPC split CLI flags`: the flag table goes to doc 15; keep only the Parquet interop gotchas (version lock, path-dependent library hash, Snappy). STAYS: layering, env-var reference, glossary, parity/bisection, perf, commit conventions. State the subject rule near the top. |
| `ai/docs/osprey-run-layout.md` | Keep; add ~6 lines tying `raw\` / `runs\` to `--work-dir` / `--output-dir`, link 00. |
| `ai/claude/skills/osprey-development/SKILL.md` | ROUTING FIX: add "Pipeline architecture + file contract: `pwiz_tools/Osprey/docs/00-pipeline-architecture.md` (read before changing what any task writes); algorithm reference index: `docs/README.md`". |
| `ai/MEMORY.md` | Add 3-4 lines under See Also: what Osprey is, the skill name, the two doc entry points. |
| `ai/docs/osprey-large-datasets.md` | Add the staging recipe (download -> SpectraCache -> delete sources -> search), flagged as a gap by `completed/TODO-20260826_osprey_run_from_cache.md`. |

## `Osprey-workflow.html` changes

Banner edits (the `task-hdr-io` text elements at ~lines 220/221, 367/368, 432/433,
474/475 as of `08a02b9e2e`):

| Task | Change |
|---|---|
| 1/4 PerFileScoring | `out` += `<stem>.spectra.bin`, library cache, tagged (cache, `--work-dir`). |
| 2/4 FirstPassFDR | `out` += `out.1st-pass.fdr_experiment.bin`, `.1st-pass.model.json`, `.1st-pass.stratum.json`, `.1st-pass.retained_base_ids.bin` (in flight); annotate `.1st-pass.fdr_scores.bin` as written during pass 1. |
| 3/4 PerFileRescoring | `in` += the four experiment-wide files + `<stem>.calibration.json`; role note "reads its own run + experiment-wide summaries only". |
| 4/4 SecondPassFDR | `in` += `out.1st-pass.fdr_experiment.bin` (+ protein-q file, in flight). |

- **Legend**: add a File-scope legend row beneath Port-status with three swatches:
  per-file (fan-out), experiment-wide (relay to every node), shared cache
  (`--work-dir`, rebuildable); use those fills on the file names in the banners.
- **Relay annotations**: a right-aligned tspan on each task banner's role line
  (`task-hdr-role`, x=1060), e.g. `relay: 4 experiment-wide files + per-run set`; a
  one-line footnote above the footer prose pointing at 00's relay checklist.
- **Link**: in the subtitle block (~line 68), `<a href="docs/00-pipeline-architecture.md">`.
  `package.ps1` (~line 221) retargets the raw.githack link for the offline bundle;
  check the new link survives that regex or add a second retarget. The bundle does
  NOT ship `docs/*.md`, so the offline copy's link should point at the GitHub URL.
- **Geometry**: each banner is `rect height 64` with text at y=22/40/56; two more
  in/out lines means height 64->96 and a `transform="translate()"` y-shift for every
  following SVG group plus the root `svg` height/viewBox. That is the real work.
- **Verification**: headless Chrome `--screenshot --window-size=1400,<h>` of the local
  file before and after; diff the PNGs for group overlap. The Chrome extension cannot
  screenshot `file://` pages.

## Sequencing against the in-flight resume branch

The resume branch (`Skyline/work/20260901_osprey_firstpass_resume`, `C:\proj\pwiz-work1`)
touches no docs, so there is no merge conflict. The risk is orphaned markers: keep
every in-flight item in the one `## In flight` section plus marked table rows so WI-11
is a single block edit, and ask Brendan to relay WI-11 to that branch's session so its
TODO carries a matching "clear the in-flight markers in docs/00 and the HTML" item
(this TODO does not edit that session's file).

## Tasks

Two PRs: WI-1..6, 9, 10 on the pwiz branch; WI-7 and WI-8 commit directly to pwiz-ai
master (stage by path; the checkout is shared with live sessions). WI-11 is a third,
tiny PR after the resume branch merges.

- [x] **WI-1 (M)** Draft 00: scope, scale, task graph (incl. the re-derived
      per-run-loop figure), principles P1-P15. `docs/00-pipeline-architecture.md` (new).
- [x] **WI-2 (L)** Sidecar contract table + per-row prose; in-flight rows marked; verify
      EVERY row against `Osprey.Tasks/TaskValiditySidecar.cs`,
      `Osprey.Core/ArtifactPaths.cs` and the writer classes; resolve every `?`.
- [x] **WI-3 (M)** Directory resolution section (`--work-dir` / `--output-dir`,
      `ArtifactPaths.ResolveCacheDir`) + the path-independence property external
      adoption relies on. Source: `Osprey.Core/OspreyEnvironment.cs`.
      **REVISED**: `-LinkFrom` is NOT an Osprey CLI flag - it is a parameter of
      `ai/scripts/Osprey/Common/OspreyDatasetRun.psm1`. By this TODO's own subject rule
      the tool belongs in `ai/docs` (moved to WI-8); only the code-side property that
      makes it possible (P15, path-independent identity) belongs in 00. No
      `docs/20-command-line.md` row.
- [x] **WI-4 (M)** Resume semantics + HPC relay checklist per boundary.
- [x] **WI-5 (M)** Trim doc 14 (sections 0 and 8 out) and doc 15 (per-task file lists
      out); pointers + ownership rule in each.
- [x] **WI-6 (S)** Doc 12 "Inputs from the first pass"; `00` row + rule in
      `docs/README.md`; `README.md` Documentation block + HPC pointer.
- [x] **WI-7 (M)** Shrink `ai/docs/osprey-development-guide.md` (3 sections out, HPC-flag
      table to doc 15, stubs in, subject rule stated). pwiz-ai master.
- [x] **WI-8 (S)** Pointers: `osprey-run-layout.md`, `osprey-development/SKILL.md`
      routing, `ai/MEMORY.md`; staging recipe in `osprey-large-datasets.md`. pwiz-ai master.
- [x] **WI-9 (L)** HTML: banner in/out edits, geometry reflow, File-scope legend, relay
      annotations, doc link, `package.ps1` link-retarget check.
- [x] **WI-10 (M)** Verification:
      1. `pwsh -File ai/scripts/audit-docs.ps1` on the pwiz-ai side; a relative-link
         check across both pools (every `docs/NN-*.md` and `00` link resolves; every
         `ai/docs` pointer into pwiz resolves).
      2. Headless-Chrome before/after screenshots of the HTML, diffed.
      3. Cross-pool consistency: the four task names and Stage 1-7 names agree
         byte-for-byte across `pwiz_tools/Osprey/README.md`, `docs/README.md`,
         `Osprey-workflow.html`, `docs/00`.
      4. Contract-vs-code: for every row in 00's table, grep the extension string in
         `pwiz_tools/Osprey/**/*.cs` and confirm the named writer class exists.
      5. Run `package.ps1` once to confirm the offline bundle's link retarget still works.
      No code changes, so `Build-Osprey.ps1` and `regression.ps1` are not needed.
- [ ] **WI-11 (S, after the resume branch merges)** Clear the in-flight markers in 00 and
      the HTML; fold `out.1st-pass.protein_q.bin` and `.1st-pass.retained_base_ids.bin`
      into settled rows.

## Review directions (2026-09-02, planning session's review of WI-1..10)

The planning session (Fable 5.1) read doc 00's core sections itself and had an Opus agent
verify every contract-table row, principle citation and relay-checklist line against the
code in `C:\proj\pwiz-work2`. The document is the right shape: the per-run loop identity,
P1's content-versus-naming distinction and "Rows that are not what they look like" are
exactly the specification that was missing. All fourteen table rows, the FileSaver sweep,
and the model.json, decoys-before-scores, manifest-path, key-composition, `HpcTask` and
library-hash claims were CONFIRMED against code. The corrections below are what the code
contradicts; fix them BEFORE `/code-review max`, because a contract document that names
a deleted method will be trusted by the next session that reads it.

- [x] **R1 - `FdrScoresSidecar.PatchProteinQvalues` does not exist; drop the P11
      violation.** `FdrScoresSidecar.cs:116-124` records that at sidecar v5 (#4486)
      `PatchProteinQvalues` "rewrote every 1st-pass sidecar after protein FDR ... All three
      are now deleted ... a per-file sidecar is written exactly once on both passes and no
      later stage reopens it." Only comment references remain (`:120`, `:222`,
      `Pass2FdrSidecar.cs:1284`), and the resume branch does not touch
      `FdrScoresSidecar.cs`. Remove the `> **In flight**` block under P11 (doc 00 ~line
      337) and item 1 of `## In flight` (~line 719). THEN re-check what the planning survey
      called the "protein-q split of the experiment-scope FDR sidecar" (the seed table's
      `out.1st-pass.protein_q.bin` row): find it in
      `TODO-20260901_osprey_firstpassfdr_resume.md` "The protein-q split, and the rule
      behind it". If it is a real unmerged change to `fdr_experiment.bin`, describe THAT
      accurately as the in-flight item; if not, it is gone from the doc. Update the WI-11
      marker list in the last progress entry to match.
- [x] **R2 - Two missing contract rows; the "side channels" paragraph is wrong under
      `--model-diagnostics`.** `<output>.model-diagnostics.data.json` is written by
      `FirstPassFDR` via `FileSaver` and read (then deleted) by `SecondPassFDR`
      (`ModelDiagnosticsReport.cs:44-54`, `:243`, `:283-292`): a genuine cross-task,
      cross-process hand-off. `<output>.model-diagnostics.html` is a declared Output of
      `SecondPassFdrTask` (`SecondPassFdrTask.cs:136-137`), so its absence invalidates the
      task. Add both rows (experiment product, conditional on `--model-diagnostics`; the
      `.data.json` must reach the `SecondPassFDR` node) and rewrite the paragraph at
      ~427-430 so it names only outputs no task reads (fdrbench manifests, trace dumps).
- [x] **R3 - Boundary 1 -> 2: `.calibration.json` MUST travel.** Doc 00 ~665-667 says it
      need not. `PerFileScoringTask.cs:1675-1700`, `:2187-2190`, `:2658` read it on every
      `--input-scores` leg (inside the `FirstPassFDR` and `SecondPassFDR` legs) for RT
      calibration and isolation-window coverage, "so a SecondPassFDR node with no mzML
      still gets per-file coverage" (`:1694-1697`), behind a `File.Exists`, so absence
      silently changes gap-fill filtering instead of failing. That is the P10-shaped
      hazard the doc warns about; say so at the boundary.
- [x] **R4 - Boundary 3 -> 4 and the Read-by column omit real readers.** `SecondPassFDR`
      reads `<stem>.reconciliation.json` (`Pass2FdrSidecar.cs:963-975`
      `LoadGapFillEntryIds`, from `TryReadWorkerContribution` `:886`, on the Stage-7 fold
      at `:2018`) and `.calibration.json` (R3). Add both to the 3 -> 4 list and to the
      rows' Read-by. Also: `1st-pass.fdr_experiment.bin` is read by
      `PerFileScoringTask.cs:1359-1361` and `:1767-1770` (rehydrate); and
      `<stem>.1st-pass.fdr_scores.bin` is NOT a `SecondPassFDR` input on the default path
      (`SecondPassFdrTask.cs:88-101` says so in capitals), only under
      `OSPREY_PASS2_VERIFY_WORKER` or where no worker answer exists. Qualify that row.
- [x] **R5 - Stage 7 tests PRESENCE of the `PerFileRescoring` stamp, not its key.**
      `Pass2FdrSidecar.cs:763-779`: "One task cannot reconstruct another task's key from a
      different leg, and should not try." Doc 00's "`SecondPassFDR` then reads the stamp to
      decide" (~460-468) and the 3 -> 4 wording invite the bug that was fixed. Say: the
      stamp's presence under the producer's task name is the signal; the key is validated
      by the producer, never re-derived by the consumer.
- [x] **R6 - "Name from the blib, directory from `ResolveOutputDir`" holds for
      `fdr_experiment.bin` only** (`FdrExperimentSidecar.cs:94-135`).
      `.1st-pass.model.json` takes its name from the run stem and its directory from the
      parquet's own directory (`FirstPassModelIO.cs:116-121`). Scope "Where experiment-wide
      artifacts live" to the blib-named artifacts and point at the replicated exception.
- [x] **R7 - Smaller factual fixes.**
      - Doc 00 ~52-56 says the `HpcTask` enum spells `PerFileRescoring`; it spells
        `FirstPassFdr`, `PerFileRescore`, `SecondPassFdr` (`OspreyConfig.cs:432-435`). The
        CLI and `.osprey.task` names are the long forms; say which is which.
      - P4 (~276-278) says `PerFileScoring`'s key is "search parameters plus library
        identity"; the base key also carries the peak-pick arm (`OspreyTask.cs:179-183`),
        as "What the key is made of" already states. Make P4 agree with it.
      - P10's story: the failing signal was a published pipeline byproduct
        (`PipelineContext`), not "an in-process flag" (`Pass2FdrSidecar.cs:174-188`; the
        332,269 / 407,624 counts are right). Still process state, so the principle stands;
        fix the mechanism. Replace "The rule is written in blood" with plain language
        ("This rule was learned from a defect:"); the project bans violent and
        crime-scene idioms.
      - `## In flight` item 2 cites `TODO-20260901_osprey_stage5_reload_materialization.md`
        by file only; its title is about `FirstPassFdrTask.ReloadFirstPassSurvivors`, so a
        reader will dismiss it. Cite the section "THE TARGET SHAPE for --task
        PerFileRescoring" and its violation table (items 6/7, `perFileEntries` /
        `reconciliationActions`).
      - `## In flight` item 3 "delete the fat pre-compaction path": the A/B
        (`OspreyEnvironment.cs:190,245-247`, `Stage6StreamSurvivors`) gates survivor
        streaming, not pre-compaction. Name what the switch actually gates.
      - Contract row `<stem>.spectra.bin`: add `SpectraCache` (the selectable
        non-pipeline task) as a writer; the "stage raw, build caches, delete sources"
        recipe depends on it.
      - Contract row `<blib-stem>.2nd-pass.fdr_experiment.bin` reads "terminal". A product
        no task reads is, by the doc's own definition, a side channel. Name its reader
        (a `SecondPassFDR` resume? `--model-diagnostics`?) or move it to that list.
- [x] **R8 - Relay hygiene, stated once.** (a) `.osprey.task` sidecars are "with its
      artifact" in the table but appear only at boundary 3 -> 4; say at the top of the
      checklist that every relayed artifact travels with its sidecar. (b)
      `LibraryIdentityHash` is name + size + mtime: a library copied to a node by a tool
      that resets timestamps changes its identity and invalidates every artifact. One
      sentence at boundary 1 -> 2 (`robocopy /COPY:DAT`, `rsync -t`, or however the
      cluster preserves mtime) prevents a multi-hour false "stale" on the join node.

A second (Sonnet) agent checked the mechanics: every relative link and anchor in the
eight pwiz files and four ai files resolves; task and stage names agree across
`README.md`, `docs/00` and the HTML; the headless-Chrome render of the reflowed diagram
(viewBox 2700 -> 2868) shows the File-scope legend legible and every banner's text inside
its border with nothing from master's render missing; the `package.ps1` regexes rewrite
exactly the intended README links and nothing else; the renamed dev-guide heading has no
inbound anchors. Three content items did fall through the reconciliation:

- [x] **R9 - Restore the `FileSaver` caller enumeration.** Doc 14's removed "Atomic writes
      via `FileSaver`" section listed the call sites; P8 in doc 00 states the rule with
      none, so "every durable artifact commits through `FileSaver`" is now unverifiable
      from the docs. Under the ownership rule this list is mechanics and belongs in doc
      14: restore it there from the CURRENT code (the Opus sweep counted 14 `FileSaver`
      call sites; the old list of 8 was itself stale, since it named the deleted
      `PatchProteinQvalues`), and have P8 point at it.
- [x] **R10 - Two dropped facts to put back.** (a) Doc 15's "Persistent files per input"
      table said WHY Stage 6 reads `<stem>.calibration.json`: inverse RT prediction plus
      isolation windows. The contract row now names the reader but not the reason; add it
      to the row's prose alongside R3/R4. (b) `PerFileRescoreTask.cs:262` also appends
      `ReconciliationParameterHash` to its key; doc 14's old text said so and nothing now
      does. Add `PerFileRescoring` to "What the key is made of".
- [x] **R11 - Two pre-existing "load-bearing" uses in files this PR touches**:
      `Osprey-workflow.html:767` ("Rust dump-writer patch (still load-bearing)") and
      `14-intermediate-files.md:232` ("`ParquetIndex` bookkeeping is load-bearing").
      Replace with "still essential" / "is essential" while the files are open; the
      project bans the phrase.

**Process directions after R1-R11:**
- `/code-review max` from `C:\proj\pwiz-work2` (cd there first; a review started
  elsewhere reviews the wrong tree). Verify each finding against the code before applying.
- Open the PR: title `osprey: Added a pipeline architecture and sidecar file contract
  document`, label `osprey`, Summary bullets for doc 00, the 12/14/15 reconciliation, the
  workflow diagram, and the `package.ps1` link retarget. Test plan = the WI-10 checks.
  Do NOT trigger the TeamCity Osprey Perf/Regression config: no pipeline code changed.
- Accepted deviations, no action: WI-7's guide is +10 net (real duplication was ~34
  lines); WI-8's `MEMORY.md` pointer skipped because the core five are 80 lines over
  budget. Add one line to `TODO-20260728_doc_reorg.md`: when the core files come under
  budget, add the Osprey entry point (`/osprey-development`, `docs/00`) to `MEMORY.md`.
- WI-11 is unchanged in intent: after the resume branch merges, clear whatever in-flight
  markers survive R1 (expected: the P5/P6 block under the per-run loop and `## In flight`
  items 2-4).

## Progress Log

### 2026-09-02 - Planning session (Fable 5.1, design review only)

- Surveyed the three documentation pools with three Sonnet Explore agents and designed
  the organization with one Opus Plan agent; all findings and the design are recorded
  above so the implementing session does not re-survey.
- Decided with Brendan: docs stay in pwiz classified by subject; one `00` doc; File-scope
  legend added and Port-status kept; docs branch off master now with in-flight markers;
  implementation handed to an Opus 5 session.
- Created `Skyline/work/20260902_osprey_pipeline_architecture_docs` in `C:\proj\pwiz-work2`
  from `origin/master` `08a02b9e2e` (local only; push with `-u` on first commit).
- Next: `/pw-continue C:\proj\pwiz-work2`, then WI-1.

### 2026-09-02 - WI-1 + WI-2 (Opus 5): doc 00 drafted through the file contract

Wrote `pwiz_tools/Osprey/docs/00-pipeline-architecture.md` (~500 lines): scope +
ownership rule, run/file vocabulary, scale targets, task graph with the per-run-loop
figure, principles, and the verified sidecar contract table.

**Brendan's framing became the spine** (recorded here because it outranks the planning
session's outline where they differ): (1) HPC fan-out tasks must decompose to any batch
size, 1..N runs per node, with joins bounded - no O(files x library-entries);
(2) sidecars are atomic + immutable, and **a validity key is about SET INCLUSION**
(software version, library, file set, params), NOT completeness - completeness comes
free from FileSaver's atomic placement; (3) the two tiers are a memory model:
experiment-wide artifacts ARE the resident baseline of a fan-out task, per-run
artifacts are loaded and freed per iteration. The doc's central claim is the identity
`peak = baseline + max(one run)`, in which neither batch size nor cohort size appears.

**Principles went 11 -> 15**, regrouped into Decomposition / Two tiers / Write
discipline / Resume. Four are new, each from code evidence rather than the outline:
- **P4** a per-run artifact's validity key must not name the cohort. `PerFileScoring`'s
  key omits file stems; `ReconciliationParameterHash` includes them. That asymmetry IS
  the HPC decomposition - a cohort-bearing key would invalidate on every rebatch.
- **P10** cross-phase questions are answered by artifacts, never process state. Recorded
  failure: Stage 7 used an in-process flag to decide whether the Stage 6 worker had run;
  correct in one process, and in an HPC chain it rewrote every sidecar survivors-only,
  332,269 records vs the straight route's 407,624.
- **P14** when a phase writes several files for one run, the file gating downstream
  reuse lands last (`FileSaver` is per-file atomic, not per-set).
- **P1 refined**: scope is about CONTENT, not naming - see the model.json finding below.

**Seed-table corrections (all verified against path-building code):**
- `.1st-pass.stratum.json` **does not exist**. The protein-compact stratum rides inside
  `<stem>.1st-pass.model.json` as an optional field, deliberately: the mode needs model
  AND stratum, one artifact = one relay hop, and a node cannot be shipped half of it.
- `.1st-pass.model.json` is **experiment-wide content under a per-run name**, replicated
  identically beside every run (`LoadFromAny` takes the first hit) so a fan-out node
  finds it by the stem derivation it already knows. This is what forced the P1 refinement.
- `<stem>.2nd-pass.fdr_scores.bin` is written by **`PerFileRescoring`** (pass-2 per-file
  worker) or by `SecondPassFDR` where no worker ran - not `SecondPassFDR` alone. The
  `.osprey.task` stamp carries the PRODUCER's task and key, and `SecondPassFDR` reads
  that stamp to decide fold-vs-recompute.
- **New row**: `<stem>.2nd-pass.fdr_decoys.bin` (`Pass2CompetitionDecoys`), per-run,
  written by `PerFileRescoring` before the scores file (P14 ordering), read by Stage 7.
- **New row**: `<blib-stem>.2nd-pass.fdr_experiment.bin` (`WritePass2ExperimentSidecar`).
- Experiment-wide products take their NAME from the output blib and their DIRECTORY from
  `ArtifactPaths.ResolveOutputDir` off a sibling artifact - never from the blib's own
  directory, since each `--task` phase runs in its own working dir with the same relative
  `-o`. The first implementation got this wrong and the HPC regression leg caught it.
- `-LinkFrom` is a runner-script parameter, not an Osprey flag (see revised WI-3).

**Staleness found in the existing docs** (feeds WI-5; the planning survey reported none):
- Doc 14 understates the validity key: the base key also appends the peak-pick arm, and
  `FirstPassFDR` appends six more components (reconciliation hash, sidecar format
  version, experiment-agg, pass-2 q mode, train-sample, library-fragment release), each
  with a recorded reason worth reusing.
- Doc 15 lists `HpcTask` as four members. It has **six**: `SpectraCache` (data staging
  ahead of the pipeline) and `ModelDiagnostics` (report regeneration) are selectable but
  are not pipeline stages and not in `CanonicalPipeline()`. Doc 00 now says so.

**Two live principle violations, both in-flight, both marked inline in 00 with the
standard marker for WI-11 to clear:**
- `FdrScoresSidecar.PatchProteinQvalues` rewrites a first-pass sidecar in place (P11).
- `PerFileRescoring`'s baseline (`RescorePassInputs`) holds maps keyed by file name with
  per-entry values and is entered with a materialised all-runs entry list (P5/P6).

- Next: WI-4 (resume semantics + HPC relay checklist per boundary), then WI-5/WI-6.

### 2026-09-02 - WI-3..WI-10 (Opus 5): doc 00 complete, docs reconciled, HTML reflowed

Four pwiz commits on `Skyline/work/20260902_osprey_pipeline_architecture_docs`
(`bd8584d355`, `aabf9905f7`, `e0079742b7`, `907a22312e`) and two pwiz-ai commits
(`a6fb123`, `7b6ac6e`, pushed). Doc 00 is 769 lines, under the ~900 guard rail.

**Corrections to my own earlier work, both caught by checking code rather than prose:**
- **P15 stated the resume safety property backwards.** It read "a key that is not
  exhaustive enough costs a recompute, never a wrong answer". The truth is the reverse:
  an OVER-inclusive key costs a recompute; an UNDER-inclusive one silently reuses an
  artifact computed under different settings and reports it as the new result. That is
  exactly the defect each of `FirstPassFDR`'s six key components was added to prevent,
  and the doc now presents that list as the worked example of the asymmetry.
- **"Identity is path-independent" was an overclaim.** `SearchParameterHash` folds in
  `DecoyPairingManifestPath` verbatim and unnormalised - the ONLY path anywhere in
  artifact identity. That is the actual mechanism behind
  `project_sead_pilot_mtg_dataset`'s "the move broke -LinkFrom": it breaks for cohorts
  searched WITH a pairing manifest and not otherwise. Both doc 00 and
  `osprey-run-layout.md` now say so precisely.

**More existing-doc errors found (all fixed):**
- Doc 15's "Safe concurrent writes" described Rust's local-temp + copy-and-verify, not
  the C# sibling-rename that replaced it.
- The dev guide's "path-dependent library hash" gotcha was backwards - both
  implementations exclude the directory (verified against `crates/osprey-core/src/config.rs`,
  whose comment names the C# port as what it matches). It had been telling developers to
  use Windows-native paths for a reason that no longer exists.
- The dev guide's HPC flag table is **Rust's** (`--no-join` / `--join-at-pass`), not the
  C# `--task` family, so it stayed in `ai/docs` (WI-7 had planned to move it to doc 15,
  which would have put Rust flags in a C# doc) and is now labelled.

**Deviations from the plan, with reasons:**
- **WI-7 did not shrink the guide by ~250 lines; it is +10 net** (1876 -> 1886). The
  actual duplication with doc 00 was ~34 lines, not 250 - the estimate was made before 00
  existed and assumed whole sections would move. Removing more would mean deleting
  content 00 does not own (env vars, gates, measured costs). The guide is still the
  largest in `ai/docs` at 1886 lines; genuinely shrinking it belongs to
  `TODO-20260728_doc_reorg.md`, not here.
- **WI-8's `ai/MEMORY.md` addition was skipped deliberately.** `audit-docs.ps1` reports
  the core five at **1080 of 1000 lines, over by 80** (pre-existing). Adding pointer lines
  to `MEMORY.md` would worsen a tracked violation to deliver routing the
  `/osprey-development` skill now carries, which is where an entry point belongs.
- **WI-8's staging recipe was already present** in `osprey-large-datasets.md` ("Staging a
  cohort", ~line 160). Added only the cache-vs-product cross-link.
- **`package.ps1` gained a README link retarget.** The bundle ships `README.md` but not
  `docs/`, so the Documentation block WI-6 added would have shipped dead links - and the
  pre-existing `Osprey-workflow.html` link was already dead, since the workflow page lands
  in `Documentation/`. Retargets `docs/*` to GitHub URLs and the workflow link to its
  subdirectory, mirroring the existing `CommandLine.html` retarget in the same function.

**WI-9 (HTML)**: banners grew 64 -> 96 px; the reflow was scripted
(`ai/.tmp/sessions/20260902-8b9d2317/reflow-svg.py`) rather than hand-edited, shifting every
following group translate and flow-path y, viewBox 2700 -> 2868. Added a File-scope legend
(per-run / experiment-wide / shared cache) and colored every artifact name in the banners to
match, plus a relay line per task. Verified by headless-Chrome render: no group overlap, and
the two tiers are distinguishable at a glance.

**WI-10 verification run:**
1. Relative-link check across both pools - clean (`check-links.sh` in the session dir).
2. Contract-vs-code - all 14 writer classes exist and every filename fragment appears
   (`check-contract.sh`).
3. Cross-pool naming - all four task names byte-identical across `README.md`, `docs/00`
   and `Osprey-workflow.html`.
4. Headless-Chrome before/after render, plus per-banner crops.
5. `package.ps1` retarget verified in isolation (`test-retarget.ps1`) rather than by a full
   packaging build, which would have locked `Osprey.exe`.
6. `audit-docs.ps1` - the core-five overage above is pre-existing and untouched by this work.

- Next: `/code-review max` in `C:\proj\pwiz-work2`, then open the PR (label `osprey`).
  WI-11 still waits on the resume branch; the in-flight markers are the two `> **In flight**`
  blocks in doc 00 plus the `## In flight` section.

### 2026-09-02 - R1-R11 applied (Opus 5), pwiz `5ae3b449e4`

Every finding verified against code before applying; all eleven were correct. Doc 00 is
now 856 lines - still under the ~900 guard rail, but close enough that the next addition
should displace something into 14 rather than extend 00.

**R1 was my error, and worth recording how it happened.** I marked
`FdrScoresSidecar.PatchProteinQvalues` as a live P11 violation on the strength of doc 14's
`FileSaver` caller list, which named it. That list was stale - the method was deleted at
sidecar v5 (#4486) along with `PatchExperimentValues` - and I never grepped the code for
it, having grepped for everything else. **A contract document must not take a writer or a
caller from another document; only from the code.** Doc 00 now states the opposite of what
I wrote: write-once is fully achieved, and it explains the patch paths historically so the
next reader is not tempted to reintroduce one. I also fixed the same stale prose where it
originated, in doc 14's section 4, which still described the two-phase write as current.

Re-checked the protein-q split per R1's second half: it IS a real unmerged change, but it
is a **P7 and P12** item, not a write-once one. `fdr_experiment.bin` is written once and
never mutated; it is written *late* - after protein FDR - so pass 2's experiment-scope
product sits in an in-memory accumulator across the protein-FDR phase and dies with it.
`## In flight` item 1 now says that.

**The other ten**, all confirmed against code and applied:
- R2: `.model-diagnostics.data.json` is a genuine cross-process hand-off (FirstPassFDR
  stashes the pass-1 data model; SecondPassFDR reads, appends, renders, deletes) and
  `.model-diagnostics.html` is a declared Output of `SecondPassFdrTask`. Both are now
  contract rows, and the "side channels" paragraph names only fdrbench and trace dumps.
- R3/R4: `.calibration.json` travels on EVERY leg (isolation-scheme windows feed the
  gap-fill m/z filter, read behind a `File.Exists`, so omission changes filtering
  silently); `SecondPassFDR` also reads `.reconciliation.json`; `fdr_experiment.bin` is
  read by `PerFileScoring` on rehydrate; and `<stem>.1st-pass.fdr_scores.bin` is **not** a
  default `SecondPassFDR` input - my row contradicted the very contract #4486 established.
- R5: Stage 7 tests the **presence** of a stamp named for `PerFileRescoring`, never
  re-deriving that task's key - `PerFileRescoreTask.ValidityKey` folds in a per-leg flag,
  so the two legs compute different keys for the same task. My "reads the stamp to decide"
  invited exactly the bug that was fixed.
- R6: the blib-name / `ResolveOutputDir` rule governs blib-named artifacts only;
  `.1st-pass.model.json` is the replicated exception and is now scoped out of it.
- R7: `HpcTask` spells three of four differently from the CLI and sidecar names (a name
  copied from the enum will not match a filename); P4 now includes the peak-pick arm; P10's
  mechanism was a published pipeline byproduct, not an in-process flag; in-flight items 2
  and 3 cite the right section and name what `OSPREY_STAGE6_STREAM_SURVIVORS` actually
  gates; `SpectraCache` added as a `.spectra.bin` writer; `2nd-pass.fdr_experiment.bin` is
  read by a resumed `SecondPassFDR` via `ResolvePass2ExperimentRecords`, not terminal.
- R8: relay hygiene stated once at the top of the checklist - every artifact travels with
  its `.osprey.task`, and copy the library with mtime preserved or `LibraryIdentityHash`
  changes and the join node recomputes for hours.
- R9: `FileSaver` call-site table restored to doc 14 from a fresh sweep - 14 sites in 13
  files, replacing the old stale list of 8. P8 now points at it, so "every durable artifact
  commits through FileSaver" is checkable from the docs.
- R10: doc 15 records WHY Stage 6 reads `.calibration.json`; `PerFileRescoring`'s key
  components added to "What the key is made of".
- R11: both in-PR uses of the banned phrase replaced. Three remain in docs 05/06/09, which
  this PR does not touch - left alone deliberately, worth a separate sweep.

Also added the deferred `MEMORY.md` pointer to `TODO-20260728_doc_reorg.md` WI-16.

Verification re-run after the fixes: link check clean, doc 00 ASCII-clean and CRLF,
headless render **pixel-identical** to the pre-R11 capture (the only HTML change was
footer prose), no stale `PatchProteinQvalues`/`PatchExperimentValues` references outside
the two sentences that describe them as deleted.

- Next: `/code-review max` from `C:\proj\pwiz-work2`, then the PR. Brendan also wants the
  active implementation session (the resume branch, `pwiz-work1`) to weigh in first, since
  it has the deepest working knowledge of the in-flight items doc 00 describes.

---

## REVIEW from the PerFileRescoring implementation session (2026-09-02)

Reviewer context: this feedback comes from the session that implemented the fan-out fix doc 00
describes as "in flight" - the per-run hydrate for `--task PerFileRescoring`, the analysis-wide
`retained_base_ids.bin`, and the measurements behind them
(`ai/todos/active/TODO-20260901_osprey_stage5_reload_materialization.md`). Everything below is
grounded in code that was changed or measurements that were taken, not in reading.

**The document is good.** The admissible/inadmissible taxonomy (00 L98-116) is the right frame,
and L289-295 has the best sentence in the tree: *"an experiment-wide file that grows with the
cohort puts the cohort in the floor."* `Osprey-workflow.html` is stronger still - see below.
The notes are about the gap between what the doc asserts and what a reader could act on.

### A. Factual corrections - two statements will mislead the next engineer

**A1. The protein-compact stratum DOES have its own file.** 00 L470-474 says, in bold, *"The
protein-compact stratum has no file of its own ... This is deliberate and worth not undoing"*,
and `12-second-pass-fdr.md` L112-118 repeats it. `FirstPassModelIO.cs` defines
`StratumSuffix = ".1st-pass.stratum.json"`, and the split was FORCED by the document's own P12 -
training does not compute the stratum, first-pass protein FDR does, so the column lives in the
file written by the phase that computes it. Two documents now argue against a change already
made. `regression.ps1` stages it as its own relay hop (`$ph2stratum`).

**A2. 00 L550 asserts a fail-fast that does not exist**, and this is the more dangerous one:
*"A node that has one and not the other is the case the fail-fast exists for, and it is the
orchestrator's job never to create it."* Measured behaviour: `FirstPassFdrTask` logs
`[ERROR] First-pass compaction: failed to read the experiment-scope FDR sidecar`, sets
`ExitCode = 1`, returns null, **and the run continues** with a different retained set, finishing
success-shaped nearly three hours later on a 446-run cohort. The doc is not silent about this
failure - it is reassuring about it.

Two consequences for the wording: the duty is stated backwards (*"the orchestrator's job never
to create it"* - the abdication that produced the wrong answer; the rule needed is that the
**task** must refuse), and the same live hazard is documented and shrugged at in the calibration
row, L497-502.

### B. Missing principles - ranked by "would this have prevented the defect?"

**B1. The fan-out invariant is stated as MEMORY, never as COST.** 00 L213-216 gives
`peak = baseline + max(one run)` and says "k does not appear, and neither does N". A worker that
reads all 446 `reconciliation.json` files to build a union **satisfies that identity at the
instant of peak and still violates the requirement**. That is exactly what shipped: 8m42s and
17.2 GB of startup on an 86-run plate before the first run was rescored - work the loop then
discarded and redid. Brendan's own framing was the correct one: *"no such 17 minute, high memory
loading phase in this task, no matter how many files it contains"* - **both terms**.

The principle to add: *a fan-out task's startup cost - wall clock and memory - must be
independent of how many runs it was handed.* Also note "block size" appears nowhere in the docs
tree, and there is no ladder (446 runs at 50 / 20 / 10 / 5 / 1) to test against.

**B2. VISITED vs RESIDENT is absent, and it is the deepest gap.** 00 L168-184 justifies the two
joins with *"requires knowing where every other run found the same precursor"* - which is a
**visited** claim - and then L130 grants resident O(distinct) with no statement that a whole-run
**fold over a stream** is a third shape. The reader is left with a binary, fan-out or join, and
no vocabulary for "stays in the join, but visits 446 runs and holds one."

**That missing vocabulary is why an all-runs pre-pass could grow inside a fan-out task without
violating any stated rule.** The code already says it - `PercolatorEngine.cs:1019`: *"Both maps
are O(distinct) ... nothing here needs a whole-run view"* - and `StreamingFdr.StreamingFirstPassQ`
is a worked example with a test pinning it, documented in doc 14 and invisible from doc 00. Every
genuinely whole-run computation named in 00 (best-of-runs experiment-q floor, protein parsimony,
the pre-blib q re-clamp) is one of these folds.

**B3. No rule reaches a PER-RUN artifact carrying an ANALYSIS-WIDE payload.** P5 covers
experiment-wide artifacts that grow with the cohort. The defect fixed this session is the mirror
image: `reconciliation.json` is filed as a "per-run product" relayed "with the run" (contract
table L427), while each of 446 copies restates the same join-wide 744,943-id
`first_pass_base_ids` array - **2.79 GB of pure duplication**, and 10.7 GB of envelope JSON that
a per-run worker had to parse to rebuild a union. P1 blesses the benign form of this
(experiment-wide content under a per-run name, "any one copy authoritative") and never addresses
the cost of replication.

**B4. Nothing is enforced.** No principle P1-P15 names a test, gate leg, or signature. P8's
"checkable" is a hand-maintained table in another document; the contract table was "verified
against the path-building code" by a human, once - which is exactly how A1 went stale.

Concretely from this session: **`regression.ps1` mode 3 was GREEN while the per-run path was not
running at all.** A phase-3 node is handed ONE run, where the per-run and all-runs paths are both
O(1) and produce identical bytes, so the outcome cannot distinguish them. This session added a
marker assertion (`mode3 (per-run hydrate): PASS (3 worker(s))`) for that reason. The principle:
*where a contract cannot be distinguished by output at N=1, the gate must assert the PATH.*

Related: mode 3 already IS the enforcement of the single-run input contract, byte for byte. 00
cites it twice as an anecdote (L93-95, L531-534) rather than naming it as the mechanism that
holds the relay checklist.

**B5. "Stop building X" is not one edit per producer.** Every consumer that independently
RECONSTRUCTS X must be found. Skipping the all-runs hydrate was not sufficient:
`HydrateRescoreBundleIfPresent` rebuilt the batch overlay on its own whenever recon sidecars were
present, and failed - loudly, which was luck. The stack is the architectural point in miniature:

```
PerFileRescoreTask.Run -> Get<CompactedEntries> -> Demand(FirstPassFdrTask) -> Rehydrate
                       -> Get<ScoredEntries>    -> Demand(PerFileScoringTask) -> Rehydrate
```

**Three tasks materialised by one `Get`.** Doc 00 never describes the byproduct registry at all -
`Publish` / `Get` / `Demand` / lazy `Rehydrate` appear nowhere in it; the only description is in
doc 15, which disclaims owning the "why". P10 forbids using byproducts for SIGNALS, which is
narrower than the defect it was learned from. The corollary worth stating: *every byproduct
crossing a task boundary must have a disk counterpart, and the in-process path should read the
same artifact the distributed one does* - otherwise the two shapes drift, because the distributed
one is forced to write files and the in-process one just reaches backwards through a cache.

### C. The artifact that makes the input contract executable is absent

`<blib-stem>.1st-pass.retained_base_ids.bin` is in no document. Neither is `first_pass_base_ids`.
So 00 never explains how a per-run worker obtains the join-wide compaction set, and its
**Boundary 2 -> 3 input list (L740-749) is a contract a single-run node cannot actually run on**.

Written by FirstPassFDR when Stage 6 planning ends; carries the join-wide first-pass base_ids
UNION every planned action target; sorted `uint32`, library-bounded (1.49 MB at 373,487 ids).
Needs adding at: contract table (~L428), "Artifacts that must relay together" (L536-550 - "Two
experiment-wide artifacts" becomes three or four), Boundary 2->3 (L747-749), Boundary 3->4
(L768-772), and the blib-named-artifact enumeration (L513-514).

The paragraph most worth writing, for "Rows that are not what they look like": **why the union of
planned action targets cannot ride in a per-run envelope** - each envelope is written the instant
that run's planning finishes, so the actions of runs planned later do not exist yet. That
ordering fact is the whole reason a separate analysis-wide artifact is needed, and it is not
deducible from anything currently in the doc.

### D. Two smaller contract gaps

* The **0-byte `.mzML` stub** is not mentioned. L744 says "`<stem>.spectra.bin` (or the raw file
  it was built from)", which reads as "ship the 6 GB mzML if you have no cache". The real
  contract is the opposite - `regression.ps1` ships the cache plus a 0-byte stub so path
  derivation works and the fingerprint check is skipped, and notes "the real 6 GB mzML is never
  shipped to a rescore worker".
* The **library + decoy-pairing manifest** are listed for boundary 1->2 only and never restated
  for 2->3 or 3->4, though every node needs them. Related: this session found `--cache-dir` is
  required for a `--task` leg whose `--output-dir` differs from the data directory, because such
  a leg has no raw input path to resolve `.spectra.bin` from. Doc 20 has no `--cache-dir` row for
  this case and doc 00's relay checklist does not mention it.

### E. `Osprey-workflow.html` - the strongest artifact of the three

It is **better than doc 00** on the point that matters most here. The banner roles state the
invariant plainly - `per-run fan-out · any batch size, 1..N nodes`, `join · 1 node · holds
O(distinct), never O(runs x entries)`, `per-run fan-out · reads its own runs + the experiment
baseline only` - and the three-tier File scope legend (`per-run` / `experiment-wide · relay to
EVERY node; the resident baseline` / `shared cache`) is exactly the distinction B3 says the prose
lacks. If anything, doc 00 should adopt the diagram's phrasing rather than the reverse.

Three fixes needed, all from the same two missing artifacts:

1. FirstPassFDR's out line annotates `<stem>.1st-pass.model.json` *(frozen model +
   protein-compact stratum)* - stale per A1; the stratum is its own file.
2. PerFileRescoring's `relay: the run's own set + 2 experiment-wide files` and FirstPassFDR's
   `relay: both experiment-wide files to EVERY downstream node` are undercounts. With
   `retained_base_ids.bin` and `stratum.json` it is four; "both" becomes "all".
3. SecondPassFDR's in-list omits `<stem>.calibration.json`, which 00 L425 says it reads on every
   leg. One of the two is wrong - worth resolving rather than leaving them to disagree.

### F. Now stale as a block

00's "In flight" section (L787-822) and the callout at L224-229 describe the state this session
changed. More importantly `15-hpc-scoring-split.md` carries **no in-flight marker at all** (00's
disclaimer at L791-793 covers only 00) while stating as current design that `--task
PerFileRescoring` rehydrates `FirstPassFdrTask` and reads an all-runs `CompactedEntries` buffer
(L54 truth table, L91). Both are what the fan-out fix removes.

Suggestion: rather than re-editing these when the resume branch lands, state the target in the
contract and keep ONE "known deviations" list with issue links - a per-document in-flight note
is what let doc 15 fall out of step with doc 00.
