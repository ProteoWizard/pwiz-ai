# TODO-osprey_progress_reporter_heartbeat -- ProgressReporter heartbeat for phases progressing < 1% per interval

- **Status**: Backlog
- **Created**: 2026-07-13
- **Raised by**: Brendan (2026-07-13, after an 82-file Stage-6 phase went silent ~1 h and looked hung)

## Problem
`ProgressReporter` (`Osprey.Core/ProgressReporter.cs`) is a stopwatch-throttled percent printer, but
its `Report()` emits a line ONLY when the integer percent ADVANCES **and** the interval has elapsed:
```
if (percent > _lastPercent && now - _lastReportSeconds >= _intervalSeconds) { ... }
```
So on a very long phase that progresses SLOWER than 1% per interval -- e.g. Stage-6 reconciliation
rescoring 344K entries while paging at RAM-0 -- the integer percent freezes and the reporter prints
NOTHING, for as long as it takes to cross the next whole percent. The console looks hung exactly when
progress is slowest, which is when a user most needs reassurance. (Confirmed on the 82-file run: ~1 h
of silence on "Reconciliation multi-charge consensus: 344,364 entries need re-scoring".)

## Goal
Keep the console reassuring on very long, very slow phases (progress < 1% per N seconds, e.g. 15 s)
without cluttering fast phases -- staying true to the "timer-style, not per-N-units" design.

## Approach
1. **Timer heartbeat decoupled from advance**: after a longer idle (e.g. no line for >= a heartbeat
   interval such as 15-30 s) reprint the CURRENT percent even when it has not advanced
   ("... still 12% (Nm elapsed)"). Fast phases never hit the idle window, so no new clutter. This is
   the primary fix -- it also surfaces PATHOLOGICAL SLOWNESS in real time (the 82-file case would have
   prompted a kill an hour earlier).
2. **Optional finer granularity**: track a fractional/per-mille percent so slow-but-nonzero progress
   trips the gate sooner. Complements (1); a hard 0%-for-an-hour stall still needs the heartbeat.
3. **Audit long loops for coverage**: confirm the phases that went silent are actually wrapped in a
   ProgressReporter (the "multi-charge consensus rescore" heading may be a plain log line, not a
   reporter heading). Wrap any that are not.

## Validation
- A run with a deliberately slow/throttled phase shows periodic heartbeats (no > ~30 s gap) while the
  percent is frozen; fast phases still emit only on advance (no extra lines).
- Pair with `--timestamp --memstamp` to see the heartbeat cadence + memory per line.

## References
- `Osprey.Core/ProgressReporter.cs` (the advance-gated `Report()`), `MultiProgressReporter.cs`.
- `--timestamp` / `--memstamp` (`OspreyCommandArgs.cs` ARG_TIMESTAMP/ARG_MEMSTAMP) as the diagnostic
  that locates silent phases + watches memory.
- Context: this session's 82-file Stage-6 stall (budget log).
