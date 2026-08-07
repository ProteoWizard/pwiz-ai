# TODO-20260807_selection_change_file.md

## Branch Information
- **Branch**: `Skyline/work/20260807_selection_change_file`
- **Base**: `master`
- **Created**: 2026-08-07
- **Status**: In Progress
- **GitHub Issue**: none
- **Module**: `skyline`
- **PR**: (pending)

## Motivation

`IToolService.AddDocumentChangeReceiver` is going away with the rest of that
interface, and its design was the problem anyway: Skyline kept a list of
registered receivers and, on every change, called each one SYNCHRONOUSLY from a
thread it spawned for the purpose (`ToolService.SendChange`), catching
`TimeoutException`, counting strikes up to `MAX_TIMEOUT_COUNT` before reaping a
receiver, and popping the Immediate Window with "No response from &lt;tool&gt;". A
tool that died, hung, or simply stopped listening became Skyline's problem.

## What changed

The fix is to invert the direction of the reference: instead of Skyline holding
references to listeners, Skyline publishes something listeners hold a reference
to. Anything built that way is self-cleaning - a listener that dies, hangs, or
never starts costs nothing, because Skyline never knew about it.

`ToolsUI/SelectionChangeFile.cs` rewrites one small file whenever the selection
changes: `%UserProfile%/.skyline-mcp/selection-<pipeName>.txt`, beside the
`connection-<pipeName>.json` that already publishes where to find that Skyline.

**Rewriting the file IS the message.** There is no payload: a listener that wants
to know what is selected now asks the service (`GetSelection`), which is the only
answer that cannot already be stale by the time it is read. The file holds the
time of the change, for a person who opens it to see what it is; a listener needs
nothing out of it and can just watch it with a `FileSystemWatcher`.

Writes are coalesced on a 200 ms timer: arrowing down the Targets tree rewrites
the file once, shortly after the last change, rather than once per keystroke -
which is what a listener wants (where the selection ended up) and keeps the file
writing off the thread the user is typing on.

Lifetime: created with the `JsonToolServer` (which owns the directory and the
pipe name), deleted on its Dispose. A file left behind by a Skyline that did not
exit cleanly is reaped by the existing stale-connection-file sweep - the
selection file carries no process id to be reaped by (it carries nothing), so it
goes when the connection file naming the same pipe is found stale.

## Verification

- New `SelectionChangeFileTest` watches the file the way a listener would, with a
  `FileSystemWatcher`, and asserts it is notified for each of two selection
  changes.
- `TestJsonToolServer`, `TestSkylineMcp`, `TestMcpConnectorDisconnect`,
  `CodeInspection` pass. ReSharper QuickInspection: zero warnings.

**A trap the first version of the test fell into**: setting `SelectedPath` to the
node that is ALREADY selected changes nothing and quite rightly notifies nobody.
The test now asserts the path differs before setting it.

## Considered and rejected

- **Counters in the file** (selection/document, monotonic). Strictly better for a
  listener that POLLS rather than watches - two changes inside one file-timestamp
  tick are otherwise indistinguishable - but nothing today polls, and the payload
  brought JSON, a second channel, and stale-file reaping by process id with it.
  One line to add if a polling listener ever appears.
- **Reusing `connection-<pipe>.json`** instead of a second file: fewer files, but
  a listener watching for "a Skyline appeared" would be woken by every selection
  change, and rewriting a file whose content says `connected_at` to mean
  "something changed" reads wrong.
- **Named event + memory-mapped file**, **`PostMessage(HWND_BROADCAST)`**, and a
  **long-poll verb** on the service. All viable; the last fits the MCP well but
  needs the single-instance pipe server made multi-instance first, since a parked
  long-poll holds the one connection.

## Follow-ups

- Nothing consumes this yet. The MCP server would be the first listener: watch the
  file, and re-read the selection when it changes.
- `AddDocumentChangeReceiver` / `RemoveDocumentChangeReceiver` and
  `ToolService.SendChange` still exist on the legacy `IToolService`; they go when
  that interface does.
