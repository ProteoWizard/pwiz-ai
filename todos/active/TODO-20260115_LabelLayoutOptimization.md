# Improving Label Layout Algorithm

## Branch Information
- **Branch**: `Skyline/work/20260115_LabelLayoutOptimization`
- **Base**: `master`
- **Created**: 2026-01-15
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: [#3847](https://github.com/ProteoWizard/pwiz/pull/3847)
- **Developer**: Rita Chupalov

## Objective
Replace the existing label positioning algorithm for scatter plots (Relative Abundance, Volcano Plot) with simulated annealing to eliminate clipping, overlaps, and suboptimal placements.

## Problem
Current label positioning frequently produces poor results:
- **Clipped labels** - Labels extend outside graph bounds and get cut off
- **Overlapping labels** - Multiple labels stack on each other in dense regions
- **Suboptimal placement** - Labels placed where a human would obviously choose a better position

Example: In the PeakImputationDia tutorial cover.png, the protein label "sp|Q8WUM4|PDC6I_HUMAN" is clipped at the bottom edge of the Relative Abundance plot.

## Approach: Simulated Annealing

### Algorithm (`LabelLayout.ComputePlacementsSimulatedAnnealing`)

**Cost function** penalizes:
| Penalty | Weight | Description |
|---------|--------|-------------|
| Label overlap | 5000 | Two labels overlap each other |
| Connector crossover | 5000 | Two connector lines intersect |
| Target overlap | 3000 | Label covers its own data point marker |
| Connector-label overlap | 1500 | One label's connector crosses another label |
| Clipping | 500 | Label extends outside chart area |
| Distance | 10000 (scaled) | Label far from its data point |
| Density | 0.2x grid | Label placed over dense marker region |

**Cooling schedule:** Linear from 7.0 to 0.1 over max(700, N*75) iterations.

**Moves:** Random x/y perturbation with step size proportional to temperature: `cellSize * (0.5 + temp)`. Metropolis acceptance with scale factor proportional to point count.

**Result:** Tracks best-cost configuration found during search, not final state.

### Density Grid
Spatial acceleration structure dividing the chart into cells (sized to minimum label height). Tracks cumulative marker density per cell for marker avoidance and path penalty computation.

### UI Integration (`LabelLayoutRunner`)
- Runs on `BackgroundWorker` thread with cooperative cancellation
- Throttled progress updates (200ms interval)
- Request ID system prevents stale results from race conditions
- Layout results persisted as JSON for restoration across graph refreshes
- Labels are draggable; manual repositioning is preserved (frozen in subsequent runs)

## Files Changed
- `pwiz_tools/Shared/zedgraph/ZedGraph/LabelLayout.cs` - New: simulated annealing algorithm, density grid, cost functions
- `pwiz_tools/Skyline/Controls/Graphs/LabelLayoutRunner.cs` - New: BackgroundWorker integration, cancellation, progress
- `pwiz_tools/Skyline/Controls/Graphs/SummaryRelativeAbundanceGraphPane.cs` - Integration with layout runner
- `pwiz_tools/Skyline/Controls/GroupComparison/FoldChangeVolcanoPlot.cs` - Integration with layout runner
- `pwiz_tools/Shared/zedgraph/ZedGraph/GraphPane.cs` - Supporting changes
- `pwiz_tools/Shared/zedgraph/ZedGraph/ZedGraphControl.*.cs` - Context menu and event changes

## Success Criteria
- No labels clipped by graph bounds
- No overlapping labels (or graceful degradation with many labels)
- Placement that a human reviewer would consider "reasonable"
- Performance acceptable for documents with thousands of points
- Non-blocking UI during computation

## Related
- Design review TODO (overall UI consistency)
- Relative Abundance performance TODO (large document handling)
