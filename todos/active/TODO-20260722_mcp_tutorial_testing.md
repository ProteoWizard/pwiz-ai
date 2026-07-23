# MCP Tutorial Testing — process, runner & results

## Status

**Active.** Spun off 2026-07-23 from the PR #4313 connector work
(`TODO-20260609_native_file_dialog_automation`, being completed to
`todos/completed/`) so this testing effort continues as its own TODO across
multiple sprints, independent of that PR's lifecycle. The connector foundation is
in place; this effort drives the Skyline tutorials end-to-end through it, catalogs
what works and what's still missing, and feeds implementation sprints — each its
own TODO (e.g. the backlog
[`../backlog/TODO-mcp_tutorial_view_layout.md`](../backlog/TODO-mcp_tutorial_view_layout.md)).

**Layout:** this file is the **runbook**. The per-tutorial result files
(`TEST-<Name>.md`) live in the sibling
**[`TODO-20260722_mcp_tutorial_testing/`](TODO-20260722_mcp_tutorial_testing/)**
folder — their presence there is also the cross-machine claim (§2.1). Where the
sections below say "this folder" for `TEST-*.md` files, they mean that folder.

**Running autonomously?** Launch `/night-session <this file>` — the executable
loop is in **[▶ Run this](#-run-this-night-session-entry-point)** below; the rest
is detail it references.

This runbook operationalizes the "tutorial runner" agent loop that PR #4313's
**Phase 3 design** describes:

> *"The tutorial runner — parse a localized tutorial into steps, resolve each
> step's control by label + container, choose the verb, handle dialog chains —
> is an agent loop in the MCP client (Claude), not C# code."*

The runner **is a Claude session following this document.** There is no C#
tutorial-runner to build; the deliverable is proof that a Claude session, given
the MCP, can complete a tutorial the way a supported user would — and a
high-signal list of where it can't (yet).

---

## ▶ Run this (night-session entry point)

Launch on any set-up machine:

```
/night-session C:\proj\ai\todos\active\TODO-20260722_mcp_tutorial_testing.md
```

The session becomes the **orchestrator**: it claims one unclaimed tutorial, runs
it (via a sub-agent), then the next, and so on until interrupted (~7–8 h). Start
it on several machines at once — coordination is automatic through the git claim
(§2.1). Sections below are the details; this is the loop.

### Kickoff — the one moment a human is needed

Do this once when you launch, then walk away:

1. Confirm Skyline (debug, on the PR #4313 branch) is running with the AiConnector
   loaded, and `skyline_get_instances` shows exactly one instance.
2. **Grant screen capture.** As its first act the orchestrator calls
   `skyline_get_form_image` on the main window; on a freshly-started Skyline this
   opens a consent dialog *inside Skyline* — click to grant while you're still
   there. The grant persists for the **life of that Skyline process**, so repeat
   night-sessions against the same running Skyline inherit it and this step goes
   silent. (Only human-in-the-loop step — Finding #3 in `TEST-MethodEdit.md`; a
   Skyline restart requires re-granting.)

### Orchestrator loop (autonomous)

Prime once: call `skyline_get_form_image` on `SkylineWindow:Skyline` and, if it
returns "permission required", surface it and wait for the grant (kickoff step 2).
Then repeat until interrupted:

1. `git pull --rebase` in `ai/` (pick up other machines' claims).
2. Get the tutorial Name list from `skyline_get_available_tutorials`. The
   **unclaimed** set = Names with no `TEST-<Name>.md` in this folder.
3. If none unclaimed → every tutorial is taken; stop and log that coverage is
   complete.
4. Pick the first unclaimed Name. `skyline_new_document` to start clean (dismiss a
   save prompt without saving if one appears).
5. **Spawn ONE sub-agent** (Agent tool) with the §7 prompt for that Name and
   **await** it. Never spawn a second while one is running — they share the one
   Skyline.
6. If it returns `CLAIM COLLISION` (another machine claimed it first), just loop.
   Otherwise keep its one-paragraph summary in your **own** context (do not
   commit it anywhere) and loop.

Keep the orchestrator lean: it does **not** fetch tutorial markdown/images or
drive the UI — the sub-agent does, so those tokens are discarded per tutorial and
the orchestrator survives the whole session. Each sub-agent claims (§2.1) and
commits its own progress, so an interruption mid-tutorial still leaves a pushed
claim plus whatever was committed.

> **Stalled claims:** a `TEST-<Name>.md` left at `Status: CLAIMED`/`WIP` by a
> dead session blocks re-pickup (claim = file present). For now a human resolves
> stalled claims (resume or delete the file); auto-resuming them is a future
> improvement, not v1.

---

## 1. Purpose & goals

For each Skyline tutorial, a test run answers three questions:

1. **Completability** — can Claude drive the tutorial from a blank document to
   its final deliverable (exported list, imported results, etc.) using only MCP
   verbs, the way a user + Claude pairing would?
2. **Fidelity** — at every tutorial screenshot, does the live Skyline UI match
   the reference image (and do document counts match the tutorial's status-bar
   numbers)?
3. **Gaps & bugs** — where the runner is blocked or the UI diverges, *why*, and
   *what should Nick and Brendan change* to fix it (MCP connector, a tool's
   fidelity, the tutorial text, or the run harness).

The output of a run is a `TEST-<Name>.md` file (see §6) ending in a classified,
actionable findings list.

Scope grows over time: start with `MethodEdit`, then **eventually all
tutorials** (reference list in §8). One tutorial = one `TEST-<Name>.md`, whose
presence in this folder also claims it (§2.1).

---

## 2. Orchestration & coordination

Runs happen on **multiple machines at once** (Brendan's and Nick's), each driving
its own Skyline instance, to get through the tutorial set quickly. Parallelism is
**across machines**; **within a machine the tutorials run one at a time.**

### Within a machine (the `/night-session` orchestrator)

To survive a full 7–8 h session without exhausting the orchestrator's context:

- The **orchestrator** owns only: which tutorials it still intends to try, and
  each finished sub-agent's **one-paragraph** status. It does **not** fetch
  tutorial markdown/images or drive the UI itself — those tokens would accrue to
  its own budget.
- It spawns **one sub-agent per tutorial**, **strictly in sequence — never in
  parallel on the same machine.** There is a **single shared Skyline instance**
  (`skyline_get_instances`); concurrent drivers would race on document state and
  modal dialogs — the same shared-instance hazard that forces `regression.ps1`
  to run serially. (Budget is the second reason: a discarded per-tutorial
  sub-agent context keeps the orchestrator lean.)
- Each sub-agent: **claims** a tutorial (§2.1), reads this README, runs §4,
  writes `TEST-<Name>.md` incrementally with periodic commits, and returns a
  short status. Prompt template in §7.
- Between tutorials the orchestrator resets to a blank document
  (`skyline_new_document`).

### 2.1 Claiming a tutorial (distributed lock via git)

Several machines share this folder through the **pwiz-ai** repo (`ai/` commits go
straight to `master`, no feature branches). **A committed `TEST-<Name>.md` is the
claim** on that tutorial. The set of `TEST-*.md` files present in this folder —
**not** the table in §8 — is the **authoritative** record of what is claimed and
done. Never coordinate by hand-editing §8; it will only merge-conflict.

Claim protocol, run **before** driving any tutorial:

1. `git pull --rebase` in `ai/`.
2. Pick the first tutorial with **no** `TEST-<Name>.md` yet.
3. Create the stub `TEST-<Name>.md` (Run-context header + `Status: CLAIMED by
   <user@machine> <timestamp>`).
4. `git add` the stub → `git commit -m "Claim <Name> tutorial test"` →
   `git pull --rebase` → `git push`.
5. If the rebase reveals the file **already exists from another machine** (a
   claim collision — rare), **yield**: discard your stub, return to step 2, pick
   the next unclaimed tutorial.
6. On a clean push you own it. Drive it, and **commit + push progress
   periodically** (and once at the end) so other machines see it is taken and can
   still read partial findings if your session is cut short.

Because different machines claim *different* files, pushes almost never textually
conflict; the only race — two machines picking the same tutorial in the same
window — is resolved by step 5 (first push wins, the loser re-picks).

---

## 3. Prerequisites (verify before driving)

A run is only valid if the environment is set up correctly. Check each:

- [ ] **Debug Skyline running on the branch** and connected: `skyline_get_instances`
      shows exactly one instance; note its PID and version.
- [ ] **AiConnector + Skyline MCP loaded** (the `mcp__skyline__*` tools respond).
- [ ] **Tutorial data on disk** at the path the tutorial references (e.g.
      `Documents\MethodEdit`). Download via the Start Page → Tutorials tab or the
      tutorial ZIP, then confirm the subfolders/files exist before starting.
- [ ] **Screen-capture permission granted.** The **first** `skyline_get_form_image`
      of a session opens a consent dialog *inside Skyline* and returns
      "permission required" — a human must grant it once. **For an autonomous
      night run this must be pre-granted** (see the finding in §5 of
      `TEST-MethodEdit.md`; a pre-authorization path is a known gap).
- [ ] **Chrome / editors kept OFF the Skyline window.** Non-Skyline content
      overlapping a Skyline form is redacted to solid **cyan** in captures. Park
      the tutorial browser on another monitor / behind Skyline.
- [ ] **Default settings + correct UI mode.** Follow the tutorial's "Getting
      Started": `Settings > Default` (answer **No** to "save current settings"),
      and set the UI mode (`skyline_set_ui_mode` → `proteomic` /
      `small_molecules`) the tutorial expects.

---

## 4. Methodology — the per-tutorial loop

1. **Discover.** `skyline_get_available_tutorials`. Note: the **Name** column is
   the directory slug used by the MCP tools (`MethodEdit`); the **Title** is the
   human name ("Targeted Method Editing"). Use the Title when narrating.
2. **Fetch the script.** `skyline_get_tutorial(name)` → read the whole markdown.
   Enumerate every `[Screenshot: s-XX.png]` — **these are the mandatory
   checkpoints.** Also note the counts the tutorial states (e.g. "reduced from 70
   to 64", "355 transitions") — they are free assertions.
3. **Confirm data.** List the data folder; confirm the files the tutorial names
   are present.
4. **Drive each step, in tutorial order,** mapping the instruction's
   `<location> + <bold control> + <action> + <value>` to MCP verbs:
   - **Menus:** `skyline_click_main_menu_item` ("Settings > Peptide Settings").
     Submenu **leaves built on demand** (e.g. `Ion Types > B`) may not resolve —
     enumerate with `perform_action get_children` to confirm the path, and see
     the §5 finding in `TEST-MethodEdit.md` for the current gap.
   - **Dialogs:** `get_open_forms` → `get_controls` → `set_form_value` /
     `click_form_button` / `perform_action select_tab`. A caption-less control
     (TabControl, SequenceTree, a graph) is addressed by **`type`**, not
     `label`. Commit/cancel with `dismiss_with_accept_button` /
     `dismiss_with_cancel_button` / `dismiss_with_button` ("No").
   - **Native file dialogs** (`Type=Dialog`, `IsNative=True`): set the **full
     path** on the file-name field, then `dismiss_with_accept_button`.
   - **Document edits:** prefer the **faithful UI path the tutorial describes**
     over a convenience tool when they diverge. Notably, reproduce a FASTA/list
     **paste** with `Set-Clipboard` (PowerShell) + `Edit > Paste`, *not*
     `skyline_import_fasta` — see the empty-proteins finding in
     `TEST-MethodEdit.md`.
   - **Selection / tree navigation:** the Targets tree is **not** enumerable via
     `get_children`. Get element locators with `skyline_get_locations`
     (`group` → `molecule` → `precursor` → `transition`, optionally scoped by a
     parent locator), then `skyline_set_selection`.
5. **At EVERY screenshot — compare.** Capture the live UI
   (`skyline_get_form_image` for forms/main window; `skyline_get_graph_image`
   for ZedGraph graphs — renders directly, no screen capture) **and** fetch the
   reference (`skyline_get_tutorial_image`). Record PASS or DIVERGENCE. A
   fully-cyan capture means window overlap — **retry once** after ensuring
   Skyline is frontmost.
6. **Assert state at section boundaries.** `skyline_get_document_status` and, for
   selection context, the status-bar counts visible in the captured main window
   (`sel/total prot · pep · prec · tran`). Compare to the tutorial.
7. **Log as you go.** Append each step outcome and every screenshot comparison to
   `TEST-<Name>.md` **immediately** — a crash or budget cutoff should leave a
   usable trail, never a silent gap.

**Don't rabbit-hole.** If a single UI action fails ~3 times, stop, classify it as
a finding (§5), record the exact failing calls, and move on. Note in the log
whether the block is cosmetic (annotation only) or halts the workflow.

---

## 5. Classifying every issue

Each divergence or block gets one label, so Nick and Brendan can route the fix:

| Class | Meaning | Fix owner |
|-------|---------|-----------|
| **MCP capability gap** | The MCP cannot perform a step the tutorial requires. | Connector / MCP code |
| **MCP tooling fidelity** | A convenience tool works but isn't faithful to the UI path (different result). | Tool behavior / docs; runner prefers UI path |
| **Tutorial-text** | Wording/menu path is ambiguous, stale, or wrong. | Tutorial HTML |
| **Environmental / harness** | Setup or capture artifact (permission handshake, cyan overlap). | Runner setup / this README |
| **Skyline bug** | Genuine product defect surfaced while driving. | File a Skyline issue |

For each finding record: **what happened**, the **exact tool call(s) + result**,
the **screenshot ref**, the **class**, whether it **halted** the run, and a
**concrete fix suggestion**.

---

## 6. `TEST-<Name>.md` format

Write one per tutorial. Structure (see `TEST-MethodEdit.md` as the worked
example):

```
# TEST — <Title> (<Name>)

## Run context
- Branch / PR, Skyline version + build hash, connected PID
- Date, data folder, UI mode
- Driver: <orchestrator or standalone session>

## Screenshot checklist
| Screenshot | Section | Status | Note |
|-----------|---------|--------|------|
| s-01 | Spectral Library | PASS | exact |
| ...   | ...             | ...    | ...   |

## Progress log
(chronological; per section, per step; PASS / DIVERGENCE / BLOCKED with the
tool calls and observations that matter)

## Findings & fix suggestions
(numbered, each classified per §5, most-impactful first)

## Final status
- Completed end-to-end? If not, where it stopped and why.
- Blocking issues vs. cosmetic issues.
- Overall: can a user + Claude finish this tutorial today via the MCP?
```

---

## 7. Sub-agent prompt template (orchestrator → per-tutorial agent)

> You are a per-tutorial test agent. Test whether Claude can drive the Skyline
> tutorial **"<Title>"** (`<Name>`) end-to-end through the Skyline MCP. The runbook
> is `ai/todos/active/TODO-20260722_mcp_tutorial_testing.md` — read it and follow §3
> prerequisites and §4 methodology **exactly**. Every `TEST-<Name>.md` (including
> the one you create) lives in `ai/todos/active/TODO-20260722_mcp_tutorial_testing/`.
>
> 1. **Load tools.** The `mcp__skyline__*` tools are deferred — load what you need
>    via ToolSearch (README §4 names the verbs).
> 2. **Claim it (§2.1).** `git pull --rebase` in `ai/`. If `TEST-<Name>.md`
>    already exists, STOP and return exactly `CLAIM COLLISION`. Otherwise create
>    the stub `TEST-<Name>.md` (Run-context header + `Status: CLAIMED`), then
>    `git add`/`commit`/`pull --rebase`/`push`.
> 3. **Run.** Drive every step through MCP verbs; **pause at every screenshot** to
>    capture the live UI and compare to the reference; log progress to
>    `TEST-<Name>.md` **as you go** and `git commit`+`push` it periodically so an
>    interruption preserves progress. Don't rabbit-hole — after ~3 failed attempts
>    at one action, classify it (§5), record the exact calls, and continue.
> 4. **Finish.** Fill in "Findings & fix suggestions" and "Final status", update
>    the `Status:` line, final `commit`+`push`.
> 5. **Return** a **one-paragraph** summary: completed end-to-end? blocking vs.
>    cosmetic finding counts; the single most important fix suggestion. (Or
>    `CLAIM COLLISION` from step 2.)

The orchestrator runs the loop at the top ("▶ Run this"): reset to a blank
document between tutorials (`skyline_new_document`), spawn one sub-agent at a time
and await it, keep the returned paragraph in its **own** context (never commit it
to §8). Each sub-agent claims via §2.1 first, so two machines never drive the same
tutorial; a `CLAIM COLLISION` return just means loop and pick the next unclaimed
Name.

---

## 8. Tutorial reference list

**Non-authoritative** — a convenience list of the tutorial set. The real
claim/coverage state is the set of committed `TEST-*.md` files in this folder
(§2.1); do **not** coordinate by editing this table (it would merge-conflict
across machines). The Status column here is at best a stale hint — trust the
files, refreshed from `skyline_get_available_tutorials`.

Status hints: `—` not started · `WIP` in progress · `PASS` end-to-end · `ISSUES`
completed-with-findings · `BLOCKED` could not finish.

| Tutorial (Name) | Title | Status | Result file |
|-----------------|-------|--------|-------------|
| MethodEdit | Targeted Method Editing | WIP | `TEST-MethodEdit.md` |
| MethodRefine | Targeted Method Refinement | — | |
| GroupedStudies | Grouped Study Data Processing | — | |
| ExistingQuant | Existing & Quantitative Experiments | — | |
| AcquisitionComparison | Comparing PRM, DIA, and DDA | — | |
| PRMOrbitrap | PRM With an Orbitrap Mass Spec | — | |
| DIA | Data Independent Acquisition | — | |
| MS1Filtering | MS1 Full-Scan Filtering | — | |
| DDASearch | DDA Search for MS1 Filtering | — | |
| PRM | Parallel Reaction Monitoring (PRM) | — | |
| DIA-TTOF | Analysis of TripleTOF DIA/SWATH Data | — | |
| DIA-PASEF | Analysis of diaPASEF Data | — | |
| DIA-Umpire-TTOF | Library-Free DIA/SWATH | — | |
| PeakBoundaryImputation-DIA | Peak Boundary Imputation for DIA | — | |
| SmallMolecule | Small Molecule Targets | — | |
| SmallMoleculeMethodDevCEOpt | Small Molecule Method Dev & CE Optimization | — | |
| SmallMoleculeQuantification | Small Molecule Quantification | — | |
| HiResMetabolomics | Hi-Res Metabolomics | — | |
| SmallMoleculeIMSLibraries | Small Molecule IMS Libraries | — | |
| CustomReports | Custom Reports | — | |
| LiveReports | Live Reports | — | |
| AbsoluteQuant | Absolute Quantification | — | |
| PeakPicking | Advanced Peak Picking Models | — | |
| iRT | iRT Retention Time Prediction | — | |
| OptimizeCE | Collision Energy Optimization | — | |
| IMSFiltering | Ion Mobility Spectrum Filtering | — | |
| LibraryExplorer | Spectral Library Explorer | — | |
| AuditLog | Audit Logging | — | |

(Tutorial set as of Skyline 26.1; refresh from `skyline_get_available_tutorials`.)
