# TODO: CarafeSharp option to place entrapment peptides in target proteins

## Idea (Brendan, 2026-11-05)
Make a low-ratio entrapment arm (e.g. 10%) something every Osprey run can carry, by building it in CarafeSharp,
which already generates entrapment libraries at a chosen percentage and from a foreign-species FASTA.

The new option: assign each entrapment peptide to a random target protein (its decoy follows its paired target),
instead of keeping it on its own entrapment protein. This is the design of the protein-shuffled entrapment audit
(`pwiz_tools/Osprey/docs/protein-shuffled-entrapment.md`, `ai/scripts/Osprey/Library/Build-ProteinShuffledEntrapment.py`),
which found that a protein-aware stage boosts targets on detected proteins while entrapment on its own proteins never
gets that boost, so the standard design cannot see protein-aware inflation (37 -> 291 entrapment hits on detected
target proteins at q 1% under pass-2 protein-compact).

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

## Osprey side: a reading in the --model-diagnostics HTML
- When the library carries entrapment (recognized by its marking), report the entrapment FDP estimate beside the
  reported q values: precursor level at q 1% (and the q-vs-FDP curve), split by the two halves - entrapment in
  target proteins vs on its own proteins - so a protein-aware inflation shows as the halves diverging.
- Protein-group FDP from the entrapment-only half.
- Show the expected-hit count and an interval, so a 10% arm's noise is read as noise.
- Strip entrapment rows from the reported outputs (blib, reports) only after the diagnostics read them.

## First test
Build a SEA-AD library with 10% split entrapment; run Osprey on A10_014; compare its precursor and protein FDP
estimates with the 1:1 library's on the same run.
