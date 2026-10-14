# Osprey: consolidate Carafe library generation out of ai/.tmp

## Branch Information
- **Branch**: none - `ai/` documentation work, committed directly to `pwiz-ai` master
- **Module**: `osprey` (tooling + docs)
- **Created**: 2026-08-01
- **Status**: Complete
- **Requester**: Brendan - NO credit line.

## Why this exists

Brendan asked to recover "the Arabidopsis entrapment library and the process we used
to generate it" so it could be shared with a second machine running its own Claude Code
session. The search found that **the entire effort lived in gitignored `ai/.tmp/`** -
four notes files, a generator, and an orchestrator, none of them committed, none of them
reachable from another machine. Committed code already referenced them
(`SEA-AD/tools/subset-entrapment-ratio.py` says "mirrors make_natural_entrapment.py";
`TODO-osprey_foreign_decoys_honest_ms1_power.md` cited four `ai/.tmp` paths), so those
references were already dead for anyone else.

## What was found (the search result)

- **No Arabidopsis library exists on disk, anywhere**, and **no Astral Arabidopsis
  library was ever built**. The natural-entrapment work was Stellar-only.
- The generator rewrites `osprey_library_db_{pairing.tsv,peptides.fasta}` **in place**,
  backing the originals up once as `*.shuffle.bak`. Those two `.bak` files are the only
  ones on `D:`, which is what pins the work to `D:\test\carafe-repro\stellar`.
- Those workdir files were **overwritten on 2026-07-06** by a shuffle rebuild and are now
  entrapment-free (target+decoy rows only); `osprey_new_library/carafe_spectral_library.tsv`
  was overwritten in the same run.
- What survives: the FDRBench inputs and FDP results per arm
  (`D:\test\carafe-repro\stellar\osprey_project\FDRBench\FDRBench-Input.arab_*.tsv`,
  `fdp_arab_*.csv`), and the source FASTA
  (`D:\test\entrapment\arabidopsis\UP000006548.fasta`).
- The Arabidopsis arms were genuine searches, not relabeling: `_p_target` rows in
  `FDRBench-Input.arab_strict.tsv` carry real foreign sequences
  (`AAEGGAAVEEYDYLPFFYSR`), against true anagrams in the shuffle file.
- The Astral and SEA-AD entrapment manifests are all shuffle (`_p_target` anagrams of
  the human target). Verified by reading them.

## What was done

**New committed tooling** - `ai/scripts/Osprey/Carafe/`:
- `Run-CarafeOspreyWorkflow.ps1` - generalized from the `ai/.tmp` orchestrator: dataset
  presets (Stellar/Astral), stage subsetting, environment-variable tool resolution, and
  a new **stage 1c** for the natural-entrapment rewrite.
- `tools/make_natural_entrapment.py` - copied **byte-identical** on purpose, so the
  committed script is exactly the one that produced the recorded 2026-07-04 numbers.
- `tools/occupancy_test.py`, `README.md`.

**New guide** - `ai/docs/osprey-library-generation-guide.md`: merges the two `ai/.tmp`
notes into one portable document - prerequisites, the 6-stage pipeline, the parameter
table, our reproduction's validation numbers, the natural-entrapment design + results +
ratio sweep, an on-disk artifact inventory, and the open questions.

**Pointers updated** so the work is discoverable: `ai/scripts/Osprey/README.md` (layout +
a "Library generation" section), the `osprey-development` skill, and the four stale
`ai/.tmp` references in `TODO-osprey_foreign_decoys_honest_ms1_power.md`.

## Findings worth keeping

1. **`-Preflight` caught a real portability bug on the machine that wrote the recipe.**
   Auto-resolution took `JAVA_HOME` (JDK 17) over the JBR 21 the original run actually
   used. Carafe's pom targets release 21, so that would have failed deep inside stage 1
   with an `UnsupportedClassVersionError`. Java resolution now **probes each candidate's
   version and takes the first that is 21+**, and rejects an explicit too-old JDK up
   front with a clear message. This is exactly the class of breakage a second machine
   would have hit first.
2. **Stage 1 is byte-reproducible; stages 2+ are not.** The digest is seeded (42/24) and
   reproduced Mike's files by SHA256. Everything downstream depends on the peptdeep
   pretrained model and the GPU, so two machines get functionally equivalent, not
   identical, libraries (we measured 494,264 vs 494,991 precursors, ~13% fewer fragment
   rows). Anyone needing identical libraries must share the built file, not the recipe.
3. **Stage 1c had to be made idempotent.** The generator backs up only if no backup
   exists, so a second run would draw foreign peptides to match *foreign* peptides. The
   driver now restores from `*.shuffle.bak` before rewriting.
4. **The Astral preset is an assumption, and is labeled as one.** Mike's `carafe_log.txt`
   is Stellar-only - it contains no Astral run - so Astral's Carafe `-itol` is
   instrument-appropriate (20 ppm), not transcribed. The driver warns loudly, and the
   guide and backlog TODO both say a rebuilt Astral library is a new library, not a
   reproduction. Osprey's own default fragment tolerance (10 ppm, `CoreTypesTest.cs:394`)
   is used for the search side, which IS a real value.

## Verification

- `Run-CarafeOspreyWorkflow.ps1` parses clean (PowerShell AST parser, 0 errors).
- Both Python tools pass `py_compile`.
- `-Preflight` resolves Java (JBR 21.0.9), carafe.jar 2.2.0, the peptdeep venv, Osprey.exe,
  and python on this machine.
- Negative test: forcing `$env:OSPREY_CARAFE_JAVA` to the JDK 17 is rejected with
  "is Java 17; Carafe needs 21 or newer."

No library was built - that is a GPU job measured in hours and was not requested here.

## Still open

- **No Astral Arabidopsis library** (the main scientific gap): does the shuffle-vs-natural
  FDP gap hold at high mass accuracy? Tracked in
  `ai/todos/backlog/brendanx67/TODO-osprey_foreign_decoys_honest_ms1_power.md`.
- **Get an Astral Carafe log from Mike** to replace the assumed `-itol`, or accept that
  an Astral rebuild is a new library.
- **Upstream stage 1c into Carafe** as an `-entrapment_source` mode so shuffle stays the
  default and the two are switchable, rather than a post-Carafe rewrite of its outputs.
- `ai/.tmp` still holds ~1000 files including several referenced-but-uncommitted scripts
  (`extract_mdiag.py` and friends). This TODO fixed the library-generation subset only.
