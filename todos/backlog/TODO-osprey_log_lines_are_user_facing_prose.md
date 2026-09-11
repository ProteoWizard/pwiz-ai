# TODO-osprey_log_lines_are_user_facing_prose.md - superseded

**Superseded 2026-09-11 by `ai/todos/backlog/brendanx67/TODO-osprey_log_readability.md`**,
which carries the full line-by-line review (583 call sites), Brendan's decided vocabulary,
the machine-channel rule for scripts and tests, and the implementation plan. Its companion
files (`-spec.html`, `-lines.csv`, `-terms.csv`) sit beside it.

The ask that started this, kept for the record (2026-09-09, after
`Reading scored rows from N file(s) for first-pass FDR` had shipped for review as
`Building the first-pass projection from N file(s)`):

> "Probably, I should add to my list a review of all logged lines to make sure they are coherent
> user-facing descriptions and not just parroting the names given to classes in the code, a
> common pitfall for programmers."

The test it proposed - name the WORK, not the type or method; say the scale; prefer the
vocabulary of the domain and the CLI over the implementation's - is now rule 5 and the
glossary of the superseding TODO.
