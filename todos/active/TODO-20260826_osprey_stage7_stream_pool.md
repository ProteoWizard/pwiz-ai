# Osprey Stage 7: make the survivor pool non-resident through pass-2 scoring and protein FDR

## Branch Information
- **Branch**: `Skyline/work/20260826_osprey_stage7_stream_pool`
- **Base**: `master` (2a0b0069f6, i.e. after #4615)
- **Worktree**: `C:\proj\pwiz-work1` — `C:\proj\pwiz` is held by the open PR #4616
  (cache-only inputs), which a CHS plate run is field-validating
- **Created**: 2026-08-26
- **Status**: In Progress
- **GitHub Issue**: [#4486](https://github.com/ProteoWizard/pwiz/issues/4486)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

Stage 7 holds the whole-run survivor pool (`RescoredEntries` =
`List<KeyValuePair<string, List<FdrEntry>>>`) resident from pool construction through
pass-2 scoring, protein FDR and the blib write. Measured post-GC on **257 CHS files**
(2026-08-25, `OSPREY_LOG_MEMORY=1`, `--task SecondPassFDR`):

| post-GC probe | live managed |
|---|---|
| `library-resident` | 4.19 GB (6,175,389 entries) |
| `stage7-inherited` / `stage7-pool` | **41.97 GB** |
| `stage7-fragments-released` → `stage7-blib-written` | 39.62 GB, **flat** |

**4.19 GB library + ~147 MB/file live** → ~78 GB at 500 files, ~152 GB at 1,000. Over any
64 GB box, and it is the last structural wall between here and the 500-file target.

## Read the issue's correction chain before planning — it has reversed twice

This issue is nine comments long and has been rescoped four times. Two reversals matter:

1. **"Stage 7 costs nothing per file" (2026-08-08) was wrong and was retracted the next
   morning.** It came from post-GC probes at substep BOUNDARIES; the pass-2 competition
   allocated and released its state *between* two boundaries, so both probes read the same
   number and the phase looked free. ~2.5 GB at 16 files (hidden), ~13 GB at 82 (dominant).
2. **The concrete lever named in that retraction is already fixed.** The three
   `Dictionary<(string, uint), double>` + `HashSet<(string,uint)>` returned by
   `StreamingFdr.ComputeFullPopulationPrecursorFdrStreaming` — 86.6 M observations, ~13 GB
   at 82 files — are gone: **#4554 ("Bounded and instrumented the Stage 7 join")** replaced
   them with `StreamedCompetitionState`, O(distinct base_id / entry_id), and moved the
   per-survivor loop into the caller's per-file emit pass. Verified in the tree today.
   `Pass2FdrSidecar` is therefore **not** the target; the pool itself is.

**Methodological consequence, which applies to my own measurements on this branch**: the
2026-08-25 table showing a flat 39.62 GB live floor is boundary-sampled too. It is evidence
that nothing *accumulates* after pool construction — not evidence that no phase allocates a
large transient inside itself. Anything I measure at a boundary inherits that blind spot.

## What is actually left

The pool is built before pass-2 scoring and released after the blib write, and **the peak is
set at construction**. So releasing it earlier buys nothing; the fix has to make it
non-resident *through* the two phases that assume a global view:

1. **`RunProteinFdr` → `ProteinFdrEngine.RunSecondPass`** — parsimony + picked-protein TDC
   over a global stratum. Genuinely whole-run, but the open question is whether it needs
   every observation or an O(distinct peptide/protein) aggregate.
2. **`Pass2FdrSidecar.ComputeAndPersist`** — its cross-file state is already bounded by
   #4554, but it still receives `perFileEntries` and writes per-file sidecars. Question is
   what it reads off the pool beyond what `StreamedCompetitionState` already answers.
3. **`WriteBlibOutput`** — already aggregate-shaped (`BuildBestExpPrecursorQ`,
   `BuildSharedBoundaries`, `BuildCrossFileObservations`) and it emits per file, so it is
   the natural second streamed pass. The issue notes it "could run on aggregates alone".

Target shape (and the standing constraint on FDR memory): **per-file compute → O(entries)
aggregate → per-file emit, with emission a SECOND streamed pass.** No `O(files × entries)`
structure in either direction.

**Documented trap — do not start here.** `entriesByPrecursor` holds
`List<KeyValuePair<string, FdrEntry>>`, references that PIN the pool, while its consumers
read only `observations.Count`, `obs.Key`, `EffectiveRunQvalue` and `ApexRt/StartRt/EndRt`
(~40 B). Converting it to a value struct unpins the pool but, while the pool is held anyway,
makes memory WORSE (16 → 40 B per observation). Step two, not step one.

## Tasks

- [ ] **Split inherited-vs-built on the straight-through path.** The issue calls this "the
      obvious next measurement". The 257-file numbers are `--task SecondPassFDR`, where the
      reload has already built the pool (hence `stage7-inherited == stage7-pool`); in-process,
      #4597 defers the build to the `.Value` read inside Stage 7, so the split differs. The
      39.62 GB floor and the 147 MB/file slope hold either way.
- [ ] Establish, per consumer, exactly which `FdrEntry` fields are read and whether that is
      expressible as an O(distinct) aggregate — protein FDR is the one that decides feasibility
- [ ] Record the two-pass design here BEFORE writing it
- [ ] Implement, gated on byte-identical output
- [ ] Post-GC memory A/B at ≥100 files, plus an in-phase sample so a transient cannot hide
      between two boundary probes (the 2026-08-08 error)

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test / `regression.ps1` modes 1+3
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

Stage 7 feeds the blib, so `regression.ps1 -Dataset All` byte-identical is the correctness
oracle, and **mode 3 (HPC chain == straight) is the direct one** because the chain runs
`--task SecondPassFDR`. Byte-parity alone cannot catch a pool that is still resident, so the
memory property additionally wants a `ResidentPoolGuardTest` entry — the ratchet that
retired `mdiag-full-resume` (#4505), `resume-survivor-handoff` (#4536) and `hpc-merge`
(#4554-era) from `ResidentPaths.KNOWN_UNFIXED`.

## Measurement harness

Stage 7 alone against a completed run, ~70 min at 257 files / ~25 min at 100, without
re-running the ~15 h of per-file work:

```powershell
pwsh -File ai\scripts\Osprey\CHS\Run-Chs.ps1 -IncludePattern 'us(0059|0060|0061)' `
  -Task SecondPassFDR -LinkFrom '<completed 257-file run dir>' `
  -Tag '-s7probe' -LogMemory -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact `
  -Threads 30 -FdrBenchPass 2 -LibraryDir '<lib>' -Exe '<snapshot>\Osprey.exe'
```

Traps carried from the issue: a repeat run against a directory that still holds
`*.2nd-pass.fdr_scores.bin` self-gates to a no-op, exits 0 and measures nothing; and never
point `Measure-Stage6Rescore.ps1 -PhaseDir` at a real run directory — it begins by deleting
`*.2nd-pass.fdr_scores.bin` and `*.scores-reconciled.parquet` inside it.

## Sequencing note

An 8 h CHS plate-0062 search (PR #4616 field validation) holds the machine until roughly
19:30 on 2026-08-26, and a second ~9.5 h run follows it. Measurement contends with those for
disk and threads; reading and design do not.

## Related

- [#4486](https://github.com/ProteoWizard/pwiz/issues/4486) — nine comments, read the
  2026-08-09 correction and the 2026-08-25 measurement before planning
- #4554 — bounded the pass-2 competition's cross-file state (the previously-named lever)
- #4597 — the deferred pool build Stage 7 now pays for
- #4615 / `ai/todos/completed/TODO-20260825_osprey_stage7_memory.md` — the transient noise
  around this peak (LOH churn in `RestorePass1Scalars`, heartbeat, pre-sized lists)
- #4526 / #4530 / #4536 / #4545 — the O(files) work upstream; this is the O(survivors) residue
- `ai/docs/memory-band-guide.md` — post-GC probes vs `--memstamp`

## Progress Log

### 2026-08-26 - Session start

Branch created in `C:\proj\pwiz-work1` off master 2a0b0069f6. Read the issue body and all
nine comments in full. Two things that a short read would have got wrong, recorded above:
the "Stage 7 costs nothing per file" finding was retracted, and the concrete lever its
retraction named (the per-observation dictionaries in `ComputeFullPopulationPrecursorFdrStreaming`)
has since been fixed by #4554 — confirmed in the tree, `StreamedCompetitionState` is O(distinct).
What remains is the live survivor pool itself.
