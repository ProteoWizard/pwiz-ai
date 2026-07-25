# TODO-osprey_env_settings_registry.md -- Formalize OSPREY_* env settings: validated registry + --help-settings

## Status
**Backlog / not started.** No branch yet. Raised by Brendan during the PR #4446 review
(2026-07-23): the growing `OSPREY_*` env-var surface is "a backdoor to command-line argument
parsing" that lacks the rigor CommandArgs already provides.

## Problem
Osprey has two config surfaces with very different rigor:
- **CommandArgs** (formal): from Skyline, pulled into `pwiz_tools\Shared\PortableUtil` to share with
  Osprey. Enumerated allowed values, a printed `--help` table, auto-error on an unrecognized value,
  localized descriptions.
- **`OspreyEnvironment`** (informal): ~20 `Environment.GetEnvironmentVariable` reads as scattered
  `static readonly` fields, string-compared, **silent fallback** on an unrecognized value, no
  registry, no table, no discoverability. PR #4446 alone adds ~15 (9 `OSPREY_GBT_*`, the pick vars,
  `OSPREY_MAX_TRAIN_SIZE`, `OSPREY_PROTEIN_COMPACT_RETRAIN`, ...).

Concrete symptom: `OSPREY_PASS2_QVALUE=transfer-complete` (a natural mistype of the real
`transfer-compete`, which Mike himself made in email) **silently** falls back to the anti-conservative
`percolator` retrain on Rust (C# at least warns). A whole class of typo/enum bugs has no guard.

## Proposal (proportionate -- mirror CommandArgs' guarantees, not its UI/localization weight)
1. **Lightweight registry.** Each setting is a declared `OspreySetting<T>` (name, type, allowed values
   for enums, default, one-line description) instead of a bare env read. Parsing routes through the
   registry.
   - **First deliverable (do this even if nothing else): HARD-FAIL on an unrecognized name or an
     out-of-set enum value** -- fixes the whole class, not just `OSPREY_PASS2_QVALUE`. (Brendan:
     "I would hard fail on transfer-complete or anything that doesn't match the 3 possibilities.")
     Apply on BOTH impls (Rust `pass2_mode()` currently `_ => Percolator` silently).
2. **`--help-settings`** (or similar): print the registered table, exactly like the arg table. Falls
   out for free once the registry exists. Invaluable for dev sessions -- today there is no way to
   enumerate the knobs.
3. **Keep the two surfaces distinct on purpose.** CLI args = user-facing / supported / documented;
   env settings = experimental / dev levers. That separation is WHY these are env vars; the registry
   preserves it (e.g. `--help-settings` hidden from the main `--help`).
4. **Graduation lifecycle.** Mark each setting `experimental | promoted`. When a lever becomes a
   default (protein-compact, LDA pick, frozen model -- see
   [[project_osprey_pass2_default_flip_and_confidence_axes]]), it either graduates to a real
   CommandArgs option (if users should control it) or the env var demotes to an escape-hatch
   override. The registry makes that lifecycle explicit instead of ad-hoc.

## Scope / sequencing
Its own small PR, NOT part of #4446. Fits the "organic growth -> periodic structural cleanup" pattern
([[project_osprey_organic_growth_needs_iterative_oop_review]]). Coordinate the hard-fail behavior
across C# + Rust so parity holds. Cross-check that no test or script relies on the current silent
fallback for an intentionally-unrecognized value.

## References
- `Osprey.Core/OspreyEnvironment.cs` (the informal surface); CommandArgs in
  `pwiz_tools\Shared\PortableUtil`.
- [[project_ospreysharp_output_architecture]], [[project_osprey_organic_growth_needs_iterative_oop_review]]
