# Catalog Osprey's environment-variable switches the way CommandArg catalogs CLI arguments

**Status**: Backlog. Raised by Brendan 2026-08-29, during the phase-1 FDR-sidecar-split session.
**Related**: [#4486](https://github.com/ProteoWizard/pwiz/issues/4486) (the session that prompted it)

## The idea

Osprey has a deliberate TWO-LEVEL system for controlling behavior:

* **CLI arguments** - user-facing, catalogued by `CommandArg`, discoverable through `--help`.
* **Environment variables** - the switches judged most likely to be debugging-only, which is why
  they were relegated off the command line.

The second level is extensive (~35 `OSPREY_DUMP_*` / `OSPREY_DIAG_*` gates today, plus behavior
switches like `OSPREY_PASS2_QVALUE`, `OSPREY_EXPERIMENT_AGG`, `OSPREY_PASS2_NO_RECALIBRATE`) and
has NO catalog at all. Brendan: *"We have created a 2-level system for controlling Osprey
behavior and relegated what we feel are most likely debugging switches to env vars, but they are
extensive and could use better cataloging since we have decided to keep them."*

## Shape of the work

Small and mechanical, per Brendan:

1. Extract a **`CommandArg` base class** carrying the common cataloging members (name,
   description, value shape, grouping).
2. Add an **`EnvVar` derived class** for the environment-variable level.
3. Build the **entry table** - one registration per switch, replacing the scattered
   `IsSetAndNotZero(@"OSPREY_...")` reads in `OspreyEnvironment`, `FdrDiagnostics` and
   `OspreyFileDiagnostics`.
4. Add a **`--help-env`** CLI argument that prints the table in the same format `--help` uses for
   arguments.

## Why it earns its place

**The decision to keep the env vars just paid off, and their poor discoverability just cost.**
In the 2026-08-29 session a golden-moving defect resisted two rounds of hypothesis-and-test.
What closed it in one cycle was `OSPREY_DUMP_RESCORED=1` on the branch and on the baseline
commit, diffing the two `cs_stage6_rescored.tsv` dumps: 8,791 rows differed, all in the
experiment-scope columns, `base=1` vs a real value on the branch - which named the defect
(gap-fill stubs receiving experiment values they were not entitled to) immediately.

The switches were there the whole time. They were not found by reading any doc; they were found
because Brendan said "there are also many existing diagnostics under environment variables". A
`--help-env` would have surfaced them in seconds.

## What a catalog unlocks beyond `--help-env`

* **`regression.ps1` can point at an authority instead of duplicating one.** A companion change
  (see the same session) adds a `-Dump <Name>` switch plus a discoverability hint printed with
  `-KeepOutput`. Without a catalog that hint has to name SOURCE FILES to look in; with one it can
  say "run `Osprey --help-env`". This repo has a documented history of hand-maintained lists
  going stale - the TeamCity config doc claimed "mode1/2/3" for months after modes 4-6 existed -
  so a second hand-maintained list is a liability, and a generated one is not.
* **Grouping by kind.** The env vars are not one population: pure DIAGNOSTIC dumps (output-only,
  safe anywhere), BEHAVIOR switches that change reported numbers (`OSPREY_PASS2_QVALUE`,
  `OSPREY_EXPERIMENT_AGG`), and ALLOWANCES that relax a gate. Those deserve visibly different
  treatment - `ai/docs/osprey-development-guide.md` already notes that an ambient allowance on a
  standing gate can only mask the regression the gate exists to catch, and that a blanket
  `OSPREY_ALLOW_UNBOUNDED_MEMORY=1` once let a `transfer` regression ride along for ten days.
* **A run's provenance becomes checkable.** A catalog makes it cheap to log every non-default
  env switch at startup, so a log answers "what arm was this run?" without inference. Some of
  this exists ad hoc today (the `OSPREY_PASS2_QVALUE` banner); a table makes it uniform.

## Notes for whoever picks it up

* The authoritative reads are currently spread across at least `Osprey.Core/OspreyEnvironment.cs`,
  `Osprey.FDR/FdrDiagnostics.cs` and `Osprey/OspreyFileDiagnostics.cs`. Enumerate with
  `grep -rho 'OSPREY_[A-Z0-9_]\+' --include=*.cs pwiz_tools/Osprey | sort -u`.
* Keep the registration next to the read, not in a central file that has to be remembered - the
  whole point is that the catalog cannot drift from the behavior.
* This is cataloging only. Do NOT promote debugging switches to CLI arguments as part of it; the
  two-level split is deliberate.

## Enforcement, so the catalog CANNOT rot (Brendan, 2026-08-29)

The design above is worth more than a catalog, because the pieces to make it self-enforcing are
already in place. **All env vars are already surfaced through a single class by rule.** Turn that
rule into a verifier and the drift concern disappears rather than being managed:

1. **A test that forbids direct environment access outside one accessor.** Exactly the shape of
   the existing `TestNoUnstableSort`, which scans production sources for `Array.Sort` /
   `List<T>.Sort` and fails with a message naming the file, the line and the cure, with an inline
   `// Array.Sort OK: <reason>` escape hatch. The analogue scans for
   `Environment.GetEnvironmentVariable` / `SetEnvironmentVariable` and allows exactly one call
   site: the accessor itself.

2. **A single accessor that THROWS for any name not in the table.** This is the part that makes
   rot extremely challenging rather than merely discouraged: an env var that is not registered
   does not read empty and quietly take the default path - it fails immediately and loudly. The
   guard works in both directions, so it also catches a switch DELETED from the table while code
   still reads it, and a typo in a name (today `OSPREY_DUMP_RESCORD` would silently mean "off"
   forever).

3. **A test that every entry carries a group and a description**, so entries cannot be added as
   bare names and `--help-env` output cannot degrade into a list of identifiers.

Together these make the table the single source of truth BY CONSTRUCTION: documentation cannot
drift from behavior, because undocumented behavior does not run.

This is `ai/CRITICAL-RULES.md`'s own framing applied to a rule that currently has no verifier:
*"Every rule below is intended to be enforced by a build, a test, or an inspection - not by the
model reading and remembering. When a rule's verifier is weak, the rule will drift; strengthen
the verifier rather than the wording."* The "surface all env vars through one class" rule is
today enforced only by convention.

**Evidence that this class of verifier works, from the session that raised this**: the
`TestNoUnstableSort` gate fired on a new `Array.Sort(ids)` added to `FdrExperimentSidecar` within
minutes of it being written, and forced an explicit justification
(`// Array.Sort OK: distinct entry_ids, so the comparison never ties`) rather than a silent
assumption. That is precisely the interaction wanted here - not a reviewer noticing later, but
the build refusing until the author states the case.

### Make #2 and #3 STRUCTURAL, not tests (Brendan, 2026-08-29)

Prefer the CommandArgs shape: the supporting class reads by TABLE LOOKUP, and the only way into
the table is an interface that REQUIRES the grouping (and description). Then a badly-formed
accessor cannot be written in the first place, rather than being written and later caught:

* **#2 (unregistered access) becomes unreachable.** There is no API that reads an env var by raw
  name, so "read something not in the table" is not an expressible program. Keep the throw as a
  cheap backstop, but it guards an impossibility rather than carrying the enforcement.
* **#3 (group + description) becomes a constructor requirement.** An entry that omits them does
  not compile. The test that checks for them is then belt-and-braces, not the mechanism.

That leaves exactly ONE thing genuinely needing a test - **#1, the source scan** - because
"nobody calls `Environment.GetEnvironmentVariable` directly" is the one property the type system
cannot express. Same division `CommandArg` already lives with.

This is the stronger form of the rule in `ai/docs/validation-cycle-principles.md`: a verifier that
makes the mistake impossible beats one that detects it.

### Open question: is there a description check for CommandArgs today?

Skyline stores `CommandArg` descriptions in RESX and finds them by NAME ASSOCIATION rather than
by an explicit link, so "every registered arg has a description" is a property that can silently
fail. Brendan is not sure Skyline checks it - and Skyline has a lot of checking of exactly this
kind, so it may already exist.

**Check first, then decide**: if such a test exists, mirror it for `EnvVar` and reuse the
mechanism. If it does not, that is a small gap worth closing for BOTH levels in one go, since the
same association pattern is what would be adopted here.

**Related decision to make explicitly, not by default**: whether `--help-env` descriptions are
user-facing text and therefore RESX-bound. `ai/CRITICAL-RULES.md` requires resource strings for
user-facing text, but these are debugging switches deliberately kept off the command line and
aimed at developers. Deciding this by analogy to `--help` (which IS user-facing) may over-apply
the rule; deciding it by "these are developer switches" may under-apply it. Worth an explicit
call at design time rather than discovering it in review.

### CORRECTION: for env vars there is no runtime "unknown" case at all (Brendan, 2026-08-29)

The framing above ("the accessor THROWS for any name not in the table") borrowed from CommandArgs
and is wrong for this level. The two are not symmetric:

* **CommandArg**: the unknown name is supplied by the USER at runtime. A runtime "unknown
  argument" error is the only thing available, and it is correct.
* **EnvVar**: access is entirely a PROGRAMMING-TIME construct. The code chooses which names it
  reads; a user cannot hand us an environment variable the code must respond to. So an
  unregistered name is a **compile-time name-not-found error** - you referenced an entry that
  does not exist - and there is no runtime unknown-name path to guard.

That makes this level structurally STRONGER than CommandArgs, not merely equal to it. Drop the
runtime throw; it guards nothing reachable.

**Two different typos, which the earlier text ran together:**

| typo | where | caught by |
|---|---|---|
| `EnvVars.DumpRescord` in C# | programming time | compile error - the entry does not exist |
| `set OSPREY_DUMP_RESCORD=1` in a shell | the user's environment | NOTHING today - reads as "off" forever |

The second is the one that actually bit in practice, and the table makes a real fix possible:

### Optional, and it depends on claiming the namespace

**If** we decide that any `OSPREY_`-prefixed variable is ours to interpret, then a startup scan of
the environment for `OSPREY_*` names absent from the table becomes meaningful - and an "unknown
variable" message makes sense again, at the layer where the unknown genuinely originates:

```
OSPREY_DUMP_RESCORD is not a recognized Osprey environment variable. Did you mean
OSPREY_DUMP_RESCORED?  (run --help-env for the full list)
```

That turns a switch which silently does nothing into an immediate, self-correcting message. It is
worth noting it costs a NAMESPACE DECISION: claiming `OSPREY_*` means a user cannot keep private
scratch variables under that prefix without being warned at them. Decide that deliberately - a
warning rather than an error is probably the right severity, since the cost of being wrong is
noise rather than a failed run.
