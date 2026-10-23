#!/bin/sh
# Install or upgrade hinhnen:
#
#   curl -fsSL https://raw.githubusercontent.com/doannc2212/hinhnen/main/install.sh | sh
#
# Safe to re-run: it replaces the binary in place, sets up autostart only if
# none exists, and restarts a running daemon.
set -eu

REPO="doannc2212/hinhnen"

say() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

# Wrapped in a function so a partially downloaded script never runs.
main() {
    [ "$(uname -s)" = Linux ] || die "hinhnen runs on Linux (Wayland) only"
    case "$(uname -m)" in
        x86_64 | amd64) arch=x86_64 ;;
        aarch64 | arm64) arch=aarch64 ;;
        *) die "no prebuilt hinhnen for $(uname -m) - build it with: cargo install --git https://github.com/$REPO" ;;
    esac
    has curl || die "curl is required"

    # 1. awww - the only runtime dependency.
    if ! has awww || ! has awww-daemon; then
        if has pacman; then
            say "installing awww"
            sudo pacman -S --needed --noconfirm awww
        else
            die "awww is required - install it with your package manager (see https://codeberg.org/LGFae/awww), then re-run"
        fi
    fi

    # 2. The binary. Upgrade an existing install in place so whatever launches
    #    it keeps working; otherwise use ~/.local/bin.
    bin="$(command -v hinhnen 2>/dev/null || true)"
    if [ -z "$bin" ] || [ ! -w "$(dirname "$bin")" ]; then
        bin="$HOME/.local/bin/hinhnen"
    fi
    mkdir -p "$(dirname "$bin")"
    say "downloading hinhnen ($arch) to $bin"
    tmp="$bin.download"
    if ! curl -fsSL "https://github.com/$REPO/releases/latest/download/hinhnen-$arch-linux" -o "$tmp"; then
        rm -f "$tmp"
        die "download failed"
    fi
    chmod +x "$tmp"
    # Rename rather than overwrite, so a running daemon isn't disturbed.
    mv -f "$tmp" "$bin"

    # 3. Autostart - keep whatever is already there, otherwise use systemd when
    #    the session supports it.
    config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
    if systemctl --user is-enabled hinhnen.service >/dev/null 2>&1; then
        autostart=systemd
    elif grep -rqs "hinhnen daemon" "$config_home/hypr"; then
        autostart=hyprland
    elif systemctl --user is-active graphical-session.target >/dev/null 2>&1; then
        say "enabling hinhnen.service"
        mkdir -p "$config_home/systemd/user"
        cat >"$config_home/systemd/user/hinhnen.service" <<EOF
[Unit]
Description=hinhnen wallpaper daemon
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=$bin daemon
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF
        systemctl --user daemon-reload
        systemctl --user enable hinhnen.service
        autostart=systemd
    else
        autostart=none
    fi

    # 4. (Re)start the daemon so the new binary is live now, not after next login.
    if [ "$autostart" = systemd ]; then
        systemctl --user restart hinhnen.service
    elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
        if pkill -x hinhnen; then
            i=0
            while pgrep -x hinhnen >/dev/null && [ "$i" -lt 50 ]; do
                sleep 0.1
                i=$((i + 1))
            done
        fi
        setsid -f "$bin" daemon >/dev/null 2>&1 </dev/null
    fi

    sleep 1
    if pgrep -x hinhnen >/dev/null; then
        say "$("$bin" --version) is running"
    else
        say "$("$bin" --version) installed - start it with: $bin daemon"
    fi

    if [ "$autostart" = none ]; then
        say "to start hinhnen on login, add to your hyprland.conf:  exec-once = $bin daemon"
    fi
    if [ "$(command -v hinhnen 2>/dev/null || true)" != "$bin" ]; then
        say "note: add $(dirname "$bin") to your PATH to use the \`hinhnen\` command"
    fi
}

main "$@"
