# TODO-20260820_osprey_scoring_linq_build_fix.md

## Branch Information
- **Branch**: `Skyline/work/20260820_osprey_scoring_linq_build_fix`
- **Base**: `master`
- **Created**: 2026-08-20
- **Status**: Completed
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: [#4594](https://github.com/ProteoWizard/pwiz/pull/4594)

## Objective

Restore the `using System.Linq;` that `Osprey.Scoring/PickLdaModel.cs` needs, so Osprey
compiles again.

## Context

`PickLdaModel.LoadFromFile` validates that a pick model's feature list matches the
expected order:

```csharp
if (dto.Features == null || dto.Features.Length != N ||
    !dto.Features.SequenceEqual(ExpectedFeatures))
```

`SequenceEqual` on `string[]` is the LINQ extension, and the file's using block does not
include `System.Linq`. The result is CS1061 on both target frameworks:

```
PickLdaModel.cs(152,31): error CS1061: 'string[]' does not contain a definition for
'SequenceEqual' [Osprey.Scoring.csproj::TargetFramework=net472]
PickLdaModel.cs(152,31): error CS1061: ... [Osprey.Scoring.csproj::TargetFramework=net8.0]
```

`Osprey.Scoring` fails, and with it everything downstream: `Osprey.Tasks`, `Osprey`,
and `Osprey.Test`. Nothing in the Osprey tree builds or tests.

The break arrived with `dd9e84581` ("Added Osprey pass-2 FDR modes ... and GBDT -- off by
default (#4446)"), which introduced the file.

## Implementation

One line, placed per the style guide's using order (System namespaces first):

- [x] `using System.Linq;` added to `pwiz_tools/Osprey/Osprey.Scoring/PickLdaModel.cs`

## Verification

Branched from a freshly pulled `origin/master` with no other change, so the build result
is attributable to this line alone.

- [x] `dotnet build Osprey.Test.csproj -c Debug`: succeeded, 0 warnings, 0 errors
- [x] `Osprey.Test` net8.0: 586/586 passed
- [x] `Osprey.Test` net472: 586/586 passed

## Notes

Found while transcribing `Osprey.ML.GradientBoostedTrees` for the MARS .NET port
([#4592](https://github.com/ProteoWizard/pwiz/issues/4592)); nothing in Osprey could be
built or tested until it was fixed. Split into its own branch and PR so the GBT change
carries no unrelated edits.

The GBT work is stacked on this branch and should be retargeted to `master` once this
merges. See `ai/todos/active/TODO-20260819_osprey_gbt_regression.md`.

Worth asking separately: TeamCity presumably builds Osprey, so either it does not, or
this has been red on master since `dd9e84581`. A green-master gate for the Osprey
solution would have caught it.
