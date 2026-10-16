# TODO-high_dpi_tutorial_screenshots.md

## Branch Information (Future)
- **Branch**: Not yet created - will be `Skyline/work/YYYYMMDD_high_dpi_screenshots`, branched from
  `Skyline/work/20260820_dpiAwareness` (PR #4602) and stacked on it
- **Module**: `skyline`
- **Depends on**: PR #4602 (system-DPI awareness), at least its commit 8346379152, which added the
  `dpiaware=on` test runner option, DWM-frame screenshot capture and DPI-scaled `CleanupBorder`
- **Objective**: auto-screenshot runs at 150% (and other scales) reproduce their own screenshots as
  closely as 100% runs do today, as a way to see most of Skyline's UI at high DPI and to keep it
  correct there.

## Why (Brendan, 2026-10-16)

The first 150% auto-screenshot run of AbsoluteQuant on PR #4602 showed that the tutorial tests set
window sizes in 96-DPI pixels (`Size = new Size(...)`, `Width =`, `Height =`) with no scaling, so the
windows come out too small for their DPI-scaled contents. Taking every tutorial at high DPI
exercises far more of the UI than the PR's form sweep did, and a reproducibility run turns it into
a check that can be repeated.

## Scale of the work (counted 2026-10-16 in TestTutorial, TestPerf, TestFunctional)

| pattern | uses | files |
|---|---|---|
| `.Size = new Size(...)` | 88 | 32 |
| `.Width =` / `.Height =` with a literal | 64 | 19 (some are controls, not windows) |
| `FloatAt(...)` / rectangles with literal sizes | 5 | 3 |
| `SplitterDistance =` with a literal | 1 | 1 |

Plus the helpers in TestUtil, e.g. `SetSkylineWindowSize` and its 14/7 frame margins.

## Scaling approach: per-axis font factor, not the DPI ratio

WinForms `AutoScaleMode.Font` scales each axis by measured font metrics, the way Windows scales
dialog units. Measured for Microsoft Sans Serif 8.25pt (Skyline's pinned default font):

| | 96 DPI | 144 DPI | ratio |
|---|---|---|---|
| average character width | 6.212 | 9.731 | 1.566 |
| height | 13 | 20 | 1.538 |

Transition Settings came out 166% x 153% at 150% and 217% x 199% at 200%. Scaling a test's window
by a uniform 1.5 would not fit contents that grew 1.566 horizontally, so:

- One helper in `AbstractFunctionalTest`, e.g. `SetFormSize(form, width96, height96)`, plus bounds,
  location, floating-pane and splitter variants, converting 96-DPI design values by the form's
  per-axis font factor (current font metrics / the same font's 96-DPI metrics, which is what
  `CurrentAutoScaleDimensions` / `AutoScaleDimensions` express).
- Exactly 1 at 96 DPI, so the 100% screenshots are untouched; migrating the ~150 call sites is then
  gated by a 100% screenshot run matching exactly.
- Window-frame margins (`SetSkylineWindowSize`'s 14/7) are frame pixels, not content: scale them by
  the border rules below, not by the font factor.

## Measured window-frame rules (Windows 11, from PR #4602)

- Border thickness is `ceil(factor)`: 2px at 150% and 200%, 3px at 300%.
- Border color on a white background: top edge `#B7B7B7` at 150%, 200% and 300% (sides `#A9`-`#B4`,
  bottom `#99`-`#9C`, darkened by the drop shadow). 1px `#707070` at 100%.
- Corner radius scales with the factor (8 x factor for forms, 4 x factor for tool windows).
- `CleanupBorder` implements these. Docked forms' interior borders (`#A0A0A0`) are assumed to stay
  1px - not yet measured at high DPI. Floating tool windows at high DPI not yet seen.

## Work items

- [ ] Explain the extra width first: Transition Settings is 166% wide at 150%, but font scaling
      predicts ~157% (~38px over). Find the control or minimum size responsible, so the helper's
      factor matches what forms actually do.
- [ ] Add the sizing helpers and migrate the call sites; gate on a 100% run matching exactly.
- [ ] Scale TestUtil's frame margins (`SetSkylineWindowSize`) by the border rules.
- [ ] Run-Tests.ps1 `-DpiAware` switch (passes `dpiaware=on`), and a SkylineTester control for it -
      UI not yet designed.
- [ ] Preview Screenshot form: option to show the old image scaled by the display factor, so 96-DPI
      and high-DPI images can be compared side by side.
- [ ] Measure docked interior borders and floating tool windows at high DPI.

## Reproducibility plan (the Windows 10 -> 11 approach)

1. Throwaway branch off this work.
2. Take all tutorial screenshots at 150% on a high-DPI monitor; commit them to the throwaway branch.
3. Take them all again and diff against that commit (ImageComparer MCP `list_changed_screenshots`).
   The diff count measures reproducibility; compare with the 100% runs.
4. As in the Windows 11 transition, change the desktop background color (e.g. red) for the runs, so
   any remaining transparency bleed-through in borders or corners shows up.
5. Fix what does not reproduce; repeat. The throwaway branch is never merged.

## Fixed along the way (in PR #4602, commit 8346379152)

- SkylineTester started TestRunner with `WindowStyle = ProcessWindowStyle.Hidden`; Windows applies
  that to the first window a GUI child shows normally, so the Skyline main window was hidden in
  Screenshot, Auto-Screenshot and Cover shot modes (Test and Demo show it without activation, which
  is not overridden). Removed; `CreateNoWindow` still hides the console.
- ImageComparer failed to build under #4810's warnings-as-errors (obsolete `Form.OnClosed`).
  `Executables/Tools/ExampleInteractiveTool/MainForm.cs` has the same override and will fail the
  same way when built.

See also: `ai/todos/active/TODO-20260820_dpiAwareness.md` (the PR #4602 TODO).
