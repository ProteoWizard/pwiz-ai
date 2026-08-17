# TODO-20260816_alphapeptdeep_xxhash_pin.md

## Branch Information
- **Branch**: `Skyline/work/20260816_alphapeptdeep_xxhash_pin`
- **Base**: `master`
- **Created**: 2026-08-16
- **Status**: In Progress
- **GitHub Issue**: (none)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Fix the nightly failure in `TestAlphaPeptDeepBuildLibrary`, which began failing
after an upstream Python dependency published a breaking change.

## Root Cause

Not a Skyline regression, and not a change in Python or AlphaPeptDeep. The break
is in a transitive dependency two levels down: peptdeep -> alphabase -> xxhash.

- python-xxhash 4.0.0 (released 2026-08-12) stopped accepting `str` and now
  requires `bytes`, raising `TypeError: Strings must be encoded before hashing`.
- `alphabase/peptide/precursor.py` `hash_mod_seq_df` passes raw `str` sequences
  to `xxh64_intdigest`. That line is unchanged since July 2024.
- alphabase's install-time requirements (`requirements_loose.txt`) list a bare,
  uncapped `xxhash`, and Skyline installs `peptdeep` unpinned, so the first
  fresh env built after 2026-08-12 resolved to 4.0.0 and broke.

The failure surfaces as `peptdeep cmd-flow` exiting 1 during `save_hdf`, then a
Skyline MessageDlg that the test times out waiting for.

Upgrading AlphaPeptDeep does not help: the nightly already installs the newest
peptdeep (1.5.1) and alphabase (1.9.1, released 2026-08-06). No release fixes
the unencoded hash call, and `main` still has it.

## Fix

`pwiz_tools/Skyline/Model/Lib/AlphaPeptDeep/AlphapeptdeepLibraryBuilder.cs` -
pin `xxhash` to 3.5.0 in `CreatePythonInstaller`, the version alphabase itself
pins in its own `requirements.txt`. Same pattern as the existing numpy 1.26.4
workaround: `PipInstall` installs in list order, so peptdeep pulls 4.0.0 and the
following entry downgrades it.

## Verification

- Build succeeded (Debug).
- `TestAlphaPeptDeepBuildLibrary` passes: 0 failures, 193 sec (en-US, offscreen,
  internet on). The test sets `IsCleanPythonMode => true`, so it deletes the
  tools Python directory and rebuilds the venv from scratch - the pin is really
  exercised, not short-circuited by the signed-directory check.
- Rebuilt venv contains `xxhash==3.5.0`, `alphabase==1.9.1`, `peptdeep==1.5.1`,
  `numpy==1.26.4`.
- Counterfactual confirmed: `pip install --dry-run xxhash` on the same Python
  3.9 still reports "Would install xxhash-4.0.0".

## Follow-up

- The pin comes out once alphabase encodes before hashing or caps `xxhash<4`.
  No upstream issue found for this; worth filing with MannLabs.
- Broader exposure: `peptdeep` is installed unpinned, so any package in that
  tree can break the nightly on any night. `peptdeep[stable]` would pin the
  whole tree, but it also pins `torch==2.5.1`, which would collide with the
  CUDA-specific torch install in `PythonInstaller.cs`. Separate decision.

## Notes

- Existing envs do not self-heal: `PipInstallPackagesTask.IsTaskComplete`
  returns true early when the venv directory is signed, before it checks any
  versions. The nightly builds its tools dir fresh per run, so it picks up the
  pin, but a dev machine with an already-signed AlphaPeptDeep env needs it
  deleted.
