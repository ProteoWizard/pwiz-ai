# Leftovers from the net10 pass-1 leak investigation

## Status: the main leak is FIXED - this covers only what it did not

The managed leak in these tests was undisposed NHibernate `ISessionFactory` objects, rooted for
the life of the process by the static `SessionFactoryObjectFactory.Instances` dictionary.
**Fixed on the port branch by #4629 (`5c046bdb7a`, 2026-09-02)** in `IonMobilityDb` and
`OptimizationDb`, by dropping the retained `_sessionFactory` and creating one per operation
under `using`.

This file exists for the parts that fix does not address, and for the method, so the next
leak hunt does not start from scratch.

- **Checkout**: investigated from `C:\dev\pwiz-net8`
- **Created**: 2026-09-02
- **Module**: `skyline`

## Independent corroboration of the fixed leak

Worth recording because it was measured rather than reasoned, and the numbers are a baseline
for judging any regression:

- `gcroot` on a surviving factory, in two unrelated tests, gave the same chain:
  strong handle -> `System.Object[]` -> static `Dictionary<String, NHibernate.ISessionFactory>`
  -> `SessionFactoryImpl`. (SOS mislabels that static slot as `NHibernate.INHibernateLogger.log`
  - adjacent-symbol artifact, ignore the name.)
- Survivors had `disposed = 0`, `isClosed = 0` - never disposed, not disposed-but-registered.
- **10** live `IonMobilityDb` objects against **540** live factories: owners were collected
  normally, each orphaned factory stayed immortal with its persisters, loaders and emitted IL.
- A probe at `SessionFactoryFactory.CreateSessionFactory` over 3 iterations of
  `SerializeIonMobilityTest` logged 49 creations, all `IonMobilityDb`; 25 of them via the
  un-`using`ed `GetIonMobilityDb` path. ~8.3 leaked factories/iteration x ~400 KB = ~3.3 MB
  against a measured 3347.6 KB. The arithmetic closed.

## Still open

### 1. `TestGroupedStudies1Tutorial` - native heap, not managed

The only leaker of the seven that is **not** the NHibernate cause and is therefore very likely
still present after #4629:

```
# TestGroupedStudies1Tutorial deltas (25): managed = -1.7 KB, heap = +813.4 KB, memory = -797.7 KB
```

Managed is flat; the growth is entirely native heap. Nothing in the managed heap diff explained
it. Not investigated. A managed-heap diff is the wrong tool here - this needs native tracking
(UMDH / heap snapshots), not `dumpheap`.

### 2. Re-measured after #4629 - three fixed, three survive

Measured on `5c046bdb7a` with a correctly staged tree (see the staging trap below):

| test | before | after #4629 | verdict |
|---|---|---|---|
| SerializeIonMobilityTest | managed +3347.6 KB | **+0.2 KB** | fixed |
| TestFilesTreeForm | managed +2069.3 KB | **+3.6 KB** | fixed |
| TestCrosslinkIms | managed +1341.5 KB | **-0.2 KB** | fixed |
| TestGroupedStudies1Tutorial | heap +813.4 KB | heap **+932.8 KB** | **not fixed** |
| FileTypeTest | managed +30.9 KB | managed **+29.0 KB** | **not fixed** |
| TestInstrumentInfo | +35.4 KB | oscillates either side of the threshold | flaky gate |
| IrtDocumentFunctionalTest | +12.2 KB | -6.8 KB | clean |

pass1 also stabilizes in 11-12 iterations now instead of running to 25, which is the clearer
signal that the retention is gone rather than merely smaller.

Two corrections to what this file previously claimed:

- **`FileTypeTest` is NOT the same cause.** It survives the NHibernate fix essentially unchanged
  at ~29 KB/run, so it needs its own look. Small, but real and reproducible.
- **`TestFilesTreeForm`'s `Form[]` growth was indeed churn, not retention** - the NHibernate fix
  alone took it from 2069 KB to 3.6 KB, so nothing further is needed there.

### 3. Leaks DO fail the build - earlier note here was wrong

A previous version of this file said leaks are reported but never reach the exit code. That is
wrong. With `buildcheck=1` - which is what `build.bat`'s pass1 step passes - a leak aborts the
run and exits 1. Observed directly: a pass1 run tripped on `TestInstrumentInfo` at 36 KB, exited
1, and never ran the remaining nine tests. Without `buildcheck` the same set runs to completion,
reports the leaks and exits 0, which is what produced the mistaken claim.

Consequence: adding leakers to the pass1 subset is **enforcing**, not merely informational. Any
test on that list that still leaks will turn the build red and hide every test after it.
`TestInstrumentInfo` oscillating around the threshold makes it a poor member of that list.

## Method, for the next leak hunt

These are *memory-delta over iterations* leaks, not the object-survival leaks that
`GarbageCollectionTracker` / `SKYLINE_GC_LEAK_ROOTS` detect - those tools never fire on this
class, which is why the leak sat unexplained. What worked:

1. `TestRunner.exe test=<name> loop=400` for a long-lived process.
2. `dotnet-dump collect -p <pid>` at two iteration counts.
3. `dotnet-dump analyze <dmp> -c "dumpheap -stat"` on each, diffed by type. A script that parses
   the two `-stat` outputs and sorts by byte growth is what turns this from guesswork into an
   answer in one step.
4. `gcroot <addr>` on a growing instance for the authoritative root chain.
5. When the type diff is ambiguous, a temporary probe at the allocation choke point recording
   `new StackTrace(1, false)` gives the caller distribution directly - far faster than reading
   dictionary entry structs out of a dump.

Dead end, do not repeat: caching session factories per path. It cut TestCrosslinkIms 50% but
SerializeIonMobilityTest only 20%, because most creations came through `CreateFromDictionary`,
which writes a **new temp .imsdb every call**, so a path-keyed cache can never hit.

Gotcha: `tasklist //FI ... //NH` emits a leading blank line, so `head -1` gets nothing - filter
for the image name instead.

**The staging trap that invalidated a whole round of measurements.** `build.bat --no-tests`
does NOT stage, despite its own doc comment saying "Build and stage" - it returns at
`goto build_only_done` before the staging step. So a build-then-measure cycle silently measures
the PREVIOUS build. This produced two confidently wrong conclusions in one sitting: that #4629
had not fixed the leaks (it had), and that a separate test fix was redundant (it was not - the
stale staged TestUtil.dll still contained it). Always run `Stage-Tests.ps1` explicitly after
`--no-tests`, and verify with
`find bin/staging/Release -maxdepth 1 -name "*.dll" -newermt "<build time>" | wc -l`
before trusting any measurement.
