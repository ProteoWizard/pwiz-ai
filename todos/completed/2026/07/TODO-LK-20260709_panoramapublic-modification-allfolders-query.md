# TODO-LK: panoramapublic modification web parts exposed an unbounded "All Folders" aggregate query

- **Status**: Completed. Merged and deployed on the server.
- **PR**: [#662](https://github.com/LabKey/MacCossLabModules/pull/662) (merged 2026-07-14 as `501ba21`)
- **Branch**: `26.3_fb_panoramapublic-disable-cross-folder-query`, off `release26.3-SNAPSHOT`
- **Module**: panoramapublic (`server/modules/MacCossLabModules/panoramapublic`)
- **Origin**: PanoramaWeb scraping incident, 2026-07-08/09. The longest request was a
  `query-executeQuery.view` on the modification query, running 1,006 s at HTTP 200.
- **Motivation**: Primarily to control bots. The site-wide aggregate was being hit by scraping traffic, and
  this scopes it so a crawler (or a hand-built URL) can no longer run it across every folder on the server.

## Problem

The "Isotope Modifications" and "Structural Modifications" web parts show a small folder-scoped grid, but
the web part title links to the full query grid (`IsotopeModifications` / `StructuralModifications` on
`query-executeQuery.view`). There the Folder Filter offered "All Folders", running the aggregate across
every targetedms folder on the server. Trimming the dropdown alone does not fix it: the applied filter comes
straight from `?query.containerFilterName=` in the URL, so a hand-built `AllFolders` URL bypasses the
dropdown. This affects both the executeQuery grid and the standalone web part grid.

## Fix (PR #662)

- `PanoramaPublicSchema.limitContainerScope(cf, container, user)` returns `CurrentAndSubfolders` for any
  filter type other than `Current` or `CurrentAndSubfolders`, else returns `cf` unchanged.
- Applied via a `getContainerFilter()` override in both `PanoramaPublicSchema.createView` (executeQuery grid)
  and `ModificationsView` (standalone web parts). Both also trim the dropdown with
  `setAllowableContainerFilterTypes(Current, CurrentAndSubfolders)`.
- Constants `QUERY_ISOTOPE_MODIFICATIONS` / `QUERY_STRUCTURAL_MODIFICATIONS`.
- Tests in `PanoramaPublicModificationsTest.testAddModInfo`: `verifyModificationQueryScopeIsRestricted` and
  `verifyModificationWebPartScopeIsRestricted`. Red on unfixed code, green after.

## Progress Log

### 2026-07-14 - Merged and deployed

PR #662 merged as `501ba21` into `release26.3-SNAPSHOT` and deployed on the server. Shipped the
`limitContainerScope` helper applied via `getContainerFilter()` overrides on both the executeQuery grid
(`PanoramaPublicSchema.createView`) and the standalone web parts (`ModificationsView`), clamping any scope
wider than `CurrentAndSubfolders` back down to `CurrentAndSubfolders`, plus the two Selenium checks.

