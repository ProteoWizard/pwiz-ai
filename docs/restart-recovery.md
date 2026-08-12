# Restart Recovery

What survives when a Windows Update reboot (or power loss, or a hard crash)
kills a `skyclaude` session mid-work, and how to pick the work back up.

## The problem

A reboot takes out three things at once:

| Lost | Recovery |
|------|----------|
| The conversation | Transcript survives on disk — reopen with `-Resume` |
| `PWIZ_LSP_DIR` and the tab pin | Re-established by naming the checkout: `skyclaude IMoffset` |
| An in-flight build or test run | Not resumable, but now *reported* so it isn't silently lost |

The working tree is untouched — a reboot costs you context, not code.

### Why `claude --continue` is not enough

Every checkout under the project root shares **one** transcript store
(`~/.claude/projects/C--Dev/`), and every record in it says `cwd: C:\Dev`
regardless of which checkout the session was working in. Nothing in a transcript
identifies its checkout.

So `claude --continue` means "the most recent conversation for the project" —
not "the most recent conversation for this checkout." With several `skyclaude`
windows open (the normal case here), a reboot kills them all, and `--continue`
reopens whichever one happened to be active last. The checkout you named on the
command line cannot influence that choice.

## Usage

```powershell
skyclaude IMoffset -Resume        # reopen IMoffset's interrupted session
skyclaude IMoffset --continue     # same thing: --continue is retargeted, out loud
skyclaude IMoffset                # fresh session; reports what was interrupted
```

A launch that finds interrupted work but is not resuming says so, so a lost
session is a choice rather than a surprise:

```
IMoffset has 1 session(s) interrupted by a restart -- 'skyclaude IMoffset -Resume' to pick up the newest.
  interrupted test: TestPerfMinimizeResults (started 2026-08-12 01:14)
```

The same summary is injected into the next session's context by the
`Set-ActiveCheckout` SessionStart hook, so Claude knows what was interrupted
without being told.

## How it works

Two kinds of record live under `ai/.tmp/` (gitignored, pruned after 14 days):

| Record | Written by | Removed by |
|--------|-----------|-----------|
| `sessions/<session-id>.json` | `Set-ActiveCheckout` SessionStart hook | the `skyclaude` launcher, on clean exit |
| `runs/<name>-<pid>.json` | `Build-Skyline.ps1`, `Run-Tests.ps1` on entry | their `finally` block |

**Removal on clean exit is the signal.** Anything still on record was killed —
nothing writes a "crashed" flag, because a killed process cannot write anything.

The session ID is only known inside the session, so the hook writes that record,
not the launcher; the launcher passes a `SKYCLAUDE_LAUNCH_ID` through the
environment so it can recognize and clear its own record on exit.

### Restart vs. crash

Every record carries a **boot ID** (`LastBootUpTime`). A survivor whose boot ID
differs from the current one was killed by a restart; a matching boot ID means
the owner died some other way (crash, closed terminal) and the message says so.
Without that distinction the report would have to guess, and a report that
guesses is one you learn to ignore.

Boot IDs are stored with a `boot-` prefix. This is not cosmetic:
`ConvertFrom-Json` revives any ISO-8601-shaped string as a `[DateTime]`, so a
bare timestamp comes back typed differently than the live boot ID, never
compares equal, and reports *every* record as restart-killed.

A run marker whose process is still alive is a concurrent run, not an
interruption, so same-boot markers are checked against the live process list
before being reported.

## Pending-reboot warning

`skyclaude` warns at launch when Windows is holding a reboot — worth knowing
before starting an unattended overnight run:

```
Windows has a reboot pending (Windows Update). Reboot now if you are about to start a long unattended run.
```

Only `WindowsUpdate\RebootRequired` and `Component Based Servicing\RebootPending`
trigger it. `PendingFileRenameOperations` is deliberately **not** treated as a
reboot signal: ordinary installers set it constantly, and a warning that fires
daily is one nobody reads.

## After a killed test run

A killed run can leave orphaned `Skyline.exe` / `TestRunner.exe` processes and
stale `.skyd` caches beside its input documents. Check for both before rerunning
— a stale `.skyd` will serve old chromatograms to the next import.

## Files

| File | Role |
|------|------|
| `ai/scripts/session/SessionState.ps1` | Shared record read/write, boot-ID logic, pending-reboot check |
| `ai/scripts/lsp/Enable-PwizLsp.ps1` | `-Resume`, `--continue` retargeting, launch-time report, clean-exit cleanup |
| `ai/claude/hooks/Set-ActiveCheckout.ps1` | Writes the session record; injects the recovery brief |
| `ai/scripts/Skyline/Build-Skyline.ps1`, `Run-Tests.ps1` | Write and remove run markers |

Every function in `SessionState.ps1` swallows its own errors. This is
bookkeeping, and it must never be the reason a build, a test run, or a session
start fails.
