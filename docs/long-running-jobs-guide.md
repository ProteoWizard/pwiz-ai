# Long-Running Jobs: Detachment, Windows, and Monitoring

Anything that runs longer than a few minutes — an Osprey cohort run, `regression.ps1`,
a SkylineTester loop, a perf A/B sweep — needs to be launched so that it **survives the
harness**, produces a **readable log**, and does **not** put a window on the developer's
desktop. Getting one of those three right and another wrong has cost multiple sessions
across multiple machines.

This is the canonical reference. `osprey-development-guide.md`,
`osprey-large-datasets.md`, `build-and-test-guide.md` and
`skylinetester-debugging-guide.md` point here rather than repeating it, because a
duplicated copy of this advice drifts and the stale copy is the one that gets followed.

## The problem: reaping

An AI session's tool calls run inside a job object. Long children of that job get
**killed** — "reaped" — while the work is still in flight. Observed repeatedly:

| when | what was launched | killed at |
|---|---|---|
| 2026-08-09 | 82-file `--task SecondPassFDR`, background bash | ~15 min, at 31% of the pass-2 competition |
| 2026-07-19 | 82f x 3 FirstPassFDR sweep, background bash | ~30 min (an earlier attempt ~93 min) |
| 2026-07-28 | `regression.ps1 -Dataset All`, background bash | ~35 min |
| 2026-08-29 | `Start-Process` **with** redirect flags | ~18 min, mid-Percolator |

**Reaping is not always fatal to the child, and that is worse than if it were.** In the
2026-07-28 case the pwsh child kept running but its **stdout stopped being captured**, so
a run that completed 3 of 4 datasets cleanly produced no readable summary and none of it
could be claimed. Silence is not success; a dead wrapper looks exactly like a quiet job.

There is no "short enough to just run it" threshold. Assume anything past a few minutes
needs detaching.

## How to launch, in order of preference

### 1. `run_in_background: true` on the Bash tool

The harness-native mechanism. It keeps running across turns, re-invokes the session when
it exits, and **creates no window**. Prefer it: it is the only option the harness itself
tracks, so completion is a notification rather than a poll.

The table above records cases where this was reaped. Those are from July/August 2026 and
sessions since have used it without trouble, so treat it as the default and escalate only
if something is actually killed — do not pre-emptively reach for the heavier options.

### 2. `Start-Process` with NO redirect flags

```powershell
Start-Process pwsh -WindowStyle Hidden -PassThru `
    -ArgumentList '-NoProfile','-File','<launcher.ps1>'
```

**Never add `-RedirectStandardOutput` / `-RedirectStandardError`.** They force
`UseShellExecute=false`, so `Start-Process` calls `CreateProcess` directly and the child
**inherits the harness job object** — which defeats the whole point. Without them it goes
through `ShellExecute` and breaks away.

Let `<launcher.ps1>` write its own log (`*>&1 | Tee-Object -FilePath <log>`). That is not
a workaround for the missing redirect flags; it is the reason they are not needed.

### 3. CIM / WMI — the heaviest hammer

```powershell
$startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly `
    -Property @{ ShowWindow = [uint16]0 }        # SW_HIDE
Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine               = 'pwsh -NoProfile -WindowStyle Hidden -File "<launcher.ps1>"'
    CurrentDirectory          = '<dir>'
    ProcessStartupInformation = $startup
}
```

The child is parented to **WmiPrvSE**, not to the caller, so it is outside the job object
entirely. Reliable regardless of flags. Use it only when 1 and 2 have actually failed.

## THE WINDOW TRAP — read this before adding redirection

> **Never wrap the command in `cmd.exe /c "... > log 2>&1"`.**

That wrapper **is** a blank `C:\Windows\system32\cmd.exe` window, one per job, visible for
the entire life of the job. On a night of 15–90 minute runs it is a screenful of them, on
the machine the developer is also trying to work on. Reported 2026-08-31 across two
machines, from both an Osprey session and a Skyline test-debugging session.

It is also unnecessary. The reason it gets added is to capture output — which the
launcher script should do itself:

```powershell
# inside <launcher.ps1>
<command> *>&1 | Tee-Object -FilePath '<log>'
```

`*>&1` rather than `>` so **stderr is captured too**; a bare stdout redirect loses exactly
the output you need when the job fails.

### Roll the log; never truncate it

**A log written to a fixed name must ROLL the previous one aside before it opens, with a
datetime suffix.** Truncating is silent, and what it destroys is the record of the run you were
about to continue.

```powershell
# before opening <dir>
un.log for a new run
if (Test-Path $log) {
    $kept = Join-Path (Split-Path $log -Parent) `
        ('run-{0}.log' -f (Get-Item $log).LastWriteTime.ToString('yyyyMMdd_HHmmss'))
    Copy-Item $log $kept -Force
}
```

Name the rolled copy for the OLD log's mtime, not for now, so the file records when its run
ended rather than when the next one started.

Two shapes, and both are fine as long as neither truncates:

* **Fixed name + roll** - right when downstream tooling looks the file up by name.
  `run.log` is read by `perfviz.py`, by the run-layout conventions and by every handoff, so the
  current run has to keep that name and the previous one rolls to `run-<datetime>.log`.
* **Datetime IN the name** - right when nothing needs a stable path.
  `Invoke-DailyReport.ps1` and `Invoke-PRReport.ps1` already do this
  (`"$Phase-$TimeStamp.log"`), so their first `Out-File` without `-Append` is harmless: the
  path is new every run.

The reference implementation is `OspreyDatasetRun.psm1` (search "NEVER truncate an existing
run.log"). It rotates with `Move-Item`, stamps from the old log's `LastWriteTime`, and
disambiguates a same-second collision rather than clobbering. Its comment records the incident
that earned it: "one `-Resume` into the wrong directory silently destroyed an 18-hour run's
1.8 MB log this way. Recovered that time only because a human happened to have it open in an
editor." Copy that block; do not reinvent it.

**A caution for anyone auditing this, from getting it wrong on 2026-09-03.** Grepping for the
`Set-Content -Path $log` on the START line and concluding "this truncates" is exactly the wrong
read - the rotation sits about thirty lines ABOVE it, and the `Set-Content` is correct precisely
because the rotation already ran. A partial read of a file that is right can manufacture a defect
that is not there, and the resulting "fix" was dead code duplicating a `Move-Item` that had
already moved the file.

Applies to the launcher's own tee as well: `Tee-Object -FilePath $log` without `-Append`
truncates on the first write, which is how the second copy of that same trace was lost.

### Verifying there is no window

`(Get-Process -Id <pid>).MainWindowHandle` is **0 for both the hidden and the visible
form** — a console window belongs to `conhost.exe`, not to `cmd.exe` — so it cannot be
used to check this. Count the processes instead:

```powershell
Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" |
    Where-Object { $_.ParentProcessId -eq <WmiPrvSE pid> }
```

Zero new `cmd.exe` children after a launch means no console was created.

## Monitoring, waiting, and chaining

**Watch with the Monitor tool, not a background-bash waiter** — the waiter is subject to
the same reaping as anything else.

**Cover the failure case in the filter.** A monitor that greps only for the success marker
stays silent through a crash, a hang, or an early abort, and silence reads as "still
running". Include the failure signatures you would act on.

**Do not wait on "no `<exe>` is running".** A multi-phase driver like `regression.ps1`
launches its executable once per phase, so between phases there is no such process and the
harness looks idle. A chained job keyed on that fired **three minutes into a thirteen-minute
gate** (2026-08-31). Wait for the driver process to be gone **and** for the log to carry
its terminal line — absence of a process is not presence of a result.

**Assert the expected result COUNT, not merely "no failures".** The same chain then
accepted a run reporting `2 PASS, 0 FAIL` when a clean Stellar gate is 11 PASS. An aborted
run and a clean one are indistinguishable under a no-failures test.

## Killing a run leaves the build output locked

Stopping a long run mid-flight (harness kill, `Stop-Process`, a cancelled chain) can leave its
executable's DLLs mapped for a while afterwards. The next run then fails to build - and the
failure does NOT read as a build failure:

```
WARN: failed to prune <TestResults dir>: The process cannot access the file
      '...\Osprey\bin\x64\Release\net8.0\SQLite.Interop.dll' because it is being used by
      another process.
```

That looks like a cosmetic cleanup warning. Observed 2026-08-31: it was read as benign and the
run was reported as "continuing" while it had in fact died at `Copy-Item SQLite.Interop.dll`
seventeen minutes earlier. The tell was not in the message - it was that no phase had advanced
in seventeen minutes on a step that takes seconds.

**Before starting a run after killing one, prove the build tree is free.** Renaming the file is
a definitive check and costs nothing:

```powershell
$dll = '<bin>\Release\net8.0\SQLite.Interop.dll'
Rename-Item $dll "$dll.locktest"
Rename-Item "$dll.locktest" $dll
```

Scanning loaded modules is NOT sufficient - a dying process can hold the file with nothing
reporting it loaded. The rename either succeeds or it does not.

## Related

- `osprey-development-guide.md` — Osprey build/run wrappers and gates
- `osprey-large-datasets.md` — cohort runs, which are always long enough to need this
- `build-and-test-guide.md` — Skyline build and test entry points
- `skylinetester-debugging-guide.md` — hour-long SkylineTester loops
- `debugging-principles.md` — cycle-time strategy, of which "can I even keep the run alive"
  is the precondition
