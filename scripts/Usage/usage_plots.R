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
# Common baseline start (fixed, then extends forward). Most teammates had only ~28 days of
# retained transcripts when they first ran the scripts; a few happened to have more. To keep
# the cross-person comparison fair, anchor every chart to one shared start date rather than
# each person's full retained history. Fixed (not Sys.Date()-28) so the window GROWS forward.
start_date <- as.Date("2026-05-15")   # 28 days before the project's common start (2026-06-12)

# Per-person / per-machine charts (05–08) show only this trailing window — a recent "burn
# rate" rather than an ever-growing all-time total, and a fair like-for-like comparison.
recent_start <- Sys.Date() - 30

usage <- read_csv(csv_path, show_col_types = FALSE) |>
  mutate(date = as.Date(date)) |>
  filter(date < Sys.Date()) |>   # drop the current, still-partial day (e.g. a 06:00 snapshot of "today") so charts don't end on a misleading sliver
  filter(date >= start_date) |>  # shared baseline so longer-retained histories don't skew the comparison
  mutate(user = factor(user), machine = factor(machine))

# Pretty, version-ordered model labels for the legend: drop the redundant "claude-" prefix,
# format like "Opus 4.8" / "Fable 5", and order by version DESCENDING (newest on top),
# tie-broken by family capability (Opus > Sonnet > Haiku). Non-versioned ids (e.g.
# <synthetic>) sort last. Applied only to the by-model chart below (others use all models).
model_order <- function(ids) {
  fam_rank <- c(fable = 1, opus = 1, sonnet = 2, haiku = 3)
  tibble(id = unique(as.character(ids))) |>
    mutate(
      base    = sub("^claude-", "", id),
      parts   = str_split(base, "-"),
      family  = map_chr(parts, 1),
      verstr  = map_chr(parts, ~ if (length(.x) > 1) paste(.x[-1], collapse = ".") else NA_character_),
      version = suppressWarnings(as.numeric(verstr)),
      version = if_else(is.na(version), -Inf, version),
      rank    = if_else(is.na(unname(fam_rank[family])), 99, unname(fam_rank[family])),
      pretty  = if_else(is.na(verstr),
                        str_to_title(str_remove_all(base, "[<>]")),
                        paste0(str_to_title(family), " ", verstr))
    ) |>
    arrange(desc(version), rank, family)
}

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
# Keep only models that are a meaningful share of all tokens; drop tinier ones (and the
# zero-token <synthetic>) so the legend lists only what's actually visible in the plot.
min_model_share <- 0.01   # 1% of total tokens
model_tok   <- usage |> group_by(model) |> summarise(t = sum(total_tokens), .groups = "drop")
keep_models <- model_tok |> filter(t >= min_model_share * sum(model_tok$t)) |> pull(model)
mo <- model_order(keep_models)

p1 <- usage |>
  filter(model %in% keep_models) |>
  mutate(model = factor(model, levels = mo$id, labels = mo$pretty)) |>
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
    filter(date >= recent_start) |>
    group_by(date, user) |>
    summarise(total_tokens = sum(total_tokens), .groups = "drop") |>
    ggplot(aes(date, total_tokens, fill = user)) +
    geom_col() +
    scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
    labs(title = "Claude usage — daily tokens by teammate (last 30 days)", x = NULL, y = "tokens", fill = "user")
  save_plot(p5, "05_tokens_by_user.png")

  p6 <- usage |>
    filter(date >= recent_start) |>
    group_by(user) |>
    summarise(est_cost_usd = sum(est_cost_usd), .groups = "drop") |>
    ggplot(aes(reorder(user, est_cost_usd), est_cost_usd)) +
    geom_col(fill = "steelblue") + coord_flip() +
    scale_y_continuous(labels = label_dollar()) +
    labs(title = "Claude usage — modeled cost by teammate (last 30 days)", x = NULL, y = "USD (modeled)")
  save_plot(p6, "06_cost_by_user.png")
} else {
  message("Single user so far — team charts (05/06) skipped until teammates join.")
}

# --- 7 & 8. Per-machine views (one person running Claude on several computers) ---------
if (multi_machine) {
  p7 <- usage |>
    filter(date >= recent_start) |>
    group_by(date, machine) |>
    summarise(total_tokens = sum(total_tokens), .groups = "drop") |>
    ggplot(aes(date, total_tokens, fill = machine)) +
    geom_col() +
    scale_y_continuous(labels = label_number(scale_cut = cut_short_scale())) +
    labs(title = "Claude usage — daily tokens by machine (last 30 days)", x = NULL, y = "tokens", fill = "machine")
  save_plot(p7, "07_tokens_by_machine.png")

  p8 <- usage |>
    filter(date >= recent_start) |>
    group_by(machine) |>
    summarise(est_cost_usd = sum(est_cost_usd), .groups = "drop") |>
    ggplot(aes(reorder(machine, est_cost_usd), est_cost_usd)) +
    geom_col(fill = "steelblue") + coord_flip() +
    scale_y_continuous(labels = label_dollar()) +
    labs(title = "Claude usage — modeled cost by machine (last 30 days)", x = NULL, y = "USD (modeled)")
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
