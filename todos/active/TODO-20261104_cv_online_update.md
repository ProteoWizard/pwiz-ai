# TODO-20261104_cv_online_update.md

## Branch Information
- **Branch**: `Skyline/work/20261104_cv_online_update`
- **Checkout**: `C:\dev\pwiz-cvupdate`
- **Base**: `master`
- **Created**: 2026-11-04
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `pwiz`
- **PR**: (none yet)

## Objective

Dynamically update the controlled vocabularies in pwiz-sharp (`pwiz/data/common`). When a
reader meets an accession that is not in the embedded OBOs, download the CV version the file
declares (or latest) and resolve the term - and every later lookup - from it. Today the term
becomes `CVID_Unknown` and is written back out as `??:0000000`.

C# only (the C++ tree is retired).

## Design (agreed 2026-11-04)

- **On by default.** Off via `CvLookup.OnlineUpdate` (`Enabled` / `CacheOnly` / `Disabled`),
  env `PWIZ_CV_ONLINE_UPDATE=0`, msconvert-sharp `--noCvUpdate`. Unit-test assemblies run with
  it off; the updater's own tests inject a fake `HttpMessageHandler`.
- **New terms are just CVIDs.** CVID = family offset + accession number, so a new term is a
  valid, unnamed enum value; `CVParam`, the writers and `CvIsA` need no changes.
- **Global source registry.** Readers call `CvLookup.RegisterSource(CV cv)` for each entry of
  the file's cvList (mzML/mzMLb, mzIdentML, TraML) or the mz5 CV dataset. Registering never
  touches the network. Deduped by (family, version, URI). Per-file registries were considered
  and rejected: the CVID table is global, so per-file source choice buys nothing.
  - Family from URI file name (`psi-ms.obo` -> MS+PEFF, `uo.obo`/`unit.obo` -> UO,
    `unimod.obo` -> UNIMOD), else from `id` (`MS`/`PSI-MS`, `UO`, `UNIMOD`); else ignored.
  - Version parsers per family: psi-ms dotted numeric, UO `releases/YYYY-MM-DD`, unimod `date:`.
    Unversioned entries rank below versioned ones.
- **On a miss in `CvTermInfo(string)`** (MS/PEFF/UO/UNIMOD only):
  1. Newest registered version for the family - even if older than embedded (deleted-term
     case), skipped only if equal to embedded or already tried. URL candidates: registered
     version-specific URIs, then the GitHub tag (`HUPO-PSI/psi-ms-CV/v{version}/psi-ms.obo`,
     UO `v{date}`), then registered unversioned URIs accepted only if downloaded data-version
     matches.
  2. Still missing -> latest, once per family per process.
  3. Each (family, version) attempted once per process, success or failure.
- **Precedence: newest version wins.** Sources merged into one global table ordered by
  version. A download newer than embedded overrides embedded names/defs/obsolete/parents; an
  older one only fills gaps. `GetCv(prefix).Version` reports the top source.
- **Cache:** `%LOCALAPPDATA%\ProteoWizard\cv\<family>\<version>.obo` + `.meta`; honors the
  `%PROGRAMDATA%` shared-root marker like `VendorSdkLoader`. Versioned entries never expire;
  latest throttled to 24h with ETag/`If-None-Match`. Temp file + atomic move. Validate before
  caching: parses, expected prefix, >= ~90% of embedded term count.
- **Least privilege, no host allowlist** (user's files are trusted): http/https only incl.
  redirects (no `file://`/UNC), `UseDefaultCredentials=false`, no cookies, ~50 MB cap,
  <= 3 redirects, ~15 s timeout. Failure -> one-time warning event, Unknown, never throws.
- **Concurrency:** immutable snapshot swapped with `Volatile.Write`; per-family single-flight.

## Tasks

- [ ] `CV.cs`: snapshot refactor (term table, accession index, CVID list), shared term builders
- [ ] `CV.cs`: `RegisterSource`, family/version parsing, `ResetForTests`, `OnlineUpdate` setting
- [ ] `CvOnlineUpdater.cs`: URL candidates, download, validation, disk cache, warning event
- [ ] Merge downloaded sources (newest wins); `GetCv().Version` from top source
- [ ] Reader registration: `MzmlReader`, `MzidReader`, `TraDataIO`, `Mz5ReferenceRead`
- [ ] `MSDataDiff.cs:824`: print term name instead of `Cvid.ToString()`
- [ ] msconvert-sharp `--noCvUpdate`
- [ ] Turn update off in unit-test assemblies
- [ ] Tests: `pwiz/data/common/test/CvOnlineUpdateTests.cs` (see list below)
- [ ] mzML round-trip test with a new accession

### Test list
1. Unknown accession resolves; `CvIsA` reaches the embedded parent
2. Newer download overrides embedded name; older download only fills gaps
3. Registration alone makes no request; two registered versions -> only the newer fetched,
   regardless of order
4. Registered version older than embedded is fetched before latest; equal -> straight to latest
5. Dead/HTML URI -> tag -> latest; unversioned URI with mismatched data-version rejected;
   `id="PSI-MS"` maps to MS
6. Concurrent misses -> one request; a second unknown term doesn't refetch
7. Cache: second "process" loads from disk with no network; versioned never expire; latest
   refetches after 24h; 304 reuses cache
8. HTML body / timeout / 500 -> Unknown, no cache written, one warning
9. `Disabled`, `CacheOnly`, env var
10. `file://` and UNC URIs never fetched
11. mzML round-trip keeps a new accession and name (no `??:0000000`)

## Out of scope / follow-ups
- `CVTranslator` (free text has no namespace to trigger on)
- Feeding new UNIMOD terms into the `Unimod` modification table (masses/specificities)

## Progress Log

### 2026-11-04
- Design agreed over several iterations (see Design). Worktree + branch created.
