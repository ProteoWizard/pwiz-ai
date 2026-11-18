# Skyline AI Connector (MCP) Design Guide

How the verbs behind the Skyline AI Connector should behave toward the LLM driving them. It covers
the in-process server (`pwiz_tools/Skyline/ToolsUI/JsonToolServer.cs`, `JsonUiService.cs`,
`DialogWatcher.cs`, `UiElement.cs`), the shared contract (`pwiz_tools/Skyline/SkylineTool/`:
`IJsonToolService.cs`, `JsonToolModels.cs`) and the MCP server's tool layer
(`pwiz_tools/Skyline/Executables/Tools/SkylineMcp/SkylineMcpServer/Tools/SkylineTools.cs`).

**Status: reviewed by Brendan 2026-11-18; awaiting Nick's review.** Most rules below already exist
as code comments; sections 0 ("Two kinds of callers") and 1 ("Never block, never pretend") record
standards that were not yet written down anywhere.

The LLM is a user who cannot see the screen. Every rule here follows from that: it learns what
happened only from what the verb returns, and while a verb blocks, it cannot tell its own user
anything. In autonomous work (a deck built overnight, a tutorial run end to end) there is no human
to notice that it is stuck or misled.

## 0. Two kinds of callers

`JsonToolServer` is not only the AI Connector's server. The same instance, on the same pipe
(`Program.MainJsonToolServer`, `Program.cs:595`), serves **external tools** - programs launched
with `$(SkylineConnection)` in their command line (`ToolMacros.cs:338`). Those are running
programs, now often written by LLMs, but with **no AI behind them at run time**. Today the server
cannot tell the two apart (pwiz issue #5053).

| | AI Connector (MCP) | External tool |
|---|---|---|
| Behind the call | an LLM, often working for a user who is waiting on it | a program; a user at the UI with no AI |
| A slow action | return in seconds: "issued, still finishing, poll" (section 1) | done when it returns, with a much longer bound; a timeout is a failure the tool can show |
| Error and result text | `LlmInstruction`: names the next tool to call | user-facing `.resx` text, localized, fit to show in a message box |
| `ActionResult.Message` on success | a description of the result (section 3) | none, or user-facing |

Rules for both:
- **An undeclared caller is an external tool.** Existing tools never declared anything, and must
  keep today's behavior. The MCP server declares itself (the proposal in #5053: a per-connection
  `SetClientInfo(kind, name)` called from `SkylineConnection.TryConnect`).
- **Verbs read the caller kind from the connection**, not from a parameter on every method.
- **Never put MCP tool names or LLM guidance where a tool's user may read it.** Until #5053 lands,
  most errors in `JsonToolServer` are `LlmInstruction`s that an external tool may show verbatim; new
  verbs that an external tool is likely to call (selection, replicate, showing graphs, settings,
  document operations) should be written with both callers in mind.

Sections 1-4 describe the AI Connector side.

## 1. Never block, never pretend

For AI Connector callers (section 0). **A verb that cannot reach the requested state in a short
time returns, and says so.** It reports
that the request was issued, what is still finishing, and how to poll for it. It never returns as if
it had completed, and it never holds the call for long.

- **Bound every wait well under the MCP call timeout.** `SkylineTools.CallTimeout` is 30 s; when it
  runs out the MCP server drops the connection and returns `CALL_TIMED_OUT_MESSAGE`, whose advice
  (Skyline is still doing the work; find the progress dialog to cancel it, or wait and retry) is
  generic. A verb's own message is more accurate, so the verb must time out first. Seconds, not
  tens of seconds: a user who asked for a spectrum is impatient after about 10.
- **A wait returns whether it reached its state.** A `void` wait that ends the same way on success
  and on timeout is the bug to avoid. The caller turns a timeout into a message.
- **The timeout message names what is unfinished and how to poll.** Example
  (`JsonToolServer.ShowFullScan`): "The Full-Scan graph was sent to the scan at 41.06 minutes and is
  still loading it after 10 seconds. Skyline finishes on its own, so carry on: read the graph ... in
  a few seconds, and again if it still shows 'Loading...'."
- **A partial result is marked partial.** Data returned after a timeout (a graph image that may show
  the previous selection, a form list missing the docked panes) carries a note saying so, beside the
  data rather than instead of it.
- **An action whose effect is asynchronous is not done when it is issued.** A click that starts a
  background load (the Full-Scan spectrum, graph recalculation, a document load) waits for the
  effect, briefly, or reports it as still finishing.

Why: testing `skyline_show_full_scan` (PR #5031) on ion mobility data, the tool returned "Showing
the full scan..." while the spectrum was still loading; the next read showed an empty graph titled
"Loading..." and no selection circle, and the LLM drew wrong conclusions from it. Known silent
timeouts still to fix are listed in pwiz issue #5052 (`WaitForGraphs`, `GetOpenForms`,
`WaitForDocumentLoaded`).

## 2. A dialog is reported, not waited behind

A gesture that opens a modal dialog returns at once with `ActionResult.Completed = false`, the
dialog's text in `Message` and its id in `FormId`, so the LLM can drive it (`DialogWatcher`,
`ToolsUI/DialogWatcher.cs`). A watchdog fails a gesture that neither finishes nor opens a dialog,
and its message states only what is known ("did not finish, but Skyline is not making any
progress") - not a guess such as "a dialog may be open", which `DialogWatcher` would have reported.

## 3. Results describe the resulting state

Return what the verb did and what is now true, so the LLM rarely needs a screenshot to find out:
the scan type and time actually shown, the transition selected, the range zoomed to - not an echo
of the request. Example: `JsonUiService.DescribeFullScan` ("Showing the MS/MS scan at 14.86 minutes
from ..., with the selection circle on the FA 18:3(+O) chromatogram; the graph is zoomed to m/z
276.2-280.7"). The request and the result can differ (here 14.83 was asked for), and the LLM needs
to know.

`ActionResult.Completed` is true only when the verb is sure the action finished. A completed result
may carry a description of the result in `Message` (`JsonToolModels.cs`); a tool returns it when
present.

## 4. Errors are instructions

Text meant for the LLM is an `LlmInstruction` (`pwiz_tools/Skyline/Util/Extensions/Text.cs`) - not
a `.resx` string (it is not shown to users) and not a bare exception message. Each error names what
was wrong and the next step: where to get a valid value ("take one from a report's
TransitionLocator column"), which tool to call. List every likely cause when there are several
(time outside the chromatogram; transition not displayed; a protein or several peptides selected;
no full-scan data).

## 5. Address what the user can see; make it discoverable

- **Find controls by what is visible**: caption, the label beside a field, a tooltip, the control's
  kind. Not by internal `Name` - Nick's rule; name matching exists only where an issue asked for it
  and is not to be extended.
- **Everything an LLM can click or set should be listed** by `skyline_get_controls`, with its state.
  Not yet true - open gaps: toolbar items, including combo boxes, and their visibility (#5050);
  property sheets (#5049); docking state and layout (#5051, #4671).
- **A missing tooltip or caption is a bug for users too.** The Full-Scan properties button had no
  tooltip because its resx entries were keyed to an old name; fixing that made it clickable over
  the MCP (#5031).

## 6. Mechanics

- **Tabular outputs only grow.** New columns are appended, so positional readers keep working
  (`skyline_get_open_forms`).
- **A new verb** goes into `IJsonToolService`, `SkylineJsonToolClient`, `JsonToolServer`, the MCP
  server's `SkylineConnection` and `SkylineTools`, with `[RequiresJsonToolServiceMethod]` so the tool
  is hidden from a Skyline that lacks it.
- **The connector ZIP.** A change to the MCP server is shipped by rebuilding
  `SkylineAiConnector.zip` (`Build-Skyline.ps1 -Target AiConnector -Configuration Release`, which
  stamps the version from the HEAD commit, so commit the code first) and updating
  `EXPECTED_ZIP_VERSION` in `TestFunctional/SkylineMcpTest.cs`.
- **CLI arguments work through `RunCommand`.** The MCP saves through the GUI path, so per-invocation
  state goes through a scoped ambient override read where all save paths meet, not through
  `SaveDocument` signatures (PR #4288; skyline-development skill).
- **Geometry verbs go through the graph's `UiActions`**, so a gesture means the same whether reached
  by a named verb or `perform_action` (`JsonToolServer.cs`).
- **Tests**: `JsonToolServerTest`, or a focused functional test driving `JsonToolServer` directly
  (`ShowFullScanJsonToolTest`). Assert state, never English text. Assert immediately after the call
  when the verb promises to have waited, so the test covers that promise.

## 7. Trying a verb in a real scenario

Unit tests rarely reach the cases that matter (dense data, ion mobility, a docked pane too small to
read). Pause a tutorial test at the step where the user would act and drive Skyline over the MCP from
there - see `ai/docs/feature-demo-guide.md` ("Trying a feature at a pause"). Then explore around the
feature rather than declaring it done: the #5031 session found a crash, the silent-timeout pattern,
and four classes of unreachable UI that way.

## Related

- `ai/docs/feature-demo-guide.md` - driving a paused test over the MCP
- `ai/docs/native-file-dialog-automation.md` - native file dialogs
- `ai/docs/mcp/development-guide.md` - the team's own Python MCP servers (a different subject)
