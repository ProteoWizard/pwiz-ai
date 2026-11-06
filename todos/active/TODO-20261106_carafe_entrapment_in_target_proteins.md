# TODO-20261106_carafe_entrapment_in_target_proteins.md

## Branch Information
- **Branch**: `Skyline/work/20261106_carafe_split_entrapment`
- **Base**: `master` (ab7c6b21a7)
- **Created**: 2026-11-06
- **Status**: In Progress (night session 2026-11-06; PR to open before morning)
- **Module**: `osprey`
- **PR**: (pending)
- **Checkout**: `C:\proj\pwiz`

## Idea (Brendan, 2026-11-05)
Make a low-ratio entrapment arm (e.g. 10%) something every Osprey run can carry, by building it in CarafeSharp,
which already generates entrapment libraries at a chosen percentage and from a foreign-species FASTA.

The new option: assign each entrapment peptide to a random target protein (its decoy follows its paired target),
instead of keeping it on its own entrapment protein. This is the design of the protein-shuffled entrapment audit
(`pwiz_tools/Osprey/docs/protein-shuffled-entrapment.md`, `ai/scripts/Osprey/Library/Build-ProteinShuffledEntrapment.py`),
which found that a protein-aware stage boosts targets on detected proteins while entrapment on its own proteins never
gets that boost, so the standard design cannot see protein-aware inflation (37 -> 291 entrapment hits on detected
target proteins at q 1% under pass-2 protein-compact).

## Refinement (Brendan, 2026-11-06, mid-session)
Two independent ratios, not a fraction of one set: the standard entrapment ratio (10% as normal, on its own
entrapment proteins) plus a second ratio of entrapment placed in target proteins (10%, "protein enhancement rate
estimation"), 20% in total - rather than today's only option of 100% matching entrapment with no visibility into
protein enhancement. Exposed in Skyline (Osprey Search and Build Library > Carafe) and as Osprey command-line
parameters; a /feature-demo of both.

## Design points
- Split the entrapment: about half scattered into target proteins (audits precursor q after any protein-aware boost),
  about half on entrapment-only proteins (keeps a protein-group FDP). One library audits both levels.
- Foreign-species peptides, each with its own predicted RT and spectrum, rather than shuffles: a shuffle is an
  anagram of its target, shares fragment masses and over-identifies (~1.6x FDP overestimate vs ~1.1x for natural
  entrapment; ai/docs/osprey-library-generation-guide.md).
- Entrapment runs through every stage, including protein inference, and is stripped only at output, so the audited
  run is the reported run.
- Cost: ~10% more candidates at 10%. Precision: at FDP 0.5% and ~57k IDs a 10% arm expects ~26 entrapment hits
  (about +/-20% on one run) - enough to flag miscalibration at q 1%, not to rank small changes.

## Implementation (this branch)
- **Marking.** Entrapment on a target protein carries the protein's clean accession, so the `_p_target` accession
  substring can no longer be the only mark. `LibraryEntry.IsEntrapment` is set from the manifest's `peptide_type`
  (`DecoyPairingManifest.ApplyToLibrary`) and from the blib `DecoyPairs.IsEntrapment` (`BlibDecoyPairs.MarkEntrapment`);
  `EntrapmentLibraryClassifier.IsEntrapment(LibraryEntry)` = flag or marker, `IsOnEntrapmentProtein` = marker only.
- **CarafeSharp**: `EntrapmentFastaSettings.EntrapmentInTargetsRatio` (own seed 20261101, so existing builds are
  byte-identical), `EntrapmentQuartet.PTargetSources`, `--entrapment-in-targets <ratio>` on both command lines,
  `LibraryBuildConfig.EntrapmentInTargetsRatio` in Osprey.
- **Diagnostics**: `EntrapmentPlacement` (base-ids on target proteins + each half's ratio) threads into the FDP views;
  `FdpView` gains the accepted and expected entrapment counts (expected = q (n_t + n_p) r / (1 + r), read with a
  Poisson interval) and the two halves' combined FDP at their own ratios; `Pass2Data.ProteinEntrapment` is the
  protein-group combined FDP from the entrapment-only groups; two new cards in the report.
- **Output**: `--strip-entrapment` leaves entrapment precursors and entrapment-only protein groups out of the blib
  and the reports after FDRBench and the diagnostics have read them. Default off tonight (goldens and the subset
  test keep today's "entrapment reported as targets"); proposal: default on for the `--fasta --entrapment` route.

## First test (2026-11-06 night)
Libraries derived from `target+decoy+entrapment-arabidopsis` (1:1 foreign-species, Carafe-built) under
`D:\test\osprey-runs\sea-ad\lib\`: `-r0.2` (nested subset) and `-r0.2-split` (half of that entrapment, 10% of
targets, placed on random target proteins; `Build-ProteinShuffledEntrapment.py --in-targets 0.5`), plus `-r0.1`,
`-r0.1-split` and `-split` (1:1). A10_014 runs, exe snapshot `D:\test\osprey-runs\_bin\split-entrap-20261106`:
`runs\seaad-1files-libdecoy-r0.2-protein-compact-arab-split-*`, `...-r0.2-...-arab-*`, `...-r1.0-...-arab-*`.
Compare precursor FDP by placement (pass 1 = negative control, pass 2 protein-compact = the audit) and the
protein-group FDP against the 1:1 run.

## Open items
- Pass-1 protein FDR has no entrapment view yet (pass 2 only).
- `--task ModelDiagnostics` on a completed run re-renders the stored pass-2 product; the protein card is kept from
  the join arm but not rebuilt on the diagnostics-only fold arm.
- Default of `--strip-entrapment` for the one-command route.
