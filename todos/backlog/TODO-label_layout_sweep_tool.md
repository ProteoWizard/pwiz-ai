# Land the label layout sweep tool

## Objective

The dot plot label layout sweep is written, inspection-clean and proven useful, but it is parked on a branch
rather than merged. Land it as its own small PR, or decide deliberately to drop it.

## Where it is

Branch `Skyline/work/20260929_labelLayoutSweep` (pushed), branched off the #4495 work before the tool was
reverted out of that PR. Since #4495 squash-merged as `93b88ee0c8` on 2026-10-05, the branch needs
`git merge origin/master` before its diff makes sense - after that it should show only:

* `pwiz_tools/Skyline/TestPerf/LabelLayoutSweep.cs` (new) and its `TestPerf.csproj` entry
* `LabelLayout.SamplerReport`, a `#if DEBUG` hook in `pwiz_tools/Shared/zedgraph/ZedGraph/LabelLayout.cs`
* its one call site in `LabelLayoutRunner.cs`, also `#if DEBUG`

## Why it was taken out of #4495

Not because it was wrong - to keep that PR to the fix alone. The tool carries a Debug-only hook in shared
ZedGraph code, which deserves review on its own merits rather than as a rider on a bug fix, and the three
code inspection warnings that turned #4495's CI red all came from it (since fixed in `a254c29857`).

## Why landing it is worth something

It found three defects in itself that each produced plausible but wrong numbers - compounding zoom, linear
zoom math on a log axis, and measuring a stale layout - all only visible by running it. A branch nothing
compiles will rot the same way, and the next person tuning the sampler will either trust stale numbers or
rewrite the tool. That is the argument for merging it rather than leaving it parked.

Its measurements are what established the post-fix behaviour recorded in
`todos/completed/TODO-20260521_labelSamplingFix.md`: sampler 40/125 at 1000x700 rising to 125/125 at
1920x1200, 19 to 91 labels visible, coverage steady near 16-18%.

## Notes for the PR

* Needs a DEBUG build; in Release the class is replaced by a stub that says so. That is deliberate and
  structural - inner `#if DEBUG` guards left a never-written field and an empty finally that the Release
  inspection flagged.
* Runs offscreen; it sizes the floating frame directly because `ResizeFormOnScreen` returns before resizing
  when `Program.SkylineOffscreen` is set.
* Off unless `SKYLINE_LABEL_SWEEP` is set, `[NoNightlyTesting]` + `[NoParallelTesting]`.
* Conventions it follows are written up in `ai/TESTING.md` under "Diagnostic Sweeps - Tools, Not Tests".
