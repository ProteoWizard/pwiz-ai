# TODO-seems_picker_use_shared_dialog.md

## Branch Information
- **Module**: `pwiz` - SeeMS lives in `pwiz_tools/SeeMS`, and the shared dialog it would move
  to is `pwiz_tools/Shared/CommonFileDialogs`
- **Status**: Backlog
- **Origin**: PR [#4525](https://github.com/ProteoWizard/pwiz/pull/4525) discussion, 2026-08-17
- **Related**: `ai/todos/completed/TODO-20260803_bruker_fid_file_picker.md`

## Objective

Move SeeMS onto the shared `BaseFileDialogNE`, as MSConvertGUI did in #4099 - but port the
details it shows first, because that part of SeeMS is better than what the shared dialog has.

## Why

SeeMS keeps its own `Dialogs/OpenDataSourceDialog.cs`, which identifies everything it meets
by content rather than by name. Listing a Windows share of ~500 directories and ~1,400 files
takes it a couple of minutes, where the shared dialog takes about three seconds. Measured on
that share during #4525:

| | per file | for 1,432 files |
|---|---|---|
| `ReaderList.identify()`, which SeeMS calls per file (`:505`) | 160.65 ms | 230 s |
| The extension switch the shared dialog uses | 2.588 ms | 3.7 s |

They agree on what they find - 245 recognized against 238 - so the extra two hundred seconds
buys almost nothing. The cost is concentrated in the formats whose extensions are least
ambiguous, because `identify()` opens the file and the XML readers then parse content:

| Extension | avg per file | count on that share |
|---|---|---|
| `.mzML` | 1,114 ms | 38 |
| `.mzXML` | 784 ms | 76 |
| `.sky` | 446 ms | 197 |

That last row is ~88 seconds spent opening Skyline documents to conclude they are not mass
spec data.

Two further costs, neither measured:

- `:491` calls `identify()` on every **directory** with no name rules and no gate. On the same
  share that was ~5.3 ms per folder, against ~3.3 ms for the shared dialog's gated path.
- `:546` runs `dirInfo.GetFiles("*", SearchOption.AllDirectories)` per recognized source to
  fill the size column - a full recursive walk of every acquisition. A Waters `.raw` with 119
  functions is 602 entries.

## What SeeMS does better, and must survive the move

From Matt on the #4525 thread, 2026-08-17:

> Not really any issue I can think of other than losing the TIC preview which is no big loss.
> Oh actually I think it has a nicer details view than the Skyline-derived dialog. Shows
> number of spectra, chromatograms, instrument model and components, etc. Should probably port
> that into the Skyline dialog and then replace.

So: **port the details view first, then swap the dialog.** The TIC preview he is willing to
lose; the details view he is not.

## The trap to avoid while porting

Spectrum counts, chromatogram counts and instrument model cannot be had from a directory
listing - they require opening the source, which is exactly what makes SeeMS slow. If those
become columns in the list, every row pays for an open and the shared dialog inherits the
problem it was chosen to avoid.

Show them for the **selected** item instead - a details pane filled on selection, one source
at a time - so browsing stays a listing operation and the expensive read happens only where
the user has already pointed. Worth confirming with Matt that a selection-driven pane is an
acceptable reading of "nicer details view" before building it.

## Notes

- The shared dialog gained a "Scanning..." count during #4525, so a slow directory no longer
  reads as a hung one; that helps whatever the per-item cost turns out to be.
- `BaseFileDialogNE` has no `FolderType`/`FileType` delegate hooks - #4099 dropped them when
  it moved the dialog out of Skyline. Anything SeeMS needs to decide differently has to be a
  virtual on the dialog or a change in `DataSourceUtil`.
- SeeMS is also the last consumer of the pre-#4099 dialog lineage, so this retires
  `pwiz_tools/SeeMS/Dialogs/OpenDataSourceDialog.*` and its breadcrumb control with it.
