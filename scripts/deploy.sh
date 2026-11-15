#!/usr/bin/env bash
# Installs a TubeMini .deb on the jailbroken iPad over SSH (scp + dpkg -i; postinst runs uicache).
#
#   TM_IPAD_HOST=192.168.1.20 TM_IPAD_PASS=... scripts/deploy.sh [file.deb] [--launch]
#
# Env:
#   TM_IPAD_HOST   iPad IP (required)
#   TM_IPAD_USER   default: root
#   TM_IPAD_PASS   root password (optional — omit when key auth is set up; never hard-code it)
# The .deb defaults to the newest one in ios/TubeMini/packages/.
# --launch opens the app afterwards if the iPad has the `cblaunch` helper in /usr/bin.
set -euo pipefail

: "${TM_IPAD_HOST:?set TM_IPAD_HOST to the iPad IP}"
USER_="${TM_IPAD_USER:-root}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEB=""
LAUNCH=0
for a in "$@"; do
    case "$a" in
        --launch) LAUNCH=1 ;;
        *) DEB="$a" ;;
    esac
done
[[ -z "$DEB" ]] && DEB="$(ls -t "$ROOT"/ios/TubeMini/packages/*.deb | head -1)"
[[ -f "$DEB" ]] || { echo "no .deb found" >&2; exit 1; }

# iOS 6 ships OpenSSH 6.x: allow its legacy host key / key exchange / cipher algorithms
OPTS=(-o ConnectTimeout=15 -o HostKeyAlgorithms=+ssh-rsa
      -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1,diffie-hellman-group-exchange-sha1
      -o Ciphers=+aes128-cbc,aes256-cbc,3des-cbc)

if [[ -n "${TM_IPAD_PASS:-}" ]]; then
    ASKPASS="$(mktemp)"
    trap 'rm -f "$ASKPASS"' EXIT
    printf '#!/bin/sh\nprintf "%%s\\n" "$TM_IPAD_PASS"\n' >"$ASKPASS"
    chmod 700 "$ASKPASS"
    export TM_IPAD_PASS SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force DISPLAY="${DISPLAY:-:0}"
    OPTS+=(-o PubkeyAuthentication=no -o NumberOfPasswordPrompts=1)
fi

NAME="$(basename "$DEB")"
echo "==> copy $NAME -> $TM_IPAD_HOST"
scp -O -q "${OPTS[@]}" "$DEB" "$USER_@$TM_IPAD_HOST:/tmp/$NAME"   # -O: legacy scp protocol for old sshd
echo "==> dpkg -i"
ssh "${OPTS[@]}" "$USER_@$TM_IPAD_HOST" "dpkg -i /tmp/$NAME && rm -f /tmp/$NAME; killall -9 TubeMini 2>/dev/null; true"
if [[ $LAUNCH == 1 ]]; then
    ssh "${OPTS[@]}" "$USER_@$TM_IPAD_HOST" \
        "if [ -x /usr/bin/cblaunch ]; then cblaunch wake; cblaunch launch vn.tubemini.io; else echo 'cblaunch not installed — open TubeMini by hand'; fi"
fi
echo "==> done"
