# TODO-20261007_pepxml_bare_ampersand.md

## Branch Information
- **Branch**: `Skyline/work/20261007_pepxml_bare_ampersand`
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-10-07
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Fix DDA/DIA search library builds failing when the data path contains `&`.

## Background

TestDiaTtofDiaUmpireTutorial failed locally (SkylineTester, DotNetPort checkout) but not
on TeamCity. The local persistent test-data root is `c:\Skyline T&est ^Data`. Comet writes
file paths into pepXML attributes (line 2, `msms_pipeline_analysis summary_xml=...`)
without escaping `&`. `CometSearchEngine.FixPercolatorPepXml` copies lines through as
text, so BiblioSpec's PepXMLreader failed: `' ' is an unexpected token. The expected
token is ';'` (it reads `&est` as an entity reference). TeamCity's data path has no `&`.

MSFragger's `FixPercolatorPepXml` already escaped bare ampersands; Comet and Tide did not.

## Changes

- [x] Extended `Test/CometPercolatorPepXmlTest.cs` with a raw-`&` header and an
      already-escaped `&amp;` header; asserts the output parses and round-trips both paths
      (red: same XmlException as the tutorial)
- [x] Added `AbstractDdaSearchEngine.EscapeBareAmpersands` (MSFragger's regex, moved)
- [x] Called it per line in the Comet, Tide and MSFragger `FixPercolatorPepXml` copies
- [x] TestCometPercolatorQValueAnnotation green; CodeInspection green
- [ ] `/code-review max` before PR
- [ ] Open PR against the port branch
- [ ] Confirm TestDiaTtofDiaUmpireTutorial passes with the `T&est` data path
