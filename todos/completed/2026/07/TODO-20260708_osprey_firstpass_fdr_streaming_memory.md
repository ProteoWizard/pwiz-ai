# TODO: Productionize the Osprey FDR projection streaming (both Percolator passes)

**Created:** 2026-07-08  **Requested by:** Mike  **Related:** PR #4378 (#4355/#4374); issue #4393 (closed, wrong premise)
**Status:** COMPLETED 2026-07-10 — productionized in PR #4378 (`f4de68645`, merged 2026-07-09): FDR projection streaming for both passes + `OSPREY_FDR_PROJECTION` flipped default-on (`UseFdrProjection = IsNotZero`; legacy path via `=0`). Issues #4355/#4374 closed-completed. See Resolution at end.

## Correction to the original filing

This TODO was first written claiming Osprey's C# port "materializes what Rust streams" and
that first-pass FDR streaming needed to be built. **That was wrong** — it analyzed the
`master` branch (no streaming). The FDR streaming for **both** Percolator passes already
exists:
- #4355 step (b): `RunFirstPassProjection` + `FdrProjectionSinks` (thin 48 B first-pass
  projection struct; streams the score pass from per-file parquet; results zipped onto stubs
  by index; four q-values streamed to the `.1st-pass.fdr_scores.bin` sidecar).
- #4374: second-pass Percolator FDR streamed through the projection engine.

Both live on the **#4378** branch (`Skyline/work/20260703_osprey_memory_bounding`). PR #4378's
own summary: it "takes the FDR path off the memory critical path."

## Why the 82-file test still hit ~120 GB

The projection path is gated behind **`OSPREY_FDR_PROJECTION`** (env var, **off by default** —
`OspreyEnvironment.cs:127` `IsSetAndNotZero`). `FirstJoinTask.cs:260` routes to the legacy
resident FdrEntry-buffer path ("the byte-identity oracle") when the flag is off (also for
`--model-diagnostics` and FDRBench pass-1). The 82-file fit-test run script never set the env
var, so it materialized all 191M observations → ~120 GB. It was **not** exercising the
reduced-memory FDR path. (Scoring bounding is default-on, which is why scoring held flat at
~48 GB.)

## Real remaining work

1. **Validate** the projection path is byte-identical with `OSPREY_FDR_PROJECTION=1`:
   `regression.ps1 -Dataset Stellar/All` (mode1/2/3) + cross-impl on Stellar + Astral. This
   is presumably why the team kept it flag-gated pending validation.
2. **Measure** the real 82-file Stage-5 peak with the flag on (combined #4378+#4381) to
   confirm it drops from ~120 GB toward the resident-stub floor and completes without thrash.
3. **Flip to default** once validated: make projection the default path with a legacy escape
   hatch (env override), so production runs stream without a hidden opt-in.
4. **Residual sinks to check** if it still overshoots: first-pass protein FDR runs on the
   full pre-compaction pool resident (`RunFirstPassProteinFdr`); the `FdrEntry`-as-class stub
   buffer floor (191M × ~176 B ≈ ~34 GB) vs Rust's ~128 B struct + `Arc<str>` interning.

This is finishing work on #4378, not a separate implementation. No new issue needed (#4393
closed).

## Resolution

**Completed** — the productionization shipped in PR #4378 ("Bounded search memory so large file
counts fit a modest machine", `f4de68645`, merged 2026-07-09); issues #4355/#4374 closed-completed.

### 2026-07-10 - Merged

The four "Real remaining work" items are done:
1–2. **Validate + measure:** the projection path is byte-identical to the legacy `FdrEntry` buffer
   (Stellar regression mode1/2/3), and the memory campaign measured the 82-file peak.
3. **Flip to default:** `OspreyEnvironment.UseFdrProjection` is now
   `IsNotZero(@"OSPREY_FDR_PROJECTION")` — projection streaming is the production default, with
   `OSPREY_FDR_PROJECTION=0` as the legacy escape hatch (slated for removal once model-diagnostics
   + FDRBench stream too).
4. **Residual sinks:** spun out and shipped as the lean-FDR campaign — Stage-5 fat stubs (#4400),
   dense XCorr cache (#4409), and first-pass `FdrProjections` retention (#4406).
