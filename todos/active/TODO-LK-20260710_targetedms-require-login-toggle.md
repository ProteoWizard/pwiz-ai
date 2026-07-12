# TODO-LK: Targeted MS Guest Access (site-admin toggle to require login for bot-targeted views)

- **Created**: 2026-07-10
- **Module**: targetedms (`server/modules/targetedms`, its own git repo)
- **Status**: **PR #1259 open and ready for review** — https://github.com/LabKey/targetedms/pull/1259.
  Built, self-reviewed twice, Selenium test green against a live server. Targets **26.3**.
- **Branch**: `26.3_fb_targetedms-require-login-toggle` off `release26.3-SNAPSHOT`.
- **Active checkout**: `C:/Users/vsharma/WORK/labkey/release-branch` (run gradle from here).
  - Build: `gradlew :server:modules:targetedms:deployModule`
  - UI test (needs a running server at localhost:8080): `gradlew :server:testAutomation:uiTests "-Ptest=TargetedMSGuestAccessTest"`
- **Anchors**: locate code by class/method name, not line number (numbers drift).
- **Origin**: PanoramaWeb bot-traffic incident (2026-07-08/09). A crawler walked showProtein ->
  showPeptide -> calibration/chromatogram pages as a guest across public data. This is the break-glass
  switch discussed with Brian: turn it on during an attack to require a login for the slow views,
  leaving the rest of Panorama Public open, then turn it off once traffic subsides.

## What it does

A site-admin settings page ("Targeted MS Guest Access") with a **master switch** (off by default) plus
one **checkbox per action**. When the master switch is on, each checked action requires an authenticated
user, so an anonymous crawler is sent to login regardless of how many IPs it rotates through. Off by
default, so normal public browsing is unchanged. Authenticated clients (AutoQC, etc.) are never affected.

Two independent tiers, kept separate:

- **Tier A (always-on, unconditional):** the most abusive per-document pages already require a login for
  guests at all times, independent of any toggle (PR #1169, 2026-01). This work is **additive and must
  not weaken them**. See the table below.
- **Tier B (toggle-gated):** the broader set below, gated only when the master switch is on.

## Implementation

- **`GuestAccessManager.java`** (new) — the registry, storage, and gate logic. `RestrictableAction` enum
  keyed by the action **class**; an action gates itself via `getClass()` -> `forClass()`, and the
  settings-page label is derived from the action's registered URL name, so a rename can't drift. Stored
  as root-container site properties (category `TargetedMSGuestAccess`); the stored key is the enum
  `name()`. `isRestricted(action)` = master on AND action checked. `save()` preserves per-action
  selections when the master switch is off and writes a `SiteSettingsAuditEvent` only on an actual change.
- **`TargetedMSController.java`** — `GuestAccessSettingsAction` (`FormViewAction`,
  `ApplicationAdminPermission`, root container) plus form/bean. Gate helpers: `getGuestLoginGate(...)`
  returns the inline HTML login view for pages; `redirectGuestToLoginForChart(...)` redirects the
  chart-image endpoints (which can't return HTML). Gating placement follows the action-lifecycle rules in
  `ai/docs/labkey/labkey-modules-coding-patterns.md` ("Gating or short-circuiting a view action"):
  HTML pages gate in `getView`; the QueryView page (`showPrecursorList`) gates in `getView` so exports
  are covered; the single-curve calibration page gates in `validate()` (skipping the expensive
  `CalibrationCurveView`) and `getView`; chart-image endpoints gate at the top of `export()`.
- **`view/guestAccessSettings.jsp`** (new) — master toggle + per-action checkboxes, CSRF via
  `<labkey:form>`, `h()` on all dynamic values.
- **`TargetedMSModule.java`** — admin-console link (`Premium`, `ApplicationAdminPermission`) shown only
  when the panoramapublic module is present (`ModuleLoader.getInstance().hasModule("panoramapublic")`,
  string literal to avoid a backwards dependency). Hiding the link is deemed enough; the page is still
  reachable by direct URL by site admins and defaults to off.
- **`TargetedMSGuestAccessTest.java`** (new) — drives guest allowed (master off) -> blocked (on) ->
  allowed again (unchecked) across two HTML pages and a chart endpoint, verifies per-action independence
  and export-URL gating, confirms a Tier A page stays blocked regardless of the toggle, and restores the
  site-wide settings in `@After` (see the guide's "Restoring site-wide settings" note).

## Tier B restrictable actions (settings-page checkboxes)

Defaults gate the pages that **assemble many charts**, not the fast single-chart image endpoints.

| Action | Class in `TargetedMSController` | Default |
| --- | --- | --- |
| `showProtein` | `ShowProteinAction` | checked |
| `showPeptide` | `ShowPeptideAction` | checked |
| `showMolecule` | `ShowMoleculeAction` | checked |
| `showCalibrationCurve` | `ShowCalibrationCurveAction` (single-curve page, gated in `validate`) | checked |
| `showPrecursorList` | `ShowPrecursorListAction` | unchecked |
| `showPeakAreas` | `ShowPeakAreasAction` (chart image) | unchecked |
| `showRetentionTimesChart` | `ShowRetentionTimesChartAction` (chart image) | unchecked |
| `precursorChromatogramChart` | `PrecursorChromatogramChartAction` (chart image) | unchecked |
| `groupChromatogramChart` | `GroupChromatogramChartAction` (chart image) | unchecked |

The chart-image endpoints are off by default so inline charts keep rendering for guests during normal
operation. Gating the detail pages already collapses most embedded-chart volume for a link-following
crawler; the chart-endpoint options exist to also block a crawler that requests the image URLs directly
by enumerating ids. `showCalibrationCurve` is the singular single-curve detail page (the bot target in
Brian's report), not the plural `ShowCalibrationCurvesAction` list.

## Tier A always-on guest gates (do not weaken)

Unconditional (`getUser().isGuest()`, no toggle). Untouched by this work.

| Tier A protection | Class | Kind |
| --- | --- | --- |
| `PrecursorAllChromatogramsChartAction` | `TargetedMSController` | full login gate |
| `MoleculePrecursorAllChromatogramsChartAction` | `TargetedMSController` | full login gate |
| `ShowTransitionListAction` | `TargetedMSController` | full login gate |
| `ChromatogramGridQuerySettings.init` | `query/ChromatogramGridQuerySettings` | throttle (caps guests to 50 rows) |
| `LibrarySpectrumMatchGetter.blockSpectraForGuest` | `view/spectrum/LibrarySpectrumMatchGetter` | block (large spectrum libraries) |

Added in PR **#1169** (Josh Eckels, merged 2026-01-28). The 50-row cap lives in
`ChromatogramGridQuerySettings` (created only by `ChromatogramsDataRegion`), so it bounds the chromatogram
image grid per request but does not stop a paginating crawler. That is why the new whole-page toggle is
the stronger lever.

## Boundary notes

- **Site-wide by design.** The master switch is a single root-container setting and the gate applies to
  guests in every container. Because a guest can only reach these pages on a folder that grants Guests
  read (a public folder), this is effectively "public folders, server-wide", which is the intended
  break-glass blast radius.
- **Public access preserved when off.** This is a temporary emergency measure, not a steady state.

## Next steps

1. Human review once TeamCity is green on the branch. Optional, billed: `/ultrareview 1259`.
2. After merge: `/pw-complete` (final TODO, move to completed, sync local, delete work branch). Targets
   26.3 directly, so no cherry-pick to a separate release branch.
