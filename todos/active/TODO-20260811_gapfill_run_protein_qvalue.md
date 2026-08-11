# Gap-fill entries get a run protein q on the batch-hydrate arm but not straight-through

## Branch Information
- **Branch**: `Skyline/work/20260811_gapfill_run_protein_qvalue`
- **Worktree**: `C:\proj\pwiz`
- **Base**: `master`
- **Created**: 2026-08-11
- **Status**: In Progress
- **GitHub Issue**: [#4559](https://github.com/ProteoWizard/pwiz/issues/4559)
- **Module**: `osprey`
- **Other labels**: none yet (candidate: `bug`)
- **PR**: (pending)
- **Requester/Reporter**: none - filed by Brendan while verifying #4557. No credit line
  (Osprey developers on Osprey code).

## Objective

A gap-fill entry created in Stage 6 has no first-pass protein FDR result by construction,
yet the two pass-2 routes give it DIFFERENT `run_protein_qvalue`:

* the chain's `SecondPassFDR` node recomputes protein q via `ProteinFdrEngine.RunFirstPass`
  (the `!preCompacted` batch-hydrate path) and assigns **0.0**
* straight-through leaves the **1.0** `ResetScores()` default because nothing assigns one

Decide which value a gap-fill entry should carry - or whether it should carry one at all -
and make both routes agree.

## Prior context - do NOT re-derive

Read `ai/todos/completed/TODO-20260809_fdr_sidecar_parity.md` first. #4557 added the first
comparison of the per-file FDR sidecars, which is the only reason this is visible. Key facts
already established there:

* All 390 diverging records (Stellar, 3 files: 133/116/141) are **absent from the 1st-pass
  sidecar** - they are gap-fill entries created in Stage 6, so #4557's seed provably cannot
  reach them (it only reads sidecar records).
* Every OTHER field agrees on those same records (0 mismatches).
* The two 1st-pass sidecars agree exactly (0 of 482,891) - nothing upstream diverged.
* `mode1 (vs golden)` PASSES on the projection-off arm, so the reported output is correct
  either way today.
* The DEFAULT streaming arm skips the recompute entirely, which is why `-Dataset All` is
  green and TeamCity is unaffected.

## Reproduce

`OSPREY_ALLOW_UNFIXED_RESIDENT` takes NAMED tokens, not a boolean (`projection-off` here;
`1` aborts in `PerFileScoringTask.GuardResidentPool`). Nested `Start-Process -ArgumentList`
can deliver the token with literal quote characters, which also fails to match - a wrapper
script that sets both vars directly is the reliable form.

```powershell
$env:OSPREY_FDR_PROJECTION = '0'
$env:OSPREY_ALLOW_UNFIXED_RESIDENT = 'projection-off'
pwsh -File ./pwiz_tools/Osprey/regression.ps1 -Dataset Stellar -KeepOutput
```

`-KeepOutput` matters: `regression.ps1` self-cleans its run directory, so on an abort the
`straight.log` the error points at is already gone. With it, both routes' sidecars survive
and can be diffed by entry_id (`straight/<stem>.1st-pass...` against
`chain/phase4_SecondPassFDR/<stem>.2nd-pass...`).

Expected failure:

```
pass2: ..._20: run_protein_qvalue differs on 133 record(s); first entry_id=1341 1 -> 0
```

`mode5` and `mode6` also fail on that arm - default-arm log assertions firing against a
switch that disables the streaming and library-fragment-release paths. Unrelated; do not
chase them.

## Open design question - the actual deliverable

Should a gap-fill entry carry a run protein q at all? If it should, which route is right?

* **0.0** is a real best-group value, but it lands on an entry that never competed at the
  protein level - the more surprising of the two, and 0 is the accept side of the boundary.
* **1.0** is the "no value" default and is what straight-through reports today.

Note the related invariant from #4553: all peptides of a protein should share a protein q.
Whichever value is chosen has to be checked against that.

Whatever is decided must land on **both** C# and Rust, or the cross-impl sidecar leg
(`Compare-FdrSidecars-Crossimpl.ps1`, added by #4557) goes red - it exists precisely to
catch a one-sided fix. Also note maccoss/osprey#61 (the Rust half of #4557) may still be
open; check before measuring cross-impl.

## Tasks

- [ ] Reproduce the failure on the projection-off arm with `-KeepOutput`
- [ ] Confirm the 0.0 assignment site in `ProteinFdrEngine.RunFirstPass` (`!preCompacted`)
      and identify why gap-fill entries land there with a best-group value
- [ ] Check the Rust side for the same behavior before choosing a fix
- [ ] Decide the contract: does a gap-fill entry carry a run protein q, and which value
      - **needs Brendan's sign-off**, this is a contract decision not a defect fix
- [ ] Implement on both C# and Rust
- [ ] Verify `mode3` green on the projection-off arm; confirm `-Dataset All` (default arm)
      unmoved, or rebaseline the golden if it moves
- [ ] Cross-impl sidecar leg green with both sides changed

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: `pwiz_tools/Osprey/regression.ps1` mode 3 (per-file FDR sidecars) -
  currently only red on the projection-off arm, which no scheduled gate runs. Part of this
  work is deciding whether that arm needs a gate at all, or whether the fix makes the
  question moot on the default arm.
- **Fails on master**: (yes - `run_protein_qvalue` differs on 390 records, Stellar 3-file,
  projection-off arm; to be re-verified with a run log path)
- **Passes on fix**: (pending)

## Progress Log

### 2026-08-11 - Session Start

Filed out of #4557 (`ai/todos/completed/TODO-20260809_fdr_sidecar_parity.md`) as a
deliberate deferral: it is a decision about the protein-compact contract, not a defect in
that fix. Starting work.
