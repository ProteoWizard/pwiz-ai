# =============================================================================
# Nightly Test Run Metrics Analysis
# =============================================================================
#
# PURPOSE:
#   Analyzes per-run metrics from mcp__labkey__save_run_metrics_csv output to:
#   - Detect memory growth trends
#   - Identify problem machines skewing aggregates
#   - Find anomalous time periods
#   - Quantify year-over-year changes
#
# INPUT:
#   CSV file from: mcp__labkey__save_run_metrics_csv with granularity="run"
#   Expected columns: date, computer, memory_mb, tests, duration_min, failures, leaks
#
# OUTPUT:
#   - 10 PNG plots in the configured output directory
#   - Console summary statistics
#   - Clean daily aggregates CSV (with outliers removed)
#
# USAGE:
#   1. Generate input data with Claude Code MCP tool:
#      mcp__labkey__save_run_metrics_csv(start_date="1y", granularity="run")
#   2. Update the CONFIGURATION section below with your CSV path
#   3. Open in RStudio and run, or: source("analyze-run-metrics.R")
#
# DEPENDENCIES:
#   install.packages(c("tidyverse", "scales", "zoo"))
#
# =============================================================================

library(tidyverse)
library(scales)
library(zoo)

# =============================================================================
# CONFIGURATION - Update these paths for your analysis
# =============================================================================

# Path to your run-level CSV from save_run_metrics_csv
csv_file <- "C:/proj/ai/.tmp/run-metrics-Nightly-x64-20250126-20260126.csv"

# Output directory for plots (will be created if it doesn't exist)
output_dir <- "C:/proj/ai/.tmp/plots-analysis"

# Known anomalous periods to exclude from trend analysis.
# These are time ranges where external factors distorted measurements.
# Add your own as needed - format: list(name, start date, end date)
#
# Example: The WebBrowser/LOH issue (Sept 2025) where TestKeyboardShortcutHelp
# caused heap fragmentation that made TestSkewness trigger LOH bloat.
exclusion_periods <- list(
  # list(
  #   name = "WebBrowser LOH fragmentation",
  #   start = as.Date("2025-09-27"),
  #   end = as.Date("2025-10-01")
  # )
)

# Outlier detection thresholds
outlier_mad_threshold <- 3      # Flag runs > N MAD from median as outliers
problem_computer_outlier_rate <- 0.20  # Flag computers with >20% outlier runs
problem_computer_memory_mb <- 1000     # Flag computers with mean memory > 1GB

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Check if a date falls within any exclusion period
is_in_exclusion_period <- function(dates) {
  if (length(exclusion_periods) == 0) return(rep(FALSE, length(dates)))
  result <- rep(FALSE, length(dates))
  for (period in exclusion_periods) {
    result <- result | (dates >= period$start & dates <= period$end)
  }
  return(result)
}

# =============================================================================
# LOAD AND PREPARE DATA
# =============================================================================

# Create output directory
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Load data (using base R read.csv for compatibility with R 4.5+)
cat("Loading data from:", csv_file, "\n")
df <- read.csv(csv_file) %>%
  mutate(
    date = as.Date(date),
    month = floor_date(date, "month"),
    week = floor_date(date, "week")
  )

cat("Loaded", nrow(df), "runs from", n_distinct(df$computer), "computers\n")
cat("Date range:", as.character(min(df$date)), "to", as.character(max(df$date)), "\n\n")

# =============================================================================
# OUTLIER DETECTION
# =============================================================================

# Calculate global baselines using robust statistics (median, MAD)
global_median_memory <- median(df$memory_mb, na.rm = TRUE)
global_mad_memory <- mad(df$memory_mb, na.rm = TRUE)
global_median_tests <- median(df$tests, na.rm = TRUE)
global_mad_tests <- mad(df$tests, na.rm = TRUE)

cat("Global baselines (robust statistics):\n")
cat("  Memory: median =", round(global_median_memory), "MB, MAD =", round(global_mad_memory), "MB\n")
cat("  Tests:  median =", round(global_median_tests), ", MAD =", round(global_mad_tests), "\n\n")

# Flag outlier RUNS using MAD-based z-scores
df <- df %>%
  mutate(
    memory_zscore = abs(memory_mb - global_median_memory) / global_mad_memory,
    tests_zscore = abs(tests - global_median_tests) / global_mad_tests,
    is_memory_outlier = memory_zscore > outlier_mad_threshold,
    is_tests_outlier = tests_zscore > outlier_mad_threshold,
    is_outlier = is_memory_outlier | is_tests_outlier
  )

# Identify problem COMPUTERS (chronic outliers or extreme memory use)
computer_outlier_rates <- df %>%
  group_by(computer) %>%
  summarise(
    n_runs = n(),
    n_outliers = sum(is_outlier),
    outlier_rate = n_outliers / n_runs,
    mean_memory = mean(memory_mb),
    mean_tests = mean(tests),
    .groups = "drop"
  ) %>%
  mutate(is_problem_computer = outlier_rate > problem_computer_outlier_rate |
                               mean_memory > problem_computer_memory_mb)

problem_computers <- computer_outlier_rates %>%
  filter(is_problem_computer) %>%
  pull(computer)

cat("=== OUTLIER DETECTION RESULTS ===\n\n")
cat("Total runs:", nrow(df), "\n")
cat("Outlier runs:", sum(df$is_outlier), "(", round(100 * mean(df$is_outlier), 1), "%)\n")
cat("Problem computers:", length(problem_computers), "\n")

if (length(problem_computers) > 0) {
  cat("\nProblem computers (>", problem_computer_outlier_rate * 100,
      "% outlier runs or mean memory >", problem_computer_memory_mb, "MB):\n")
  computer_outlier_rates %>%
    filter(is_problem_computer) %>%
    arrange(desc(outlier_rate)) %>%
    print()
}

# Create clean dataset excluding problem computers AND exclusion periods
df_clean <- df %>%
  filter(!computer %in% problem_computers) %>%
  filter(!is_in_exclusion_period(date))

# Report on exclusions
if (length(exclusion_periods) > 0) {
  cat("\nExclusion periods (treated as missing data):\n")
  for (period in exclusion_periods) {
    n_excluded <- sum(is_in_exclusion_period(df$date) & !df$computer %in% problem_computers)
    cat("  ", period$name, ": ", as.character(period$start), " to ", as.character(period$end),
        " (", n_excluded, " runs)\n", sep = "")
  }
}

cat("\nClean dataset:", nrow(df_clean), "runs from", n_distinct(df_clean$computer), "computers\n")

# =============================================================================
# PLOT 1: Raw vs Clean Memory Trends
# =============================================================================

daily_raw <- df %>%
  group_by(date) %>%
  summarise(mean_memory = mean(memory_mb), .groups = "drop") %>%
  mutate(memory_30d = rollmean(mean_memory, 30, fill = NA, align = "right"),
         dataset = "All machines")

daily_clean <- df_clean %>%
  group_by(date) %>%
  summarise(mean_memory = mean(memory_mb), .groups = "drop") %>%
  mutate(memory_30d = rollmean(mean_memory, 30, fill = NA, align = "right"),
         dataset = "Excluding problem machines")

daily_combined <- bind_rows(daily_raw, daily_clean)

p1 <- ggplot(daily_combined, aes(x = date, y = memory_30d, color = dataset)) +
  geom_line(size = 1) +
  scale_color_manual(values = c("All machines" = "red", "Excluding problem machines" = "steelblue")) +
  labs(
    title = "Memory Usage: Raw vs Clean Data",
    subtitle = paste("Problem machines excluded:", paste(problem_computers, collapse = ", ")),
    x = NULL, y = "30-day Rolling Mean Memory (MB)", color = NULL
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave(file.path(output_dir, "01_raw_vs_clean_memory.png"), p1, width = 12, height = 6, dpi = 150)
cat("\nSaved: 01_raw_vs_clean_memory.png\n")

# =============================================================================
# PLOT 2: Clean Memory Trend with Confidence Band
# =============================================================================

daily_clean_stats <- df_clean %>%
  group_by(date) %>%
  summarise(
    mean_memory = mean(memory_mb),
    sd_memory = sd(memory_mb),
    n = n(),
    se_memory = sd_memory / sqrt(n),
    .groups = "drop"
  ) %>%
  mutate(
    mean_30d = rollmean(mean_memory, 30, fill = NA, align = "right"),
    lower_30d = rollmean(mean_memory - 1.96 * se_memory, 30, fill = NA, align = "right"),
    upper_30d = rollmean(mean_memory + 1.96 * se_memory, 30, fill = NA, align = "right")
  )

# Build exclusion period rectangles for plots
if (length(exclusion_periods) > 0) {
  exclusion_rects <- do.call(rbind, lapply(exclusion_periods, function(p) {
    data.frame(xmin = p$start, xmax = p$end, name = p$name)
  }))
} else {
  exclusion_rects <- data.frame(xmin = as.Date(character()), xmax = as.Date(character()), name = character())
}

p2 <- ggplot(daily_clean_stats, aes(x = date)) +
  {if (nrow(exclusion_rects) > 0) geom_rect(data = exclusion_rects,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = "gray80", alpha = 0.5, inherit.aes = FALSE)} +
  geom_ribbon(aes(ymin = lower_30d, ymax = upper_30d), fill = "steelblue", alpha = 0.2) +
  geom_line(aes(y = mean_memory), alpha = 0.3, color = "steelblue") +
  geom_line(aes(y = mean_30d), color = "darkblue", size = 1) +
  labs(
    title = "Clean Memory Trend (Problem Machines Excluded)",
    subtitle = "Daily mean (light), 30-day rolling avg (dark), 95% CI band",
    x = NULL, y = "Mean Memory (MB)"
  ) +
  theme_minimal()

ggsave(file.path(output_dir, "02_clean_memory_trend.png"), p2, width = 12, height = 6, dpi = 150)
cat("Saved: 02_clean_memory_trend.png\n")

# =============================================================================
# PLOT 3: Clean Test Count Trend
# =============================================================================

daily_tests_clean <- df_clean %>%
  group_by(date) %>%
  summarise(mean_tests = mean(tests), .groups = "drop") %>%
  mutate(tests_30d = rollmean(mean_tests, 30, fill = NA, align = "right"))

p3 <- ggplot(daily_tests_clean, aes(x = date)) +
  geom_line(aes(y = mean_tests), alpha = 0.3, color = "forestgreen") +
  geom_line(aes(y = tests_30d), color = "darkgreen", size = 1) +
  labs(
    title = "Clean Test Count Trend (Problem Machines Excluded)",
    subtitle = "Daily mean (light), 30-day rolling average (dark)",
    x = NULL, y = "Mean Tests per Run"
  ) +
  scale_y_continuous(labels = comma) +
  theme_minimal()

ggsave(file.path(output_dir, "03_clean_tests_trend.png"), p3, width = 12, height = 6, dpi = 150)
cat("Saved: 03_clean_tests_trend.png\n")

# =============================================================================
# PLOT 4: Per-Computer Memory Distribution
# =============================================================================

p4 <- ggplot(df, aes(x = reorder(computer, memory_mb, FUN = median), y = memory_mb)) +
  geom_boxplot(aes(fill = computer %in% problem_computers), outlier.size = 0.5) +
  scale_fill_manual(values = c("FALSE" = "steelblue", "TRUE" = "red"),
                    labels = c("Normal", "Problem"), name = "Status") +
  coord_flip() +
  labs(
    title = "Memory Distribution by Computer",
    subtitle = "Red = problem computers (excluded from clean analysis)",
    x = NULL, y = "Memory (MB)"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")

ggsave(file.path(output_dir, "04_computer_memory_boxplot.png"), p4, width = 10, height = 8, dpi = 150)
cat("Saved: 04_computer_memory_boxplot.png\n")

# =============================================================================
# PLOT 5: Problem Computer Timeline
# =============================================================================

if (length(problem_computers) > 0) {
  df_problems <- df %>% filter(computer %in% problem_computers)

  p5 <- ggplot(df_problems, aes(x = date, y = memory_mb, color = computer)) +
    geom_point(alpha = 0.5, size = 1) +
    geom_line(alpha = 0.3) +
    geom_hline(yintercept = global_median_memory, linetype = "dashed", color = "gray50") +
    facet_wrap(~computer, ncol = 1, scales = "free_y") +
    labs(
      title = "Problem Computer Memory Over Time",
      subtitle = paste("Dashed line = global median:", round(global_median_memory), "MB"),
      x = NULL, y = "Memory (MB)"
    ) +
    theme_minimal() +
    theme(legend.position = "none")

  ggsave(file.path(output_dir, "05_problem_computers_timeline.png"), p5,
         width = 12, height = 3 + 2 * length(problem_computers), dpi = 150)
  cat("Saved: 05_problem_computers_timeline.png\n")
}

# =============================================================================
# PLOT 6: Memory Efficiency (MB per 1000 tests)
# =============================================================================

daily_efficiency <- df_clean %>%
  group_by(date) %>%
  summarise(mean_memory = mean(memory_mb), mean_tests = mean(tests), .groups = "drop") %>%
  mutate(
    memory_per_1k_tests = mean_memory / (mean_tests / 1000),
    efficiency_30d = rollmean(memory_per_1k_tests, 30, fill = NA, align = "right")
  )

p6 <- ggplot(daily_efficiency, aes(x = date)) +
  {if (nrow(exclusion_rects) > 0) geom_rect(data = exclusion_rects,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = "gray80", alpha = 0.5, inherit.aes = FALSE)} +
  geom_line(aes(y = memory_per_1k_tests), alpha = 0.3, color = "purple") +
  geom_line(aes(y = efficiency_30d), color = "darkviolet", size = 1) +
  geom_hline(yintercept = mean(daily_efficiency$memory_per_1k_tests, na.rm = TRUE),
             linetype = "dashed", color = "gray50") +
  labs(
    title = "Memory Efficiency: MB per 1000 Tests",
    subtitle = "Upward trend = regression, flat = healthy proportional growth",
    x = NULL, y = "Memory (MB) per 1000 Tests"
  ) +
  theme_minimal()

ggsave(file.path(output_dir, "06_clean_memory_efficiency.png"), p6, width = 12, height = 6, dpi = 150)
cat("Saved: 06_clean_memory_efficiency.png\n")

# =============================================================================
# PLOT 7: Monthly Comparison
# =============================================================================

monthly_clean <- df_clean %>%
  group_by(month) %>%
  summarise(
    mean_memory = mean(memory_mb),
    sd_memory = sd(memory_mb),
    mean_tests = mean(tests),
    n_runs = n(),
    .groups = "drop"
  )

p7 <- ggplot(monthly_clean, aes(x = month)) +
  geom_col(aes(y = mean_memory), fill = "steelblue", alpha = 0.7) +
  geom_errorbar(aes(ymin = mean_memory - sd_memory, ymax = mean_memory + sd_memory),
                width = 10, alpha = 0.5) +
  labs(
    title = "Monthly Mean Memory (Clean Data)",
    subtitle = "Error bars = +/- 1 SD",
    x = NULL, y = "Mean Memory (MB)"
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(output_dir, "07_monthly_memory_clean.png"), p7, width = 12, height = 6, dpi = 150)
cat("Saved: 07_monthly_memory_clean.png\n")

# =============================================================================
# PLOT 8: Linear Trend Analysis
# =============================================================================

df_clean_daily <- df_clean %>%
  group_by(date) %>%
  summarise(mean_memory = mean(memory_mb), mean_tests = mean(tests), .groups = "drop")

memory_model <- lm(mean_memory ~ as.numeric(date), data = df_clean_daily)
tests_model <- lm(mean_tests ~ as.numeric(date), data = df_clean_daily)

memory_trend_per_day <- coef(memory_model)[2]
tests_trend_per_day <- coef(tests_model)[2]

p8 <- ggplot(df_clean_daily, aes(x = date, y = mean_memory)) +
  {if (nrow(exclusion_rects) > 0) geom_rect(data = exclusion_rects,
            aes(xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf),
            fill = "gray80", alpha = 0.5, inherit.aes = FALSE)} +
  geom_point(alpha = 0.3, color = "steelblue") +
  geom_smooth(method = "lm", color = "red", se = TRUE) +
  labs(
    title = "Memory Trend with Linear Fit (Clean Data)",
    subtitle = sprintf("Trend: %+.2f MB/day (%+.1f MB/year)",
                       memory_trend_per_day, memory_trend_per_day * 365),
    x = NULL, y = "Daily Mean Memory (MB)"
  ) +
  theme_minimal()

ggsave(file.path(output_dir, "08_memory_linear_trend.png"), p8, width = 12, height = 6, dpi = 150)
cat("Saved: 08_memory_linear_trend.png\n")

# =============================================================================
# PLOT 9: Run Count Over Time (Infrastructure Health)
# =============================================================================

daily_run_count <- df_clean %>%
  group_by(date) %>%
  summarise(run_count = n(), .groups = "drop")

p9 <- ggplot(daily_run_count, aes(x = date, y = run_count)) +
  geom_col(fill = "steelblue", alpha = 0.7, width = 1) +
  geom_hline(yintercept = median(daily_run_count$run_count), linetype = "dashed", color = "red") +
  labs(
    title = "Daily Run Count (Number of Machines Reporting)",
    subtitle = paste("Dashed line = median (", median(daily_run_count$run_count), " runs)"),
    x = NULL, y = "Number of Runs"
  ) +
  theme_minimal()

ggsave(file.path(output_dir, "09_daily_run_count.png"), p9, width = 12, height = 5, dpi = 150)
cat("Saved: 09_daily_run_count.png\n")

# =============================================================================
# PLOT 10: Failures and Leaks Over Time
# =============================================================================

daily_issues <- df_clean %>%
  group_by(date) %>%
  summarise(
    total_failures = sum(failures),
    total_leaks = sum(leaks),
    .groups = "drop"
  ) %>%
  mutate(
    failures_7d = rollmean(total_failures, 7, fill = NA, align = "right"),
    leaks_7d = rollmean(total_leaks, 7, fill = NA, align = "right")
  )

p10 <- ggplot(daily_issues, aes(x = date)) +
  geom_col(aes(y = total_failures), fill = "red", alpha = 0.3, width = 1) +
  geom_line(aes(y = failures_7d), color = "darkred", size = 1) +
  labs(
    title = "Daily Test Failures (Clean Data)",
    subtitle = "Bars = daily total, Line = 7-day rolling average",
    x = NULL, y = "Total Failures"
  ) +
  theme_minimal()

ggsave(file.path(output_dir, "10_daily_failures.png"), p10, width = 12, height = 5, dpi = 150)
cat("Saved: 10_daily_failures.png\n")

# =============================================================================
# SUMMARY STATISTICS
# =============================================================================

cat("\n")
cat(strrep("=", 60), "\n")
cat("SUMMARY STATISTICS (CLEAN DATA)\n")
cat(strrep("=", 60), "\n\n")

# First vs last month
first_month_clean <- df_clean %>% filter(month == min(month))
last_month_clean <- df_clean %>% filter(month == max(month))

cat("First month (", format(min(first_month_clean$month), "%b %Y"), "):\n", sep = "")
cat("  Mean memory: ", round(mean(first_month_clean$memory_mb), 1), " MB\n", sep = "")
cat("  Mean tests:  ", round(mean(first_month_clean$tests)), "\n", sep = "")

cat("\nLast month (", format(max(last_month_clean$month), "%b %Y"), "):\n", sep = "")
cat("  Mean memory: ", round(mean(last_month_clean$memory_mb), 1), " MB\n", sep = "")
cat("  Mean tests:  ", round(mean(last_month_clean$tests)), "\n", sep = "")

memory_yoy_pct <- (mean(last_month_clean$memory_mb) - mean(first_month_clean$memory_mb)) /
                   mean(first_month_clean$memory_mb) * 100
tests_yoy_pct <- (mean(last_month_clean$tests) - mean(first_month_clean$tests)) /
                  mean(first_month_clean$tests) * 100

cat("\nYear-over-year change:\n")
cat("  Memory: ", sprintf("%+.1f%%", memory_yoy_pct), "\n", sep = "")
cat("  Tests:  ", sprintf("%+.1f%%", tests_yoy_pct), "\n", sep = "")

cat("\nLinear trends:\n")
cat("  Memory: ", sprintf("%+.2f MB/day (%+.1f MB/year)", memory_trend_per_day, memory_trend_per_day * 365), "\n", sep = "")
cat("  Tests:  ", sprintf("%+.1f tests/day (%+.0f tests/year)", tests_trend_per_day, tests_trend_per_day * 365), "\n", sep = "")

# Memory efficiency
first_efficiency <- mean(first_month_clean$memory_mb) / (mean(first_month_clean$tests) / 1000)
last_efficiency <- mean(last_month_clean$memory_mb) / (mean(last_month_clean$tests) / 1000)

cat("\nMemory efficiency (MB per 1000 tests):\n")
cat("  First month: ", round(first_efficiency, 2), "\n", sep = "")
cat("  Last month:  ", round(last_efficiency, 2), "\n", sep = "")
cat("  Change:      ", sprintf("%+.1f%%", (last_efficiency - first_efficiency) / first_efficiency * 100), "\n", sep = "")

cat("\n")
cat(strrep("=", 60), "\n")
cat("PLOTS SAVED TO:", output_dir, "\n")
cat(strrep("=", 60), "\n")

# =============================================================================
# EXPORT CLEAN DAILY AGGREGATES
# =============================================================================

daily_export <- df_clean %>%
  group_by(date) %>%
  summarise(
    run_count = n(),
    mean_memory_mb = round(mean(memory_mb), 1),
    mean_tests = round(mean(tests), 0),
    mean_duration_min = round(mean(duration_min), 0),
    total_failures = sum(failures),
    total_leaks = sum(leaks),
    .groups = "drop"
  )

export_file <- file.path(output_dir, "daily-metrics-clean.csv")
write.csv(daily_export, export_file, row.names = FALSE)
cat("\nExported clean daily aggregates to:", export_file, "\n")
