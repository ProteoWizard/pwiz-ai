#!/usr/bin/env bash
# WSL counterpart of Setup-ThisMachine.ps1: set transcript retention, install a daily systemd
# user timer that snapshots + combines Claude usage, and take a first capture. Idempotent.
#
# Usage: setup-this-machine.sh [--allow-unshared-store] [--retention-days N] [--at HH:MM]
#                              [--machine NAME] [--user EMAIL]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
py="$(command -v python3)"
tool="$here/claude_usage.py"
retention=365
at="06:00"
allow=""
machine=""
user=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --allow-unshared-store) allow="--allow-unshared-store"; shift ;;
        --retention-days) retention="$2"; shift 2 ;;
        --at) at="$2"; shift 2 ;;
        --machine) machine="$2"; shift 2 ;;
        --user) user="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null || { echo "jq is required (sudo apt install jq)" >&2; exit 1; }
[[ "$(ps -p 1 -o comm=)" == systemd ]] || {
    echo "systemd is not PID 1. Add '[boot]\nsystemd=true' to /etc/wsl.conf, then 'wsl --shutdown'." >&2; exit 1; }

# --- 0. Store must resolve (and be the shared one unless explicitly allowed) --------------
store="$("$py" "$tool" resolve)"
echo "$store"
case "$store" in
    "NOT THE SHARED STORE"*) [[ -n "$allow" ]] || { echo "Refusing: pass --allow-unshared-store to write to a private store." >&2; exit 1; } ;;
esac
store_path="${store#*: }"

# --- Store path and identity, resolved now (Windows interop is not available inside ------
# --- systemd services, and Drive shortcuts can only be followed through it) ---------------
if [[ -z "$machine" ]]; then
    win_host="$(cmd.exe /c 'echo %COMPUTERNAME%' 2>/dev/null | tr -d '\r' || true)"
    machine="${win_host:-$(hostname)}"
    machine="${machine^^}-WSL"
fi
if [[ -z "$user" ]]; then
    # Same rule as the PowerShell snapshot: email in the Drive volume label, else <winuser>@proteinms.net
    if [[ "$store_path" =~ ^/mnt/([a-zA-Z])/ ]]; then
        label="$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='${BASH_REMATCH[1]^^}:'\").VolumeName" 2>/dev/null | tr -d '\r' || true)"
        user="$(grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' <<<"$label" | head -1 || true)"
    fi
    if [[ -z "$user" ]]; then
        win_user="$(cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r' || true)"
        user="${win_user:-$USER}@proteinms.net"
    fi
fi

# --- 1. Transcript retention -------------------------------------------------------------
settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[[ -f "$settings" ]] || echo '{}' > "$settings"
cp "$settings" "$settings.bak"
jq --argjson d "$retention" '.cleanupPeriodDays = $d' "$settings.bak" > "$settings.tmp"
mv "$settings.tmp" "$settings"
echo "[1/3] cleanupPeriodDays = $retention in $settings"

# --- 2. systemd user timer -----------------------------------------------------------------
unit_dir="$HOME/.config/systemd/user"
mkdir -p "$unit_dir"
cat > "$unit_dir/claude-usage-snapshot.service" <<EOF
[Unit]
Description=Snapshot Claude Code usage into the team store

[Service]
Type=oneshot
ExecStart="$py" "$tool" --store "$store_path" $allow snapshot --machine "$machine" --user "$user"
ExecStart="$py" "$tool" --store "$store_path" $allow combine
TimeoutStartSec=30min
EOF
cat > "$unit_dir/claude-usage-snapshot.timer" <<EOF
[Unit]
Description=Daily Claude Code usage snapshot

[Timer]
OnCalendar=*-*-* $at:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now claude-usage-snapshot.timer >/dev/null
echo "[2/3] Timer claude-usage-snapshot.timer -> daily at $at (catches up at next WSL start if missed)"
echo "      machine=$machine  user=$user"

# --- 3. First capture ----------------------------------------------------------------------
echo "[3/3] Running a first capture..."
if systemctl --user start claude-usage-snapshot.service; then
    journalctl --user -u claude-usage-snapshot.service -n 20 --no-pager -o cat | tail -n 20
    echo "Done. Data: $store_path/data"
else
    journalctl --user -u claude-usage-snapshot.service -n 30 --no-pager -o cat
    exit 1
fi
