# Detecting Failing Hardware in Nightly Test Results

Nightly test machines fail. When a CPU starts to go bad, Skyline's nightly runs are usually
the first thing to notice, weeks or months before anyone concludes the machine is broken.
Meanwhile its crashes look like Skyline bugs, and developers lose days investigating them.
Daily report sessions should spot this early and say so plainly, **before** anyone starts
debugging the code.

This guide is based on a September 2026 review of every early-ending nightly run on
skyline.ms since October 2017 (73,502 runs on 43 computers).

## The signal

TestRunner itself dying with a hardware-type exit code. In the run log:

```
# Process TestRunner had nonzero exit code -1073741819 (0xC0000005 STATUS_ACCESS_VIOLATION)
```

| Exit code | Hex | Name |
|---|---|---|
| -1073741819 | 0xC0000005 | ACCESS_VIOLATION (the common one) |
| -1073741795 | 0xC000001D | ILLEGAL_INSTRUCTION (almost never software in managed code) |
| -1073741571 | 0xC00000FD | STACK_OVERFLOW |
| -1073740940 | 0xC0000374 | HEAP_CORRUPTION |
| -1073740791 | 0xC0000409 | STACK_BUFFER_OVERRUN (also Windows fail-fast; weaker signal) |

Often preceded by `Internal CLR error. (0x80131506)` or `AccessViolationException`. That
means the .NET runtime found its own data corrupted, even when the stack shows plain
managed code.

**Crashes of programs the tests launch count too.** Native tools run by tests (Crux
percolator, search engines, converters) report the same codes inside a test failure, and
TestRunner survives:

```
Exit code: -1073741819 (0xC0000005 STATUS_ACCESS_VIOLATION)
```

A run can reach its full duration and still carry this signal. On SKYLINE-DEV6, a full
540-minute run after every vendor repair step still had `crux.exe percolator` crash with
an access violation. These tools are third-party native code shared by every machine, so
an access violation in them on one machine points away from a Skyline bug. Scan for
`Exit code: -1073741819` in failure text as well as TestRunner's own exit line.

On the machine itself, the Windows Application log (Event 1000) names the faulting module.
**The same runtime module crashing in unrelated programs is a strong hardware sign.** On
SKYLINE-DEV6 the .NET JIT (`clrjit.dll`, 0xc0000409) crashed in `TestRunner.exe` and, the
same morning, in `VBCSCompiler.exe` during the nightly build, which runs no Skyline code.

A crashed run ends early, so it shows in the report as `short (N min)`. Hard reboots
often post nothing at all, so a machine that starts **missing** runs belongs in the same
review.

## Hardware or software? Three questions

| Question | Points to failing hardware | Points to software |
|---|---|---|
| **Which machines?** | Only this machine crashed that day | 3+ machines crashed the same day (a shared-build bug) |
| **Which tests?** | Different, unrelated tests each time: whichever was running when the CPU erred | The same test (or sibling tests) every time |
| **When did it start?** | No code change explains it; machine-specific; often ramps up over weeks | Starts with a specific build/commit; stops when fixed |

**Hardware signature = solo crash days AND scattered, unrelated tests.** Both are needed:

- **SKYLINE-DEV6 (2026), failing i9-14900:** 17 solo crashes in 3 months across 16 different
  tests. Hardware, confirmed by the CPU's own machine-check errors.
- **BSPRATT-UW2 (2026), i7-6700:** 12 solo crashes, but all in two sibling DIA-QE
  full-search tutorial tests at the same point in the run. Solo days alone are not enough:
  a same-test pattern means look at that test and at the machine's resources (memory, disk)
  before blaming the CPU.

## What the fleet history shows

Since 2017, healthy machines have had **at most 8** hardware-type TestRunner crashes in
their whole history, most of them on the three shared-build days (2021-03-27,
2023-12-05, 2025-08-27; 3–6 machines each).

Sustained solo streaks (a dozen or more crashes in unrelated tests) have belonged to
machines whose hardware was failing:

| Machine (later name) | CPU | Streak | Outcome |
|---|---|---|---|
| JASON-XPS | i9-14900 | 32 crashes, Jul–Sep 2024, within 5 weeks of first testing | Returned to Dell |
| EDUARDO-DEV (→ BRENDANX-UW8) | i9-14900K | 32, Nov 2024 – Jan 2026 | CPU replaced |
| DSHTEYN-DEV01 (→ SKYLINE-DEV6) | i9-14900 | 65, May 2025 – Jan 2026; replacement CPU 23 more from May 2026 | Two CPUs failed |
| KAIPO-DEV | i7 | 34, 2021–2026 | Decommissioned |
| DONMARSH1 | i7-4770 (2013) | 32, 2018–2024 | Died |
| VSHARMA-PC | i7-6700 (2017) | 12, 2019–2020 | Died |

Note the renames: a machine's history may be split across computer names. Ask the user
if a new name has an unexplained pre-history.

**Intel 13th/14th-gen desktop CPUs (i9-13900/14900 family) are a known risk.** In this lab
four of six such chips started crashing within 5–16 weeks of sustained nightly testing,
including a replacement CPU. Treat solo crashes on these machines as hardware until shown
otherwise.

## What to do in the daily report

**Raise it at 2 solo crash days on one machine within 30 days, with unrelated tests.**
Don't wait for more; this is the stage where the lab has lost the most time.

1. **Run the scan** to see the machine's history and whether other machines crashed the
   same days:
   ```bash
   python ai/mcp/LabKeyMcp/scripts/scan_testrunner_crashes.py --since <90 days ago>
   ```
   It prints shared-build days and, per computer, labels the crashes with
   `HARDWARE PATTERN` (solo crashes in unrelated tests) or `SAME-TEST PATTERN`.
2. **Put it in the email Summary**, not just the Infrastructure section, for example:
   *"SKYLINE-DEV6: 3 TestRunner access violations in 8 days, each in a different test, no
   other machine affected. This matches failing hardware. Don't investigate these crashes
   as Skyline bugs; check the machine (WHEA errors, see below)."*
3. **Don't open GitHub issues** for crashes that match the hardware pattern, and **mark
   the machine's other one-off failures as suspect.** Unexplained failures and timeouts
   that occur only on that machine are part of the same picture. SKYLINE-DEV6's
   `TestDdaSearchTide` timeouts: 0 in 190 runs while its CPU was healthy, 17 after it began
   degrading.
4. **Name the next check for whoever sits at the machine:** CPU machine-check errors in the
   Windows event log:
   ```powershell
   Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-WHEA-Logger';Id=19} |
     Select TimeCreated, Message | Format-List
   ```
   "Processor Core / Corrected Machine Check / Internal parity error" concentrated on one
   APIC ID is the CPU reporting its own faults. Absence does not clear the machine:
   SKYLINE-DEV6's original CPU crashed 11 of 14 runs without logging any.
5. **Record it** in `suggested-actions-YYYYMMDD.md` under Infrastructure, and suggest
   `deactivate_computer` or a hardware check if the pattern continues.

## Machine acceptance test

The nightly suite is also the lab's acceptance test for hardware, for new machines and for
machines we want a vendor to fix. It has settled cases with Dell in days that otherwise
would have taken months of "run diagnostics and reinstall Windows."

**New machine:**
1. Set it up with [new-machine-setup.md](new-machine-setup.md) (or `/pw-configure`).
2. Run the nightly tests **21 hours a day for at least 2 days**: one standard run
   (9 hours) plus one perf or leak-detection run (12 hours) each day.

**Problem machine we want the vendor to address:**
1. Move everything of value off it, or onto its D: drive.
2. Reinstall Windows and set it up from scratch with
   [new-machine-bootstrap.md](new-machine-bootstrap.md).
3. Set it up with [new-machine-setup.md](new-machine-setup.md) (or `/pw-configure`).
4. Run the nightly tests 21 hours a day for at least 2 days, as above.

A clean Windows install removes "reinstall the OS" from the vendor's script before they can
ask for it. It also makes the comparison fair: a fresh machine running a suite that other
machines, many of them Dell, have passed for years.

**Results so far:**
- **January 2026:** run on three problem machines that developers had reported as flaky for
  months (spurious failures, blue screens). Two failed with the hardware signature: SKYLINE-DEV6
  (Windows installed Jan 8, failed within a day) and BRENDANX-UW8. Dell replaced both CPUs
  within about two weeks of the report.
- **September 2026:** SKYLINE-DEV6's replacement CPU began failing the suite again. With the
  January record, crash links to skyline.ms, and the CPU's own WHEA errors on the same core
  after every requested step, Dell dispatched a repair within a week (motherboard, dispatch
  469001494).

A machine that fails this test is not ready for developers. Its failures would otherwise be
investigated as Skyline bugs.

## Things that do not clear a machine

- **Vendor diagnostics pass.** Dell ePSA passed twice on SKYLINE-DEV6 while it was crashing.
- **Stress tools pass.** Four hours of Prime95 and y-cruncher pinned to SKYLINE-DEV6's
  failing core found nothing, while the nightly suite crashed it within a day. The suite's
  mixed load is the more sensitive test.
- **BIOS/driver updates.** Updating to the latest BIOS did not stop SKYLINE-DEV6's crashes.
- **A clean day or two.** A machine crashing in half its runs will have clean stretches.

## Related

- [daily-report-guide.md](daily-report-guide.md) - Investigating Early Terminations
- [mcp/nightly-tests.md](mcp/nightly-tests.md) - `testruns` schema (the `log` column is gzip)
- `ai/mcp/LabKeyMcp/scripts/scan_testrunner_crashes.py` - fleet crash scan
