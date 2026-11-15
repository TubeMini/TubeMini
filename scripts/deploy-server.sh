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
# What it does: copies server/ and scripts/install.sh to the target and runs `install.sh --service --yes` there
# (installs what is missing — build tools, Rust, yt-dlp, Deno —, builds, keeps $DIR/config.toml and the data,
# sets up the systemd unit `tubemini` and a daily `yt-dlp -U`). See docs/SETUP.md section 7.
set -euo pipefail

: "${TM_SERVER_HOST:?set TM_SERVER_HOST=root@<host>}"
DIR="${TM_SERVER_DIR:-/opt/tubemini}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SSH=(ssh -o ConnectTimeout=15 -o ServerAliveInterval=30)

if [[ -n "${TM_SERVER_PASS:-}" ]]; then
    ASKPASS="$(mktemp)"
    printf '#!/bin/sh\nprintf "%%s\\n" "$TM_SERVER_PASS"\n' >"$ASKPASS"
    chmod 700 "$ASKPASS"
    export TM_SERVER_PASS SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-:0}"
    SSH+=(-o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1)
fi

echo "==> sync server/ + install.sh -> $TM_SERVER_HOST:/tmp/tubemini-install"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "${ASKPASS:-}"' EXIT
mkdir -p "$STAGE/server"
tar -C "$ROOT/server" --exclude=./target --exclude=./data --exclude=./config.toml -cf - . | tar -xf - -C "$STAGE/server"
cp "$ROOT/scripts/install.sh" "$STAGE/install.sh"
tar -C "$STAGE" -cf - . |
    "${SSH[@]}" "$TM_SERVER_HOST" "rm -rf /tmp/tubemini-install && mkdir -p /tmp/tubemini-install && tar --no-same-owner -xf - -C /tmp/tubemini-install"

echo "==> install.sh --service (build on the target, keeps config and data)"
"${SSH[@]}" "$TM_SERVER_HOST" "bash /tmp/tubemini-install/install.sh --service --yes --dir $DIR && rm -rf /tmp/tubemini-install"
echo "==> done"
