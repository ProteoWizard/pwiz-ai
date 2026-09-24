#!/usr/bin/env bash
#
# Claude Code statusline script -- WSL2/Linux port of statusline.ps1.
# Displays project, git branch, model, and context usage.
#
# Example outputs:
#   ai-dev [master] | Sonnet | 84% left
#   pwiz [Skyline/work/20260113_feature] | Opus | 49% left
#
# This mirrors statusline.ps1 field-for-field so the two can coexist on a
# mixed Windows/WSL2 team: same active-project-<pid>.json and
# context-state-<pid>.json file formats, same tier order for resolving the
# active project, same 97%-usable-window calibration. See statusline.ps1's
# own header comment for the rationale behind each of those; this file only
# calls out where the port differs.
#
# Differences from the .ps1:
#   - No pwsh dependency -- it isn't installed in this WSL2 environment. JSON
#     parsing/writing is delegated to `jq`; everything else (process walk,
#     git, file sweep) is plain bash/coreutils.
#   - The Windows-only "walk parents looking for claude.exe via
#     Get-CimInstance Win32_Process" becomes a `ps`-based walk looking for a
#     process named `claude*`.
#
# Requires: jq (see https://jqlang.org/download/).
#
# SETUP: add to ~/.claude/settings.json (adjust path to your ai/ checkout):
#   {
#     "statusLine": {
#       "type": "command",
#       "command": "bash <your-root>/ai/scripts/statusline.sh"
#     }
#   }

set -u

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ai_root="$(dirname -- "$script_dir")"
tmp_dir="$ai_root/.tmp"

input_json="$(cat)"

# --- Parse the payload (workspace dir, model, token usage) ------------------
# Defaults first: if jq fails outright (bad/missing input), the statusline
# must still print something rather than crash under `set -u`. Each output
# line is `KEY='value'`, meant to be eval'd -- @sh shell-quotes the two
# string fields so spaces/quotes in a path or model name can't break eval.
WS_PROJECT_DIR="" MODEL_NAME="" INPUT_TOKENS=0 CACHE_CREATION_TOKENS=0
CACHE_READ_TOKENS=0 CONTEXT_WINDOW_SIZE=0
payload_vars="$(printf '%s' "$input_json" | jq -r '
  "WS_PROJECT_DIR=" + ((.workspace.project_dir // "") | @sh),
  "MODEL_NAME=" + ((.model.display_name // "") | @sh),
  "INPUT_TOKENS=" + ((.context_window.current_usage.input_tokens // 0) | tostring),
  "CACHE_CREATION_TOKENS=" + ((.context_window.current_usage.cache_creation_input_tokens // 0) | tostring),
  "CACHE_READ_TOKENS=" + ((.context_window.current_usage.cache_read_input_tokens // 0) | tostring),
  "CONTEXT_WINDOW_SIZE=" + ((.context_window.context_window_size // 0) | tostring)
' 2>/dev/null)"
[[ -n "$payload_vars" ]] && eval "$payload_vars"

# --- Find the Claude Code process's PID by walking up the parent chain ------
# The direct parent is often a transient per-tick shell wrapper; walk up to
# the first process named `claude*` for a stable per-session identity that
# the StatusMcp server computes the same way (so both sides land on the same
# PID-keyed files). Capped at 16 levels.
find_claude_pid() {
  local cur=$$ depth=0 line pid ppid comm
  while [[ -n "$cur" && "$cur" != "0" && $depth -lt 16 ]]; do
    line="$(ps -o pid=,ppid=,comm= -p "$cur" 2>/dev/null)"
    [[ -z "$line" ]] && return 1
    read -r pid ppid comm <<<"$line"
    if [[ "$comm" == claude* ]]; then
      printf '%s' "$pid"
      return 0
    fi
    cur="$ppid"
    depth=$((depth + 1))
  done
  return 1
}
claude_pid="$(find_claude_pid || true)"

# Reads an active-project-*.json file, emits ACTIVE_PATH/ACTIVE_NAME lines.
# No output (and thus no `eval`) if the file has no usable .path.
read_active_project() {
  jq -r 'if (.path // "") == "" then empty else
    "ACTIVE_PATH=" + (.path | @sh), "ACTIVE_NAME=" + ((.name // "") | @sh)
  end' "$1" 2>/dev/null
}

per_session_file=""
[[ -n "$claude_pid" ]] && per_session_file="$tmp_dir/active-project-$claude_pid.json"
legacy_file="$tmp_dir/active-project.json"

project_dir=""
project_name=""

# 1. Per-session active project: an explicit set_active_project for THIS
#    session (keyed by the Claude Code PID), which deliberately overrides
#    the launch dir.
if [[ -n "$per_session_file" && -f "$per_session_file" ]]; then
  active_vars="$(read_active_project "$per_session_file")"
  if [[ -n "$active_vars" ]]; then
    eval "$active_vars"
    project_dir="$ACTIVE_PATH"
    project_name="$ACTIVE_NAME"
  fi
fi

# 1.5 skyclaude scoping: when PWIZ_LSP_DIR points at a checkout's
#     pwiz_tools, show that checkout (and its git branch) rather than the
#     launch dir. An explicit set_active_project (above) still outranks
#     this; single-clone layouts leave PWIZ_LSP_DIR unset and fall through.
if [[ -z "$project_dir" && -n "${PWIZ_LSP_DIR:-}" ]]; then
  checkout_dir="$(dirname -- "$PWIZ_LSP_DIR")" # strip trailing 'pwiz_tools'
  if [[ -n "$checkout_dir" && -d "$checkout_dir" ]]; then
    project_dir="$checkout_dir"
    project_name="$(basename -- "$checkout_dir")"
  fi
fi

# 2. The directory Claude Code was actually launched in (this session's
#    real workspace). This must outrank the legacy global below -- otherwise
#    a weeks-old global set_active_project shadows the live session.
if [[ -z "$project_dir" && -n "$WS_PROJECT_DIR" ]]; then
  project_dir="$WS_PROJECT_DIR"
  project_name="$(basename -- "$project_dir")"
fi

# 3. Legacy global active project (cross-session, no PID): final fallback
#    only, used when the payload carried no workspace dir.
if [[ -z "$project_dir" && -f "$legacy_file" ]]; then
  active_vars="$(read_active_project "$legacy_file")"
  if [[ -n "$active_vars" ]]; then
    eval "$active_vars"
    project_dir="$ACTIVE_PATH"
    project_name="$ACTIVE_NAME"
  fi
fi

model="$MODEL_NAME"

# --- Git branch for the active project ---------------------------------------
git_info=""
if [[ -n "$project_dir" ]]; then
  branch="$(git -C "$project_dir" branch --show-current 2>/dev/null)"
  [[ -n "$branch" ]] && git_info=" [$branch]"
fi

# --- Context remaining (mirrors the .ps1's 97%-usable-window calibration) --
# See statusline.ps1 for why 97: calibrated for the 1M-context tier so "0%
# left" lines up with Claude Code's own auto-compact warning. On the 200K
# tier this reads looser than the real warning point; Claude's own warning
# is authoritative there.
ctx=""
if [[ "$CONTEXT_WINDOW_SIZE" -gt 0 ]]; then
  current=$((INPUT_TOKENS + CACHE_CREATION_TOKENS + CACHE_READ_TOKENS))
  read -r used_pct left <<<"$(awk -v cur="$current" -v size="$CONTEXT_WINDOW_SIZE" -v maxpct=97 \
    'BEGIN { used = (cur * 100) / size; left = maxpct - used; if (left < 0) left = 0; printf "%.2f %d", used, int(left) }')"
  ctx=" | ${left}% left"

  # Cache the snapshot so get_context_usage serves the same number the user
  # sees here. Keyed by the Claude Code PID found above; StatusMcp does the
  # same walk so both sides land on the same file.
  if [[ -n "$claude_pid" ]]; then
    mkdir -p "$tmp_dir" 2>/dev/null
    jq -n \
      --arg model "$model" \
      --argjson context_window_size "$CONTEXT_WINDOW_SIZE" \
      --argjson input_tokens "$INPUT_TOKENS" \
      --argjson cache_creation_input_tokens "$CACHE_CREATION_TOKENS" \
      --argjson cache_read_input_tokens "$CACHE_READ_TOKENS" \
      --argjson used_tokens "$current" \
      --argjson used_pct "$used_pct" \
      --argjson left_pct "$left" \
      --argjson usable_max_pct 97 \
      --arg calibrated_at "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
      '{model:$model, context_window_size:$context_window_size,
        input_tokens:$input_tokens, cache_creation_input_tokens:$cache_creation_input_tokens,
        cache_read_input_tokens:$cache_read_input_tokens, used_tokens:$used_tokens,
        used_pct:$used_pct, left_pct:$left_pct, usable_max_pct:$usable_max_pct,
        calibrated_at:$calibrated_at}' \
      > "$tmp_dir/context-state-$claude_pid.json" 2>/dev/null || true
  fi
fi

# --- Sweep orphan context-state / active-project files ----------------------
# Any file whose PID is no longer running is from a session that has exited.
# Cheap (a few `kill -0` checks per tick); keeps ai/.tmp/ tidy without a
# separate cron/cleanup script.
for f in "$tmp_dir"/context-state-*.json "$tmp_dir"/active-project-*.json; do
  [[ -e "$f" ]] || continue
  base="$(basename -- "$f" .json)"
  pid="${base##*-}"
  [[ "$pid" =~ ^[0-9]+$ ]] || continue
  kill -0 "$pid" 2>/dev/null || rm -f "$f"
done

echo "${project_name}${git_info} | ${model}${ctx}"
