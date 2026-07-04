# TODO-osprey_parsimony_linear.md -- Near-linear protein parsimony (rarest-peptide candidate scan)

> Osprey's protein parsimony subset-elimination is O(groups^2 x peptides) -- a naive
> pairwise scan. Port the rarest-peptide candidate scan (a proper superset must contain
> the group's rarest peptide) for near-linear time with IDENTICAL grouping. CPU perf only,
> independent of the #4355 memory work.

## Status

- **Backlog** (planned, not started -- no branch cut yet).
- **GitHub Issue**: [#4357](https://github.com/ProteoWizard/pwiz/issues/4357)
- **Branch**: (create `Skyline/work/YYYYMMDD_osprey_parsimony_linear` when starting; move this
  file to `ai/todos/active/` with the date prefix per WORKFLOW.md).
- **Base**: `master`

## The problem

- `Osprey.FDR/ProteinFdr.cs` `BuildProteinParsimony` Step 3 (`:285-298`): for each group, scan
  every retained group and `IsSubsetOf` -- O(groups^2 x peptides). Code already comments it
  "the O(N^2) hot path on Stage 7"; only the constant was optimized (HashSet vs SortedSet).
- Rust has the same shape (`crates/osprey-fdr/src/protein.rs:135`, `.any(is_subset)`) -- shared
  gap, not a port omission. Runs in both first-pass (`FirstJoinTask.RunFirstPassProteinFdr`) and
  Stage 7 (`MergeNodeTask`).
- ~0.5s at Stellar (~5K groups); tens of s to minutes on a deep 82-file SEA-AD run (potentially
  tens of thousands of groups). (190k-peptide dataset elsewhere: ~2h unfinished under the naive scan.)

## The fix (identical grouping, near-linear)

A proper superset of group A must contain ALL of A's peptides -> in particular A's **rarest**
peptide (fewest groups). Index `peptide -> groups`; for each A, test only groups sharing A's
rarest peptide as superset candidates. Osprey already builds `peptideToGroups` (Step 4,
`ProteinFdr.cs:302`) -- build it before Step 3 and reuse it.

## Reference implementation (proven, identical-output)

`maccoss/skyline-prism` @ `csharp-port`:
`src/SkylinePrism.Core/Parsimony/ParsimonyEngine.cs` (~`:172-203`) -- builds `pepToProt`, picks
`pivot` = the peptide of `a` with the fewest proteins, scans only `pepToProt[pivot]` for the
lexicographically-smallest proper superset. https://github.com/maccoss/skyline-prism/tree/csharp-port
Local: `D:\GitHub-Repo\maccoss\skyline-prism\dotnet`.

## Plan when picked up

1. Port the rarest-peptide candidate scan into `ProteinFdr.BuildProteinParsimony` Step 3 (C# first).
2. Mirror in Rust `protein.rs` for cross-impl parity (or note the divergence if C# is now the oracle).
3. Assert IDENTICAL protein groups vs current (Stellar + a large set); regression golden's
   protein-group output stays byte-identical. Measure group count + parsimony `[TIMING]` at
   SEA-AD scale before/after. `Osprey.Test` green.
