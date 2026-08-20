# TODO-20260820_osprey_scoring_linq_build_fix.md

## Branch Information
- **Branch**: `Skyline/work/20260820_osprey_scoring_linq_build_fix`
- **Base**: `master`
- **Created**: 2026-08-20
- **Status**: Completed
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: [#4594](https://github.com/ProteoWizard/pwiz/pull/4594)

> The branch name records the symptom this started from, not the fix. The original
> premise -- that `PickLdaModel.cs` was missing a `using System.Linq;` and master was
> broken -- was wrong. Master is fine. See Diagnosis.

## Objective

Pin `<LangVersion>` for the Osprey tree so the C# 14 requirement it already has is
declared, instead of being inherited from whichever SDK is installed.

## Diagnosis

`PickLdaModel.LoadFromFile` validates that a pick model's feature list matches the
expected order:

```csharp
if (dto.Features == null || dto.Features.Length != N ||
    !dto.Features.SequenceEqual(ExpectedFeatures))
```

Both operands are `string[]`, and the file imports `System` but not `System.Linq`.

* Under **C# 14**, `string[]` implicitly converts to `ReadOnlySpan<string>` in extension
  receiver position ("first-class span types"), so the call binds to
  `System.MemoryExtensions.SequenceEqual`, which `using System;` already covers.
  `using System.Linq;` is redundant, and ReSharper says so.
* Under **C# 13 and earlier** that conversion does not exist, so the only candidate is
  `System.Linq.Enumerable.SequenceEqual`, which is not imported. The build fails.

So Osprey has required C# 14 -- and therefore the .NET 10 SDK -- since `dd9e84581`
introduced the file. `<LangVersion>latest</LangVersion>` concealed it: the property means
"whatever this SDK supports", so the same source builds on VS 2026 and fails on a .NET 9
SDK. TeamCity and the Skyline developers are all on the newer SDK, which is why master has
been green throughout.

Reproduced both directions on a clean `origin/master` worktree:

| SDK | LangVersion resolves to | Result |
|---|---|---|
| 10.0.400 | C# 14 | builds clean, net472 and net8.0 |
| 9.0.315 | C# 13 | `CS1061: 'string[]' does not contain a definition for 'SequenceEqual'` |

The failure message is the problem. It points at a line of source that looks fine and
says nothing about language versions, so the obvious reading is "master is broken" rather
than "this SDK is too old".

## Implementation

- [x] `pwiz_tools/Osprey/Directory.Build.props`: `<LangVersion>latest</LangVersion>` ->
      `<LangVersion>14</LangVersion>`, with a comment recording what requires it
- [x] Reverted the `using System.Linq;` that the first version of this branch added.
      It is redundant under C# 14 and would be flagged by inspection

Adding the using was the other way to make an SDK 9 build work, but it would have to
survive ReSharper on a C# 14 toolchain, and it would leave the real requirement
undeclared.

## Verification

- [x] .NET 10.0.400 SDK: `Osprey.sln` builds clean, 0 warnings, 0 errors
- [x] .NET 10.0.400 SDK: `Osprey.Test` 586/586 on net8.0 and 586/586 on net472
- [x] .NET 9.0.315 SDK: build now stops at
      `CS1617: Invalid option '14' for /langversion`, naming the actual cause

## Notes

Consistent with the rest of the tree: `pwiz_tools/Directory.Build.props` pins `8.0`, and
`CommonFileDialogs`, `CommonMsData`, `PanoramaClient` and `BullseyeSharp` pin `8.0` or
`7.3`. Osprey was the outlier in tracking the SDK.

Worth considering separately, not done here:

* A repo-root `global.json` would state the SDK requirement once, rather than leaving each
  project to imply it through `LangVersion`. That is a repo-wide decision.
* The same audit applies to the other `<LangVersion>latest</LangVersion>` users
  (`PortableUtil`, the `DevTools` projects). They may have picked up C# 13/14 dependencies
  without anyone choosing to.

The GBT regression work is stacked on this branch and was rebased onto the new commit;
it should be retargeted to `master` once this merges. See
`ai/todos/active/TODO-20260819_osprey_gbt_regression.md`.
