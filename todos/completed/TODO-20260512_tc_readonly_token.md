# Switch SkylineNightly TC artifact downloads to bearer-token auth

## Branch Information
- **Branch**: `Skyline/work/20260512_tc_readonly_token`
- **Base**: `master`
- **Created**: 2026-05-12
- **Status**: Completed
- **PR**: https://github.com/ProteoWizard/pwiz/pull/4202 (merged 2026-05-12 as ad91bfdca)

## Objective

Replace TeamCity `guestAuth` (hardcoded `guest`/`guest` credentials) in the
nightly test pipeline with a read-only bearer token kept in a machine-scope
env var. TC is disabling anonymous artifact downloads, which would break
every nightly test machine.

## Scope

Two places hit TC's artifact endpoint:
1. `SkylineNightlyShim/Program.cs` — fetches `SkylineNightly.zip` from `bt209`
   master to self-update the shim and its launchee.
2. `SkylineNightly/Nightly.cs` — fetches `SkylineTester.zip` from master,
   release, or integration build configs, with a `.lastFinished` →
   `.lastSuccessful` fallback for TC outages.

Both previously did `client.Credentials = new NetworkCredential("guest", "guest")`
and hit the `/guestAuth/` URL prefix.

## Approach

- New env var `TEAMCITY_NIGHTLY_TEST_AUTH_TOKEN` carries a read-only token,
  set machine-scope on each test box.
- New helper `TeamCityNightlyAuth` (one source file, linked into both projects)
  centralizes: env-var read, URL composition, TLS configuration, and the
  `Authorization: Bearer <token>` header.
- Missing/empty env var fails fast with a pointer to
  https://skyline.ms/home/development/project-begin.view rather than silently
  retrying for two hours.

## Rollout (out of repo)

Existing installed shims can't self-update from TC once guest is disabled.
A one-time admin batch file (`Install-NightlyAuth.bat`, kept private — not
in this repo) sets the env var and replaces the five files the shim normally
updates, using the install dir from Windows Task Scheduler. From then on,
the shim updates itself nightly via the new bearer-token path.

## Validation

- Both projects build clean (Release|x64).
- Manual probe: `https://teamcity.labkey.org/repository/download/bt209/.lastFinished/SkylineNightly.zip?branch=master`
  with `Authorization: Bearer <token>` returns HTTP 200 (~655 KB zip with all
  expected entries).
- Cherry-pick: **no** — POST-RELEASE PATCH phase, master-only infrastructure
  work with no impact on released users.

## Progress Log

### 2026-06-24 - Merged (closeout)

PR #4202 merged to master 2026-05-12 as commit ad91bfdca; TODO had simply never
been moved out of active. No follow-up — bearer-token auth shipped as designed.
