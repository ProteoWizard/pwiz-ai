-- Query: leakcheck_stats
-- Container: /home/development/Nightly x64 (and other test folders)
-- Schema: testresults
-- Description: Analyze pass-1 (leak detection) iteration counts and time per test
--
-- Parameters:
--   StartDate (TIMESTAMP) - Start date (e.g., 2026-01-01)
--   EndDate (TIMESTAMP) - End date (e.g., 2026-01-31)
--
-- Used by: save_leakcheck_stats()
--
-- Pass 1 is the leak detection pass. Each testpasses row with pass=1 represents
-- one leak-check iteration. Tests run 8-24 iterations (configurable), stopping
-- early if memory/handles stabilize. Tests needing many iterations to stabilize
-- (or that never stabilize) produce more rows.

PARAMETERS (StartDate TIMESTAMP, EndDate TIMESTAMP)

SELECT
    p.testname,
    COUNT(*) AS total_iterations,
    COUNT(DISTINCT p.testrunid) AS run_count,
    ROUND(CAST(COUNT(*) AS DOUBLE) / NULLIF(COUNT(DISTINCT p.testrunid), 0), 1) AS avg_iterations_per_run,
    ROUND(AVG(p.duration)) AS avg_duration_sec,
    ROUND(SUM(p.duration) / 60.0) AS total_time_min,
    ROUND(CAST(SUM(p.duration) AS DOUBLE) / NULLIF(COUNT(DISTINCT p.testrunid), 0) / 60.0, 1) AS avg_time_per_run_min
FROM testpasses p
JOIN testruns t ON p.testrunid = t.id
WHERE p.pass = 1
  AND CAST(t.posttime AS DATE) >= StartDate
  AND CAST(t.posttime AS DATE) <= EndDate
GROUP BY p.testname
ORDER BY avg_iterations_per_run DESC
