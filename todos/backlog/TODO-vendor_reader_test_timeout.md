# TODO-vendor_reader_test_timeout.md

## Branch Information
- **Branch**: (to be created when work starts)
- **Base**: `master` (pwiz)
- **Created**: (pending)
- **Status**: Backlog
- **PR**: (pending)
- **Objective**: Add a per-test timeout so a hung vendor-reader test (e.g. `Reader_Agilent_Test`) fails fast and names itself, instead of hanging the whole `Core Windows x86_64` (bt83) build ~47-60 min until a human kills it.

## Background / the incident

Surfaced while merging the OspreySharp -> Osprey rename (pwiz PR #4335,
2026-06-27). The `Core Windows x86_64` (bt83) CI build on `pull/4335`
(build #21327, ID 4067832) ran ~60 min and was forcibly terminated. It was
NOT caused by that PR (the rename is .NET-only; bt83 builds the C++ core).
The build compiled fine -- it produced and uploaded the release binaries
(`pwiz-bin-...-4f2193b.tar.bz2`, `pwiz-setup-...4f2193b.msi`) -- then hung
in the Step 2/5 unit-test phase.

This is an intermittent, long-standing flake (multiple recent bt83 failures
across different agents -- cloud `pwiz-windows-i-*` and `MacCoss TeamCity
Agent 1` -- so it is the test suite, not one bad agent).

## Root cause

The Agilent vendor-reader test, `Reader_Agilent_Test`, intermittently HANGS
or FAILS. It drives the Agilent MassHunter / MHDAC .NET vendor DLLs (COM
init, registration, runtime IO), which are unreliable on CI agents -- the
classic pwiz vendor-reader flake.

Evidence:
- Build 4067832 (the 60-min hang): last log output at 17:11:27 (BiblioSpec
  tests), then ~47 min of total silence; TeamCity's process dump at
  termination (17:58:47) shows the live/hung process was
  `...\pwiz\data\vendor_readers\Agilent\Reader_Agilent_Test.test.test\...`
  (PID 20364).
- Build 4021591 (#21023, a different failure): same test FAILED --
  `...failed testing.capture-output ...\Agilent\Reader_Agilent_Test.run`
  -> `Changed build status to failed due to build problem: TC_FAILED_TESTS_bt83`.

So the same test is the destabilizer in both failure modes (hang and fail).

## Impact

- A hang burns ~47-60 min of a scarce Windows agent, blocks the queue
  (e.g. it delayed the Osprey configs behind it on the only Osprey-capable
  agent), and requires a human to notice and forcibly terminate it.
- It adds noise: a 60-min "interrupted" failure looks alarming and takes
  log-sleuthing to attribute to a flaky vendor DLL.

## Proposed solution: a per-test timeout launcher

Make a hung test self-identify and die fast. Per-test granularity (not a
whole-build timeout) so the failure names the offending test.

**Normal timing (for sizing the timeout):** from a build that actually ran
the tests, the entire vendor-reader suite ran ~20:08:26 -> 20:12:13
(< 4 min total); individual readers take seconds to ~1.5 min (ABI and
Bruker are the slowest); Agilent normally finishes in seconds. So a 5-minute
(300 s) per-test timeout never touches a healthy test yet catches a hang
~10x faster. Could tighten to 3 min if desired.

**Mechanism / injection point.** Boost.Build (vendored at
`libraries/boost-build/src/tools/`) launches every test via the LAUNCHER
slot in the `capture-output` and `unit-test` actions
(`testing-aux.jam` line ~195: `$(LAUNCHER) "$(>)" $(ARGS) ... > out 2>&1`).
`<testing.launcher>` (defined `testing.jam:63`, free/optional) is prepended
to that command. That is the clean hook.

**Why scope it to vendor-reader tests, not globally.** `python.jam` already
"hijacks" `<testing.launcher>` to set `PYTHONPATH` for python tests
(`python.jam:992,1011`), so a naive GLOBAL launcher would collide and break
python tests. The vendor-reader tests are NOT python tests, and they are
exactly where the flake lives -- so scope the timeout launcher to them and
avoid the collision and the broad blast radius.

**Implementation sketch:**
1. Add a small cross-platform wrapper (pwiz already builds with Python),
   e.g. `pwiz/data/vendor_readers/test-timeout.py <seconds> <exe> [args...]`:
   - run the test exe (forwarding stdout/stderr -- Boost.Build redirects them
     to the output file),
   - on timeout, **kill the whole process tree** (critical: MHDAC spawns
     .NET children; killing only the parent leaves them running),
   - print a clear, greppable line: `TIMEOUT: <test> exceeded <N>s`,
   - exit non-zero so bjam marks the test failed (TC_FAILED_TESTS).
2. Attach it ONCE via `<testing.launcher>` in the parent
   `pwiz/data/vendor_readers/Jamfile.jam` project requirements so every
   `Reader_*_Test` inherits it -- no per-reader edits. The Agilent test is
   declared with `run-if-exists` in
   `pwiz/data/vendor_readers/Agilent/Jamfile.jam` (target `Reader_Agilent_Test`);
   the other readers follow the same pattern under
   `pwiz/data/vendor_readers/*/Jamfile.jam`.
3. Value: 300 s (5 min) to start.

## Validation

- Unit-test the wrapper standalone: a fast command passes through unchanged
  (exit 0, output intact); a sleeping/hanging command is killed at the limit
  with a non-zero exit and the TIMEOUT line; verify child processes are gone.
- Then a full bt83-equivalent build (the change touches test execution, so it
  must not perturb passing tests). Confirm a normal run is unaffected and an
  artificially-hung vendor test now fails at the timeout instead of hanging.

## Alternatives considered

- **Global per-test timeout** by wrapping the command inside the
  `capture-output`/`unit-test` actions in `testing-aux.jam`. Catches ANY
  hanging test, but: bigger blast radius (edits vendored Boost.Build,
  affects every test), must compose with python.jam's launcher use, and
  needs a more generous value (~10 min) to not flake the slowest legitimate
  non-vendor test. Reasonable as a later generalization once the
  vendor-scoped version is proven.
- **TeamCity build-execution timeout** on bt83 (~30 min). Trivial, no code,
  but coarse -- it kills the whole build, not the specific test, so it does
  not "name the culprit" and still wastes up to 30 min. Useful only as a
  backstop.
- **Quarantine / retry** `Reader_Agilent_Test` (or move the vendor-reader
  tests out of the per-commit gate into a nightly/dedicated config) so a
  flaky vendor DLL does not red-X every PR. Orthogonal to the timeout and
  could be combined with it.

## References

- pwiz PR that surfaced it: #4335 (OspreySharp -> Osprey rename); the bt83
  hang there was an unrelated flake (decision: ignore it for that PR).
- Builds: 4067832 (hang, terminated), 4021591 (#21023, Agilent test failed).
- Code: `libraries/boost-build/src/tools/testing-aux.jam` (actions, ~line 195),
  `libraries/boost-build/src/tools/testing.jam` (`testing.launcher` feature,
  line 63; LAUNCHER flags lines 515 & 779), `libraries/boost-build/src/tools/python.jam`
  (launcher hijack, ~line 992), `pwiz/data/vendor_readers/Jamfile.jam` (parent;
  proposed injection point), `pwiz/data/vendor_readers/Agilent/Jamfile.jam`
  (`Reader_Agilent_Test` declaration).
