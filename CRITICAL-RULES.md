# CRITICAL RULES

Bare constraints only - no explanations. See ai/MEMORY.md, ai/STYLEGUIDE.md, and ai/TESTING.md for details.

> **MUST READ [ai/STYLEGUIDE.md](STYLEGUIDE.md) before writing or editing ANY C# in
> this project.** Open the file - a pointer to it in a skill, or a one-line summary of
> what it contains, is not a substitute for reading it. This file lists constraints;
> STYLEGUIDE.md shows the conventions, and the two are not interchangeable.

**Trust comes from verifiers, not from the LLM.** Every rule below is intended to be enforced by a build, a test, or an inspection — not by the model reading and remembering. When a rule's verifier is weak, the rule will drift; strengthen the verifier rather than the wording. See [ai/docs/validation-cycle-principles.md](docs/validation-cycle-principles.md).

## File Format Requirements
- Line endings in **pwiz**: always write CRLF. Blob storage is NOT uniform and the
  extension does not predict it - a 25-file sample of `.cs` was 15 CRLF / 10 LF, and
  some `.txt` blobs are mixed. Writing CRLF is safe against both: `core.autocrlf=true`
  normalises it away where the blob is LF, and preserves it where the blob is CRLF.
  Writing LF into a CRLF-stored blob churns the WHOLE file (measured: a 3-line file
  diffs as 3 changed). `CodeInspectionTest` catches MIXED endings only
  (`crlfCount != 0 && crlfCount < lines.Length-1`), so an all-LF `sed -i` rewrite
  passes it. Fix with `pwsh -File ./ai/scripts/fix-crlf.ps1` before committing
- Line endings in **pwiz-ai**: not a rule, do not check or convert them. The repo
  stores LF, `core.autocrlf=true` yields CRLF on checkout, and a file written
  either way commits identically. Flagging an `ai/` file for line endings, or
  converting one, is churn - the CRLF prescription is for pwiz source only
- Use spaces, not tabs
- Blank lines must be completely empty (no spaces/tabs)
- **NEVER** use Unicode dashes (em dash `U+2014`, en dash `U+2013`) - use ASCII hyphen `-`
- Avoid all characters above ASCII 127 in code and comments unless required by the domain

## Asynchronous Programming
- **NEVER** use `async`/`await` keywords in C# code
- Use `ActionUtil.RunAsync()` in Skyline code (`pwiz_tools/Skyline/`)
- Use `CommonActionUtil.RunAsync()` in Common libraries (`pwiz_tools/Shared/`)

## Resource Strings (Localization)
- **ALL** user-facing text must be in .resx files
- **NO** string literals in .cs files for UI text
- Add new UI strings to `pwiz_tools/Skyline/Menus/MenusResources.resx`
- .resx changes require corresponding .Designer.cs updates
- Resource properties in .Designer.cs must be in alphabetical order

## Naming Conventions
- Private fields: `_camelCase`
- Constants: `ALL_CAPS_WITH_UNDERSCORES`
- Types/namespaces: `PascalCase`
- Interfaces: `IPascalCase`
- Enum members: `snake_case`
- Locals/parameters: `camelCase`

## Testing - Translation-Proof
- **NEVER** use English text literals in test assertions
- **ALWAYS** use resource strings for expected text
- Prefer `AssertEx` over `Assert` in LLM-generated code — supports debugger-break-on-fail
- **Exception**: Use `Assert.IsNotNull()` not `AssertEx.IsNotNull()` — ReSharper only recognizes `Assert.IsNotNull` as a null-guard, so `AssertEx.IsNotNull` leaves subsequent dereferences flagged as possible NRE warnings
- **ALWAYS** use `AssertEx.Contains()` not `Assert.IsTrue(string.Contains())`
- **ALWAYS** use `HttpClientTestHelper.GetExpectedMessage()` for network errors

## Testing - Structure
- **NEVER** create multiple `[TestMethod]` for related validations
- **ALWAYS** consolidate validations into single test with private helpers
- Test.csproj: Fast unit tests, no UI, no data
- TestFunctional.csproj: UI tests (most common)
- See ai/TESTING.md for comprehensive guidelines

## DRY Principle
- Extract helpers when duplication exceeds 3 lines
- 17-year-old project - duplication is maintenance burden
- Place helpers after public methods that use them
- Isolate PInvoke calls in one place to reduce duplication and simplify usage of Win32 APIs (e.g. pwiz.Common.SystemUtil.PInvoke.Kernel32)

## Control Flow
- If statements must not be single-line
- Keep condition and body on separate lines if braces omitted

## Build System
- Use `quickbuild.bat` on Windows
- **DO NOT** introduce new build systems
- **DO NOT** reformat unrelated code
- Update Jamfile or Visual Studio project when adding sources

## PowerShell Scripts
- **ALL** `.ps1` scripts require PowerShell 7+ (`pwsh.exe`)
- Windows PowerShell 5.1 (`powershell.exe`) will fail on modern syntax
- Run scripts with: `pwsh -File ./path/to/script.ps1`
- See `ai/docs/developer-setup-guide.md` for PowerShell 7 installation

## File and Member Ordering
1. static variables/fields
2. static public methods
3. private instance fields
4. constructor(s)
5. public methods/properties
6. **private helper methods AFTER public methods that use them**

**CRITICAL**: Helpers go LAST, not first. C# is not C - no forward declarations needed.
- ✅ Main method first → helper methods below
- ❌ Helper methods first → main method last (old C style)

## Tools and Quality
- Aim for zero warnings in Visual Studio 2022 + ReSharper
- Solution must build with zero warnings
- All tests must pass before commit
- ReSharper must show green (no inspections)

## Code Review Runs Where You Are Standing

- **`cd` to the checkout holding the PR branch BEFORE `/code-review`** - started in the
  wrong repo it does not fail, it reviews the wrong code. Enforced by
  `.claude/hooks/Deny-CodeReviewInAiRepo.ps1` for the `ai/` case; the reason and the
  measured cost are in ai/docs/version-control-guide.md, at the step that tells you to
  run it

## Bash Tool: Avoid Compound Commands
- **NEVER** use `cd /path && command` — the shell working directory persists between Bash tool calls
- `cd` once, then run subsequent commands individually
- **NEVER** pipe build/test script output through `grep`, `tail`, `head` etc.
- Use `-Summary` flag on `Build-Skyline.ps1` and `Run-Tests.ps1` instead
- Use `Build-Skyline.ps1 -RunTests -TestName X -Summary` for build+test in one command
- Piped commands trigger compound-command permission prompts, blocking unattended iteration

## Commits Require Build and Test Verification
- **NEVER** commit code that has not been built and tested
- Before offering to commit, confirm that the code compiles and tests pass
- If the LLM has not built/tested the code itself, ask the developer: "Has this been built and tested?"
- This applies after every round of changes, including review feedback fixes
- A commit that does not build breaks the entire team - treat this as a hard gate

## ai/.tmp is NEVER committed
- `ai/.tmp/` is gitignored - it holds local working files (handoffs,
  profiling snapshots, diagnostic dumps, MCP tool output)
- **NEVER** `git add` anything in `ai/.tmp/`, even with `-f`
- Handoff files (`ai/.tmp/handoff-*.md`) are temporal session-to-session
  instructions, NOT durable project records
- All durable sprint context belongs in `ai/todos/active/TODO-*.md`

## ai/.tmp is the ONLY temp/working folder
- Use `C:\proj\ai\.tmp\` for all temp files created while working in
  `C:\proj`: measurement scripts, saved binaries, log captures, diffs,
  baselines, whatever
- Do NOT use `/tmp/` (Git Bash maps it to `$env:TEMP`, invisible to
  PowerShell), `C:\tmp\`, `C:\Users\...\AppData\Local\Temp\`, or any
  other ad-hoc location
- If a tool needs a scratch directory, create a subfolder under
  `ai/.tmp/` (e.g. `ai/.tmp/memtest/`, `ai/.tmp/diag-before/`)
- **Your own working files go in `ai/.tmp/sessions/<YYYYMMDD>-<short-session-id>/`**
  - patch scripts, commit message drafts, captured build logs. The ROOT of
  `ai/.tmp/` is for files exchanged with the developer (handoffs, pasted
  context, downloads); dozens of session `.py` and `.txt` files there bury it
- Test and run output goes to the machine's test data area, NEVER to `ai/.tmp/`
- Keeping everything under `ai/.tmp/` keeps the paths consistent
  between Git Bash and PowerShell, and between sessions

## NEVER
- Use `async`/`await` keywords
- Use English text literals in test assertions
- Parse exception messages for status codes
- Create multiple `[TestMethod]` for related validations
- Use string literals for user-facing text
- Reformat unrelated code
- Mix tabs and spaces
- Use Unicode when ASCII alternative exists
- Commit anything in `ai/.tmp/` to Git
