# Osprey pipeline architecture document and sidecar file contract

## Branch Information
- **Branch**: `Skyline/work/20260902_osprey_pipeline_architecture_docs`
- **Base**: `master`
- **Created**: 2026-09-02
- **Status**: Planned - not started
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

- [ ] **WI-1 (M)** Draft 00: scope, scale, task graph (incl. the re-derived
      per-run-loop figure), principles P1-P11. `docs/00-pipeline-architecture.md` (new).
- [ ] **WI-2 (L)** Sidecar contract table + per-row prose; in-flight rows marked; verify
      EVERY row against `Osprey.Tasks/TaskValiditySidecar.cs`,
      `Osprey.Core/ArtifactPaths.cs` and the writer classes; resolve every `?`.
- [ ] **WI-3 (M)** Directory resolution + `-LinkFrom` section; `-LinkFrom` row in
      `docs/20-command-line.md`. Source: `Osprey.Core/OspreyEnvironment.cs`.
- [ ] **WI-4 (M)** Resume semantics + HPC relay checklist per boundary.
- [ ] **WI-5 (M)** Trim doc 14 (sections 0 and 8 out) and doc 15 (per-task file lists
      out); pointers + ownership rule in each.
- [ ] **WI-6 (S)** Doc 12 "Inputs from the first pass"; `00` row + rule in
      `docs/README.md`; `README.md` Documentation block + HPC pointer.
- [ ] **WI-7 (M)** Shrink `ai/docs/osprey-development-guide.md` (3 sections out, HPC-flag
      table to doc 15, stubs in, subject rule stated). pwiz-ai master.
- [ ] **WI-8 (S)** Pointers: `osprey-run-layout.md`, `osprey-development/SKILL.md`
      routing, `ai/MEMORY.md`; staging recipe in `osprey-large-datasets.md`. pwiz-ai master.
- [ ] **WI-9 (L)** HTML: banner in/out edits, geometry reflow, File-scope legend, relay
      annotations, doc link, `package.ps1` link-retarget check.
- [ ] **WI-10 (M)** Verification:
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
