# TODO-20260901_watersconnect_token_poco.md

## Branch Information
- **Branch**: `Skyline/work/20260901_watersconnect_token_poco`
- **Module**: `skyline` - waters_connect remote API in `Shared/CommonMsData`
- **Base**: `master` @ `08a02b9e2e`
- **Created**: 2026-09-01

## Problem

#4613 moved waters_connect onto `HttpClientWithProgress`, including the token request,
which now does its own form POST, its own RFC 6749 credential encoding and its own error
classification. What it kept from IdentityModel was one thing: `TokenResponse`, purely as
a JSON-parsed shape.

That leftover is what makes master and the .NET 10 port branch disagree. Master compiles
against the checked-in IdentityModel 3.9, where `TokenResponse` has public constructors
taking a raw body, an HTTP status, or an exception. The port branch references
IdentityModel 7.0.0 from NuGet, where `TokenResponse` has exactly one public constructor -
the parameterless one. Probed directly:

```
IdentityModel 7.0.0  IdentityModel.Client.TokenResponse
Public constructors:
Void .ctor()
```

So merging master into `Skyline/work/20260612_net8_port` produces three compile errors in
`RequestToken`, and there is no resolution that satisfies both sides while either side
still depends on IdentityModel's type. The conflict recurs on every future master -> port
merge.

The port branch has already dealt with this its own way: Matt rewrote `Authenticate` onto
IdentityModel 7's `RequestPasswordTokenAsync` / `RequestRefreshTokenAsync` extension
methods, which take an `HttpClient`. That is the raw-`HttpClient` usage the port to
`HttpClientWithProgress` exists to remove, so taking that side is not an option.

## Fix

Own the shape. `WatersConnectTokenResponse` in `RemoteApi.WatersConnect`, parsed with
`JsonConvert.DeserializeObject` behind static factories - the pattern the Ardia response
types alongside it already use (`StorageInfoResponse.Create`,
`GetParentFolderResponse.FromJson`).

The used surface is eight members, all of them verified by grep before starting:
`AccessToken`, `RefreshToken`, `ExpiresIn`, `IsError`, `ErrorType`, `Error`,
`ErrorDescription`, `Raw`. Three construction sites map one-to-one onto factories:

| Was | Now |
|-----|-----|
| `new TokenResponse(raw)` | `FromJson(raw)` |
| `new TokenResponse(status, reason, body)` | `FromHttpError(status, reason, body)` |
| `new TokenResponse(ex)` | `FromException(ex)` |

`ResponseErrorType` becomes a local `TokenErrorType`, only ever compared against
`Exception`.

Semantics reproduced from IdentityModel 3.9, measured rather than recalled: a body that is
not JSON is an error rather than a throw, and an HTTP-error response keeps the body
verbatim as `Raw`.

## Why this is low risk

`HandleAuthenticationException` - the classification that turns `invalid_scope`,
`invalid_client` and `invalid_grant` into user-facing messages - does not touch
`TokenResponse` at all. It re-parses `ex.Data[TOKEN_DATA]` with `JObject.Parse` and reads
the raw JSON fields. So the whole classification path is untouched, provided `Raw` still
carries the body verbatim, which the POCO preserves and the factory contracts state.

## Verification

* [x] Solution builds clean
* [x] `TestWatersConnectExportMethodDlg` en + fr - covers both the success path and the
  authentication-failure path (`_authenticationError`), which is the part most changed
* [x] CodeInspection - 0 failures

## Scope

waters_connect only. `UnifiAccount.Authenticate()` still returns IdentityModel's
`TokenResponse`, so the package reference stays in `CommonMsData` either way. Unifi is the
obvious follow-on and wants both treatments together rather than this one alone -
`UnifiAccount.cs:168` is still `new HttpClient()` per call, which is the same raw-client
usage #4613 removed from waters_connect.

## Notes

* This is deliberately a PR to master rather than a resolution inside the port branch
  merge. It gets net472 CI, where `TestWatersConnectExportMethodDlg` actually runs, and it
  puts the change in front of Rita and Matt as a reviewable diff rather than burying it in
  a conflict resolution in Matt's file.
* Once this lands, the master -> `20260612_net8_port` merge for this file becomes
  mechanical and stays that way.
