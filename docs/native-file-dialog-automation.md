# Native file dialog automation (UI Automation + Win32) — reference & cross-OS checklist

Context for branch `Skyline/work/20260609_native_file_dialog_automation` and issue
[#4089](https://github.com/ProteoWizard/pwiz/issues/4089). The connector drives Skyline's
**native** Open/Save file dialogs (they are not WinForms forms, so they never appear in
`FormUtil.OpenForms`). Code lives in `pwiz_tools/Skyline/ToolsUI/`:
`NativeDialogAutomation` (base), `FileDialogAutomation` (file-dialog base),
`OpenFileDialogAutomation`, `SaveFileDialogAutomation`.

**Why this doc exists:** the dialog's internal control identifiers can vary by Windows
version. The automation hard-codes a few of them. When validating on a new Windows build,
re-dump the dialog (scripts below) and confirm the IDs the code keys on still match.

## How discovery works

- Both the modern Open and Save dialogs are **`#32770`** top-level windows, **owned by**
  the window that launched them (the main window, or a nested modal wizard).
- An *owned* window nests under its owner in the **UI Automation** tree — it is NOT a child
  of the desktop root. So a UIA child-walk from `RootElement` misses it. Discovery therefore
  uses Win32 **`EnumWindows`** (filter to the process + class `#32770`), then
  `AutomationElement.FromHandle(hwnd)`. See `NativeDialogAutomation.FindDialogElements`.
- The threading contract: a native dialog is modal and runs its own message loop on the UI
  thread, so all of this must run **off** the UI thread (the MCP pipe thread / test thread),
  never on the UI thread.

## Identifiers the code depends on (verified on Windows 11 Pro 26200)

### Open dialog — `OpenFileDialogAutomation`
- Recognized by a descendant with **`AutomationId = "1148"`** (the classic "File name" combo,
  cmb13). The modern Open dialog still exposes this and its inner `Edit` supports the UIA
  **`ValuePattern`**, so the path is set with `ValuePattern.SetValue` and accepted by posting
  **Enter** (`WM_KEYDOWN`/`WM_KEYUP`, `VK_RETURN`) to the edit.

### Save dialog — `SaveFileDialogAutomation`
The modern (Vista-style `IFileDialog`) Save dialog is structurally different:
- It does **NOT** have `AutomationId 1148`. It is recognized instead by a descendant with
  **`AutomationId = "FileNameControlHost"`** (class `AppControlHost`).
- File-name field: inside that host, an element with **`AutomationId = "1001"`,
  `ClassName = "Edit"`** (UIA `ControlType` is reported as `Pane`, not `Edit`). It exposes
  **no `ValuePattern`/`InvokePattern`**, but it IS a real Win32 `Edit` window with a handle.
  → set the text with **`WM_SETTEXT`** on its `NativeWindowHandle`.
  - ⚠️ `AutomationId "1001"` is **ambiguous** — the address-bar breadcrumb (`ToolbarWindow32`)
    shares it. Locate the edit by **host + `ClassName="Edit"`**, not by id alone.
- Save button: **`AutomationId = "1"`, `ClassName = "Button"`** (control id 1 = IDOK). Real
  Win32 `Button`, no `InvokePattern`. → click with **`BM_CLICK`** on its `NativeWindowHandle`.
- Cancel button: `AutomationId = "2"` (IDCANCEL); the base `Cancel()` posts `WM_CLOSE` instead.

Because the work runs **in-process** with the dialog (the JSON tool server is hosted inside
Skyline), `WM_SETTEXT` can pass a locally-allocated `Marshal.StringToHGlobalUni` pointer as
lParam. `User32.SendMessage` is `CharSet.Auto` → `SendMessageW`, so the wide string is correct.

### Reference UIA dump of the Save dialog (Windows 11, abridged)

```
Window  name='Save As' class='#32770'
  Pane  class='DUIViewWndClassName'
    ... Details Pane ...
      Text  name='File name:'  id='SaveDialogLabel'  class='CIDLabel'
      Pane  name='File name:'  id='FileNameControlHost'  class='AppControlHost'
        Pane  name='<file>.sky'  id='1001'  class='Edit'        <-- WM_SETTEXT target
      Pane  name='Save as type:' id='FileTypeControlHost'
  Pane  name='Save'    id='1'  class='Button'                   <-- BM_CLICK target (IDOK)
  Pane  name='Cancel'  id='2'  class='Button'                   (IDCANCEL)
  Pane  class='WorkerW' ... (address bar; note another id='1001' ToolbarWindow32 here)
```

Proven end to end: setting the edit + clicking Save changed the document path and cleared
the dirty flag, all via window messages.

## Cross-OS verification checklist (run on the new Windows version)

1. Launch the freshly built Skyline, open a document, trigger **File > Save As**.
2. Run `dump-dialog-uia.ps1` (below). Confirm:
   - A `#32770` dialog is found for the process (owned by the main window).
   - There is a descendant `AutomationId="FileNameControlHost"` (recognition still works).
   - Under it, an element `ClassName="Edit"` exists.
   - A `ClassName="Button"`, `AutomationId="1"` "Save" button exists.
3. Run `probe-save-dialog.ps1`. Confirm the file-name Edit and Save button both report a
   non-zero `NativeWindowHandle` (the WM_SETTEXT/BM_CLICK approach depends on this).
4. If any identifier differs (e.g. the host id, the edit class, or the Save button id), update
   the constants in `SaveFileDialogAutomation` and add a comment noting the Windows version.
5. Best: drive it through the connector — `skyline_get_open_forms` should list
   `FileDialog:Save As` (IsNative=True); `skyline_set_form_value` then `skyline_click_form_button
   "FileDialog:Save As" "Save"` should save. Also re-verify **Open** has not regressed.

If something is off, `dump-dialog-uia.ps1` is the first tool — it shows the live tree so you
can see how the new OS names things and adjust the recognizer/locators.

## Diagnostic scripts

These were used to reverse-engineer the dialog. They take no arguments beyond an optional
save path; they find the `#32770` dialog of the running `Skyline-daily` process. (Adjust the
process name for a release build named `Skyline`.) Saved here because `ai/.tmp/` is not
committed.

### `dump-dialog-uia.ps1` — dump the dialog's UIA subtree

```powershell
# Finds the #32770 dialog owned by the Skyline-daily process (via Win32 EnumWindows, since an
# owned dialog nests under its owner in the UIA tree) and dumps its UIA subtree.
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
}
"@
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$ae=[System.Windows.Automation.AutomationElement]
$proc=Get-Process -Name 'Skyline-daily'|Select-Object -First 1
$target=[uint32]$proc.Id
$dlg=[IntPtr]::Zero
$cb=[W+EnumProc]{ param($h,$l)
  [uint32]$pid2=0;[void][W]::GetWindowThreadProcessId($h,[ref]$pid2)
  if($pid2 -eq $target){ $cn=New-Object System.Text.StringBuilder 256;[void][W]::GetClassName($h,$cn,256)
    if($cn.ToString() -eq '#32770'){ $script:dlg=$h } }
  return $true }
[void][W]::EnumWindows($cb,[IntPtr]::Zero)
if($dlg -eq [IntPtr]::Zero){ 'No #32770 dialog found'; exit }
'DIALOG hwnd=0x{0:X}' -f [int64]$dlg
$el=$ae::FromHandle($dlg)
$probe=@{ 'Value'=[System.Windows.Automation.ValuePattern]::Pattern
  'Invoke'=[System.Windows.Automation.InvokePattern]::Pattern }
function Pats($e){ $n=@(); foreach($k in $probe.Keys){ $o=$null; if($e.TryGetCurrentPattern($probe[$k],[ref]$o)){$n+=$k} }; return ($n -join ',') }
function Dump($e,$d){ if($d -gt 14){return}
  try{ $ct=$e.Current.ControlType.ProgrammaticName -replace 'ControlType\.',''
    Write-Output ((' '*($d*2))+("{0} | name='{1}' | id='{2}' | class='{3}' | pat=[{4}]" -f $ct,$e.Current.Name,$e.Current.AutomationId,$e.Current.ClassName,(Pats $e)))
  }catch{return}
  $wk=[System.Windows.Automation.TreeWalker]::RawViewWalker; $c=$wk.GetFirstChild($e)
  while($c -ne $null){ Dump $c ($d+1); $c=$wk.GetNextSibling($c) } }
Dump $el 0
```

### `probe-save-dialog.ps1` — confirm the key controls have native handles

```powershell
# Probes the Save dialog's file-name Edit and Save button: prints NativeWindowHandle and
# whether Value/Invoke patterns are supported (expected: handles non-zero, patterns absent).
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
}
"@
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$ae=[System.Windows.Automation.AutomationElement]
$proc=Get-Process -Name 'Skyline-daily'|Select-Object -First 1
$target=[uint32]$proc.Id
$dlg=[IntPtr]::Zero
$cb=[W+EnumProc]{ param($h,$l)
  [uint32]$pid2=0;[void][W]::GetWindowThreadProcessId($h,[ref]$pid2)
  if($pid2 -eq $target){ $cn=New-Object System.Text.StringBuilder 256;[void][W]::GetClassName($h,$cn,256)
    if($cn.ToString() -eq '#32770'){ $script:dlg=$h } }
  return $true }
[void][W]::EnumWindows($cb,[IntPtr]::Zero)
if($dlg -eq [IntPtr]::Zero){ 'No #32770 dialog'; exit }
$root=$ae::FromHandle($dlg); $ts=[System.Windows.Automation.TreeScope]::Descendants
function Probe($el,$label){ if($el -eq $null){ "$label : NOT FOUND"; return }
  $v=$null;$hasV=$el.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern,[ref]$v)
  $i=$null;$hasI=$el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern,[ref]$i)
  "{0}: id='{1}' class='{2}' hwnd=0x{3:X} Value={4} Invoke={5}" -f $label,$el.Current.AutomationId,$el.Current.ClassName,[int64]$el.Current.NativeWindowHandle,$hasV,$hasI }
$host2=$root.FindFirst($ts,(New-Object System.Windows.Automation.PropertyCondition($ae::AutomationIdProperty,'FileNameControlHost')))
$edit = if($host2){ $host2.FindFirst($ts,(New-Object System.Windows.Automation.PropertyCondition($ae::ClassNameProperty,'Edit'))) } else { $null }
Probe $edit 'FileNameEdit'
$save=$root.FindFirst($ts,(New-Object System.Windows.Automation.AndCondition(@(
  (New-Object System.Windows.Automation.PropertyCondition($ae::AutomationIdProperty,'1')),
  (New-Object System.Windows.Automation.PropertyCondition($ae::ClassNameProperty,'Button'))))))
Probe $save 'SaveButton'
```

### `drive-save-dialog.ps1` — prove WM_SETTEXT + BM_CLICK saves (use a throwaway path)

```powershell
# Sets the file-name Edit (WM_SETTEXT) and clicks Save (BM_CLICK). Pass a fresh path to avoid
# the overwrite prompt. Verifies the message-based approach independently of the C# code.
param([string]$SavePath = "$env:TEMP\mcp_saveas_test.sky")
Add-Type @"
using System;using System.Text;using System.Runtime.InteropServices;
public class W {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageW(IntPtr h, uint msg, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
}
"@
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes
$ae=[System.Windows.Automation.AutomationElement]
$proc=Get-Process -Name 'Skyline-daily'|Select-Object -First 1
$target=[uint32]$proc.Id
$dlg=[IntPtr]::Zero
$cb=[W+EnumProc]{ param($h,$l)
  [uint32]$pid2=0;[void][W]::GetWindowThreadProcessId($h,[ref]$pid2)
  if($pid2 -eq $target){ $cn=New-Object System.Text.StringBuilder 256;[void][W]::GetClassName($h,$cn,256)
    if($cn.ToString() -eq '#32770'){ $script:dlg=$h } }
  return $true }
[void][W]::EnumWindows($cb,[IntPtr]::Zero)
if($dlg -eq [IntPtr]::Zero){ 'No #32770 dialog'; exit }
$root=$ae::FromHandle($dlg); $ts=[System.Windows.Automation.TreeScope]::Descendants
$host2=$root.FindFirst($ts,(New-Object System.Windows.Automation.PropertyCondition($ae::AutomationIdProperty,'FileNameControlHost')))
$edit=$host2.FindFirst($ts,(New-Object System.Windows.Automation.PropertyCondition($ae::ClassNameProperty,'Edit')))
$save=$root.FindFirst($ts,(New-Object System.Windows.Automation.AndCondition(@(
  (New-Object System.Windows.Automation.PropertyCondition($ae::AutomationIdProperty,'1')),
  (New-Object System.Windows.Automation.PropertyCondition($ae::ClassNameProperty,'Button'))))))
$editH=[IntPtr]$edit.Current.NativeWindowHandle; $saveH=[IntPtr]$save.Current.NativeWindowHandle
[void][W]::SendMessageW($editH,0x000C,[IntPtr]::Zero,$SavePath)  # WM_SETTEXT
Start-Sleep -Milliseconds 300
[void][W]::SendMessage($saveH,0x00F5,[IntPtr]::Zero,[IntPtr]::Zero)  # BM_CLICK
"sent WM_SETTEXT('$SavePath') + BM_CLICK"
```

## Related session state (already committed)

- pwiz branch `Skyline/work/20260609_native_file_dialog_automation`, commit
  `Added Save file dialog automation for the AI Connector`.
- Other landed work (see `ai/todos/active/TODO-20260609_native_file_dialog_automation.md`):
  MCP works while the StartPage is showing (sync-context marshaling, tool service starts
  before the StartPage); `ClickFormButton` drives any `IButtonControl` (StartPage tiles);
  `SetFormValue` selects radio buttons; the PRM tutorial's Import Peptide Search wizard runs
  end to end over the connector (`Documentation/Tutorials/PRM/mcp-steps.txt`).
- PRM tutorial data on the original machine: `D:\Downloads\Tutorials\TargetedMSMSMzml_2.zip`,
  extracted to `...\TargetedMSMSMzml_extracted\TargetedMSMSMzml\Low Res\` (mzML, not .raw).
- Pre-existing CodeInspection failures on the branch (not from this work): the `oleacc.dll`
  P/Invoke in `OpenFileDialogAutomation` (the MSAA accept spike) and the User32/Kernel32
  `[DllImport]` "more methods than expected" counts. The Save work adds no new `DllImport`.
