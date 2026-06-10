# TODO-spectrum_ruler_host_extraction.md

## Branch Information
- **Branch**: TBD (off master after PR #4158 merges)
- **Base**: `master`
- **Repo**: `pwiz`
- **Status**: Backlog
- **Created**: 2026-06-05

## Origin

Deferred from Copilot review on PR #4158 (thread #10): the ruler context-menu
building logic (including `FindIndexAfterFirstSeparator` and the pinned/hovered
menu items) is duplicated across `GraphSpectrum`, `GraphFullScan`, and
`ViewLibraryDlg`. The duplication increases the chance of the three hosts
diverging over time — every recent ruler bug fix (mirror drop lines, pinned
rulers across annotation toggles) has needed to be applied to all three hosts
in lockstep.

## Objective

Extract the duplicated ruler state machine (pin / hover / menu) from the three
spectrum hosts into a single shared helper, so future ruler changes touch one
file instead of three.

## What is duplicated

Across `GraphSpectrum`, `GraphFullScan`, `ViewLibraryDlg`:

- Fields: `_pinnedSeriesKeys`, `_lastPrecursorId`, `_contextMenuOpen`
- `AddRulerMenuItems(ContextMenuStrip)` body
- `FindIndexAfterFirstSeparator` static helper
- `PinRuler` / `UnpinRuler` / `UnpinAllRulers` / `PinHoveredRuler`
- `SyncPinnedSeriesToGraphItem(s)` (the only divergence is the trailing `s`)
- `UpdateHoveredPeak(RankedMI)` (already shares
  `SpectrumGraphItem.GetBestSeriesKey`)
- Public test seams: `HoverRulerPeak`, `RulerGraphItem`,
  `PinHoveredRuler`, `UnpinRuler`, `UnpinAllRulers`

## Design — composition via `SpectrumRulerHost`

New class `SpectrumRulerHost` in `pwiz_tools/Skyline/Controls/Graphs/`. Each
host holds one as a field and forwards. Composition rather than a base class
because the three hosts derive from unrelated parents (`DockableFormEx`,
`FormEx`) and can't easily share a base.

```csharp
public class SpectrumRulerHost
{
    private readonly Func<SpectrumGraphItem> _getGraphItem;
    private readonly Action _invalidate;
    private readonly List<IonSeriesKey> _pinnedSeriesKeys = new();
    private object _lastPrecursorId;
    private bool _contextMenuOpen;

    public SpectrumRulerHost(Func<SpectrumGraphItem> getGraphItem, Action invalidate);

    public void UpdateHoveredPeak(LibraryRankedSpectrumInfo.RankedMI peak);
    public void OnPrecursorChanged(object precursorId);
    public void SyncPinnedSeriesToGraphItem();
    public void PinRuler(IonSeriesKey key);
    public void UnpinRuler(IonSeriesKey key);
    public void UnpinAllRulers();
    public void PinHoveredRuler();
    public void BuildMenuItems(ContextMenuStrip menu);
    public IReadOnlyList<IonSeriesKey> PinnedSeriesKeys => _pinnedSeriesKeys.AsReadOnly();
    public bool IsContextMenuOpen { get; set; }
}
```

## Per-host shape after extraction

Each host:

- Constructor: instantiate `_ruler` with `() => GraphItem` (or
  `() => _currentGraphItem`) and `() => graphControl.Invalidate()`.
- Replace `AddRulerMenuItems` body with `_ruler.BuildMenuItems(menuStrip)`.
- Replace per-host `PinRuler` / `UnpinRuler` / `UnpinAllRulers` etc. with calls
  to `_ruler`.
- `MakeGraphItem`'s precursor-change clear becomes
  `_ruler.OnPrecursorChanged(precursor.Id)`.
- Public test seams forward to `_ruler` so `SpectrumSequenceRulerTest` keeps
  working unchanged.

Mouse-event wiring (`DisplayTooltip`, `graphControl_MouseMove`,
`UpdateHoveredPeakAt`) stays per-host because each host hit-tests differently,
but all funnel into `_ruler.UpdateHoveredPeak(peakRmi)`.

## Mirror handling (GraphSpectrum only)

Keep `GraphItem.MirrorItem = MirrorGraphItem` cross-link inside `GraphSpectrum`
where it already is. The helper stays mirror-agnostic.

## Risks

- **Sync method name mismatch** (`SyncPinnedSeriesToGraphItems` plural vs
  `SyncPinnedSeriesToGraphItem` singular) — trivial; pick one and update call
  sites.
- **`graphControl` casing** varies across hosts (lowercase vs uppercase) —
  hidden behind the `Action _invalidate` callback.
- **`ViewLibSpectrumGraphItem` subclass** in ViewLibraryDlg — works through the
  `Func<SpectrumGraphItem>` accessor since the helper only uses base API.
- **`_contextMenuOpen`** — helper owns it; per-host `MouseLeave` handlers read
  `_ruler.IsContextMenuOpen`.

## Validation

- `TestSpectrumSequenceRuler` already exercises hover / pin / unpin / unpin-all
  on all three hosts via the public seams; if it still passes after the
  refactor, behavior is preserved.
- Pre-commit: build + test + QuickInspection clean.
- Manual: open all three hosts (Full Scan, Library Match, Library Explorer),
  pin / unpin rulers in each.

## Scope estimate

~400 LOC removed, ~250 added; net ~−150.

## Branch / PR strategy

- Start AFTER PR #4158 merges so the test seams and consolidated
  `GetBestSeriesKey` are on master.
- New branch off master: `Skyline/work/<YYYYMMDD>_SpectrumRulerHostExtraction`.
- New, focused PR; don't bundle with another feature.
