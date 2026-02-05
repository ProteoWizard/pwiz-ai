---
name: labkey-development
description: Use this skill when working on LabKey Server modules (testresults, MacCossLabModules).
---

# LabKey Server Module Development

When working on LabKey Server modules, consult these documentation files.

## Core Files

1. **ai/docs/labkey/testresults-module.md** - Architecture of the testresults module (controller, schema, JSP views, model classes)
2. **ai/docs/labkey-dev-setup.md** - LabKey development environment setup

## Skyline Team LabKey Modules

All MacCossLab LabKey modules live under:
```
labkeyEnlistment/server/modules/MacCossLabModules/
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

## Key Patterns

- **Controllers** extend `SpringActionController` with static inner action classes
- **Actions** use `@RequiresPermission`, `@RequiresSiteAdmin`, or `@RequiresNoPermission`
- **API actions** extend `MutatingApiAction` or `ReadOnlyApiAction` and return `ApiSimpleResponse`
- **Views** are JSP files under the module's `view/` directory
- **SQL** uses `SQLFragment` with parameterized queries (never string concatenation for values)
- **Transactions** use `DbScope.Transaction` with try-with-resources
- **Schema access** goes through static methods on the module's schema class (e.g., `TestResultsSchema.getTableInfoTestRuns()`)
- **CSRF** - JSP forms use `LABKEY.CSRF` header for POST requests
- **JSP URL generation** uses `jsURL(new ActionURL(...))` for JavaScript and `h(new ActionURL(...))` for HTML attributes
