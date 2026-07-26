# Compare/ -- Cross-impl Bridge

This folder holds the cross-implementation comparison scripts that
gate Osprey output against Rust osprey (`maccoss/osprey` or a
local fork).  Now that Osprey is the primary implementation,
these scripts are used rarely -- the Osprey-alone regression
gate (`../Test-Snapshot.ps1` / `../Test-Full-Regression.ps1`) handles
the day-to-day correctness checks.  Keep this folder when you need
to ask:

  "Did my Osprey change drift us from Rust at the 1e-9 gate?"

Typically only relevant for changes that touch scoring, calibration,
LOESS, KDE, the SVM kernel, FDR thresholds, or the blib write path.

## Requirements

A Rust osprey checkout must be present (default: sibling of the
pwiz checkout under `<project root>/osprey`).  Override location
via `$env:OSPREY_ROOT` or the `-OspreyRoot` parameter on
`Build-OspreyRust.ps1`.

## BUILD BOTH SIDES FIRST -- the gate builds neither

`Compare-EndToEnd-Crossimpl.ps1` **runs prebuilt binaries**; it does not
build.  Build both sides explicitly before invoking it:

```powershell
pwsh -File ./ai/scripts/Osprey/Compare/Build-OspreyRust.ps1
pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Release
```

Note the **Release**.  The two documented procedures do not compose: the
Osprey pre-commit gate builds **Debug**
(`Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`) while this
gate runs the **Release** exe.  So "edit, run the gates green, run the
comparison" silently leaves the C# side stale, and the comparison returns
entirely plausible numbers measured against the *old* code.

That is not hypothetical.  It produced a "46% cross-impl divergence" that was
investigated across three sessions before being retracted -- the run had
compared swap-removed Rust against a swap-present C# binary.  The obvious
control (check out the baseline branches and re-run) is **inert** here, because
checking out source does not change which exe runs: it returns byte-identical
numbers that read as confirmation of a pre-existing divergence.

Since 2026-07-26 the script **hard-fails (exit 3)** when either side's build
output is older than that side's newest source file, naming both timestamps.
`-AllowStaleBinaries` overrides it when the mismatch is deliberate.

The freshness check compares against the newest build output *beside* the exe,
not the exe itself: on net8.0 `Osprey.exe` is only the apphost stub and
`Osprey.dll` the entry assembly, so a change confined to a dependency project
(`Osprey.Core`, `.Scoring`, `.FDR`, `.Tasks`, ...) rebuilds only that dll and
leaves both untouched.  Timestamping the exe alone reports a false "stale"
right after a successful incremental build.

## The 1e-9 gate

`Compare-EndToEnd-Crossimpl.ps1` runs both implementations
straight-through (no HPC chain, no rehydration) and compares Stage 7
protein FDR + blib SQL content at per-column 1e-9 absolute tolerance.
PASS = the two implementations agree byte-for-byte at the gate's
tolerance.

```powershell
# Stellar single-file (~5 min): cheapest sanity check
pwsh -File ./ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files Single

# Astral 3-file (~45 min): rigorous stress test, recommended pre-merge
# for algorithm-affecting changes
pwsh -File ./ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1 -Dataset Astral -Files All -Force
```

The two sub-scripts `Compare-Stage7-Crossimpl.ps1` and
`Compare-Blib-Crossimpl.ps1` are invoked internally by the
end-to-end gate; you can call them directly to compare just one
artifact during a focused investigation.

## When the gate fails

Most cross-impl drift falls into one of two categories:

* Bit-parity drift past 1e-9 -- usually a reduction-order change
  (SIMD lane stride, parallel partial-sum order) that needs the
  same algebraic change on the other side, or a deliberate decision
  to widen the tolerance.
* Threshold-boundary flip -- a ULP-scale score change pushes a
  borderline target/decoy across the FDR threshold, changing
  precursor counts.  Look at the differing entries' scores; if
  they're at sub-ULP distance from the threshold, document and
  widen the comparator.

The `archive/` folder under this directory holds the per-stage
bisection tooling we used during the original parity sprint: if a
fresh failure surfaces and the end-to-end gate doesn't tell you
which stage diverged, those scripts are the next step in.  They are
sprint-specific and not maintained; expect to rebuild them rather
than treat them as supported.
