# TODO-osprey_version_git_hash.md -- Stamp Osprey version with commit-date DOY + git hash on every build path

## Status
Active (brendanx67). Branch `Skyline/work/20260701_osprey_version_git_hash`,
PR #4352 (opened 2026-07-01, autonomous night session). Motivated by a concrete,
expensive incident (2026-07-01, below).

### Progress (2026-07-01 night session)
- DONE. `Directory.Build.targets` stamps `AssemblyInformationalVersion =
  YEAR.ORDINAL.BRANCH.DOY-<shorthash>[-dirty]` on every build path via
  `stamp-version.ps1` (dot-sources `version.ps1`'s new
  `Get-OspreyInformationalVersion` -- single source, no drift). `OspreyVersion`
  adds `InformationalVersion`/`GitHash`/`DisplayVersion`; `--version` + startup
  log show `Osprey v26.1.1.182 (8c0be655c8)`. `Current` stays bare numeric
  (cache/golden/tests unchanged).
- Verified: plain `dotnet build` (former DOY-0 path) stamps DOY+hash; clean-tree
  Release build drops `-dirty`; `Build-Osprey -RunTests -RunInspection` green
  (450 tests, 0 warnings); `OspreyVersionTest` added.
- DEFERRED to follow-up: embedding the hash in blib `osprey_version` / sidecar
  provenance cells (proposed-work item 1) -- changes golden-compared artifacts,
  needs a golden re-capture; kept out of this versioning-only PR. `Current`
  (numeric) still keys cache-compat as before.

## Motivation -- the incident this prevents
We spent several hours unable to answer "what source produced this Osprey binary?"
while reproducing Mike's PR #4347 FDRBench result. Mike's Carafe-bundled Osprey
reported `Osprey v26.1.1.0` and produced a materially different entrapment FDP
(0.98%) than every build we could make from the current PR source (1.57%, identical
across net472 / net8.0 framework-dependent / net8.0 win-x64 self-contained / Debug).
Because the version string carried **no git hash** and a **DOY of 0**, we could not
tell which commit his binary came from, and could not close the investigation. A
Skyline-style stamp (`26.1.1.181 (89ea8de8a1)`) would have made it a 5-second
diagnosis. For a tool whose entire value proposition is *reproducible FDR
assessment*, an untraceable binary is a first-class defect.

## Current state (verified 2026-07-01)
- **Version string**: `OspreyVersion.ResolveVersion()`
  (`pwiz_tools/Osprey/Osprey.Core/OspreyVersion.cs`) returns the assembly version
  `YEAR.ORDINAL.BRANCH.DOY` (e.g. `26.1.1.181`). **No git hash is appended anywhere.**
  `--version` prints just `Osprey v<that>`.
- **DOY source is already the git COMMIT date -- but only on the version.ps1 path.**
  `pwiz_tools/Osprey/version.ps1:38` computes
  `$doy = ((yy) - OSPREY_YEAR)*365 + $verDate.DayOfYear` where `$verDate` is the
  **git commit date** (docstring lines 12-14: "DOY is the day-of-year of the git
  commit date (reproducible across rebuilds of the same commit)"). Confirmed:
  HEAD `89ea8de8a1` committed 2026-06-30 -> DOY 181 -> a Release build stamped
  `26.1.1.181`. So the commit-date-DOY requirement is *met* where version.ps1 runs.
- **But Debug / plain `dotnet build` / Carafe's build bypass version.ps1 and stamp
  DOY = 0** (`26.1.1.0`). Both our Debug build and Mike's Carafe binary show this.
  Those builds get neither a real DOY nor a hash -> untraceable.

So the day-vs-build-day concern is already handled on the release path; the real gaps
are (a) **no git hash on any path**, and (b) **the commit-date DOY (and hash) are not
applied on the Debug / dotnet-build / Carafe paths**, which is exactly where Mike's
binary came from.

## Proposed work
1. **Append the git commit short hash to the Osprey version on every build path**,
   Skyline-style: `26.1.1.181 (89ea8de8a1)`. Mirror Skyline's mechanism (SkylineCmd
   `--version` already prints `26.1.1.181 (221a3df43f)`); locate where Skyline injects
   the hash into its AssemblyInformationalVersion / version resource and reuse the
   same approach for Osprey. Surface it in `OspreyVersion` and in the `--version`
   output, the FDRBench/blib provenance, and the `.osprey.task` sidecar `version`
   field (so artifacts are traceable too).
2. **Make DOY = commit date and include the hash on ALL build paths**, not just
   `version.ps1`. Move the version computation into an MSBuild target (a
   `Directory.Build.targets` / pre-build step that runs `git show -s --format=%cI`
   + `git rev-parse --short HEAD`) so a bare `dotnet build`, a Debug build, and a
   Carafe/redistribution build all produce the identical, commit-derived stamp.
   Eliminate the DOY=0 fallback for in-checkout builds; keep a clearly-marked
   `+localmods`/`0` only for genuinely non-git or dirty-tree builds.
3. **Flag dirty working trees.** If the tree has uncommitted changes at build time,
   append a marker (e.g. `26.1.1.181 (89ea8de8a1-dirty)`) so a modified build can
   never masquerade as a clean commit.
4. **Test/gate**: a small check that `--version` contains a 7+ hex-char hash and a
   nonzero DOY for an in-checkout Release build; and that two builds of the same
   commit produce the identical string (reproducibility).

## Notes / gotchas
- `regression.ps1` deliberately ignores the version stamp when diffing goldens
  (`regression.ps1:127-132`, the DOY "changes every day" comment). Adding a hash must
  not break that -- keep the golden comparison version-insensitive (it already strips
  `osprey_version`).
- `package.ps1:273` maps `YEAR.ORDINAL.BRANCH.DOY -> YEAR.ORDINAL.DOY` for the MSI
  ProductVersion (4th field ignored); a hash is informational only and should live in
  AssemblyInformationalVersion, not the numeric AssemblyVersion, so it won't disturb
  MSI upgrade logic.

## References
- `pwiz_tools/Osprey/Osprey.Core/OspreyVersion.cs` (ResolveVersion)
- `pwiz_tools/Osprey/version.ps1` (commit-date DOY, no hash)
- `pwiz_tools/Osprey/build.ps1:153` (version block), `package.ps1:273`
- Skyline: `SkylineCmd --version` -> `26.1.1.181 (221a3df43f)` (mechanism to mirror)
- Incident write-up: `ai/.tmp/mike-repro-forensics.md`
