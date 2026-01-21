-- Query: leaks_by_date
-- Container: /home/development/Nightly x64 (and other test folders)
-- Schema: testresults
-- Description: Memory and handle leaks within a timestamp window
--
-- Parameters:
--   WindowStart (TIMESTAMP) - Start of window (e.g., 2025-12-04 08:01:00)
--   WindowEnd (TIMESTAMP) - End of window (e.g., 2025-12-05 08:00:00)
--
-- Used by: get_daily_test_summary()
-- Note: Combines memoryleaks and handleleaks tables
--
-- The nightly "day" runs from 8:01 AM the day before to 8:00 AM the report date.

PARAMETERS (WindowStart TIMESTAMP, WindowEnd TIMESTAMP)

SELECT
    m.testname,
    u.username AS computer,
    'memory' AS leak_type
FROM memoryleaks m
JOIN testruns t ON m.testrunid = t.id
JOIN "user" u ON t.userid = u.id
WHERE t.posttime >= WindowStart
  AND t.posttime <= WindowEnd

UNION ALL

SELECT
    h.testname,
    u.username AS computer,
    'handle' AS leak_type
FROM handleleaks h
JOIN testruns t ON h.testrunid = t.id
JOIN "user" u ON t.userid = u.id
WHERE t.posttime >= WindowStart
  AND t.posttime <= WindowEnd

ORDER BY testname, leak_type
