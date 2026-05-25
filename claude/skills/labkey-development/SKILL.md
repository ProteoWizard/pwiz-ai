---
name: labkey-development
description: ALWAYS load when working on LabKey Server modules (MacCossLabModules, targetedms), in a LabKey enlistment directory, or on GitHub issues/PRs in LabKey repositories.
---

# LabKey Server Module Development

When working on LabKey Server modules, consult these documentation files.

## Always Read

1. **ai/docs/labkey/labkey-feature-branch-workflow.md** - Feature branch naming rules and merge process

## Ask These Questions First

Ask the user the following questions upfront (can be combined into one message):

1. **Which module** are you working on?
2. **Which LabKey enlistment are you using?** Check both candidate locations and report what you find before touching any files:
   - `C:/proj/labkeyEnlistment`
   - `C:/Users/vsharma/WORK/labkey/<checkout-name>` (e.g. `WORK/labkey/release-branch`)
   Ask the user to confirm which one to use if both exist or neither is obvious.
3. **Do you need to create a feature branch?** If yes:
   - Ask: **Which release are you targeting?** (e.g. `26.3`)
   - Check the current branch by running `git status -b` in the confirmed repo path.
   - If not already on the correct `releaseXX.Y-SNAPSHOT` branch, **tell the user which branch is currently checked out and which one is needed, and ask for confirmation before switching**. Only proceed after the user confirms.
   - Then create the feature branch:
     ```bash
     git checkout -b XX.Y_fb_<label>
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

The LabKey enlistment spans **multiple git repositories**. Key ones:

| Repo path (relative to enlistment root) | Contains |
|---|---|
| `.` (enlistment root) | LabKey platform, core modules |
| `server/modules/MacCossLabModules/` | MacCoss lab modules: `signup`, `panoramapublic`, `testresults`, `pwebdashboard`, `skylinetoolsstore`, etc. |
| `server/modules/targetedms/` | targetedms (Panorama) module |

**When creating a feature branch, create it in every repo that has changes.** Branch names must be identical across repos — TeamCity matches them by name.

```bash
# Create branch in the enlistment root repo
cd <enlistment-root>
git checkout -b 26.3_fb_my-feature

# Create the same branch in MacCossLabModules if it has changes
cd <enlistment-root>/server/modules/MacCossLabModules
git checkout -b 26.3_fb_my-feature
```

where `<enlistment-root>` is the confirmed path (e.g. `C:/proj/labkeyEnlistment` or `C:/Users/vsharma/WORK/labkey/release-branch`).

### Key Modules

- **targetedms** - The Panorama module. Our most important LabKey module overall. Stores and visualizes targeted mass spec data. Started by Vagisha, now largely maintained by LabKey with funding from pharma contracts. Foundation of the entire Panorama platform.
- **panoramapublic** - Panorama Public, our public-facing repository for publishable proteomics data as part of ProteomeXchange. Maintained by Vagisha. High external visibility.
- **pwebdashboard** - Panorama web dashboard. Maintained by Vagisha.
- **testresults** - Nightly test results dashboard on skyline.ms. Internal to the Skyline team but critical for development workflow. Primary data source for the LabKey MCP server that supports our `/pw-daily` reporting system.

## Build Commands

Run these from `<enlistment-root>` (the confirmed repo path — see "Ask These Questions First" above).

```bash
# Build and deploy the testresults module
gradlew :server:modules:MacCossLabModules:testresults:deployModule
```

```bash
# Build and deploy the targetedms module
gradlew :server:modules:targetedms:deployModule
```

```bash
# Build and deploy any MacCossLabModules module (replace <moduleName> with e.g. skylinetoolsstore, panoramapublic)
gradlew :server:modules:MacCossLabModules:<moduleName>:deployModule
```

```bash
# Build and deploy all modules (use when changes span multiple modules)
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
