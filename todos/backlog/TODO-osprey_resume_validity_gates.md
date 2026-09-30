# TODO-osprey_resume_validity_gates.md

## Branch Information
- **Branch**: (not yet created) - start from `Skyline/work/20260612_net8_port`
- **Base**: `Skyline/work/20260612_net8_port`
- **Module**: `osprey`
- **Status**: Backlog
- **Origin**: split from `TODO-20260929_osprey_computed_fragment_typing.md` (completed) when
  #4746 and #4749 merged on 2026-09-30. Brendan asked to be reminded then; he was.

## Resume-invalidation fixes (Brendan, 2026-09-29: "fix #2 and #3 after PR 2")

**REMIND BRENDAN when #4746 and PR 2 are both merged**, then do this as its own PR.
From #4746's `/code-review max`; pre-existing, not caused by either PR. Each lets a resume reuse
an output whose validity key no longer matches, so any future key term is silently bypassed:
- [ ] **#2 PerFileRescoring self-gate**: `PerFileRescoreTask.Pass2SidecarCurrent`
      (`PerFileRescoreTask.cs` ~1710) accepts a `.2nd-pass.fdr_scores.bin` by FORMAT only, returns
      `RefillOnly` (~491), and `AnalysisPipeline.WriteTaskSidecars` (~224-242) then stamps the old
      Stage 6 outputs with the new key. Fix: also require
      `PerFileResumeDriver.IsCurrent(pass2Path, Name, ValidityKey(ctx))`. Reach it via
      `--task PerFileRescoring` after re-running Stages 1-5, and `--task ModelDiagnostics`.
- [ ] **#3 SecondPassFDR transfer-mode gate**: `Pass2FdrSidecar.cs` ~206
      (`recomputed = anyRescoreWork && (missingPass2 > 0 || workerDidPerFileHalf)`) judges
      existing pass-2 files by format (`Pass2SidecarWriter.IsCurrent -> IsCurrentFormat`). Under
      `OSPREY_PASS2_QVALUE=transfer`, a key change reloads old pass-2 values, re-stamps them, then
      throws "No second-pass experiment-scope records were published" (`Pass2FdrSidecar.cs` ~1490)
      on every later run until the `.2nd-pass` files are deleted by hand.
- [ ] Tests in `SubsetPipelineTest` (the pipeline-mechanics home): change a key, resume, assert
      the stage re-runs instead of adopting.
- Not doing #1 (the `--task` join validates scores parquets by footer version/hashes only; a
  fix needs a footer marker mirrored in Rust).


## Later, separate

- Rust port of the typing (blib libraries are not in the parity datasets)
- Issue for consolidating C# BLIB read/write (Skyline `BlibDb`/`BiblioSpecLite`, Osprey
  `BlibWriter`/`BlibLoader`/`BlibSpectrum`) into `pwiz_tools/Shared/BiblioSpec` (not yet filed -
  Brendan asked for the write-up)
- Pre-existing issues #4730's first review found, "to be filed" in its description - confirm filed:
  decoys move N-terminal modifications to an internal residue (C# and Rust);
  `DiannTsvLoader.StripFlankingChars` mangles sequences with two decimal bracket masses; the second
  of two adjacent TSV bracket mods lands on residue 0

