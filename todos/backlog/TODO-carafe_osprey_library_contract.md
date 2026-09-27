# TODO-carafe_osprey_library_contract.md

## Branch Information (Future)
- **Branch**: Not yet created - will be `Skyline/work/YYYYMMDD_carafe_osprey_library_contract`
- **Module**: `osprey`
- **Depends on**: CarafeSharp landing in `pwiz_tools/CarafeSharp` (PR #4717, Mike); the pairing
  refusal in PR #4720 / maccoss/osprey#70
- **Objective**: One shared, executable definition of a correct Osprey library, which CarafeSharp
  guarantees when it WRITES a library and Osprey verifies when it LOADS one - so a library
  CarafeSharp produces loads in Osprey with zero warnings, zero repairs and zero refusals.

## Why (Brendan, 2026-09-26)

> "I am not satisfied with Carafe continuing to produce libraries that Osprey sees as imperfect.
> ... When we own 2 tools, they need to have perfect integration and a shared understanding of
> what is correct."

Today Osprey quietly REPAIRS what Carafe writes, and the repairs hid a real defect for two
months: the 07-27 SEA-AD library merged 35 decoys with identical real targets into one
`decoy_`-prefixed row, which gave two decoys one entry_id - silent until #4621's check turned it
into an abort 4 hours into an 82-file run (see
`ai/todos/active/TODO-20260925_osprey_libdecoy_pairing_collision.md`). Tolerance made sense while
Carafe was someone else's tool. With CarafeSharp in pwiz, a repair in the reader is a bug report
the writer never receives.

## What Osprey tolerates today (measured on the GOOD library)

Load of `sea-ad\lib\target+decoy+entrapment-20260817` (the library CHS, TDP-43 and SEA-AD use),
2026-09-25, from `runs\seaad-82files-libdecoy-r1.0-protein-compact-lib0817-pr4703\run-20260926_000218.log`:

| Imperfection | Evidence | Osprey's current handling |
|---|---|---|
| Per-peptide `_pepNNNNN` suffix on every protein accession | `[WARN]` 4,781,439 distinct accessions on 6,175,389 entries collapse to 82,460 real proteins | `CarafeProteinIdNormalizer` strips them |
| ProteinID disagrees with the manifest | manifest replaced protein_ids on 16,062 entries | manifest wins, silently |
| `Decoy` column is 0 on every row | SEA-AD README; decoys known only by `decoy_` prefix | prefix rule + manifest flip |
| Unpaired decoys / targets | 1,628 unpaired decoys, 2,247 unpaired targets (99.9% paired) | tolerated above `DecoyPairMinFraction` 0.80 |
| Pairing outside the manifest | composition fallback paired 1 decoy | composition pairing |
| Library duplicates at scoring | per-file `Deduplicated: N -> N` (07-27: ~26/file; 08-17: none) | per-file dedup keeps the best |
| Decoy merged with identical target | 07-27: 35 rows; 08-17: 0 | **refused** since #4720 |

The 07-27 library, for scale: 98.0% paired, 61,494 unpaired decoys, 84,066 unpaired targets.

## Plan

1. **Write the contract down** as a document both tools cite (in `pwiz_tools/Osprey/docs`, next
   to the library-format pages): what one row means, how target / decoy / entrapment is marked
   (the `Decoy` column vs the prefix), the accession format, one-to-one decoy pairing, the
   manifest's authority, uniqueness of (modified sequence, charge), and which of the above are
   errors vs tolerated inputs from third-party libraries.
2. **Make it executable, once.** A shared validator (a small library both CarafeSharp and Osprey
   reference) that returns EVERY violation, grouped by class - not the first (Skyline experience:
   first-only hides the class of defect behind most failures).
3. **CarafeSharp calls it before writing** and fails the build of a library that violates it.
   Carafe's generator fixes: stop merging identical target/decoy sequences into one row, write
   the `Decoy` column, write clean accessions (or the manifest's), pair every decoy.
4. **Osprey calls it at load.** For a CarafeSharp-produced library (identified by a provenance
   stamp CarafeSharp writes), every violation is an error. For third-party libraries, keep today's
   repairs but REPORT them as a summary, so tolerance is visible rather than silent.
5. **A round-trip test** in the Osprey or CarafeSharp suite: build a small library with
   CarafeSharp from a FASTA fixture, load it in Osprey, assert zero warnings and 100% pairing.
6. **Tighten the thresholds last**, once CarafeSharp output is clean: e.g. `DecoyPairMinFraction`
   near 0.99 for CarafeSharp libraries (0.80 today; only ~0.99 separates the 07-27 and 08-17
   builds).

## Open questions

- Where the shared validator lives (Osprey.Core, a new small project, or pwiz-sharp) so
  CarafeSharp can reference it without depending on the Osprey search stack.
- Whether the Rust Carafe (Python) path gets the same contract, or CarafeSharp becomes the only
  supported producer for Osprey.
- Provenance stamp format: a header comment in the TSV, a sidecar, or a blib metadata field.
