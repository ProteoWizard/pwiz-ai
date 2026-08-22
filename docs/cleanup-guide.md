# Cleanup Guide

How to clean up `ai/.tmp/` and the machine's test data area. Driven by `/pw-cleanup`.

## Why this is a command and not a script

The measuring is deterministic and already scripted: `ai/scripts/Clean-TmpFiles.ps1`
lists candidates by age, category and size and can delete them. What it cannot do is
decide whether a given file is disposable, misplaced, or something that should have
been a durable document. That decision needs judgement and a conversation with the
developer, which is what makes this a command.

The script has existed for a long while and was not the gap. On 2026-08-22 `ai/.tmp`
had reached **79 GB across 706 entries**, and the largest item - a 75 GB directory of
Osprey run output - was 18 days old, well inside what the script would have swept. It
survived because nothing prompts anyone to run the script, and running it blind is
unsafe. The command is the thing that gets invoked.

## Phase 1 - `ai/.tmp`

1. **Measure first**, so the result can be stated as a before and after:

   ```bash
   du -sh ai/.tmp; ls -A ai/.tmp | wc -l
   ```

2. **Report** with the existing script - it already gives categories, per-item sizes,
   ages and a "would free" total, so do not write new reporting code:

   ```bash
   pwsh -File './ai/scripts/Clean-TmpFiles.ps1' -IncludeSubdirs -WhatIf
   ```

3. **Apply judgement** to what it lists. Every candidate is one of three things, and
   only the first is a simple delete:

   - **Disposable** - one-off logs, patch scripts, commit message drafts, MCP page
     downloads. Delete.
   - **Misplaced** - test or run output that should never have been written here.
     Delete it, and say so plainly: the fix is where the next one gets written, not
     the cleanup. Run output belongs under the machine's test data area; a session's
     own working files belong in `ai/.tmp/sessions/<YYYYMMDD>-<short-session-id>/`.
   - **Durable** - a design note, a measured result, an inventory someone will want in
     three months. Promote it to `ai/docs/` or into the relevant TODO first, then
     delete the copy. A durable document sitting in a temp folder is a document nobody
     will find.

4. **Name anything large or ancient explicitly** - over 100 MB or older than 90 days -
   with its size and date, and ask. Do not let a big or strange item go past in a
   summary line. Itemise the script's catch-all "Other" bucket rather than trusting it.

5. **Execute** the same command without `-WhatIf`, then report the before and after.

## Phase 2 - the test data area

The test data root is machine-specific (on BRENDANX-UW8 it is `D:\test`). Treat it as
**report-only** unless the developer approves specific items.

- **Do not run a recursive `du`.** Measured on a 2.4 TB tree, it exceeded two minutes
  and timed out. Use shallow listings, `ls -lt`, and modification times.
- **Read the tree's own `README.md` first.** It carries retention policy the developer
  already wrote - for example "raw can be deleted after the mzML are verified" and
  "do not delete it casually" next to a directory that costs 47 minutes to rebuild.
  Surface those lines; do not invent a policy beside them.
- **Report what is expensive versus what is regenerable.** Staged instrument data and
  libraries took days to download and convert. Run output usually did not.
- **Propose reorganisation, not just deletion.** Sessions create run directories ad hoc
  and inconsistently; grouping them the way the tree's README prescribes is often worth
  more than the space.
- **Delete per item, with an explicit yes.** Never a blanket sweep here.

## Never deleted

- The script's protected list: `screenshots`, `state`, `daily`, `pr-report`, `history`,
  `attachments`, `icons`, `plots`, `plots-outliers`, and the live
  `active-project*.json` - these are owned by other tooling and regenerate on a schedule
- Anything tracked by git
- Anything the developer says is in use - when in doubt, ask, and list the paths so the
  answer is easy

## Prevention

- Session working files go in `ai/.tmp/sessions/<YYYYMMDD>-<short-session-id>/`, not at
  the root. The root is for files exchanged with the developer: handoffs, pasted
  context, downloads. A session writing dozens of `.py` and `.txt` files there buries
  the thing the folder exists for - on 2026-08-22 a single day's session accounted for
  123 of 706 entries.
- Test and run output goes to the test data area, never to `ai/.tmp`.
