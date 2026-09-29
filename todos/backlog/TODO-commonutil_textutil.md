# TODO-commonutil_textutil.md - move Skyline's TextUtil into CommonUtil so Osprey can share it

## Branch Information
- **Branch**: (not started) - `Skyline/work/YYYYMMDD_commonutil_textutil`
- **Base**: `Skyline/work/20260612_net8_port` (Osprey depends on it; CommonUtil is shared)
- **Module**: `skyline` (primary change is in Skyline / CommonUtil; Osprey follows)
- **Created**: 2026-09-27 (Brendan's review of PR #4721, comment on FdrDiagnostics.cs)

## Why
Skyline's `pwiz_tools/Skyline/Util/Extensions/Text.cs` (`TextUtil`) holds the text helpers every
writer and log needs: `SEPARATOR_TSV` / `SEPARATOR_CSV`, `ToDsvLine`, `EXT_TSV` / `EXT_CSV`,
`GetIndentation` / `Indent`, `SpaceSeparate` / `LineSeparate` (the last two already forward to
`pwiz.Common.SystemUtil.CommonTextUtil`). Osprey cannot reference Skyline, so PR #4721 added a small
`pwiz.Osprey.Core.TextUtil` that MIRRORS those names and signatures. Two copies drift.

## Plan
1. Move the portable members of Skyline's TextUtil (no WinForms, no Skyline resources) into
   `pwiz_tools/Shared/CommonUtil` (extend `CommonTextUtil`, or a `TextUtil` there), leaving
   Skyline's TextUtil forwarding to it so no Skyline call site changes.
2. Delete `pwiz.Osprey.Core.TextUtil` and switch Osprey to the CommonUtil one (a using change,
   because the names match).
3. Byte-identical outputs: Skyline tests + `regression.ps1 -Dataset All` for Osprey.
