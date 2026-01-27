# LabKey MCP Analysis Scripts

Scripts for analyzing data exported by LabKey MCP tools.

## Scripts

### analyze-run-metrics.R

Analyzes nightly test run metrics exported by `mcp__labkey__save_run_metrics_csv`.

**Purpose:** Detect memory regressions, identify problem machines skewing aggregates,
and quantify long-term trends.

**Prerequisites:**
```r
install.packages(c("tidyverse", "scales", "zoo"))
```

**Input:** CSV from `save_run_metrics_csv` with `granularity="run"`:
```
mcp__labkey__save_run_metrics_csv(start_date="1y", granularity="run")
```

**Configuration:** Edit the top of the script:
- `csv_file` - Path to input CSV
- `output_dir` - Where to save plots
- `exclusion_periods` - Known anomalous date ranges to exclude

**Output:**
- 10 PNG plots (trends, outliers, efficiency metrics)
- Console summary statistics
- `daily-metrics-clean.csv` with outliers removed

**Key features:**
- Robust outlier detection using MAD (median absolute deviation)
- Automatic identification of problem computers
- Exclusion periods for known anomalies
- Linear trend quantification (MB/year growth rate)
- Memory efficiency metric (MB per 1000 tests)

See comments in the script for detailed documentation.

## Related Documentation

- [Nightly Tests MCP Tools](../../docs/mcp/nightly-tests.md)
- [save_run_metrics_csv tool](tools/nightly.py) - generates input data

## Historical Context

Known anomalies that may need exclusion periods:

| Period | Issue | Resolution |
|--------|-------|------------|
| 2025-09-27 to 2025-10-01 | WebBrowser/LOH fragmentation from TestKeyboardShortcutHelp | WebView2 migration + TestSkewness lazy enumeration |
| 2025-07 to 2025-09 | BSPRATT-UW4 hardware degradation (2.4GB memory) | Auto-detected as outlier; machine taken offline |
