# TODO: Audit + annotate List&lt;T&gt;.Sort sites, extend CodeInspectionTest

**Status**: Backlog
**Priority**: Low-Medium (silent cross-impl-parity hazard until exercised; deferred only because the active sprint cleared the load-bearing site by hand)
**Complexity**: Medium (mostly mechanical 40+ one-line annotations, plus ~5 sites that need genuine conversion to LINQ `OrderBy`)
**Created**: 2026-05-22
**Scope**: `C:\proj\pwiz\pwiz_tools\OspreySharp` (OspreySharp C# port + its CodeInspectionTest)

## Motivation

`OspreySharp.Test.CodeInspectionTest.TestNoUnstableArraySort` currently
catches only `Array.Sort(` calls in production code and requires an
inline `// Array.Sort OK: <reason>` exemption. `List<T>.Sort` (also
introsort, also unstable, also tie-divergent vs Rust's stable
`slice::sort_by`) is NOT caught, even though the same parity hazard
applies. The pattern that prompted this TODO:

> "List&lt;T&gt;.Sort becomes the reflexive choice and gets sprinkled
> everywhere without thinking about whether the call site needs stable
> behavior. The right pattern would be: think about whether ties are
> possible AND consequential, then pick OrderBy (default-safe) or
> List&lt;T&gt;.Sort with annotation (deliberate exception)."

The 2026-05-22 Astral 3-file `group_qvalue` investigation was the
canonical incident. `ProteinFdr.ComputeProteinFdr` used
`winners.Sort(Comparison)` with `GroupId` as the tiebreak — a stack
of two flaws (unstable sort + HashMap-iteration-order tiebreak key)
that was invisible until upstream calibration drift was repaired
and ties started actually firing. Fix at osprey `0c867a9` /
pwiz `7ed9cf7485` carries a sorted-accessions string as the
secondary key (unique by parsimony construction → comparator never
returns 0 → unstable code path unreachable) and an inline
`// Array.Sort OK:` annotation explaining why.

That fixed the one load-bearing site. **This TODO sweeps the rest.**

## What needs to happen

### Phase 1 — audit (~1 hr)

For each unannotated `<identifier>.Sort(` in production code,
classify as:

- **(S) Safe by construction** — comparator can never return 0
  (unique key) or output ordering is uninspected. Inline-annotate
  with `// Array.Sort OK: <reason>`.
- **(U) Ties possible AND consequential** — convert to
  `list.OrderBy(...).ToList()` (or `OrderBy(...).ThenBy(...)` for
  multi-key sorts).
- **(D) Defer with caveat** — diagnostic-only, output not used
  cross-impl-parity-sensitively. Still annotate to make the
  thought process explicit.

### Phase 2 — extend inspection (~10 min)

Once all sites are annotated/converted, change
`CodeInspectionTest.TestNoUnstableArraySort`:

```csharp
// before
var pattern = new Regex(@"\bArray\.Sort\s*\(");
// after
var pattern = new Regex(@"\b\w+\.Sort\s*\(");
```

Update the docstring + assert message to mention both
`Array.Sort` and `List<T>.Sort`. Keep the same `// Array.Sort OK:`
exemption tag so a single grep finds every exemption (the tag is
a convention name, not a literal "Array" reference).

A draft of the extended test was prepared during the 2026-05-22
session — see the conversation transcript at the time-of-creation
for the regex + docstring rewrite.

## Inventory (as of 2026-05-22 audit)

`find C:/proj/pwiz/pwiz_tools/OspreySharp -name "*.cs" -not -path "*/obj/*"
-not -path "*/Test/*" | xargs grep -nE '\b\w+\.Sort\s*\('
| grep -v "// Array.Sort OK:" | grep -v "^\s*///"` returned 40+
sites across these files:

- `OspreySharp/OspreyDiagnostics.cs` — ~15 sites (mostly dump
  generation, likely **S** category)
- `OspreySharp/Tasks/AbstractScoringTask.cs` — at least 5 sites
  including the two highest-risk candidates:
  - `windowSpectra.Sort((a, b) => a.RetentionTime.CompareTo(b.RetentionTime))`
    (multiple spectra at the same RT is plausible — **U** candidate)
  - `windows.Sort((a, b) => a.Center.CompareTo(b.Center))` (m/z
    window centers could repeat — **U** candidate)
- `OspreySharp/Tasks/PerFileScoringTask.cs` — 1+ sites
- `OspreySharp/Tasks/FirstJoinTask.cs` — 4+ sites
- `OspreySharp/Tasks/MergeNodeTask.cs` — 2+ sites
- `OspreySharp.Core/LibraryDecoyPairing.cs` — 3 sites
- `OspreySharp.Core/OspreyConfig.cs` — 2 sites (filename sorts, **S**)
- `OspreySharp.FDR/FdrController.cs` — 1 site
- `OspreySharp.FDR/PercolatorFdr.cs` — 5+ sites
- `OspreySharp/RescoreHydration.cs` — 1 site

Full inventory in conversation transcript or re-run the grep above.

## Why this is backlog, not immediate

- The Astral 3-file end-to-end gate that motivated the investigation
  is closed by the targeted fix at `ProteinFdr.ComputeProteinFdr`.
  No other site has been observed to fail cross-impl parity.
- The sweep is mechanical but voluminous and would balloon the
  active sprint's PR scope past what's reasonable to review.
- The right venue is its own cleanup PR with a clear "no behavior
  change, just future-proofing" commit message.

## Related

- `ai/docs/osprey-development-guide.md` § "Stable vs unstable sort"
  — the doctrine this TODO operationalizes
- osprey commit `0c867a9`, pwiz commit `7ed9cf7485` — the
  load-bearing fix that made the broader gap visible
- `ai/.tmp/astral-group-qvalue-rca.md` — bisection writeup
  including the protein-FDR tiebreak as layer 9 of the cascade
