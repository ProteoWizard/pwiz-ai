---
name: labkey-development
description: Use this skill when working on LabKey Server modules (MacCossLabModules, targetedms).
---

# LabKey Server Module Development

When working on LabKey Server modules, consult these documentation files.

## Always Read

1. **ai/docs/labkey/labkey-feature-branch-workflow.md** - Feature branch naming rules and merge process

## Ask Which Module First

**Ask the user which module they are working on**, then read the appropriate doc(s):

| Module | Doc(s) to read |
|---|---|
| `testresults` | `ai/docs/labkey/testresults-module.md` |
| `panoramapublic` | `ai/docs/labkey/panoramapublic-module.md` AND `ai/docs/labkey/panoramapublic/panoramapublic-coding-patterns.md`|
| Other / unsure | Skip — rely on Key Patterns below |

Also read `ai/docs/labkey-setup/README.md` if environment setup is needed.

## Read On Demand

- **ai/docs/labkey/labkey-modules-coding-patterns.md** - Full coding patterns reference (action types, forms, DOM builder, unit tests, Selenium tests). Read when writing or modifying code — the Key Patterns section below covers the common cases.

---

## Skyline Team LabKey Modules

All LabKey modules developed by the MacCoss lab live under:
```
labkeyEnlistment/server/modules/MacCossLabModules/
```

targetedms module lives under:
```
labkeyEnlistment/server/modules/targetedms/
```

### Key Modules

- **targetedms** - The Panorama module. Our most important LabKey module overall. Stores and visualizes targeted mass spec data. Started by Vagisha, now largely maintained by LabKey with funding from pharma contracts. Foundation of the entire Panorama platform.
- **panoramapublic** - Panorama Public, our public-facing repository for publishable proteomics data as part of ProteomeXchange. Maintained by Vagisha. High external visibility.
- **pwebdashboard** - Panorama web dashboard. Maintained by Vagisha.
- **testresults** - Nightly test results dashboard on skyline.ms. Internal to the Skyline team but critical for development workflow. Primary data source for the LabKey MCP server that supports our `/pw-daily` reporting system.

## Build Commands

```bash
# Build and deploy the testresults module
cd C:/proj/labkeyEnlistment
gradlew :server:modules:MacCossLabModules:testresults:deployModule
```

```bash
# Build and deploy the targetedms module
cd C:/proj/labkeyEnlistment
gradlew :server:modules:targetedms:deployModule
```

## Key Patterns

- **Controllers** extend `SpringActionController` with static inner action classes
- **Actions** use `@RequiresPermission`, `@RequiresSiteAdmin`, or `@RequiresNoPermission`
- **API actions** extend `MutatingApiAction` or `ReadOnlyApiAction` and return `ApiSimpleResponse`
- **Views** are JSP files under the module's `view/` directory
- **SQL** uses `SQLFragment` with parameterized queries (never string concatenation for values)
- **Transactions** use `DbScope.Transaction` with try-with-resources
- **Schema access** goes through static methods on the module's schema class (e.g., `TestResultsSchema.getTableInfoTestRuns()`)
- **CSRF** — JSP forms use `<labkey:form>` or `DOM.LK.FORM`; JavaScript POSTs include `LABKEY.CSRF` header
- **JSP URL generation** uses `jsURL(new ActionURL(...))` for JavaScript and `h(new ActionURL(...))` for HTML attributes
