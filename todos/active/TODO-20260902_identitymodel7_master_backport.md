# Backport IdentityModel 7 to master, removing the recurring #4619 merge conflict

## Branch Information
- **Branch**: `Skyline/work/20260902_identitymodel7`
- **Worktree**: `C:\dev\pwiz-im7` (separate from the main `C:\dev\pwiz-net8` checkout)
- **Base**: `origin/master` (currently `08a02b9e2e`)
- **Created**: 2026-09-02
- **Status**: In progress - core port done and verified against real servers; two open test
  failures under active investigation; not yet compiled into a commit or pushed
- **Module**: `skyline`
- **PR**: none yet
- **Related**: [#4619](https://github.com/ProteoWizard/pwiz/pull/4619) (the net10 port PR this
  removes a recurring conflict for), [#4613](https://github.com/ProteoWizard/pwiz/pull/4613)
  (HttpClientWithProgress, already on master, this backport builds on top of it),
  [#4632](https://github.com/ProteoWizard/pwiz/pull/4632) (competing/parallel work on the same
  problem - see "Open question" below, **check this before doing anything else**)

## Why

#4619 (the net10 port) keeps conflicting with master in the same six files every time master
moves, because master's #4613 introduced `HttpClientWithProgress` while the net10 branch
independently solved "IdentityModel 7 removed `TokenResponse`'s constructors and `TokenClient`'s
old shape" with a different design (`HttpMessageHandlerFactory` mock seam). Landing IdentityModel
7 *on master*, in master's own `HttpClientWithProgress` shape, means the branch's next merge
finds master already compatible instead of refighting this.

## Open question - check PR #4632 first

**#4632** (`Skyline/work/20260901_watersconnect_token_poco`, open, mergeable, targets master) is
titled "Replaced IdentityModel's TokenResponse with an owned waters_connect type" - a **different
solution to the same problem**: it introduces a new `WatersConnectTokenResponse.cs` type instead
of depending on IdentityModel's `TokenResponse`/`ProtocolResponse` at all. This was noticed but
**never compared in detail** against this branch's approach. Before continuing this work, diff
#4632 against what's here and decide: does #4632 supersede this branch, should the two be
reconciled, or are they solving different enough scopes to coexist? Don't duplicate effort.

## What's done (uncommitted in `C:\dev\pwiz-im7`)

Three files changed, all verified against the real Waters dev servers:

| file | change |
|---|---|
| `pwiz_tools/Shared/CommonMsData/RemoteApi/OAuthPasswordGrantClient.cs` | **new** - shared static helper: `RequestToken(Uri, clientId, clientSecret, form)` (POST + `ProtocolResponse` parsing + exception mapping) and `PasswordGrantForm(username, password, scope)` (the RFC 6749 password-grant form, byte-identical between the two callers) |
| `pwiz_tools/Shared/CommonMsData/RemoteApi/WatersConnect/WatersConnectAccount.cs` | `RequestToken` now delegates to `OAuthPasswordGrantClient` |
| `pwiz_tools/Shared/CommonMsData/RemoteApi/Unifi/UnifiAccount.cs` | `Authenticate()`, `GetFolders()`, `GetFiles()`, `GetAuthenticatedHttpClient()` all moved off raw `HttpClient` onto `HttpClientWithProgress` (matching what #4613 did for WatersConnect only) |
| `pwiz_tools/Shared/CommonMsData/RemoteApi/Unifi/UnifiSession.cs` | its two `GetFolders(Uri)`/`GetFiles(Uri)` moved onto `HttpClientWithProgress.SendRequest`; dropped a now-redundant `EnsureSuccessStatusCode()` (SendRequest already throws on non-2xx); picked up a latent resource leak fix as a side effect (the returned client is now disposed via `using`, wasn't before) |
| `pwiz_tools/Shared/CommonMsData/CommonMsData.csproj` | one line, the new file |
| `pwiz_tools/Shared/Lib/IdentityModel.dll` | binary swap, 152,464 -> 192,000 bytes, 3.9.0.0 -> 7.0.0.0 (the **net472 asset** from the NuGet package - NOT a `PackageReference`, see below) |
| `pwiz_tools/Skyline/TestConnected/UnifiFunctionalTest.cs` | see "Test fixes" below |
| `scripts/misc/vcs_trigger_and_paths_config.py` | unrelated fix cherry-picked from #4632 while working here, see the main net8-port TODO |

### Why the vendored-DLL swap instead of `PackageReference`

Drafted `PackageReference IdentityModel 7.0.0` across five csproj files first. Broke
`TestData.csproj`: it has no other `PackageReference`, and adding one flips a legacy csproj into
a restore mode its `RuntimeIdentifiers`-less targets reject (`doesn't list 'win' as a
"RuntimeIdentifier"`). Master already vendors this DLL (`Shared/Lib/IdentityModel.dll`,
referenced via `<Reference Include="IdentityModel"><HintPath>` in five places with
`SpecificVersion=False`), so swapping the vendored binary for the 7.0.0 **net472** package asset
needs zero csproj edits and all five references keep resolving. Do not redo the
`PackageReference` approach without solving the `TestData.csproj` problem first.

**Trap hit along the way, worth avoiding**: `dotnet restore Skyline.sln` (run once to fetch
WebView2) silently wrote `PackageReference`-style restore assets (`*.nuget.g.props/targets`,
`project.assets.json`) into 16 legacy projects that don't use `PackageReference` at all,
including `TestData.csproj` - which produced the exact same `RuntimeIdentifiers` error
independent of my own edits, and cost a debugging cycle to trace back. **Never run `dotnet
restore` against `Skyline.sln` on master.** If it happens, clean with:
```
find pwiz_tools -maxdepth 4 -type d -name obj | while read d; do
  # keep assets only for projects that legitimately use PackageReference (Common.csproj etc.)
  rm -f "$d"/*.nuget.g.props "$d"/*.nuget.g.targets "$d"/project.assets.json \
        "$d"/project.nuget.cache "$d"/*.nuget.dgspec.json
done
```
then re-restore only the projects that need it (`Common.csproj`, the Osprey projects, etc.).

### `UnifiAccount.Authenticate()` - IdentityModel 7 API port

```csharp
// IdentityModel 7 replaced TokenClient's (address, clientId, clientSecret, handler)
// constructor and RequestResourceOwnerPasswordAsync, both of which needed an
// HttpMessageInvoker/HttpClient - HttpClientWithProgress is neither. POST the
// password grant directly instead (mirroring WatersConnectAccount.RequestToken,
// which solves the identical problem against a sibling Waters identity server) and
// hand IdentityModel the raw response rather than the removed client.
```
Correction made along the way: `TokenClient`/`TokenClientOptions` are **not** removed in
IdentityModel 7 (an earlier comment on the net10 branch claiming this is wrong) - what changed is
the constructor shape (`(HttpMessageInvoker, TokenClientOptions)` instead of
`(address, clientId, clientSecret, handler)`) and `RequestResourceOwnerPasswordAsync` becoming
`RequestPasswordTokenAsync`. Don't propagate the wrong claim if porting anything else that used
the old `TokenClient` shape.

### `ParseTokenResponse` / `ProtocolResponse.FromHttpResponseAsync` - measured, not assumed

`TokenResponse` in IdentityModel 7 has only a parameterless constructor. The replacement
reconstructs an `HttpResponseMessage` from the caught status/body (since `HttpClientWithProgress`
throws on every non-2xx rather than returning a response) and feeds it to
`ProtocolResponse.FromHttpResponseAsync<TokenResponse>(response).Result`. Verified this is safe
without `Task.Run`/`async`: for in-memory `StringContent`, the returned task comes back
`IsCompleted: true` (measured via reflection against the real assembly), so there is no
continuation to post to a captured WinForms `SynchronizationContext` and `.Result` cannot
deadlock. The code comment records this; don't "fix" it into an async chain.

## Verification performed

- Master builds clean from a fresh worktree (established a genuine, ProteowizardWrapper-rebuilt
  baseline before touching anything - see "Environment setup" below for what that took).
- `WatersConnectMethodExportTest` (en/fr) - 0 failures, exercises the 400-with-JSON auth-error
  path this port reroutes.
- `OAuthPasswordGrantClient.RequestToken` called directly via PowerShell reflection against the
  real `devconnect.waters.com` identity server with a deliberately invalid scope: came back
  `ErrorType=Protocol, Error=invalid_scope, Raw={"error":"invalid_scope"}` - matches the server's
  actual raw HTTP response (independently confirmed with a bare Python `urllib` POST to the same
  endpoint, bypassing all C# code, to have ground truth for what the server sends).
- `UnifiAccount.Authenticate/GetFolders/GetFiles` and `UnifiSession.GetFolders(Uri)/GetFiles(Uri)`
  all called directly via reflection against the real `democonnect.waters.com` Unifi server -
  correct data, fast (<3s), `Hi3_ClpB_MSe_01` found exactly where the test expects it.

## Test fixes in `UnifiFunctionalTest.cs` (uncommitted, same worktree)

Two genuine, **pre-existing** bugs found and fixed while running `TestConnected` with real
credentials (`WC_PASSWORD`, `UNIFI_PASSWORD` env vars) - neither caused by this session's port
work, both predate it:

### 1. WatersConnect-only OAuth-validation block, unguarded for Unifi

`d1c5c45927` (Rita Chupalov, #3386, "Waters connect implementation", 2025-12-03) added an
"invalid client id/scope/secret" + "invalid password" validation block into the **shared**
`DoTest()` used by both `TestUnifi` and `TestWatersConnect`, hard-casting
`(_testAccount as WatersConnectAccount)!` unconditionally. For `TestUnifi`, `_testAccount` is a
`UnifiAccount`, so the cast is null and `!.ChangeClientId(...)` NullReferenceExceptions
immediately. Fixed by guarding the whole block on `_testAccount is WatersConnectAccount`
(confirmed via the resource-string names and the block's own comment that the password-error
text is "a non-L10N string from Waters server" - this was always WatersConnect-specific, never
generalized).

### 2. `HandleAuthenticationException` never populated `message` for most branches

`EditRemoteAccountDlg.TestWatersConnectAccount`'s switch on `HandleAuthenticationException`'s
result falls through to `MessageDlg.ShowError(..., message)` for every case except `Generic`, but
`HandleAuthenticationException` only ever set the `out message` parameter for the `Generic` and
`InvalidResponse` branches - `InvalidClientScope`/`InvalidPassword`/`InvalidIdentityServer` all
returned with `message` still `null` from initialization (only `InvalidClientSecret` worked,
because its `case` block happens to override `message` itself with a hardcoded string). Result:
an invalid-scope error showed a bare generic message with no detail. Fixed by setting
`message = error` (the OAuth error/error_description text) before each of those returns. Verified
against the real server's actual `{"error":"invalid_scope"}` response.

### 3. Multi-level `ChangePathParts` navigation doesn't work for Unifi (found while digging into a hang)

The bigger find. `TestUnifi` was hanging for the full 720s hang-detector timeout at
`WaitForConditionUI(() => openDataSourceDialog.ListItemNames.Contains(name))`. Root cause:
`UnifiUrl.Id` is a plain stored field, untouched by `ChangePathParts`; `UnifiSession.ListContents`
matches children only via `folderObject.ParentId == unifiUrl.Id`. Jumping straight to a 3-level
path (`SetCurrentDirectory(GetRootUrl().ChangePathParts(["Company","Demo Department","Peptides"]))`)
leaves `.Id` empty, so `ListContents` returns the ROOT's children forever (or nothing), never the
target folder - proved directly: `ListContents(navUrl)` returns **0 items** for exactly this URL
construction, reflectively, against the real server.

This predates Rita's commit - the exact same single-jump code was already there beforehand, with
a **commented-out** incremental-navigation alternative sitting directly above it (dead code that
already knew the right shape). `TestWatersConnect` uses the identical shared code with a 4-level
path and it works, because (empirically, not yet read in source) `WatersConnectSession`'s
`ListContents` must resolve names differently.

Fixed by making navigation account-type-conditional in `DoTest()`: WatersConnect keeps the direct
`ChangePathParts` jump (proven working); Unifi walks one level at a time via `OpenFile(dlg,
pathSegment)` per path segment (restoring the shape of the dead code). **Verified**: no more
hang - fails in ~20-34s instead of 720s, at a different point entirely (see below).

## Two test failures still open

### `TestUnifi` - blocked by a test-environment limitation, not a real bug

After fix #3 above, `TestUnifi` now reaches actual file *reading* and fails fast with:
```
[Impl::connect(https://msconvert:...@democonnect.waters.com:48505/unifi/v1/sampleresults(...)...)]
Could not load file or assembly 'IdentityModel, Version=3.9.0.0, Culture=neutral, PublicKeyToken=null'
or one of its dependencies. The located assembly's manifest definition does not match the
assembly reference. (Exception from HRESULT: 0x80131040)
```
`pwiz_data_cli.dll` (the mixed-mode C++/CLI native reader bridge that actually performs this
HTTP connect) has a compiled-in reference demanding IdentityModel 3.9.0.0 **unsigned**
(`PublicKeyToken=null`), while what's on disk now is 7.0.0.0 **strongly-signed**
(`PublicKeyToken=e7877f4675df049f`). This is not a version gap, it's a signing-model gap.

**Root cause, confirmed by file timestamp**: `pwiz_data_cli.dll` (and originally
`ProteowizardWrapper.dll` itself, until a genuine rebuild fixed that half) is a native binary
*borrowed wholesale from `pwiz-net8`* (the net10 port branch) via an earlier robocopy done purely
to unblock this worktree's *managed*-code compilation - it was never built from master's own
native source. **Not a real product bug on master.**

**Tried and empirically ruled out**: a `bindingRedirect` in `TestRunner.exe.config` for
IdentityModel 7.0.0.0. Classic .NET Framework binding redirects only apply to strongly-named
assemblies; `pwiz_data_cli.dll`'s reference is to an *unsigned* build, so the redirect is
silently ignored - confirmed by adding it and getting the byte-identical error on rerun.

**What a real fix needs**: compiling `pwiz_data_cli.dll` (and whatever else) from master's own
C++/CLI source, full native toolchain (bjam/quickbuild + boost + VS native tools + vendor SDKs),
likely hours. If `pwiz_data_cli.dll`'s IdentityModel reference is purely transitive (via
referencing `pwiz.CommonMsData.dll`, not hand-written), a genuine rebuild would probably just
pick up 7.0.0.0 automatically with zero native code changes - unconfirmed, would need the actual
rebuild to know.

**Recommendation given to and left with the user**: don't do the native rebuild for this
validation. The actual deliverable (the managed OAuth/token code) is already proven correct
independent of the native reader - see "Verification performed" above. Document this as a known
test-environment limitation. **Decision was pending when this session ended** - check with the
user before either doing the native rebuild or writing it off permanently.

### `TestWatersConnect` - root cause suspected, not confirmed

`Assert.IsTrue failed. Multiple GraphChromatogram forms open simultaneously: [GraphChromatogram]
and [GraphChromatogram]`, importing 2 replicate files. Reproduces standalone (rules out
state-leak from `TestUnifi` running first in the same process - ran both ways, deterministic).

Not caused by this session's changes or by Rita's commit - both files import correctly via the
now-verified-correct managed code; this happens *after* successful import, in graph-window
management. Leading hypothesis, **not yet confirmed**: `Settings.settings` default
`ArrangeGraphsType="separated"` (unchanged since the original MultiFileLoad merge, `5fff74128b`,
long predates anything in this session) may mean "one `GraphChromatogram` window per replicate"
is Skyline's actual, correct, long-standing default behavior for a 2-replicate import - in which
case the test's assumption (`FindOpenForm` expecting exactly one window with
`CurveCount==_filenames.Length`) is what's stale, not the product.

**Confirming this needs reading `GraphChromatogram` creation and `SelectElement`'s
replicate-consolidation logic** - substantial, separate Skyline UI-internals territory, not
started. If picking this up: start by checking whether `ArrangeGraphsType` or a related setting
governs single-vs-per-replicate graph windows when `SelectElement` navigates to a molecule (not a
specific replicate), and whether that behavior is intentional for multi-file imports specifically.

## Environment setup notes (if this worktree needs recreating, or a new one is made)

Getting master to build in a **fresh worktree** (no prior native build) took seven iterations,
none of them code problems - all environment/checkout gaps:

1. **Native CLI bindings** (`pwiz_data_cli.dll` etc.) - `ProteowizardWrapper.csproj` needs these
   present at `obj/x64/*` (flat, no subfolder) to even reference-resolve at compile time. Copied
   wholesale from an already-built checkout via `robocopy ... /E /XC /XN /XO` (copy-only-missing,
   so it never overwrites anything already present). **This is what caused the `pwiz_data_cli.dll`
   / IdentityModel version problem above** - the borrowed binary carries its own stale
   compiled-in references. If redone, prefer copying from a checkout that's *also* on master (or
   accept the same limitation knowingly).
2. **13 generated `Properties/AssemblyInfo.cs` files** - gitignored bjam side-effects, not
   present in a fresh worktree. Copied from a sibling checkout that has them.
3. **NuGet restore** for WebView2 (`Microsoft.Web.WebView2` `PackageReference` in
   `Common.csproj`) - needed one `dotnet restore Skyline.sln` (see the trap noted above about
   what this silently breaks elsewhere).
4. **Submodules never initialized**: `BullseyeSharp`, `Hardklor/Hardklor`,
   `Hardklor/MSToolkit` - `git submodule update --init --depth=1`.
5. **`Model/Koina/Config/*.xml`** and other untracked-but-needed resources - copied from a
   sibling checkout (used `git ls-files --others --ignored --exclude-standard` to find the full
   set, filtered out `.vs`/`.tlog`/build noise).
6. **~465 MB of native trees** (`libraries/msparser_*`, `pwiz_aux/.../vendor_api/**`,
   `Executables/Hardklor/obj`) - `robocopy /E /XC /XN /XO`, copy-only-missing, from a sibling
   checkout's already-built native output.
7. **`BiblioSpec/obj/x64`** native executables (`BlibBuild.exe` etc.) - same robocopy pattern,
   smaller (45 files, ~40 MB).

**Gotcha discovered late**: directly editing/copying files into `obj/`+`bin/` bypasses MSBuild's
normal staleness tracking. `ProteowizardWrapper.dll` sat there for the *entire session* as a
`net10.0`/`net10.0-windows`-targeted binary (impossible on master, which only targets `net472`)
robocopied in from `pwiz-net8`, and every subsequent `dotnet build` silently reused it without
ever recompiling from master's actual source - discovered only by checking file timestamps
against when edits were actually made. **If anything in `ProteowizardWrapper` needs to be
trusted as "compiles clean on master," verify the output timestamp is fresh, not just that the
build reported success.** Fixed by deleting `obj/x64/Debug`, `obj/x64/Release`,
`obj/x64/Release/net10.0*`, and `bin/x64` (keeping only the top-level `obj/x64/*.dll`/`*.exe`
native artifacts) and rebuilding - master's `ProteowizardWrapper` does compile cleanly from its
own source once forced to actually try.
