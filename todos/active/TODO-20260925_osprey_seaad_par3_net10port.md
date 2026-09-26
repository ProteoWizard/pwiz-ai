# TODO: SEA-AD 82-file end-to-end on the .NET 10 port branch at --parallel-files 3

## Branch Information
- **Branch**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619), "Port ProteoWizard core to .NET 10")
- **Pinned commit for this measurement**: `5bd83dae8b7b2347c8b9f60bac020c46199699b7` (2026-09-25, "pwiz: Reverted the Spectronaut parquet support pushed by mistake")
- **Base**: `master` (branch was 1 commit behind master at pin time)
- **Created**: 2026-09-25
- **Status**: Not started - build + run to be done by a night session
- **Module**: `osprey`
- **PR**: none of our own; we are MEASURING #4619, not modifying it
- **Worktree**: `D:\Users\brendanx\proj\pwiz-net10`, local branch `net10port-par3`, reset to the pinned SHA and clean

## Goal

End-to-end 82-file SEA-AD numbers from the **.NET 10 port branch** on MACS2 at
`--parallel-files 3`, as a starting point for further analysis. Brendan is running
**the same analysis on two other machines** and wants to compare all three in the
morning, so the configuration must be recorded exactly and reproduced exactly.

This is a measurement of the port branch, NOT a concurrency A/B. Do not present it
as comparable to the 4h29m `--parallel-files 4` figure from 2026-09-10: that ran on
master-lineage code, at a different concurrency, before eight Osprey commits landed.

## The configuration being measured (record this with any result)

| | |
|---|---|
| host | MACS2 |
| cpu | 2 x Intel Xeon Gold 6354 @ 3.00GHz - 36 cores / 72 threads |
| RAM | 511.5 GB |
| OS | Windows Server 2022 Standard 10.0.20348 |
| branch / commit | `Skyline/work/20260612_net8_port` @ `5bd83dae8b` |
| target framework | **net10.0** (the branch name says net8; the target moved to .NET 10) |
| dataset | SEA-AD, 82 files, from `.spectra.bin` caches on D: |
| library | `lib/astral/target+decoy+entrapment-20260817` |
| arm | `-DecoyMode libdecoy -Ratio 1.0` |
| concurrency | `--parallel-files 3`, `--threads 72` (threads are DIVIDED across files, so ~24/file) |

## Reference numbers from this machine (different code, different concurrency)

From 2026-09-10 on master-lineage code, for orientation only:

| stage | sequential | par4 |
|---|---|---|
| PerFileScoring | 15,340.1 s | 7,223.1 s |
| FirstPassFDR | 4,173.7 s | 4,086.3 s |
| PerFileRescoring | 7,905.4 s | 4,163.3 s |
| SecondPassFDR | 689.7 s | 662.5 s |
| **total** | **28,109 s (7h48m)** | **16,135 s (4h29m)** |

Correctness anchors that a good run should reproduce: **353,085,961 scored entries**,
and `pass1_fdp.py` pass-1 experiment-scope `q=0.0100 n=45943 combinedFDP=0.7460%`.
A different scored-entry count is a red flag worth stopping for.

## Progress Log

### 2026-09-25 - Set up, not yet run

Established the branch state and prepared the worktree. Nothing built or run yet.

**A serious false start worth recording.** The remote-tracking ref for this branch
was corrupted locally - the same ref stored twice with different values (loose
`5d27353235`, packed-refs `5c046bdb7a`), so every `git fetch` failed its
compare-and-swap and silently left a **two-week-old** view of the branch. On that
stale data I reported that #4619 lacked #4652 and #4680, was 23 commits behind, and
carried a different `ParquetNet.dll`, and I began merging master into it. All of
that was wrong; Brendan stopped it. The real tip has both parquet fixes and the
same DLL as master, and was 1 commit behind. The merge was aborted, nothing pushed.

Lesson: **read fetch output.** The first fetch printed
`error: cannot lock ref ... is at X but expected Y` and I proceeded anyway. When a
branch's history looks implausibly stale, verify against `git ls-remote origin
<ref>` or `gh api repos/ProteoWizard/pwiz/pulls/<N> --jq .head.sha` before drawing
any conclusion.

The ref broke again on a later plain `git fetch origin` in the worktree, so it is
not a one-off. **Pin the SHA rather than trusting the ref.**

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260925_seaad_par3_net10port.md` before starting work.
