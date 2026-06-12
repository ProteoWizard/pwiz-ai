# ============================================================================
# Claude usage — visualization (ggplot2)
#
# Tooling lives in the pwiz-ai repo (ai/scripts/Usage); DATA lives on Google Drive at
# "<drive>:/My Drive/Claude/Usage". This script locates the store by SCANNING drive
# letters, so it works on any machine regardless of Google Drive's letter — no editing.
#
# Reads data/usage_combined.csv (built by Combine-ClaudeUsage.ps1); writes PNGs to the
# store's plots/ folder. Run start-to-finish in RStudio (Source), or step through.
# ============================================================================

library(tidyverse)
library(scales)

# --- Locate the shared Google Drive store by scanning drive letters -------------------
find_store <- function() {
  for (L in LETTERS) {
    p <- file.path(paste0(L, ":"), "My Drive", "Claude", "Usage")
    if (dir.exists(p)) return(p)
    for (sd in list.dirs(file.path(paste0(L, ":"), "Shared drives"),
                         full.names = TRUE, recursive = FALSE)) {
      q <- file.path(sd, "Claude", "Usage")
      if (dir.exists(q)) return(q)
    }
  }
  stop("Could not find 'Claude/Usage' on any mounted Google Drive.")
}
store    <- find_store()
data_dir <- file.path(store, "data")
plot_dir <- file.path(store, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

csv_path <- file.path(data_dir, "usage_combined.csv")
stopifnot(file.exists(csv_path))

# --- Load & shape ---------------------------------------------------------------------
usage <- read_csv(csv_path, show_col_types = FALSE) |>
  mutate(date = as.Date(date)) |>
  filter(date < Sys.Date()) |>   # drop the current, still-partial day (e.g. a 06:00 snapshot of "today") so charts don't end on a misleading sliver
  mutate(model = factor(model), user = factor(user), machine = factor(machine))

multi_user    <- nlevels(usage$user) > 1
multi_machine <- nlevels(usage$machine) > 1

daily <- usage |>
  group_by(date) |>
  summarise(across(c(total_tokens, est_cost_usd, input_tokens,
                     cache_creation_tokens, cache_read_tokens, output_tokens), sum),
            .groups = "drop") |>
  arrange(date)

theme_set(theme_minimal(base_size = 12))
collected <- list()  # accumulate plots so we can also emit a single multi-page PDF
save_plot <- function(p, name, w = 10, h = 5) {
  ggsave(file.path(plot_dir, name), p, width = w, height = h, dpi = 120)
  collected[[name]] <<- p
  if (interactive()) print(p)   # RStudio stepping only; under Rscript print() opens Rplots.pdf in the CWD, which fails when run from a read-only dir (e.g. a Scheduled Task's System32)
}

# --- 1. Daily tokens, stacked by model ------------------------------------------------
p1 <- usage |>
  group_by(date, model) |>
  summarise(total_tokens = sum(total_tokens), .groups = "drop") |>
  ggplot(aes(date, total_tokens, fill = model)) +
  geom_col() +
  scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
  labs(title = "Claude usage — daily tokens by model", x = NULL, y = "tokens", fill = "model")
save_plot(p1, "01_daily_tokens_by_model.png")

# --- 2. Daily modeled cost ------------------------------------------------------------
p2 <- ggplot(daily, aes(date, est_cost_usd)) +
  geom_col(fill = "steelblue") +
  scale_y_continuous(labels = label_dollar()) +
  labs(title = "Claude usage — daily modeled cost (relative trend, not a bill)",
       x = NULL, y = "USD (modeled)")
save_plot(p2, "02_daily_cost.png")

# --- 3. Trailing 30-day modeled cost — a rolling "monthly bill if paying by token" -----
# Fill calendar gaps with $0 so the window is a true trailing 30 CALENDAR days (not 30
# active days); each point = sum of the prior 30 days, inclusive. Ramps up until 30 days
# of history have accrued.
trailing30 <- daily |>
  complete(date = seq(min(date), max(date), by = "day"),
           fill = list(est_cost_usd = 0)) |>
  arrange(date) |>
  mutate(roll30 = cumsum(est_cost_usd) - lag(cumsum(est_cost_usd), 30, default = 0))

p3 <- ggplot(trailing30, aes(date, roll30)) +
  geom_area(fill = "steelblue", alpha = 0.3) +
  geom_line(color = "steelblue", linewidth = 1) +
  scale_y_continuous(labels = label_dollar()) +
  labs(title = "Claude usage — trailing 30-day modeled cost",
       subtitle = "Rolling sum of the prior 30 days — a monthly run-rate if paying by token (ramps up over the first 30 days)",
       x = NULL, y = "USD (modeled, trailing 30 days)")
save_plot(p3, "03_trailing_30d_cost.png")

# --- 4. Token composition over time ---------------------------------------------------
p4 <- daily |>
  select(date, input_tokens, cache_creation_tokens, cache_read_tokens, output_tokens) |>
  pivot_longer(-date, names_to = "kind", values_to = "tokens") |>
  mutate(kind = recode(kind, input_tokens = "input", cache_creation_tokens = "cache write",
                       cache_read_tokens = "cache read", output_tokens = "output")) |>
  ggplot(aes(date, tokens, fill = kind)) +
  geom_col() +
  scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
  labs(title = "Claude usage — token composition", x = NULL, y = "tokens", fill = NULL)
save_plot(p4, "04_token_composition.png")

# --- 5 & 6. Team views (only meaningful once >1 teammate reports) ----------------------
if (multi_user) {
  p5 <- usage |>
    group_by(date, user) |>
    summarise(total_tokens = sum(total_tokens), .groups = "drop") |>
    ggplot(aes(date, total_tokens, fill = user)) +
    geom_col() +
    scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
    labs(title = "Claude usage — daily tokens by teammate", x = NULL, y = "tokens", fill = "user")
  save_plot(p5, "05_tokens_by_user.png")

  p6 <- usage |>
    group_by(user) |>
    summarise(est_cost_usd = sum(est_cost_usd), .groups = "drop") |>
    ggplot(aes(reorder(user, est_cost_usd), est_cost_usd)) +
    geom_col(fill = "steelblue") + coord_flip() +
    scale_y_continuous(labels = label_dollar()) +
    labs(title = "Claude usage — total modeled cost by teammate", x = NULL, y = "USD (modeled)")
  save_plot(p6, "06_cost_by_user.png")
} else {
  message("Single user so far — team charts (05/06) skipped until teammates join.")
}

# --- 7 & 8. Per-machine views (one person running Claude on several computers) ---------
if (multi_machine) {
  p7 <- usage |>
    group_by(date, machine) |>
    summarise(total_tokens = sum(total_tokens), .groups = "drop") |>
    ggplot(aes(date, total_tokens, fill = machine)) +
    geom_col() +
    scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
    labs(title = "Claude usage — daily tokens by machine", x = NULL, y = "tokens", fill = "machine")
  save_plot(p7, "07_tokens_by_machine.png")

  p8 <- usage |>
    group_by(machine) |>
    summarise(est_cost_usd = sum(est_cost_usd), .groups = "drop") |>
    ggplot(aes(reorder(machine, est_cost_usd), est_cost_usd)) +
    geom_col(fill = "steelblue") + coord_flip() +
    scale_y_continuous(labels = label_dollar()) +
    labs(title = "Claude usage — total modeled cost by machine", x = NULL, y = "USD (modeled)")
  save_plot(p8, "08_cost_by_machine.png")
} else {
  message("Single machine so far — machine charts (07/08) skipped.")
}

# --- Combined multi-page PDF (one chart per page) -------------------------------------
pdf_path <- file.path(plot_dir, "claude_usage.pdf")
pdf(pdf_path, width = 10, height = 5, onefile = TRUE)
for (nm in sort(names(collected))) print(collected[[nm]])
dev.off()

message("Plots written to: ", plot_dir)
message("Combined PDF: ", pdf_path)
