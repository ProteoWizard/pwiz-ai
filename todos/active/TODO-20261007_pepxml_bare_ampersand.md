# TODO-20261007_pepxml_bare_ampersand.md

## Branch Information
- **Branch**: `Skyline/work/20261007_pepxml_bare_ampersand`
- **Base**: `Skyline/work/20260612_net8_port`
- **Created**: 2026-10-07
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: [#4790](https://github.com/ProteoWizard/pwiz/pull/4790)

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
Master passes because there TestDiaTtofDiaUmpireTutorial searches with MSAmanda (mzIdentML
written by a real XML writer); the port switched it to Comet. Expat rejects a bare `&` too,
so the C# BlibBuild port is not the cause.

## Changes

- [x] First commit: per-line escape in all three rewrites (via a new base-class helper)
- [x] `/code-review max`: escape ran BEFORE the PSM key was parsed from `spectrum=`, so an
      `&` in a spectrum's folder/file name mis-keyed every PSM to q=1 (silent data loss).
      MSFragger had this ordering bug since 2024.
- [x] Escape only what is written; keys from the raw line
- [x] Consolidated escapers onto `PathEx.EscapePathForXML` with a stricter pattern
      (complete char refs only, `[0-9]` not `\d`); deleted unused `XmlUtil.EscapePath`
- [x] Replaced the three hand-synced `FixPercolatorPepXml` copies with one
      `PercolatorPepXmlAnnotator` (Model/DdaSearch), configured per engine (spectrum-ID
      parser, rank separator, q-value anchor/placement)
- [x] `Test/PercolatorPepXmlTest.cs` (renamed from CometPercolatorPepXmlTest): one check
      run for all three engines, incl. `&` in spectrum ID; verified it fails with the
      ordering bug reintroduced. `UtilTest.TestEscapePathForXML` extended.
- [x] Unit tests + CodeInspection green
- [x] TestDdaSearchComet/CometAutoTolerance/Tide/MsFragger green before the refactor
- [x] Same functional tests green after the refactor
- [x] Open PR against the port branch (#4790)
- [x] TestDiaTtofDiaUmpireTutorial passes with the `T&est` data path (1292 s, Quickee Debug)
- [x] Copilot review: numeric refs now kept only for legal XML Chars; PercolatorPepXmlTest
      consolidated into one TestMethod (e5d792eb3f); both threads replied (marked as
      Claude Code replies) and resolved
- [x] Deferred PSM key-matching bugs (dotted Tide stems, Comet drive-root folder) -> #4791
- [ ] TeamCity green, human review
