# TODO-20260609_native_file_dialog_automation.md -- Drive the native OpenFileDialog via UI Automation, and surface it to the MCP

## Status

Active -- on the feature branch. Native Open + **Save** dialog automation, MCP
StartPage support, and the generic form verbs (incl. radio buttons and custom
clickable controls) have landed. The PRM tutorial's Import Peptide Search wizard
now runs end to end over the connector. PR not yet opened.

## Branch Information

- **pwiz branch**: `Skyline/work/20260609_native_file_dialog_automation`
- **PR**: TBD
- **ai branch**: `master`

## Background

Automated tests (and, ultimately, the Skyline MCP server -- see
[#4089](https://github.com/ProteoWizard/pwiz/issues/4089)) need to interact
with Skyline's File > Open command the way a user does. The native Windows
common file dialog is not a WinForms form, so it never appears in
`FormUtil.OpenForms` and cannot be introspected or driven the way the rest
of Skyline's UI is. UI Automation (Accessibility) is the mechanism that can
reach it.

## Objective

1. Let tests open a document through the real File > Open UI instead of
   calling `SkylineWindow.OpenFile` directly.
2. Make the native OpenFileDialog a first-class citizen of the MCP's generic
   UI-introspection layer: it shows up in `get_open_forms` and
   `get_form_image` works on it.

## Done (this commit)

* `SkylineWindow.ShowOpenFileDialog()` extracted from `openMenuItem_Click`
  so the menu code path is callable.
* Shared product code (not test-only) that drives the native dialog via UI
  Automation, split into a base class and a subclass:
  * `NativeDialogAutomation` (abstract base) -- instance-based; drives any
    native `#32770` dialog: `WaitForDialog`, `GetOpenDialogs`, `Cancel`
    (WM_CLOSE), `PressEnter`, the off-UI-thread enumeration, and the
    `WaitFor`/`WaitForElement` plumbing. Subclasses override `IsMatch`.
  * `OpenFileDialogAutomation : NativeDialogAutomation` -- identifies the
    dialog by its file-name combo (AutomationId `1148`) and adds
    `EnterPathAndAccept(path)`.
* `AbstractFunctionalTest.OpenDocument(path)` -- posts the dialog with
  `BeginInvoke`, drives it, waits for the new document. LiveReportsTutorialTest
  migrated to it.
* MCP discovery: `JsonUiService.GetOpenForms` enumerates native dialogs
  (`FormInfo.IsNative`, `Type="FileDialog"`); `GetFormImage`/`GetFormImageBytes`
  capture a native window by HWND. MCP server `skyline_get_open_forms` adds an
  `IsNative` column.
* `NativeFileDialogTest` -- covers discovery, image capture, cancel, and open.

## Done (2026-06-17 session)

* **Save file dialog automation** (`6be78fc6f`). The modern Save dialog is NOT
  the classic combo (`AutomationId 1148`) the Open path keys on: its file-name
  field is a Win32 `Edit` (`AutomationId 1001`, inside `FileNameControlHost`) and
  its Save button a Win32 `Button` (control id `1` = IDOK), neither exposing a UI
  Automation Value/Invoke pattern. They ARE real windows, so `SaveFileDialogAutomation`
  drives them with `WM_SETTEXT` / `BM_CLICK`. Extracted a `FileDialogAutomation`
  base shared by Open and Save; `GetOpenForms` now lists `FileDialog:Save As` and
  `SetFormValue`/`ClickFormButton` drive it like Open. Verified live end to end (the
  earlier "Save dialogs are undriveable" note is now obsolete).
* **MCP works while the StartPage is showing** (`Make ActionBoxControl clickable.`).
  The tool service now starts before the StartPage and marshals via a captured
  `WindowsFormsSynchronizationContext`, so `GetOpenForms`/`GetFormImage`/
  `ClickFormButton` work with no `SkylineWindow`. `ScreenCapture` consent uses
  `Program.MainWindow ?? Program.StartWindow` as owner. `ToolService` no longer
  requires the window at construction.
* **Generic clickable controls**: `ClickFormButton` now drives any `IButtonControl`,
  and `ActionBoxControl` (the StartPage tiles) implements it -- so Blank Document /
  Import-PRM tiles are clickable. `SetFormValue` now selects **radio buttons**
  (needed for the PRM workflow and retention-time-filtering options).
* **PRM tutorial** (`More steps of PRM tutorial`): `Documentation/Tutorials/PRM/
  mcp-steps.txt` now drives File>Open through the completed Import Peptide Search
  import (2 replicates) over the connector, validated live against the mzML data.

## Key findings (hard-won; keep for the MCP work)

* `InvokePattern.Invoke` on the common file dialog's buttons is **unreliable**
  (it is a DirectUI surface) -- it silently no-ops. Drive the dialog with
  window messages instead: a posted **Enter** (`WM_KEYDOWN`/`WM_KEYUP`,
  `VK_RETURN`) to accept, `WM_CLOSE` to cancel.
* The screen-reader accept path **does** work on this dialog (spike, this
  branch). Two facts: (1) the managed `System.Windows.Automation` wrapper does
  **not** expose `LegacyIAccessiblePattern` -- it exists only in the COM UIA API
  and in raw MSAA -- so a "legacy pattern" accept via `AutomationElement` is not
  available without dropping a level; (2) going straight to MSAA/oleacc
  (`AccessibleObjectFromWindow` -> walk the accessible tree -> the
  `ROLE_SYSTEM_PUSHBUTTON` with `STATE_SYSTEM_DEFAULT` -> `accDoDefaultAction`)
  accepts the dialog where `InvokePattern.Invoke` no-ops. It works **offscreen**
  (no foreground/focus needed, unlike `SendInput`) and is **locale-independent**
  (keys on the default-button state + `AutomationId`, never the caption "Open").
  Spike code: `OpenFileDialogAutomation.EnterPathAndAcceptViaButton` +
  `NativeFileDialogLegacyAcceptTest` (decide keep-vs-revert before PR).
* Set the path on the **Edit** control inside the "File name" combo box
  (AutomationId `1148`), not on the combo box -- the combo auto-completes and
  discards the directory portion. Setting the full path on the Edit + Enter
  navigates and opens in one action, regardless of the dialog's current folder.
* Discover native dialog windows with Win32 **`EnumWindows`** (filter to
  process + class `#32770`, then `AutomationElement.FromHandle`), NOT a UIA
  child walk. EnumWindows enumerates *owned* top-level windows regardless of
  nesting, so it finds a dialog owned by a **nested** modal form (e.g. the
  "Add Input Files" dialog owned by the Import Peptide Search wizard, which is
  itself nested under the main window). The earlier approach -- `RootElement`
  children + their *direct* children -- only caught dialogs owned by a
  top-level window like the main window, and silently missed grandchild
  dialogs (`RootElement.FindAll(Children, processId)` returns only the main
  window, not nested modal forms). EnumWindows visits only top-level windows,
  so it also avoids the prohibitively slow full `Subtree` walk.
* The UIA scan must run off the UI thread (the modal dialog holds the UI
  thread in its own message loop); the WinForms enumeration still marshals to
  the UI thread.
* To click a WinForms button programmatically, post **`BM_CLICK`** to the
  button handle -- NOT `Button.PerformClick()`, which is gated by `CanSelect`
  and `ValidateActiveControl` and silently no-ops on a freshly opened form
  (focused field fails validation). `BM_CLICK` clicks like a real mouse and is
  fire-and-forget (does not block when the click opens a modal dialog).

## Remaining work

* Migrate remaining tutorial/functional tests from `SkylineWindow.OpenFile`
  to `OpenDocument` incrementally (not all at once).
* MCP Phase 3: generic form automation -- enumerate controls, set values, and
  submit/click, working uniformly for WinForms forms and wrapped native dialogs.
  See **Phase 3 design** below for the full plan.
  * **Done (this branch):** `InvokeMenuItem` / `ClickFormButton` /
    `SetFormValue` added to `IJsonToolService` + `JsonToolServer` +
    `SkylineJsonToolClient` + `JsonUiService`, and wired through the external
    MCP server: `SkylineConnection` delegations + MCP tools
    `skyline_invoke_menu_item` / `skyline_click_form_button` /
    `skyline_set_form_value` in `SkylineTools.cs` (`SkylineMcpServer` compiles;
    `SkylineMcpTest` `EXPECTED_TOOL_COUNT` bumped 47 -> 50). The PRM tutorial's
    Import Peptide Search open steps (menu -> wizard -> Add Files -> native
    dialog -> select 2 files -> Open) run end to end through these verbs,
    verified by `PrmConnectorTest` (offscreen, translation-proof; it waits for
    the dialog by polling `GetOpenForms`, the connector discovery method).
    Native dialog discovery switched to `EnumWindows` (see Key findings) so the
    wizard-owned dialog is found.
  * **Non-blocking commands (alert-watch):** `JsonUiService.RunWithAlertWatch`
    runs a verb's work on a background thread (`ActionUtil.RunAsync`) and, if a
    `CommonAlertDlg` appears first, reads its text and throws -- returning
    immediately instead of blocking on the modal. The alert is left open for the
    model to dismiss (`ClickFormButton` is intentionally NOT wrapped, so it can
    still dismiss alerts). Applied to `RunCommand` (`RunCommandImpl` ->
    `RunCommandCore`) and `SetFormValue`; extend to more verbs as needed.
    Progress dialogs (`LongWaitDlg`) are not `CommonAlertDlg`, so normal command
    progress does not trip it. Verified by `AlertWatchTest`. (An earlier
    multi-connection JsonToolServer approach to the same blocking problem was
    implemented and then reverted in favor of this -- fail-fast keeps the single
    connection free, so no second connection is needed to dismiss a hung dialog.)
  * **Done since:** `SetFormValue` selects radio buttons; `ClickFormButton` drives
    any `IButtonControl` (e.g. StartPage tiles); the native **Save** dialog;
    ranked control matching (exact > symbol-stripped, prefer visible+enabled, so
    "Next"/"Finish" match "Next >"/the live Finish button); and **graph
    right-click context-menu invocation** -- `InvokeContextMenuItem` builds a
    graph's context menu via its `ContextMenuBuilder` and walks it by path
    (`ContextMenuConnectorTest` passes; exposed as `skyline_invoke_context_menu_item`,
    tool count 50 -> 51). This unblocks most of the "Reviewing the Data" section.
  * **Not yet done (remaining gaps for the PRM tutorial):**
    `GetFormState` (enumerate a form's controls into the hierarchical DTO);
    `SelectTab` (tabbed settings dialogs); `SelectTreeNode` + tree pop-up
    pick-lists (manual precursor picking); send-key; and **derived-label
    matching** so a text field can be addressed by its adjacent `Label`
    (e.g. "Ion match tolerance") rather than only its control name. Also:
    `SkylineMcpTest` only runs end to end against an
    *installed* AiConnector tool (else `Assert.Inconclusive`); after this
    change the tool must be repackaged (`SkylineAiConnector.csproj`) and
    reinstalled for the new 51-tool count to be exercised. (Standalone
    `dotnet build` of `SkylineAiConnector.csproj` fails on a pre-existing
    net472 `System.Text.Json` restore quirk in `SkylineTool.csproj` -- build it
    via the solution/MSBuild with restore, not standalone.)

## Phase 3 design (generic form automation + tutorial runner)

### Ultimate goal

Claude (via the AI Connector / MCP) should be able to **run the Skyline
tutorials** in `pwiz_tools/Skyline/Documentation/Tutorials`. Those tutorials are
step-by-step instructions that name controls and values, e.g. (MethodEdit):

* "In the **Name** field of the **Build Library** form, enter "Yeast (Atlas)"."
* "From the **Background proteome** drop-list, choose **<Add…>**."
* "In the **Peptide Settings** form, click the **Digestion** tab."
* "On the **Settings** menu, click **Peptide Settings**."
* "Click the **Browse** button." (-> the native file dialog this branch wraps)

The instruction format is regular -- `<location> + <bold control label> +
<action> + <optional value>` -- and the `<b>` spans delimit the UI identifiers,
so steps can be parsed into structured actions fairly reliably. Tutorials are
**localized** (`en/`, `ja/`, `zh-CHS/`): each transcribes the *visible label in
that language*, matching the localized UI.

### Decision: Approach A (two backends, unified contract)

Drive WinForms forms via **direct `Control`-tree access on the UI thread**;
drive native dialogs via **UIA/MSAA off the UI thread**. Unify only at the
**DTO + verb contract** -- each verb dispatches on `FormInfo.IsNative`, exactly
as `GetOpenForms`/`GetFormImage` already do.

Rejected alternative **B** (drive *everything* through UIA, since WinForms
controls also expose UIA providers): more uniform, but UIA over in-process
WinForms is slower/flakier than typed access and some custom controls have thin
UIA support. Keep the proven typed path for real forms. (If duplication ever
hurts, B is worth a spike; setting `AccessibleName` -- see below -- would also
make a future B pivot cheaper.)

### Control-model DTO (`GetFormState`)

Not a flat list -- a **hierarchy**, because the tutorials disambiguate by
container ("the **Name** field of the **Build Library** form", "the **Digestion**
tab"). Per control:

* **Stable key** -- `Control.Name` (WinForms) / `AutomationId` (native). The key
  the *service* acts on. Locale-independent; never used for matching tutorial
  text.
* **Visible label** -- *derived*, in the current UI language, by precedence:
  `Control.Text` -> associated/preceding `Label` -> `AccessibleName` if set ->
  `Control.Name`. This is what tutorial text matches against.
* **Container path** -- Form title -> TabPage -> GroupBox -> control, for scoped
  disambiguation.
* **Kind** -- model on UIA's `ControlType` vocabulary (Edit, Button, ComboBox,
  CheckBox, RadioButton, List, Tab, ...).
* **Current value** + **states** (enabled / visible / focusable / checked).

### Matching rule (tutorial step -> control)

Match the bolded label against the **derived visible label in the current UI
language**, scoped by the named container (form / tab / group) and filtered by
control kind. Labels are not unique ("Name", "OK" recur), so the container path
does the disambiguation -- the same way the tutorial sentence does.

**Localization is the through-line.** The connector operates in terms of the
current language's visible strings; automation/tests run per language. Always
**derive labels from the live UI**, never author a parallel copy -- a derived
label is guaranteed to match the string the tutorial author transcribed.

### On `AccessibleName`

Do **not** start setting `AccessibleName` across Skyline for the sake of the AI
Connector. Under Approach A the action key is `Control.Name`, and the match key
is the derived visible label -- both already exist. A hand-authored
`AccessibleName` is a separately-localized duplicate that can drift from the
visible label and silently break matching, and tutorials never reference a
control that has no visible label anyway. Keep `AccessibleName` as optional
real-accessibility work (blind users / Section 508), justified on its own
merits, plus surgical use on the rare unlabeled control the AI cannot resolve.

### Verbs (beyond enumerate / set / submit)

The MethodEdit tutorial alone exercises all of these, so the service needs more
than form-filling:

* `GetFormState(formId)` -- the DTO above.
* `SetFormValues(formId, {controlKey: value})` -- text, checkbox, combo
  selection (combo set **by visible item text**, also localized).
* `ClickButton(formId, buttonKey)` / submit-default (the native default-button
  accept is proven by the spike; WinForms = `AcceptButton.PerformClick()` or a
  named button).
* `InvokeMenuItem(path)` -- e.g. "Settings > Peptide Settings".
* `SelectTab(formId, tabKey)`.
* `SelectTreeNode(locator)` -- the Targets tree (overlaps existing
  selection/ElementLocator APIs).
* `SendKeys` / press-key -- "Press the down-arrow key...".

Out of scope for the service: steps that leave Skyline (e.g. Notepad
copy/paste) -- those are the connector/agent's own desktop control, not this API.

### Threading

WinForms verbs marshal to the UI thread; native modal-dialog verbs run **off**
it (the UI thread is blocked in the dialog's message loop -- the deadlock
already noted for `GetOpenForms`). Each verb branches on `IsNative` and picks
the thread accordingly. The "unified" surface is the contract, not one code
path.

### Dialog chains are on the critical path

Tutorials stack modal dialogs (Peptide Settings -> Build Library -> Browse ->
native file dialog -> ...). The native-dialog automation in this branch is not a
side feature; it is directly on the tutorial path, and the off-UI-thread
contract is what makes nested native dialogs operable.

### Division of labor

The C# service exposes **primitives** (the verbs above). The **tutorial runner**
-- parse a localized tutorial into steps, resolve each step's control by label +
container, choose the verb, handle dialog chains -- is an agent loop in the MCP
client (Claude), not C# code.

## Verification

* `NativeFileDialogTest` (discovery + image + cancel + open) -- passes,
  stable across repeated runs (~1-2s).
* `LiveReportsTutorialTest` -- passes (~20s), exercises `OpenDocument`.
* `SkylineMcpTest`, `CodeInspection` -- pass. Solution builds clean.

## Localization fix for connector verb tests (2026-07-21, Brendan + Claude)

### Problem

Nightly ran the new `*McpConnectorTest` functional tests under all languages and
11 failed under Chinese (zh-CHS) and Japanese (ja) but passed in English,
French, and Turkish (fr/tr are not translated, so the UI stays English). Root
cause: the tests match controls / assert against **hardcoded English UI text**,
which only diverges once the UI is actually translated -- a violation of the
translation-proof rule that will red the localized nightly on merge. This is a
merge blocker.

Failing tests: ClickControl, Clipboard, ContextMenu, GetControls, LazyMenu,
PerformAction, PickChildren, PlainGrid, Prm, SetFormValue, SetGridText.

### Fix pattern

Resolve every localized token from its resource the same way the *passing*
sibling tests (`ClickCheckedList`, `SetItem`) already do -- never a literal:

* **Designer control captions** (labels, buttons, tab pages) ->
  `GetLocalizedText<TForm>("fieldName")` (reads `"<field>.Text"` from the form's
  ComponentResourceManager).
* **Image-only controls matched by tooltip** -> new helper
  `GetLocalizedToolTip<TForm>("fieldName")` (reads `"<field>.ToolTipText"`);
  added to `McpConnectorTest` beside `GetLocalizedText`. Needed because the
  PopupPickList green-check commit button's caption is `"OK"` in en/ja but
  `"确定"` in zh-CHS, and it lives in `.ToolTipText`, not `.Text`.
* **Menu paths** -> `MenuPath<TMenu>(...field names...)`.
* **Grid column headers** -> read the live column's `HeaderText` (already
  localized by `ApplyResources` / the databinding `DisplayName`), not a literal.
* **Enum display values** (annotation type "Number") ->
  `ListPropertyType.GetAnnotationTypeName(AnnotationDef.AnnotationType.number)`.
* **String-table entries** -> the strongly-typed `Resources.*` /
  `AuditLogStrings.*` identifier.

### Per-test mapping (all source-verified)

| Test | Literal -> resolution |
|------|----------------------|
| GetControls | `"Name"`/`"Applies to"`/`"OK"` -> `GetLocalizedText<DefineAnnotationDlg>("lblName"/"lblAppliesTo"/"btnOK")` |
| SetFormValue | `"Name"`/`"Type"` -> `GetLocalizedText<DefineAnnotationDlg>("lblName"/"lblType")`; `"Number"` -> `ListPropertyType.GetAnnotationTypeName(AnnotationDef.AnnotationType.number)` |
| Clipboard | `"Name"` -> `GetLocalizedText<DefineAnnotationDlg>("lblName")` |
| PerformAction | `"Name"` -> `lblName`; `"Cancel"` -> `GetLocalizedText<DefineAnnotationDlg>("btnCancel")` |
| ContextMenu | `"Log Scale"` -> `GetLocalizedText<PeakAreasContextMenu>("peptideLogScaleContextMenuItem")` |
| PickChildren | `"Pick Children"` -> `GetLocalizedText<TreeNodeContextMenu>("pickChildrenContextMenuItem")`; `"OK"` -> `GetLocalizedToolTip<PopupPickList>("tbbOk")` |
| ClickControl | `"Enable audit logging"` -> `AuditLogStrings.AuditLogForm_AuditLogForm_Enable_audit_logging`; `"Quantification"` -> `GetLocalizedText<PeptideSettingsUI>("tabQuantification")` |
| Prm | `"Add Files"` -> `GetLocalizedText<BuildPeptideSearchLibraryControl>("btnAddFile")` |
| LazyMenu | menu path -> `MenuPath<ViewMenu>("viewToolStripMenuItem","liveReportsMenuItem","groupComparisonsMenuItem","addGroupComparisonMenuItem")` (base class changed `AbstractFunctionalTest` -> `McpConnectorTest` so the helper is in scope) |
| PlainGrid | header `"Pattern"` -> `rulesGrid.Columns["colPattern"].HeaderText` |
| SetGridText | header `"Note"` -> `noteColumnObj.HeaderText` |

Also corrected the now-stale "Runs in en" / "runs in en otherwise" class-doc
comments on SetFormValue and ClickControl.

### Connector bug uncovered by the fix (UiElement.GetChild)

Fixing the labels advanced GetControls / PerformAction past the label lookup and
exposed a real **connector** defect (not a test bug): the GetControls -> PerformAction
round-trip threw in ja/zh:

    The TextBox at index 0 does not match the Text '名前(N)' in the path.

`UiElement.GetChild`'s indexed branch verified the path's Text with only a LOOSE
match (`MatchesText(text, false)`). Loose match rejects any key carrying a symbol
by design (`TextMatches`: `if (HasSymbol(key)) return false`). GetControls emits
the normalized label as the path Text, and a Japanese mnemonic normalizes to
`名前(N)` -- the parentheses are a symbol -- so the loose-only check always failed
to re-resolve a path the connector itself produced. The non-indexed branch already
did strict-then-loose; the indexed branch was inconsistent. English hid it (`Name`
has no symbol; the old English-literal test also failed earlier, never reaching the
round-trip).

Fix (`pwiz_tools/Skyline/ToolsUI/UiElement.cs`, GetChild indexed branch): accept a
strict OR loose match, matching the non-indexed branch:
`!indexed.MatchesText(path.Text, true) && !indexed.MatchesText(path.Text, false)`.
Strictly additive (more permissive), so it cannot regress a previously-passing match.

### Verification (done, warm build)

Built pwiz-work2 (solution build after the C# change) and ran the connector verb
tests offscreen:

* All 11 verb tests -- **0 failures in ja**.
* The two round-trip tests (GetControls, PerformAction) -- **0 failures in en AND ja**.

Still recommended before merge: the full localized nightly (ja + zh-CHS) across the
whole branch, ideally on a dedicated integration branch, since this is a large branch
and this class of failure only shows under a real multi-language run.

### TestPrmMcpConnector: case-insensitive path compare (parallel Docker)

A follow-up run under the parallel Docker test framework failed TestPrmMcpConnector in
ALL languages. Not a localization issue: the native Open dialog returns the drive letter
upper-cased ("C:\..."), while the Docker worker's results path (and so the expected
paths) is lower-cased ("c:\AlwaysUpCLT\TestResults_N\..."), and the pre-existing
`CollectionAssert.AreEquivalent` compared case-sensitively. Reproduced locally by
running the test with a lowercase-drive `results=` path; the added expected-vs-actual
dump showed the drive letter as the only difference. Fixed by comparing the paths
case-insensitively (Windows paths are case-insensitive) and keeping the diagnostic
message. Verified: lowercase-drive repro passes, and all 11 tests pass in en/fr/ja/tr/zh.
