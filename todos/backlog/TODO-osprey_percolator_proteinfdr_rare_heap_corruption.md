# TODO: Rare intermittent heap-corruption crash in Percolator → protein-FDR path

**Status**: Backlog — filed 2026-06-04 during PR-C (byproduct context) final validation.
**Priority**: Medium — rare (1 occurrence in ~25+ executions), but it's a memory-safety
symptom, which is never truly benign. Not a PR-C regression (failing code is unchanged by
PR-C; see "Attribution").
**Type**: Defect (intermittent / non-deterministic).

## Symptom

A single `--join-at-pass=1 --join-only` run (Stellar 3-file, net8.0) crashed in Stage 5
first-pass protein FDR with:

```
[ERROR] Pipeline failed: Unable to cast object of type
        'pwiz.Osprey.Tasks.FirstJoinTask' to type
        'System.Collections.Generic.IEqualityComparer`1[System.String]'.
   at System.Collections.Generic.HashSet`1.IsSubsetOf(IEnumerable`1 other)
   at pwiz.Osprey.FDR.ProteinFdr.BuildProteinParsimony(...) ProteinFdr.cs:line 225
   at pwiz.Osprey.Tasks.FirstJoinTask.RunFirstPassProteinFdr(...) FirstJoinTask.cs:1646
   at pwiz.Osprey.Tasks.FirstJoinTask.Run(...) FirstJoinTask.cs:231
```

The crash happened immediately after the parallel Percolator folds completed
("Percolator train all folds (parallel): 60.0s"), in the next heap-heavy operation.

## Why this is heap corruption (not a logic bug in BuildProteinParsimony)

`ProteinFdr.BuildProteinParsimony` (ProteinFdr.cs:150-233) is entirely single-threaded and
builds every `HashSet<string>` with `StringComparer.Ordinal` or the default. At line 225 it
calls `group.Key.IsSubsetOf(larger.Key)`; `IsSubsetOf` reads the set's `Comparer`. For that
`_comparer` field (typed `IEqualityComparer<string>`) to hold a `FirstJoinTask`, the object's
memory must have been overwritten — a `FirstJoinTask` is not assignable there through any
normal code path. So the set's memory was corrupted by *something else*, and the cast merely
surfaced it.

The Percolator parallel infrastructure looks thread-safe on inspection
(`SvmTrainScratchPool` is a `ConcurrentBag`, `OspreyParallel.For` uses `Interlocked`), so the
corruption source is not obvious there. Prime remaining suspects: unsafe/`Span`/`stackalloc`
out-of-bounds writes in the SVM / matrix numeric code (`Osprey.ML`,
`Osprey.FDR/PercolatorFdr.cs`), or the nested-parallel grid search. Not yet root-caused.

## Attribution (not PR-C)

- `ProteinFdr.cs`, `PercolatorFdr.cs`, and the SVM/matrix code are **byte-for-byte unchanged
  by PR-C** (the byproduct-context refactor only changed how upstream state is *handed to*
  protein FDR, not the computation).
- Frequency on a fully clean PR-C build: **0 failures in 20** dedicated `--join-only` runs +
  1 full strict-gate pass (~23 protein-FDR executions). The single failure occurred once on
  the incrementally-built binary, which then *passed* on its own re-run — i.e. intermittent on
  a fixed binary, not a deterministic build artifact.
- User decision (2026-06-04): accept as a pre-existing rare flake, file separately, do not
  block PR-C.

## Repro / investigation pointers

- Harness: `ai/.tmp/prc_reprochar.ps1` loops the exact failing `--join-only` command (clearing
  FirstJoin's Stage-5 outputs each iteration to force recompute). ~77s/run.
- Next step to make it deterministic: run under `DOTNET_GCStress` (e.g. `0x1`/`0xC`) to amplify
  a GC-hole / use-after-free into a reliable crash; if it reproduces under GC-stress, capture a
  dump and walk the corrupting writer. If GC-stress never reproduces, suspect a native/unsafe
  out-of-bounds write and reach for PageHeap / Application Verifier on the SVM/matrix path.
- Compare master HEAD under the same harness to confirm pre-existing (a master failure is
  decisive; absence in N runs is only weak evidence given the low rate).
```

## Related
- `ai/todos/active/TODO-20260604_ospreysharp_byproduct_context_prc.md` (PR-C — where this surfaced)
