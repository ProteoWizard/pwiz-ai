# TODO-20261105_pwiz_demux_port.md

## Branch Information
- **Branch**: none yet (one `Skyline/work/...` branch per port PR, from master)
- **Base**: `master`
- **Created**: 2026-11-05
- **Status**: Planning. Data inventory first (Phase 0), then the port PRs.
- **Module**: `pwiz` (the Osprey and Skyline wiring PRs late in the plan are `osprey` / `skyline`)
- **Reference**: PR [#4710](https://github.com/ProteoWizard/pwiz/pull/4710), branch
  `Skyline/work/20260923_osprey_demux` (Mike). **#4710 stays unmerged.** Mike keeps working there,
  and everything it can do is ported into ProteoWizard (`pwiz/analysis`), so msconvert, Skyline import
  (`MsDataFileImpl`) and Osprey on master all get it. Brendan to Mike: he keeps working, we port.
- **Reviewer**: Matt (`chambm`) on every pwiz PR.
- **Predecessor**: `TODO-20261008_osprey_pwiz_demux.md` (the first port, through #4818 and #4827)

## Objective

Port everything #4710 can do into `pwiz/analysis`, each step as a focused PR to master,
and gate each one on #4710's own output or measured benefit. Mike's work logs:
`TODO-20261021_osprey_stellar_demux.md` (Stellar, Centrix, Astral, ZT Scan since 2026-10-21)
and `TODO-20260923_osprey_demux.md` (the original engines, ZT Scan).

## Rules

- Every port PR records the #4710 commit it was ported from, in the ledger below.
- Gate: reproduce #4710's output on its fixtures (byte-identical where the algorithm is the same),
  or show the difference is a bug fix or a measured gain. Nothing ports without a test in
  `pwiz/analysis` (subset tests at the ProteoWizard layer, not only in Osprey).
- Settings that change output go in the demux descriptor, including whether fill-time ions were
  actually used. Fill time and analyzer come from the source spectrum (pwiz reads
  `MS_ion_injection_time` and the analyzer), so there is no `.acquisition.bin` sidecar.
- Streaming with bounded memory. msconvert and Skyline hosts cannot take #4710's 21-42 GB per file.
- Every session starts by syncing the ledger:
  `git log --first-parent <last-ledger-commit>..origin/Skyline/work/20260923_osprey_demux -- pwiz_tools/Osprey/Osprey.Demux pwiz_tools/Osprey/Osprey.Centroid pwiz_tools/Osprey/Osprey.DemuxTool`

## Phase 0: data (before any implementation)

Catalog: `ai/docs/osprey-large-datasets.md` sections 5-9 (added 2026-11-05). Goal: any machine can
reproduce every gate. Local scripts first; expand Osprey Perf/Regression where practical.

- [ ] Agents group read grants (403 on 2026-11-05):
  - [ ] `/MacCoss/Lauren/20261009_Stellar-Centroiding-for-Mike` (Stellar, section 6)
  - [ ] `/MacCoss/maccoss/2024-06 Astral Normal vs Staggered` (Astral, section 7)
- [ ] Then measure both by PROPFIND and replace the "reported" sizes in the catalog
- [ ] Ask Mike to upload to `Shared_w_lab/@files/RawFiles/`: Stellar fine-tuned library
  (`carafe-finetune\osprey_new_library\carafe_spectral_library.blib` + pairing), Astral fine-tuned
  mouse library, and the FASTAs (`hela-filtered.fasta`, `uniprot_arabidopsis_feb2023.fasta`,
  `uniprot_mouse_may2025_contam_yeastENO1.fasta`). Otherwise rebuild them with `Run-CarafeSharpWorkflow.ps1`.
- [ ] Choose the machine and drive for the port's gates. BRENDANX-UW6 has no D:; E: has 3.8 TB free
  and no Osprey setup.
- [ ] Download: Eclipse (section 5), ZT Scan without `.wiff.dia*` (26 GB + 12.6 GB library),
  Stellar (all 24), Astral reps 1-3 of all seven conditions
- [ ] Runner scripts: one per set in `ai/scripts/Osprey/Demux` (msconvert path and Osprey path),
  reading `DEMUX_DATA_ROOT` / `DEMUX_RUN_ROOT`
- [ ] Baseline: master's pwiz engine on Astral ME reps 1-3 vs Mike's `search-ME` (105,352 with
  fill-time ions; never measured, planned in Mike's TODO line 629)
- [ ] Subset tests: #4710's real-data slices (Osprey.Test/Data/Demux, Data/Centrix; 0.05-4.8 MB each)
  are the first candidates for `pwiz/analysis` tests; decide in-repo vs Panorama-hosted for pwiz.

## Port plan (each a PR to master)

| # | Module | Content | Gate |
|---|---|---|---|
| 1 | pwiz | Ion scale (per-analyzer response x fill time; Poisson weights and floor in ions; interpolation in rates); `MinChannelIons` option | Astral ME slice golden; Astral ME IDs |
| 2 | pwiz | Centrix as `peakPicking centrix` (calibration, `GridCentroider`), restricted to evenly spaced profile data | Rust golden, Stellar slices |
| 3 | pwiz | Scheme detection: variable widths, passes; one output per input, empties in place | unit tests |
| 4 | pwiz | Stellar joint profile solve (`LinearGrid`, `JointApportioner`), `PortableMath` | Stellar slice golden (Windows + Linux), remultiplexed 2 Th truth, bounded memory |
| 5 | pwiz | ZT Scan scanning demux, kernel calibration in C# | ZT slice golden, ZT IDs vs DIA-NN on `.wiff` |
| 6 | osprey | master's `--demux auto` / `--centroid centrix` through the new options | Osprey regression, Mike's search arms |
| 7 | pwiz / skyline | msconvert and `MsDataFileImpl` defaults (incl. Poisson + makima on), Skyline import | Matt's call on msconvert defaults |

Not ported (documented negative results on #4710): the elution fit (-11% on Stellar), and the
overlap "msconvert engine" (superseded by master). The weighted centroid engine's measured value
is in steps 1 and 3.

Review of #4710 on 2026-11-02 (Osprey wiring, not ported; lessons are in the rules above): the
`--demux off` refusal throws `InvalidOperationException` (prints a stack); the descriptor says
`ions_from_fill_time=True` after falling back to the constant; a stale `.acquisition.bin` can be
accepted; whole-run residency on a cache hit; the Centrix cache tag is a process-global static;
MSX is not detected by the default engine.

## Ledger (#4710 commits)

Last synced: `06901835ec` (2026-11-04; only master merges since `9b58026d77`, 2026-10-30).

| #4710 commits | What | Status |
|---|---|---|
| to `936b79994f` (Oct 8) | weighted engine, detection, Osprey `--demux` | ported (#4805-#4827, #4818) or superseded |
| `bf1933d1a8`, `2a781c91ee`, `f7f7d937b6`, `256ee8f199`, `6a48ae29dd`, `74c4a0ee34` | ion scale, fill-time ions, no output floor | pending (PR 1) |
| `ad6f14adca` .. `19ce5cdf42`, `033c8c2e5a` | Centrix, calibration, GridCentroider | pending (PR 2) |
| `90a692b196`, `0834d6fc03`, `ffb9065228`, `a86c4b7ad5`, `e5e1c8d71c`, `eab28e8141`, `94f729c75f`, `35bf44a0cd`, `926d5cbcae` | Stellar joint solve, speed and memory | pending (PR 4) |
| `e1b2446b83` | PortableMath | pending (PR 4) |
| `f3beac1fcd`, `2d8b20835e`, `618a65c96e` | ZT Scan joint memory/speed | pending (PR 5) |
| `4b972cbaad` | real-data fixtures for every path | pending (Phase 0, subset tests) |
| `bc76e155e9`, `d31553c8ff`, `2e26144263` | DemuxTool remultiplex, thinning, writer | tooling; port remultiplex as a test filter |
| `74df92bbba`, `bea8a1e2cb`, `cc6cb198ea`, `5ad993e159` | elution fit | not ported (negative) |

## Progress log

- 2026-11-05: TODO created. Reviewed #4710 through 9b58026d77. Data inventory in
  osprey-large-datasets.md sections 6-9; Stellar and Astral containers need grants.
