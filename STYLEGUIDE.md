# Skyline C# Coding Style - Quick Reference

> ## MUST READ THIS FILE BEFORE WRITING OR EDITING ANY C# IN THIS PROJECT
>
> Not "know that it exists" — **open it**. A pointer to this file in a skill or
> CLAUDE.md is not a substitute for reading it, and a one-line summary of its
> contents is not either. Read it before the first edit, and re-read the relevant
> section whenever you are about to deviate from what it shows.
>
> If you find yourself reasoning "this rule probably doesn't cover my case" or
> "the surrounding code / a doc-comment example does it this way", that is exactly
> when to open this file and check. Both of those rationalisations have produced
> real style violations that reviewers then had to catch by hand.

Essential C# conventions for Skyline. See [ai/docs/style-guide.md](docs/style-guide.md) for comprehensive details and [ai/CRITICAL-RULES.md](CRITICAL-RULES.md) for absolute constraints.

**Universal AI Guidelines**: This file serves as the style guide for all AI tools (Cursor, Claude Code, GitHub Copilot, ChatGPT, etc.).

## Critical Style Rules

See [ai/CRITICAL-RULES.md](CRITICAL-RULES.md) for full list. Key style rules:

### File Format
- **Line endings**: CRLF (`\r\n`) - Windows standard
- **Indentation**: Spaces only (no tabs)
- **Blank lines**: Must be completely empty (no spaces/tabs)
- **Characters**: Prefer ASCII over Unicode

### Naming Conventions
- Private fields: `_camelCase`
- Constants: `ALL_CAPS_WITH_UNDERSCORES`
- Types/namespaces: `PascalCase`
- Interfaces: `IPascalCase`
- Enum members: `snake_case`
- Locals/parameters: `camelCase`

### Control Flow
```csharp
// ❌ BAD - single-line if
if (condition) DoThing();

// ✅ GOOD - separate lines, single-line body
if (condition)
    DoThing();

// ✅ GOOD - with braces
if (condition)
{
    DoThing();
}

// ❌ BAD - multi-line body without braces
if (condition)
    throw new ArgumentException(
        string.Format(@"Message: {0}", value));

// ✅ GOOD - braces required when body spans multiple lines
if (condition)
{
    throw new ArgumentException(
        string.Format(@"Message: {0}", value));
}
```

**Rule**: A braceless body is only allowed when the body is a **single line**.
If the body spans multiple lines, always add braces.

**This applies to every statement that can take a braceless body**, not just
`if`/`else`: `using`, `foreach`, `for`, `while`, `do`, `lock`, and `fixed`.

The trap is a body that *reads* as one statement but spans many lines — most
often a `using` wrapping a parallel loop. One call, thirty-five lines, no braces:

```csharp
// ❌ BAD - one statement, but the body spans 35 lines
using (var progress = new ProgressReporter("Scoring windows", windows.Count))
    Parallel.ForEach(windows, new ParallelOptions { MaxDegreeOfParallelism = n },
        () => CreateScorer(),
        (kvp, loopState, scorer) =>
        {
            // ... 30 more lines ...
            return scorer;
        },
        scorer => { });

// ✅ GOOD - braces, because the body spans multiple lines
using (var progress = new ProgressReporter("Scoring windows", windows.Count))
{
    Parallel.ForEach(windows, new ParallelOptions { MaxDegreeOfParallelism = n },
        () => CreateScorer(),
        (kvp, loopState, scorer) =>
        {
            // ... 30 more lines ...
            return scorer;
        },
        scorer => { });
}
```

Adding the braces costs a re-indent of the body. **Take the bigger diff** — diff
size is not a reason to leave a multi-line body braceless.

Beware doc-comment examples that show the braceless form: they are usually
demonstrating a genuinely one-line body. Copy the *rule*, not the shape.

### File and Member Ordering

**Order members from high-level to low-level (like a document: introduction before details):**

1. static variables/fields
2. static public methods
3. private instance fields
4. constructor(s)
5. public methods/properties
6. **private helper methods (AFTER the public methods that use them)**

**CRITICAL**: C# is not C/C++ - helpers go LAST, not first:
- ✅ Main method first → helpers below (reader sees PURPOSE, then DETAILS)
- ❌ Helpers first → main method last (old C style - forces backward reading)

### Using Directive Ordering
**System and Windows namespaces come first**, then external libraries, then project namespaces (not strictly alphabetical):
```csharp
// ✅ GOOD - System namespaces first, then external libraries, then project namespaces
using System;
using System.Collections.Generic;
using System.IO;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Newtonsoft.Json;
using pwiz.Common.SystemUtil;
using pwiz.Skyline;
using pwiz.Skyline.Model;
```

**ReSharper setting**: "Place 'System.*' and 'Windows.*' namespaces first when sorting 'using' directives" is enabled.

### Array Literal Type Inference

**Prefer `new[] { ... }` over `new T[] { ... }`** when the element type can be
inferred from the initializer. ReSharper flags the explicit form as
`RedundantExplicitArrayCreation`.

```csharp
// ❌ Avoid - redundant explicit type
var mzs = new double[] { 500.25, 600.37, 700.48 };
var ids = new int[] { 1, 2, 3 };
var scores = new float[] { 0.9f, 0.8f, 0.7f };

// ✅ Prefer - inferred element type
var mzs = new[] { 500.25, 600.37, 700.48 };
var ids = new[] { 1, 2, 3 };
var scores = new[] { 0.9f, 0.8f, 0.7f };
```

**Only keep the explicit type when needed**:
- Type cannot be inferred (e.g. mixed numeric types that must widen):
  `new double[] { 1, 2.5 }` keeps the `double[]` so `1` is not treated as `int`.
- Array element type must differ from the inferred type (covariance, interface):
  `new IFoo[] { concreteFoo }`.
- Empty array literals: `new int[0]` or `Array.Empty<int>()`.

**Why this matters for tests**: expected-value arrays (`new double[] { ... }`)
are especially common in unit tests; the redundant form spreads quickly across
a test suite if not caught early.

## Resource Strings (Localization)

**CRITICAL**: ALL user-facing text must be in .resx files.

```csharp
// ❌ NEVER - string literals for UI
MessageBox.Show("File not found");

// ✅ ALWAYS - resource strings
MessageBox.Show(Resources.ErrorMessage_FileNotFound);
```

**Workflow:**
1. Add string to `pwiz_tools/Skyline/Menus/MenusResources.resx`
2. Add corresponding property to `.Designer.cs` file
3. Keep properties in alphabetical order
4. Build to verify no CS0117 errors

**Note:** When viewing `.ja.resx` and `.zh-CHS.resx` files (Japanese/Chinese translations), UTF-8 encoding must be configured for characters to display correctly. Developers who followed `ai/docs/developer-setup-guide.md` already have permanent UTF-8 configured in their PowerShell profile.

## Asynchronous Programming

**CRITICAL**: DO NOT use `async`/`await` keywords.

```csharp
// ❌ NEVER
public async Task DoWorkAsync() { await Task.Run(...); }

// ✅ ALWAYS - use ActionUtil.RunAsync()
ActionUtil.RunAsync(() => { /* background work */ });

// In Common libraries (pwiz_tools/Shared/)
CommonActionUtil.RunAsync(() => { /* background work */ });
```

## Error Handling and Diagnostics

### Debug.WriteLine for Development Diagnostics
```csharp
using System.Diagnostics;

catch (Exception ex)
{
    // Ignore but log to debug console in debug builds
    Debug.WriteLine($@"Failed to connect: {ex.Message}");
}
```

**Note**: Use `$@""` format (verbatim interpolated string) to avoid ReSharper localization warnings.

### Non-Localizable Text
For debugging-only strings (ToString(), internal exceptions):
```csharp
// Text for debugging only
public override string ToString() => $@"Connection[Host={_host}]";

// Exception text for internal diagnostics, not displayed to user
throw new InvalidOperationException($@"Invalid state: {_state}");
```

## File Headers and AI Attribution

All source files should include:
```csharp
/*
 * Original author: [Author Name] <[email] .at. [domain]>,
 *                  [Affiliation]
 * AI assistance: [Tool] ([Model]) <[email]>
 *
 * Copyright [Year] University of Washington - Seattle, WA
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * ...
 */
```

**AI attribution formats**:
- Cursor: `Cursor (Claude Sonnet 4) <cursor .at. anysphere.co>`
- Claude Code: `Claude Code (Claude Opus 4.5) <noreply .at. anthropic.com>`

**Always include AI assistance line** when code is created/modified with AI tools.

## Comments and XML Documentation

**CRITICAL**: Comments should start with a capital letter (especially imperative sentences). True sentences should end with a period. Use `<see cref="ClassName">` for class references in XML docs.

**CRITICAL**: In comments and string literals, use a single ASCII hyphen `-` for any dash. This bans two things:
- **Unicode dashes** (em dash `U+2014`, en dash `U+2013`): visually indistinguishable in many UIs but cause encoding issues. Avoid all characters above ASCII 127 unless required by the domain.
- **Double hyphen `--` used as an em-dash substitute** in prose comments (e.g. `// foo -- bar`). Human comments use a single `-`; a `--` is an LLM tell, and inside XML/Razor/Jam comments (`<!-- -->`) a literal `--` is a parse error. Write `// foo - bar` instead. (This does not apply to real code: the C# `--` operator, CLI flags like `--task`, or `--` inside a quoted string are fine.)

See [ai/docs/style-guide.md](docs/style-guide.md) for detailed guidelines and examples.

## User Interface Guidelines

### Menu Items
- All items in `menuMain` should have mnemonics (e.g., `&File`)
- Menu text uses title-case (e.g., "Keyboard Shortcuts")
- Only `menuMain` items should have mnemonics and shortcuts
- Context menus: no mnemonics or shortcuts

## Testing Guidelines

See [ai/TESTING.md](TESTING.md) for comprehensive testing guidelines. Key rules:

- **NEVER** use English text literals in test assertions
- **ALWAYS** use resource strings for expected text
- **ALWAYS** use `AssertEx.Contains()` not `Assert.IsTrue(string.Contains())`
- **ALWAYS** consolidate functional test validations into private methods

## Tools and Quality

- Visual Studio 2022 + ReSharper
- Aim for zero warnings
- ReSharper must show green (no inspections)
- Build guide: https://skyline.ms/wiki/home/software/Skyline/page.view?name=HowToBuildSkylineTip

## Executables Solutions

Projects under `pwiz_tools/Skyline/Executables` are independent solutions. They:
- Are NOT built by `Skyline.sln`
- Inherit repository-wide `.editorconfig` for C# naming/formatting
- Prefer Skyline conventions unless local project requires override
- Can add minimal project-level `.editorconfig` if needed

## See Also

- [ai/docs/style-guide.md](docs/style-guide.md) - Comprehensive style guide with examples
- [ai/CRITICAL-RULES.md](CRITICAL-RULES.md) - All absolute constraints
- [ai/TESTING.md](TESTING.md) - Testing conventions and patterns
- [ai/MEMORY.md](MEMORY.md) - Project context and common gotchas
