# TODO-20261013_image_extractor_sizes.md

## Branch Information
- **Branch**: `Skyline/work/20261013_image_extractor_sizes`
- **Base**: `master`
- **Created**: 2026-10-13
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#4839](https://github.com/ProteoWizard/pwiz/pull/4839)

## Objective

The DevTools ImageExtractor (`pwiz_tools/Skyline/Executables/DevTools/ImageExtractor`)
could only pull the 16x16 PNG icons out of the Visual Studio ImageCatalog. The DPI
awareness work (issue #4599) needs larger icon assets for 125%, 150% and 200% image
lists, so the tool must produce other sizes too.

## Finding

The catalog DLL (`Microsoft.VisualStudio.ImageCatalog.resources.dll`) stores PNG
bitmaps only at 16x16 (4,047 of them, plus a handful of odd sizes). There are no
larger bitmaps to extract. Every icon also has a compiled XAML vector image
(`xaml/<name>.baml`, 4,067 of them), which is what Visual Studio scales at high DPI.

## Design

- Sizes come from the command line: `dotnet run -c Release -- 16 32 48`. No args
  means 16, matching the old behavior.
- 16 copies the native, hand-tuned PNGs as before.
- Any other size loads the BAML with `Baml2006Reader` + `XamlReader`, wraps the root in
  a `Viewbox` of that size and renders it with `RenderTargetBitmap` to an 8-bit RGBA PNG.
  The project enables WPF alongside Windows Forms for this.
- Output is one folder per size, `ai\.tmp\icons\<N>x<N>\<name>.<N>.<N>.png`, so the
  same icon has the same base name in every folder.
- Icons use real alpha transparency, not the magenta color key used by Skyline's legacy
  .bmp resources. Keying is 1-bit and would fringe the anti-aliased edges; the DPI
  branch's image lists already switch to 32-bit with a Transparent key above 100%.

## Completed

- [x] Program.cs: size arguments, vector rendering, single byte[]/Stream helper, file header
- [x] ImageExtractor.csproj: `UseWPF`
- [x] README.md: sizes, per-size output folders, removed the obsolete dotPeek RESX steps
- [x] Built Release with zero warnings; ran `16 32 48` with no errors or skipped icons
      (log: `ai/.tmp/sessions/20261006-d785f537/extract-16-32-48.log`)

## Remaining

- [x] Push branch, open PR with `skyline:` prefix and label (#4839, 2026-10-13)
- [ ] Address Copilot review if any

## Notes

- The tool is a standalone solution, not part of Skyline.sln; QuickInspection and the
  Skyline test suite do not cover it.
- Developed on the pwiz1 checkout (DPI branch) and moved to its own branch so the
  DPI PR stays focused.
