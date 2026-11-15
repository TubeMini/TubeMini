#!/usr/bin/env bash
# Builds and installs tubemini-server on a Linux machine (Ubuntu/Debian with systemd) over SSH.
# The build runs on the target itself so the binary matches its glibc.
#
#   TM_SERVER_HOST=root@192.168.1.192 TM_SERVER_PASS=... scripts/deploy-server.sh
#
# Env:
#   TM_SERVER_HOST   ssh target, must be root (required)
#   TM_SERVER_PASS   root password (optional — omit when key auth works; never hard-code it)
#   TM_SERVER_DIR    install dir (default /opt/tubemini)
#
# Target prerequisites (installed once): build-essential, rustup (cargo in /root/.cargo/bin), yt-dlp and deno in
# /usr/local/bin — see docs/SETUP.md section 7.
# What it does: sync server/ → $DIR/src, cargo build --release, install $DIR/tubemini-server, create $DIR/config.toml if
# missing, a `tubemini` system user, the systemd unit `tubemini` and a daily `yt-dlp -U`, then restart the service.
set -euo pipefail

: "${TM_SERVER_HOST:?set TM_SERVER_HOST=root@<host>}"
DIR="${TM_SERVER_DIR:-/opt/tubemini}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH=(ssh -o ConnectTimeout=15 -o ServerAliveInterval=30)

if [[ -n "${TM_SERVER_PASS:-}" ]]; then
    ASKPASS="$(mktemp)"
    trap 'rm -f "$ASKPASS"' EXIT
    printf '#!/bin/sh\nprintf "%%s\\n" "$TM_SERVER_PASS"\n' >"$ASKPASS"
    chmod 700 "$ASKPASS"
    export TM_SERVER_PASS SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-:0}"
    SSH+=(-o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1)
fi

echo "==> sync server/ -> $TM_SERVER_HOST:$DIR/src"
tar -C "$ROOT/server" --exclude=./target --exclude=./data --exclude=./config.toml -cf - . |
    "${SSH[@]}" "$TM_SERVER_HOST" "mkdir -p $DIR/src && find $DIR/src -mindepth 1 -maxdepth 1 ! -name target -exec rm -rf {} + && tar --no-same-owner -xf - -C $DIR/src"

echo "==> build + install"
"${SSH[@]}" "$TM_SERVER_HOST" "DIR=$DIR bash -s" <<'REMOTE'
set -euo pipefail
cd "$DIR/src"
/root/.cargo/bin/cargo build --release -q
id tubemini >/dev/null 2>&1 || useradd --system --home-dir /var/lib/tubemini --create-home --shell /usr/sbin/nologin tubemini
install -m 755 target/release/tubemini-server "$DIR/tubemini-server.new"
mv -f "$DIR/tubemini-server.new" "$DIR/tubemini-server"
if [ ! -f "$DIR/config.toml" ]; then
    sed -e 's#^yt_dlp_path = .*#yt_dlp_path = "/usr/local/bin/yt-dlp"#' config.example.toml > "$DIR/config.toml"
fi
mkdir -p "$DIR/data" && chown -R tubemini:tubemini "$DIR/data"
cat > /etc/systemd/system/tubemini.service <<UNIT
[Unit]
Description=TubeMini server (GData + /tm/v1 for old YouTube apps and TubeMini on iOS 6)
After=network-online.target
Wants=network-online.target

[Service]
User=tubemini
WorkingDirectory=$DIR
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=$DIR/tubemini-server --config $DIR/config.toml
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
# YouTube changes often: keep yt-dlp current
cat > /etc/systemd/system/tubemini-ytdlp-update.service <<UNIT
[Unit]
Description=Update yt-dlp for TubeMini

[Service]
Type=oneshot
ExecStart=/usr/local/bin/yt-dlp -U
UNIT
cat > /etc/systemd/system/tubemini-ytdlp-update.timer <<UNIT
[Unit]
Description=Daily yt-dlp update for TubeMini

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now tubemini-ytdlp-update.timer >/dev/null 2>&1
systemctl enable tubemini >/dev/null 2>&1
systemctl restart tubemini
sleep 3
systemctl is-active tubemini
journalctl -u tubemini --no-pager -n 6 -o cat
REMOTE
echo "==> done"
