# TODO: C# Astral ~9% slower than the published baseline at FIXED source — runtime/build drift, NOT a sprint regression

**Status**: **RESOLVED 2026-06-05 (night session)** — the gap was transient machine state, NOT a
regression. A fresh-reboot re-measure at the recorded commit reproduces the published baseline.
Filed 2026-06-04 during PR-C perf gating; conclusion CORRECTED 2026-06-04 after a full bisect;
**closed 2026-06-05 after a fresh-reboot 3-run median** (see RESOLUTION below).

## RESOLUTION (2026-06-05 night session) — fresh-reboot re-measure reproduces the baseline

The user rebooted the machine to approximate the original overnight-capture conditions, then asked
for a 3-run median at the **recorded commit #4246 (a56498ca78)** — the exact commit listed with the
published Osprey-workflow.html numbers. Result (net8.0, Astral, MaxParallelFiles=1, 16 threads,
`ai/.tmp/measure-pipeline/n4246_fresh_reboot_3run/`):

| metric    | published | **fresh-reboot 3-run median** | prior-today (after a day of heavy builds) |
|-----------|----------:|------------------------------:|------------------------------------------:|
| stage1to4 | 437       | **455.7** (+4.3%)             | 488 (+12%)                                |
| total     | 970       | **983.6** (+1.4%)             | 1053.9 (+9%)                              |

The reboot recovered **83% of the total gap** (1053.9→983.6) and **63% of the stage1to4 gap**
(488→455.7), at the SAME commit and SAME build process. Residual is **+1.4% total / +4.3% stage1to4**
— within day-to-day machine variance and the imperfect reproduction of the original capture schedule.
**There is no durable 10% regression.**

### Corroborating evidence — the residual is thermal/sustained-load, not code
The three back-to-back runs are **monotonically increasing** in every heavy stage:
- total: 962.6 → 983.6 → 986.9
- stage1to4: 451.9 → 455.7 → 458.6
- stage6: 316.0 → 332.4 → 336.6

The **cold run 1 was the fastest** — the opposite of a cold-cache signature — which is the
fingerprint of thermal/sustained-load throttling as 3 consecutive ~16-min Astral runs heat the CPU.
The published 2026-05-28 overnight capture interleaved Rust + Stellar + other datasets between the
C# Astral runs (giving CPU cooling gaps), so a back-to-back 3-run reasonably sits ~1-4% above it.

### Why it was never build-SDK or source (priors that agreed in advance)
- OspreySharp `Release` builds a **pure-IL net8.0 dll with no ReadyToRun/crossgen** (no `<PublishReadyToRun>`
  in the csproj), so hot loops are JIT-compiled at runtime by the **8.0.27 runtime — identical in both
  captures**. Roslyn IL differences from a newer build SDK don't move a compute kernel ~10% when the
  JIT is fixed. No `global.json` SDK pin, no `DOTNET_`/`COMPlus_` overrides, default Tiered+PGO,
  workstation GC — same both times. So there was no build-time codegen lever to explain it.
- (An 8.0 SDK is winget-installable as `Microsoft.DotNet.SDK.8` if a future build-SDK A/B is ever wanted,
  but it is not indicated.)

### Process lesson (the durable fix still stands)
Perf captures must run on a **clean/idle machine** (ideally fresh-rebooted) and, for the closest match
to the published numbers, with **cooling gaps between heavy same-dataset runs** (interleave tools/datasets
rather than back-to-back). The durable fix from the original filing remains valid: a **pinned, reproducible
perf baseline + a standing gate** captured under controlled (rebooted, interleaved) conditions — not a
one-off number in HTML compared against an ad-hoc end-of-day measurement.

---
*Original investigation notes below (retained for the record).*

**Priority**: Medium — the C# port still beats Rust on Astral today (0.73×), but ~9% short of
the published 0.66× advantage we want to maintain. The gap is in the C# runtime/build layer, not
OspreySharp source.
**Type**: Performance investigation (NOT a code regression in the OOP sprint or PR-C).

## What was first suspected, and the correction

Initial read (single Astral run, PR-C vs published): master HEAD ~9% slower than the published
970s, so it looked like the OOP sprint (PR-A #4264 / PR-B #4266) regressed per-file scoring.
**A full bisect disproved that.**

## Bisect result — the sprint is perf-FLAT

Astral straight-through, C#, net8.0, this machine, 2026-06-04, MaxParallelFiles=1 (default),
single run each:

| commit                         | Astral C# total | stage1to4 |
|--------------------------------|----------------:|----------:|
| #4246 (a56498ca78, published-era / svm_stage5_perf) | 1063.5 | 498.3 |
| #4250 (c19e035b02, last "green" perf gate)          | 1068.8 | 502.3 |
| #4264 (b2d4072ff1, post-PR-A)                       | 1065.1 | 502.2 |
| #4266 (23d196a762, master / post-PR-B)              | 1064.8 | 504.1 |
| PR-C (#4267)                                         | 1057.9 | 510.3 |

All within 0.5%. **No sprint PR regressed perf** — including #4246, the published-baseline commit
itself. PR-C is marginally faster than master.

## The actual finding: published-vs-today gap at FIXED source, C#-specific

The published Osprey-workflow.html Astral C# total is **970s** (3-run medians, `svm_stage5_perf`
branch ≈ #4246, ~0527 — only ~8 days before this measurement). But **#4246 measured today = 1063.5s**.
Same source commit, +93s.

Attribution via the change-immune Rust anchor (same dataset, same machine, today):

| stage     | C# pub | C# #4246 today | Rust pub | Rust today | read |
|-----------|-------:|---------------:|---------:|-----------:|------|
| stage1to4 | 437    | 498.3          | 549      | 546.6      | Rust FLAT, C# +61 → **C#-specific** |
| stage5    | 74     | 67.6           | 102      | 89.5       | both faster today |
| stage6    | 295    | 340.6          | 478      | 566.3      | both slower today → **environmental** |
| stage7    | 150    | 140.8          | 194      | 181.6      | both faster today |
| blib      | 9      | 9.1            | 113      | 72.6       | — |
| **total** | **970**| **1063.5**     | **1466** | **1464.7** | Rust total reproduces to 0.1% |

- Rust total reproduces (1464.7 vs 1466) → machine environment is stable at aggregate.
- stage6 is slower today for BOTH impls → an environmental per-stage shift (nets out for Rust).
- **stage1to4: Rust flat, C# +61s at the SAME commit** → a C#-runtime/build difference between
  the ~0527 capture and today, NOT OspreySharp source and NOT environment.

Ruled out: `MaxParallelFiles` (Astral = 3 files, default 1/serial for both published and today).

## Hypothesis — narrowed after checking the runtime (2026-06-04)

Framework: ALL measurements (published and today) are **net8.0**, framework-dependent, rolling
forward to the latest installed patch.

Installed `Microsoft.NETCore.App`: **8.0.26** (2026-04-19) and **8.0.27** (2026-05-18). The
published capture was ~**2026-05-27** — *after* 8.0.27 landed — so BOTH the published run and
today's run used **8.0.27**. **A runtime patch change is therefore REFUTED** (same JIT runtime
both times, same source commit, Rust-controlled environment, yet C# stage1to4 +61s).

Remaining candidates (all build-time / measurement, not runtime patch):
- **Build SDK**: only **9.0.313** and **10.0.300** SDKs are installed now — *no 8.0.x SDK*. If the
  ~0527 build used an 8.0 SDK (since removed) and today builds net8.0 with the .NET 10 SDK, the
  build-time IL / ReadyToRun / Dynamic-PGO defaults could differ even with the same JIT runtime.
- **Measurement methodology**: ruled out. A **3-run median at #4246** (published methodology,
  2026-06-04) = **1053.9s total** (stage1to4 488s) with very low variance (total 17:33..17:47,
  ±~1%; stage1to4 8:04..8:15). So the gap is NOT a single-run / JIT-warmup artifact — the
  published 970 simply does not reproduce at its own baseline commit today, reproducibly.

So the only surviving candidate is a **build-time difference** (the missing 8.0 SDK → net8.0 now
built with the .NET 10 SDK; different ReadyToRun / Dynamic-PGO / IL), or genuinely different
capture conditions on ~0527 that we can't reconstruct from the record. Deferred to an overnight
full-perf rerun (the durable fix: a pinned, reproducible baseline + standing gate).

**User decision (2026-06-04): the OOP sprint is perf-flat and PR-C is clean; C# still beats Rust
(~0.73x, ~10% off the best-seen). Move on. Re-run the complete perf numbers overnight regularly
going forward for the closest match to the original capture conditions.**

## Next steps to recover the published 0.66× advantage

1. Confirm with a 3-run median at #4246 (published methodology) vs today's single runs, to rule
   out a single-run/median artifact (Rust matching to 0.1% argues it's not, but confirm).
2. Identify the SDK used for the ~0527 capture vs now (`dotnet --list-sdks`; any record in the
   svm_stage5_perf TODO / session notes). If an SDK update regressed it, pin via `global.json`
   and re-measure.
3. Check perf-relevant build/runtime knobs in the OspreySharp csproj + environment
   (TieredCompilation, TieredPGO, ReadyToRun, DOTNET_* env) — set them explicitly and re-measure.
4. If recoverable, **re-instate a stage1to4-watching perf A/B gate** (like #4250's Stellar 3-repeat)
   so future work measures against a pinned, reproducible baseline.

## Per-stage breakdown (2026-06-04) — the resolution target is stage1to4 only

Published vs today, with Rust as the change-immune control and the C#/Rust ratio per stage
(C# = #4246 3-run median; Rust = today single-run, which reproduced the published total to 0.1%):

| stage     | C# pub | C# today | C# Δ        | Rust pub | Rust today | Rust Δ      | C#/Rust pub | C#/Rust today |
|-----------|-------:|---------:|-------------|---------:|-----------:|-------------|------------:|--------------:|
| stage1to4 | 437    | 488      | **+51 (+12%)** | 549   | 546.6      | −2 (flat)   | 0.80x       | **0.89x**     |
| stage5    | 74     | 68.1     | −6 (−8%)    | 102      | 89.5       | −12         | 0.73x       | 0.76x         |
| stage6    | 295    | 345.9    | +51 (+17%)  | 478      | 566.3      | +88 (+18%)  | 0.62x       | 0.61x         |
| stage7    | 150    | 134.8    | −15 (−10%)  | 194      | 181.6      | −12         | 0.77x       | 0.74x         |
| blib      | 9      | 12.1     | +3          | 113      | 72.6       | −40         | 0.08x       | 0.17x         |
| **total** | **970**| **1053.9**| **+84 (+9%)**| **1466**| **1464.7** | −1 (flat)   | **0.66x**   | **0.72x**     |

The +84s total splits into two stages with DIFFERENT causes:

1. **stage6 +51s — environmental, not a C# problem.** Rust is up the same ~18% here; the C#/Rust
   ratio held (0.62 → 0.61). Shared with Rust, washes out of the comparison. C# keeps its big lead.
2. **stage1to4 +51s — C#-specific, the real target.** Rust is FLAT here (549 → 546.6), but C# is
   +12% at FIXED source (#4246, which predates the scoring decompositions — so not the refactors
   either). Same runtime (8.0.27), Rust-controlled environment, low variance.

**Is C# notably slower than Rust? No.** C# is still faster than Rust in EVERY stage today and 28%
faster overall (0.72x). The only erosion is stage1to4, where C#'s lead thinned from 0.80x to 0.89x
(still faster, by less). The entire total-ratio erosion (0.66 → 0.72) traces to that one stage.

**Resolution target = stage1to4 (per-file scoring) only.** Same source, same runtime, Rust flat,
~+51s. Runtime patch ruled out. Live hypothesis: build-time (no 8.0 SDK installed now → net8.0 is
built by the .NET 10 SDK; different ReadyToRun / Dynamic-PGO / IL). Clean test: build #4246 with an
8.0 SDK and re-measure stage1to4 — if it drops toward 437, that's the cause and it's recoverable.
**To be pursued in a fresh session.**

## Process lesson

The perf gate lapsed after #4250 (the #4254–#4259 scoring decompositions + #4259's explicit
"No regression gate — pure type-widening" skip), which is what made a regression *plausible* and
worth bisecting. The bisect cleared the sprint but surfaced that our published baseline isn't
currently reproducible — so the durable fix is a **pinned, reproducible perf baseline + a standing
gate**, not a one-off number in HTML.

## Related
- `ai/todos/active/TODO-20260604_ospreysharp_byproduct_context_prc.md` (PR-C — where this surfaced)
- `ai/todos/completed/TODO-20260527_svm_stage5_perf.md` (the published-baseline perf work, #4246)
- `Osprey-workflow.html` perf table (the published baseline)
