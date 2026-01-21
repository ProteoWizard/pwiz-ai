-- Query: failures_by_date
-- Container: /home/development/Nightly x64 (and other test folders)
-- Schema: testresults
-- Description: Test failures within a timestamp window with computer and run info
--
-- Parameters:
--   WindowStart (TIMESTAMP) - Start of window (e.g., 2025-12-04 08:01:00)
--   WindowEnd (TIMESTAMP) - End of window (e.g., 2025-12-05 08:00:00)
--
-- Used by: get_daily_test_summary(), save_test_failure_history()
--
-- The nightly "day" runs from 8:01 AM the day before to 8:00 AM the report date.

PARAMETERS (WindowStart TIMESTAMP, WindowEnd TIMESTAMP)

SELECT
    f.testname,
    u.username AS computer,
    f.testrunid,
    t.posttime
FROM testfails f
JOIN testruns t ON f.testrunid = t.id
JOIN "user" u ON t.userid = u.id
WHERE t.posttime >= WindowStart
  AND t.posttime <= WindowEnd
ORDER BY t.posttime DESC, f.testname
