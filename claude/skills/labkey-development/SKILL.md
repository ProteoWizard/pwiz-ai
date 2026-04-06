---
name: labkey-development
description: Use this skill when working on LabKey Server modules (MacCossLabModules, targetedms).
---

# LabKey Server Module Development

When working on LabKey Server modules, consult these documentation files.

## Always Read

1. **ai/docs/labkey/labkey-feature-branch-workflow.md** - Feature branch naming rules and merge process

## Ask These Questions First

Ask the user the following questions upfront (can be combined into one message):

1. **Which module** are you working on?
2. **Do you need to create a feature branch?** If yes:
   - Ask: **Which release are you targeting?** (e.g. `25.11`)
   - Check the current branch: call `mcp__status__get_project_status()` and find the labkeyEnlistment repo
   - If not already on the correct `releaseXX.Y-SNAPSHOT` branch, **tell the user which branch is currently checked out and which one is needed, and ask for confirmation before switching**. Only proceed after the user confirms:
     ```bash
     cd C:/proj/labkeyEnlistment
     git checkout release25.11-SNAPSHOT
     git pull
     ```
   - Then create the feature branch:
     ```bash
     git checkout -b 25.11_fb_<label>
     ```
   - **Never create a version-prefixed feature branch from `develop`** — the PR will show a massive diff of unrelated commits.

## Module-Specific Docs

Based on the module the user is working on, read the appropriate doc(s):

| Module | Doc(s) to read |
|---|---|
| `testresults` | `ai/docs/labkey/testresults-module.md` |
| `panoramapublic` | `ai/docs/labkey/panoramapublic-module.md` AND `ai/docs/labkey/panoramapublic/panoramapublic-coding-patterns.md`|
| Other / unsure | Skip — rely on Key Patterns below |

Also read `ai/docs/labkey-setup/README.md` if environment setup is needed.

## Read On Demand

- **ai/docs/labkey/labkey-modules-coding-patterns.md** - Full coding patterns reference (action types, forms, DOM builder, unit tests). Read when writing or modifying code — the Key Patterns section below covers the common cases.
- **ai/docs/labkey/labkey-selenium-testing-guide.md** - Selenium test patterns, commonly used methods, locators, assertions, and DRY practices. Read when writing or modifying Selenium tests.

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

```bash
# Build and deploy any MacCossLabModules module (replace <moduleName> with e.g. skylinetoolsstore, panoramapublic)
cd C:/proj/labkeyEnlistment
gradlew :server:modules:MacCossLabModules:<moduleName>:deployModule
```

```bash
# Build and deploy all modules (use when changes span multiple modules)
cd C:/proj/labkeyEnlistment
./gradlew deployApp
```

## MANDATORY: Always Build Before Committing

**After making any code changes, always build before committing.** A successful build confirms there are no compilation errors (e.g. references to deleted classes or JSP files).

- **Single module changed** → run `deployModule` for that module (see commands above)
- **Multiple modules changed** → run `./gradlew deployApp`

This is critical because JSP files are compiled at build time, not by the IDE — compilation errors in JSPs will not be caught by the IDE and will only surface during a build.

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
