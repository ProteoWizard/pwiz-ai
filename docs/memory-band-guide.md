# Reading the memory band (`--timestamp --memstamp`)

**Applies to both Skyline and Osprey.** They emit the identical format because they share
one writer: `pwiz_tools/Shared/PortableUtil/SystemUtil/CommandStatusWriter.cs`
(`WriteLine`, ~:125). Anything here works on either tool's console log.

This is the cheapest and most informative memory diagnostic in the project. It answers the
question that matters at scale - **does this run's memory return to the same floor after
each unit of work, or does it climb?** - from an ordinary run log, with no profiler
attached and no instrumentation build.

## Producing the log

Add both flags and tee the console to a file:

```
Osprey.exe ... --timestamp --memstamp --log-file run.log
SkylineCmd ... --timestamp --memstamp        (tee stdout)
```

Every emitted line is then prefixed:

```
[yyyy/MM/dd HH:mm:ss]<TAB>managedMB<TAB>privateMB<TAB>message
```

* **column 1** = `GC.GetTotalMemory(false)` - the managed heap **including uncollected
  garbage**. No collection is forced.
* **column 2** = `Process.PrivateMemorySize64` - private bytes.
  `ai/scripts/perfviz.html` labels this series "Total Memory"; it is private bytes.

Because every line carries a timestamp, the log also measures its OWN reporting cadence -
the gap between consecutive lines is how long the tool went silent, which is how a
missing-progress stall gets found without a debugger.

## Reading it

Two readers over the same log. Use both; they answer different questions.

| tool | for | gives |
|---|---|---|
| `ai/scripts/perfviz.html` | a human, visually | interactive plot of the three series |
| `ai/scripts/perfviz.py` | terminal / CI / an agent | numbers: peak, floor drift, gap list |
| `ai/scripts/phase_mem_shape.py` | either | memory shape WITHIN each phase, by decile, with a fan-out-vs-join verdict |

```
python ai/scripts/perfviz.py run.log --files 20 --png run.png
python ai/scripts/perfviz.py before.log after.log       # A/B two runs
python ai/scripts/phase_mem_shape.py run.log            # per-phase shape + verdict
```

`phase_mem_shape.py` answers a question the whole-run summary cannot: **is this phase
flat iteration, or does it ramp into a join at the end?** A fan-out phase (one file at a
time) must stay flat; only a join phase should ramp, and a join is where an
O(files x entries) structure can appear. It prints each phase in deciles and compares the
last decile's peak against the median of the first eight.

Worked example - pwiz #4600 moved PerFileRescoring's whole-run join into SecondPassFDR's
pull. On the 163-file TDP-43 cohort the signature is unmistakable:

| PerFileRescoring | before #4600 | after |
|---|---|---|
| flat body | ~15.5 GB | ~17.5 GB |
| final decile max | **44.3 GB** | **20.2 GB** |
| verdict | 2.34x RAMPS INTO A JOIN | 1.04x flat iteration |

It **refuses a verdict on a phase that is still running**, because a phase that ramps only
at its end looks flat for its first 90%. A partial log cannot answer the question, and a
'flat iteration' verdict read off one would be worse than no answer.

The **numeric summary is stdlib-only**, so it runs on a fresh machine with nothing
installed. `--png` additionally needs matplotlib (`pip install matplotlib`); the import is
inside the plotting function, so without it you still get every number and just a note that
the plot was skipped.

The PNG exists so a plot can be handed to a person directly, rather than asking them to
find the log and paste it into `perfviz.html`. It draws the same three series with a second
y-axis for the time gap. For deciding anything, read the numbers - they are less lossy than
a picture, and they are what a CI check can assert on.

### What the shape means

A stage that processes N units emits a **sawtooth**: memory rises through a unit's work and
drops when it is released. Read the **floor**, not the peaks:

* **floor returns to the same level** every cycle -> bounded. The stage holds one unit's
  data at a time. Tall peaks are fine.
* **floor rises across cycles** -> O(N) accumulation. This is the signature that a
  structure is being retained across units, and it is what breaks a large run.
* **floor falls** -> a start-up spike draining. Benign, and a completely different
  phenomenon from accumulation - do not report them with the same word.

`perfviz.py` reports `floor A -> B`, the drift, and (with `--files N`) **MB/file**, which is
the number a scaling decision actually turns on: MB/file x target file count says whether a
bigger run fits in RAM.

## Traps

Every one of these produced a wrong conclusion in real work.

**1. `--memstamp` is not a live-set measurement.** Column 1 includes uncollected garbage, so
two identical runs can differ by tens of GB purely on whether a gen-2 collection happened to
land before a sample. It is excellent for SHAPE (does the floor climb?) and unreliable for
MAGNITUDE. To answer "will this fit in RAM", use a probe that forces a collection first - in
Osprey, `ProfilerHooks.LogManagedHeapAfterGcIfEnabled`, enabled by `OSPREY_LOG_MEMORY=1`,
which emits `[MEM <label>] managed_heap=<X> GB` after a full GC. Osprey's own docs call that
"the only probe here that answers 'will this fit'".

**2. Within-run band and across-run slope are different quantities.** Comparing the resident
memory of a 4-file run vs a 16-file run measures state materialized BEFORE the work loop
(it shows up as a higher starting level). The band's climb WITHIN one run measures
accumulation DURING the loop. A fix can flatten one and not touch the other. perfviz draws
the second. Say which you mean.

**3. Never analyze a failed run's log.** A run that died 30 seconds in produces a beautiful
"0 gaps, flat memory" summary. This has happened. `perfviz.py` refuses to report statistics
when the log contains an error unless `--force`, for exactly this reason - check the run
succeeded before believing any number derived from it.

**4. Exclude start-up from floor measurements.** Every process begins near zero and climbs
while it warms up (Osprey loads a multi-GB spectral library first). Include that and the
first floor is ~0, the drift equals the floor, and EVERY run looks like it is accumulating.
`perfviz.py` starts measuring once a series first reaches half its peak.

**5. A per-unit driver flattens the band by construction.** If the harness invokes the tool
once per file, each process holds exactly one file and the band is flat no matter what the
code does - you would "confirm" a fix that does not exist. Drive the multi-unit path the
real workload uses.

**6. Peaks can be Server-GC committed-but-free.** .NET Server GC expands heaps toward the
high-memory-load threshold before collecting, so a high private-bytes plateau is not
necessarily a live set. Distinguish with the post-GC probe (trap 1) before hunting a leak
that is not there.

## Osprey specifics

* `OSPREY_LOG_MEMORY=1` enables the post-GC `[MEM ...]` probes at stage boundaries. Zero
  cost - collection included - when unset.
* With a dotMemory session attached (`ai/scripts/Osprey/Profile-Osprey.ps1 -MemoryProfile`),
  the same boundaries capture a retention snapshot, so "who holds this" reconciles with the
  `managed_heap` number just logged.
* `ai/scripts/Osprey/SEA-AD/Measure-Stage6Rescore.ps1` prepares Stage 1-5 once and re-runs a
  single `--task` at several file counts, so one stage's scaling is measurable in minutes
  instead of a multi-hour full run.

## A/B-ing two runs (elapsed-matched)

Pass **two** logs and perfviz adds an elapsed-matched comparison after the two
summaries:

```bash
python ai/scripts/perfviz.py before.log after.log --files 82 --every 20
```

Two runs of the same workload start at different wall-clock times, so their
timestamps are not comparable. This aligns both on seconds-since-first-sample and
reports the delta at fixed offsets.

**It works on a run still in progress.** The table stops at whatever the shorter
log has reached, so you get an A/B verdict long before the slower run finishes -
on a 2h45m run, the answer was readable at 36 minutes. Do not sit through a long
run to learn something the first half already showed.

**Read the sign, not the magnitude.** Private bytes swing enormously *within* a
run, because each sample catches the per-file transient at a different phase - a
single pair of readings proves nothing, and two samples 20 minutes apart in the
same healthy run can differ by 10 GB. What is diagnostic is whether the sign
holds across many offsets. GC-timing noise flips sign; a real retention
difference does not. perfviz says so explicitly and tells you when a mixed sign
means "inconclusive - read the floor drift instead".

**The floor drift is the verdict; the delta table is the early read.** If the two
disagree, believe the floor drift. It is fitted across the whole run; the table
is point samples.

### Managed vs private: they can move in opposite directions

Report BOTH columns. On one measured change the private-bytes peak improved only
3% (35.2 -> 33.9 GB) while managed-heap drift went from +26 MB/file to
**+1 MB/file, LEVEL** - the same change looked marginal on one axis and decisive
on the other. Managed is the post-GC "will it fit" number; private includes
allocator retention the GC has released but not returned. Quoting only the peak
would have hidden the actual result.

Also expect a fix that releases something mid-run to move the FLOOR and not the
PEAK, when the peak is set by a transient before the release point. That is not a
failed fix - check which phase sets the peak before concluding anything.

## Related

* `ai/docs/leak-debugging-guide.md` - handle/GC leaks in tests. Different problem: that is
  "something is never released", this is "released, but not until the run ends".
* `ai/docs/osprey-development-guide.md` - Osprey memory work and its gates.
