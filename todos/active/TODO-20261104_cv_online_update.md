# TODO-20261104_cv_online_update.md

## Branch Information
- **Branch**: `Skyline/work/20261104_cv_online_update`
- **Checkout**: `C:\dev\pwiz-cvupdate`
- **Base**: `master`
- **Created**: 2026-11-04
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `pwiz`
- **PR**: [#5002](https://github.com/ProteoWizard/pwiz/pull/5002)

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
  caching: starts with `format-version:`, has terms of the CV's prefix, states a readable
  version (which must match for a pinned version); a latest download also needs >= 90% of the
  embedded term count.
- **Least privilege, no host allowlist** (user's files are trusted): http/https only incl.
  redirects (no `file://`/UNC), no credentials, no cookies, 50 MB cap, <= 5 redirects, 30 s
  timeout. Failure -> `OnlineUpdateMessage`, Unknown, never throws.
- **Concurrency:** immutable snapshot swapped with `Volatile.Write`; per-family single-flight.

## Tasks

- [x] `CV.cs`: immutable `CvTermTable` snapshot (term table, accession index, CVID list,
      per-CV versions) swapped with `Volatile.Write`; embedded build unchanged in behavior
- [x] `CV.cs`: `RegisterSource`, `OnlineUpdate`, `OnlineUpdateMessage`, `ResetOnlineUpdateForTests`
- [x] `CvOnlineUpdater.cs`: `CvFamily` (MS+PEFF / UO / UNIMOD), `CvVersion`, steps, download,
      validation, disk cache + `.meta`, messages
- [x] Merge downloaded sources (newest wins; older only fills gaps); `GetCv().Version` from top source
- [x] Reader registration: `MzmlReader`, `MzidReader`, `TraDataIO`, `Mz5ReferenceRead`
- [x] ~~`MSDataDiff.cs:824`~~ - dropped: it only builds a matching key, and an unnamed CVID's
      number is still unique
- [x] msconvert-sharp `--noCvUpdate` (+ messages to the log; msconvert-help.txt regenerated)
- [x] Off in test assemblies: `build/TestSupport/DisableCvOnlineUpdate.cs` module initializer,
      compiled into every IsTestProject by root `Directory.Build.targets` (sets
      `PWIZ_CV_ONLINE_UPDATE=0` unless already set). Skyline test projects don't import the root
      targets, so they are NOT covered.
- [x] Tests: `pwiz/data/common/test/CvOnlineUpdateTests.cs` (15) + shared
      `CvOnlineUpdateFixtures.cs` (fake server, OBO builders), linked into MsData.Tests
- [x] mzML round-trip: `pwiz/data/msdata/test/MzmlCvOnlineUpdateTests.cs`
- [x] Code review, commit, PR (#5002)

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
- Implemented. Common.Tests 83/83 (15 new), MsData.Tests 104/104, IdentData 7, TraData 6,
  MsConvert 24; Pwiz.sln builds clean with vendor licenses.
- Live check (real network): tiny.pwiz.1.1.mzML restamped psi-ms 4.2.14 (keeping its dead
  SourceForge URI) with MS:1003870 "index array" (new since embedded 4.1.257). msconvert-sharp
  fetched the v4.2.14 tag, wrote the term with its name; second run served from
  `%LOCALAPPDATA%\ProteoWizard\cv\MS\4.2.14.obo` with no download; `--noCvUpdate` wrote
  `??:0000000`. (Editing an indexed mzML by hand: keep attribute lengths or the offsets break.)
- psi-ms 4.2.14 has ~2000 MS terms the embedded 4.1.257 lacks - updating the embedded OBO
  (and CVID.generated.cs) is a separate, worthwhile chore.
- Download timeout ended up 30 s (psi-ms is ~1.9 MB) and redirect cap 5 (the psi-ms purl
  alone redirects through GitHub releases to release-assets).
- `/code-review high` (10 findings). Fixed:
  - is_a cycle in a download -> uncatchable stack overflow in CvIsA: `WithSource` rejects a
    merge that creates a cycle; parent ids out of the value block are dropped.
  - Accessions now resolve by parsed CVID, so padded spellings match. Fixes an existing mz5
    bug: mz5 writes `UNIMOD:0000001` (cpp `%s:%07lu`), which never matched `UNIMOD:1`.
  - Lock-free "exhausted" fast path for repeat misses (until a new registration or a retry falls due).
  - Stalls offline: 10 s connect timeout; a host that fails to connect is skipped 10 min;
    steps that failed for network/5xx/mode reasons are retried after 10 min instead of never.
  - Mode read once per resolution (volatile); `Converter` restores the previous mode.
  - Incremental merge (`CvTermTable.WithSource`, per-term loaded version) instead of
    rebuilding from all retained OBOs.
  - **Design change:** `GetCv()` back to the embedded version always - `MSData.DefaultCVList`
    is a static snapshot, so "newest loaded" made output depend on input order/network.
  - Not changed: file-chosen URIs are fetched and trusted (user decision: trust files).
  - Common.Tests now 87 (4 new: older-download precedence, padded accession, cycle, unreachable host).
    Full Pwiz.sln suite green; live msconvert check re-run OK.
