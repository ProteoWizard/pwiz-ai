# TODO-osprey_log_lines_are_user_facing_prose.md - audit every logged line for whether it describes the WORK

**Module**: `osprey`
**Status**: Backlog
**Raised**: 2026-09-09, developer, after `Reading scored rows from N file(s) for first-pass FDR`
had shipped for review as `Building the first-pass projection from N file(s)`.

## The ask

> "Probably, I should add to my list a review of all logged lines to make sure they are coherent
> user-facing descriptions and not just parroting the names given to classes in the code, a
> common pitfall for programmers."

## Why it is worth doing rather than fixing case by case

The failure is systematic, not incidental: a log string is written by whoever is inside the
class, and the class's own name is the nearest word to hand. It reads as informative to the
author for exactly the reason it is opaque to the reader - the author already knows what
`FdrProjectionSet` is. Nothing in review catches it, because the line is *accurate*.

The instance that prompted this: a progress bar was named "building the first-pass projection",
which is the type's name. What it DOES is read every scored row of every file so first-pass FDR
has something to compete over - and that is what an operator waiting ten minutes needs to see.
The developer's response was simply that the phrase "is not inherently a meaningful phrase to
me", which is the whole test.

## Scope (measured 2026-09-09, `pwiz_tools/Osprey`)

| surface | sites |
|---|---|
| `ProgressReporter` labels | 67 |
| `LogInfo` | 218 |
| `LogWarning` | 86 |
| `LogError` | 49 |

**Start with the 67 progress labels.** They are the highest value per line - a progress bar is
read by someone who is WAITING, and it is the only thing standing between a long phase and
"is this hung?". They are also a closed, enumerable set, so the pass is finite.

Errors and warnings are the second tier and have a sharper test than prose quality: does the
line name what failed, in the operator's vocabulary, and what to do about it.

## The test to apply

For each line, ask what a person watching the run is waiting for, and whether the line answers
it. Concretely:

* Name the WORK, not the type or method. "Reading scored rows from 446 file(s)", not
  "Building the FdrProjectionSet" / "Running BuildFromEntries".
* Say the SCALE where there is one - `from N file(s)` turns "wait" into "wait this long".
* Prefer the vocabulary of the domain and the CLI (runs, files, scored rows, survivors,
  reconciled boundaries) over the vocabulary of the implementation (projection, buffer,
  milestone, byproduct, stub).
* An identifier is fine in a DIAGNOSTIC aimed at a developer (`[MEM ...]`, `[STAGE-WALL]`);
  the rule is for lines on the ordinary path.

## Related

Not the same as the reporting-GAP problem (a phase that logs nothing at all), which is
`TODO-20260909_osprey_projection_scan_progress.md`. The two travel together though: both are
found by watching a real run rather than by reading code, and both are invisible at
regression-gate scale.
