#!/usr/bin/env bash
# TubeMini server installer for Ubuntu / Debian (systemd). Two ways, same config and data in --dir:
#   1) Docker  - the server in a container (Docker, or Podman when the machine has only that),
#                started with the machine; yt-dlp is updated at every start and daily.
#   2) Service - built from source (Rust) and run as the systemd service "tubemini"; yt-dlp updated daily.
#
#   sudo ./install.sh                          # asks: Docker or service, port, access token
#   sudo ./install.sh --docker --port 8080 --token abc123 --yes
#   sudo ./install.sh --service --yes          # also the way to update: run it again
#   sudo ./install.sh --uninstall [--purge]    # --purge also deletes config and data (subscriptions, history)
#   ./install.sh --status
# Other options: --dir DIR (default /opt/tubemini), --no-autostart (Docker/Podman without systemd, e.g. rootless tests).
set -euo pipefail

MODE="" PORT="" TOKEN="" TOKEN_SET=0 DIR="/opt/tubemini" YES=0 UNINSTALL=0 PURGE=0 AUTOSTART=1 STATUS=0
NAME="tubemini" IMAGE="tubemini:latest" UNIT_DIR="/etc/systemd/system"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGS=("$@")
# Sources: next to this script (release archive) or the repository layout (scripts/install.sh)
if [[ -d "$HERE/server" ]]; then SRC="$HERE/server"
elif [[ -d "$HERE/../server" ]]; then SRC="$(cd "$HERE/../server" && pwd)"
else SRC=""; fi

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mLỗi:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
    --docker) MODE=docker ;;
    --service) MODE=service ;;
    --port) PORT="${2:-}"; shift ;;
    --token) TOKEN="${2:-}"; TOKEN_SET=1; shift ;;
    --dir) DIR="${2:-}"; shift ;;
    --yes | -y) YES=1 ;;
    --no-autostart) AUTOSTART=0 ;;
    --uninstall) UNINSTALL=1 ;;
    --purge) PURGE=1 ;;
    --status) STATUS=1 ;;
    -h | --help) usage ;;
    *) die "không hiểu tham số: $1 (xem --help)" ;;
    esac
    shift
done

interactive() { [[ $YES -eq 0 && -t 0 ]]; }

confirm() { # confirm "question" → 0 when yes (always yes with --yes / no terminal)
    interactive || return 0
    local a
    read -rp "$1 [Y/n] " a
    [[ -z "$a" || "$a" =~ ^[YyCc] ]]
}

config_value() { # config_value key → value of `key = "value"` in config.toml
    [[ -f "$DIR/config.toml" ]] || return 0
    sed -n -E "s/^$1[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$DIR/config.toml" | head -n1
}

lan_ip() { hostname -I 2>/dev/null | awk '{print $1}'; }

# ---------------------------------------------------------------- status / uninstall

installed_mode() {
    if [[ -f "$UNIT_DIR/$NAME.service" ]]; then echo service
    elif [[ -f "$UNIT_DIR/$NAME-container.service" ]]; then echo podman
    elif command -v docker >/dev/null 2>&1 && docker inspect "$NAME" >/dev/null 2>&1; then echo docker
    elif command -v podman >/dev/null 2>&1 && podman inspect "$NAME" >/dev/null 2>&1; then echo podman
    else echo none; fi
}

ping_server() { # ping_server port → 0 when /tm/v1/ping answers
    local token
    token="$(config_value auth_token)"
    curl -fsS -m 3 -H "X-Auth-Token: $token" "http://127.0.0.1:$1/tm/v1/ping" 2>/dev/null
}

show_status() {
    local mode port
    mode="$(installed_mode)"
    port="$(config_value listen | sed -E 's/.*:([0-9]+)$/\1/')"
    case "$mode" in
    service) say "Cách cài: service systemd ($(systemctl is-active $NAME 2>/dev/null))" ;;
    docker | podman) say "Cách cài: container ($mode)" ;;
    *) say "Chưa cài TubeMini server ở $DIR"; return 0 ;;
    esac
    if [[ -n "$port" ]] && ping_server "$port" >/dev/null; then
        say "Đang chạy: http://$(lan_ip):$port"
    else
        warn "Không trả lời ở cổng ${port:-?}"
    fi
}

uninstall() {
    say "Gỡ TubeMini server"
    systemctl disable --now "$NAME.service" "$NAME-container.service" "$NAME-ytdlp-update.timer" >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/$NAME.service" "$UNIT_DIR/$NAME-container.service" \
        "$UNIT_DIR/$NAME-ytdlp-update.service" "$UNIT_DIR/$NAME-ytdlp-update.timer"
    systemctl daemon-reload 2>/dev/null || true
    for engine in docker podman; do
        if command -v "$engine" >/dev/null 2>&1; then
            "$engine" rm -f "$NAME" >/dev/null 2>&1 || true
            "$engine" rmi "$IMAGE" >/dev/null 2>&1 || true
            "$engine" image prune -f --filter label=org.tubemini.image >/dev/null 2>&1 || true
        fi
    done
    rm -rf "$DIR/src" "$DIR/tubemini-server"
    if [[ $PURGE -eq 1 ]]; then
        if confirm "Xoá luôn cấu hình và dữ liệu (kênh theo dõi, lịch sử) trong $DIR?"; then
            rm -rf "$DIR"
            userdel "$NAME" >/dev/null 2>&1 || true
            say "Đã xoá $DIR"
        fi
    else
        say "Giữ cấu hình và dữ liệu trong $DIR (thêm --purge để xoá)"
    fi
}

# ---------------------------------------------------------------- shared

choose() {
    if [[ -z "$MODE" ]]; then
        interactive || die "chọn --docker hoặc --service"
        echo "Cài TubeMini server theo cách nào?"
        echo "  1) Docker  — chạy trong container (Docker hoặc Podman), tự khởi động cùng máy"
        echo "  2) Service — build từ mã nguồn, chạy như dịch vụ systemd của Ubuntu"
        local c
        read -rp "Chọn 1 hoặc 2 [1]: " c
        case "${c:-1}" in 1) MODE=docker ;; 2) MODE=service ;; *) die "chỉ chọn 1 hoặc 2" ;; esac
    fi
    local current_port current_token
    current_port="$(config_value listen | sed -E 's/.*:([0-9]+)$/\1/')"
    if [[ -z "$PORT" ]]; then
        PORT="${current_port:-8080}"
        if interactive; then
            local p
            read -rp "Cổng HTTP [$PORT]: " p
            PORT="${p:-$PORT}"
        fi
    fi
    [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || die "cổng không hợp lệ: $PORT"
    current_token="$(config_value auth_token)"
    if [[ $TOKEN_SET -eq 0 ]] && interactive; then
        local t
        read -rp "Mã truy cập (để trống nếu chỉ dùng trong mạng nhà)${current_token:+ [giữ mã hiện tại]}: " t
        if [[ -n "$t" ]]; then TOKEN="$t"; TOKEN_SET=1; fi
    fi
    [[ "$TOKEN" =~ ^[A-Za-z0-9._~-]*$ ]] || die "mã truy cập chỉ gồm chữ, số và . _ ~ -"
}

write_config() { # config.toml shared by both ways; the data directory beside it
    mkdir -p "$DIR/data"
    if [[ ! -f "$DIR/config.toml" ]]; then
        sed -e 's#^yt_dlp_path = .*#yt_dlp_path = "/usr/local/bin/yt-dlp"#' "$SRC/config.example.toml" >"$DIR/config.toml"
    fi
    sed -i -E "s#^listen = .*#listen = \"0.0.0.0:$PORT\"#" "$DIR/config.toml"
    if [[ $TOKEN_SET -eq 1 ]]; then
        sed -i -E "s#^auth_token = \"[^\"]*\"#auth_token = \"$TOKEN\"#" "$DIR/config.toml"
    fi
}

ytdlp_timer() { # ytdlp_timer "command" → daily yt-dlp update
    cat >"$UNIT_DIR/$NAME-ytdlp-update.service" <<UNIT
[Unit]
Description=Update yt-dlp for TubeMini

[Service]
Type=oneshot
ExecStart=$1
UNIT
    cat >"$UNIT_DIR/$NAME-ytdlp-update.timer" <<UNIT
[Unit]
Description=Daily yt-dlp update for TubeMini

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
UNIT
}

wait_ready() {
    say "Chờ máy chủ trả lời ở cổng $PORT…"
    for _ in $(seq 1 60); do
        if ping_server "$PORT" >/dev/null; then
            ping_server "$PORT" | grep -o 'server="[^"]*" yt_dlp="[^"]*"' || true
            return 0
        fi
        sleep 1
    done
    die "máy chủ không trả lời sau 60 giây"
}

summary() {
    local ip
    ip="$(lan_ip)"
    say "Xong. Máy chủ: http://${ip:-<IP máy này>}:$PORT"
    echo "    iPad: TubeMini → Cài đặt → địa chỉ máy chủ http://${ip:-<IP>}:$PORT"
    echo "    App YouTube cũ + TubeRepair: Custom URL http://${ip:-<IP>}:$PORT (thêm /720 để xem HD)"
    echo "    Cấu hình: $DIR/config.toml   Dữ liệu: $DIR/data"
    echo "    Log: $1"
    echo "    Cập nhật: chạy lại install.sh. Gỡ: sudo ./install.sh --uninstall"
}

need_packages() { # need_packages cmd:package ... → apt-get install what is missing
    local missing=()
    for pair in "$@"; do
        command -v "${pair%%:*}" >/dev/null 2>&1 || missing+=("${pair#*:}")
    done
    [[ ${#missing[@]} -eq 0 ]] && return 0
    say "Cài gói: ${missing[*]}"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" >/dev/null
}

# ---------------------------------------------------------------- 1) Docker / Podman

install_docker() {
    local engine
    if command -v docker >/dev/null 2>&1; then engine=docker
    elif command -v podman >/dev/null 2>&1; then engine=podman
    else
        confirm "Máy chưa có Docker. Cài docker.io từ kho Ubuntu?" || die "cần Docker (hoặc chọn --service)"
        need_packages docker:docker.io
        engine=docker
    fi
    [[ "$engine" == docker && $AUTOSTART -eq 1 ]] && systemctl enable --now docker >/dev/null 2>&1 || true
    local bin
    bin="$(command -v "$engine")"
    say "Build image bằng $engine (lần đầu vài phút)…"
    "$engine" build -t "$IMAGE" "$SRC" >/tmp/tubemini-build.log 2>&1 || die "build lỗi, xem /tmp/tubemini-build.log"
    # Old images of earlier builds (build stage ~1.6 GB) would pile up with every update
    "$engine" image prune -f --filter label=org.tubemini.image >/dev/null 2>&1 || true
    write_config
    # Free the port: the other way may be installed
    systemctl disable --now "$NAME.service" >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/$NAME.service"
    "$engine" rm -f "$NAME" >/dev/null 2>&1 || true
    # Host network: the server listens on the port of config.toml directly, and its mDNS announcement
    # reaches the home network (iPad "Tìm máy chủ trong mạng")
    local opts="--name $NAME --network host -v $DIR:/data"
    if [[ "$engine" == docker ]]; then
        # The Docker daemon starts with the machine and brings the container back
        # shellcheck disable=SC2086
        "$bin" run -d --restart unless-stopped $opts "$IMAGE" >/dev/null
    elif [[ $AUTOSTART -eq 1 ]]; then
        cat >"$UNIT_DIR/$NAME-container.service" <<UNIT
[Unit]
Description=TubeMini server (Podman container)
After=network-online.target
Wants=network-online.target

[Service]
ExecStartPre=-$bin rm -f $NAME
ExecStart=$bin run --rm $opts $IMAGE
ExecStop=$bin stop -t 10 $NAME
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
        systemctl daemon-reload
        systemctl enable --now "$NAME-container.service" >/dev/null
    else
        # shellcheck disable=SC2086
        "$bin" run -d $opts "$IMAGE" >/dev/null
    fi
    if [[ $AUTOSTART -eq 1 ]]; then
        ytdlp_timer "$bin exec $NAME yt-dlp -U"
        systemctl daemon-reload
        systemctl enable --now "$NAME-ytdlp-update.timer" >/dev/null 2>&1
    fi
    wait_ready
    summary "$engine logs -f $NAME"
}

# ---------------------------------------------------------------- 2) systemd service

install_tools() { # yt-dlp (standalone build) and Deno in /usr/local/bin
    local arch ytdlp deno
    case "$(uname -m)" in
    x86_64) ytdlp=yt-dlp_linux deno=deno-x86_64-unknown-linux-gnu.zip ;;
    aarch64 | arm64) ytdlp=yt-dlp_linux_aarch64 deno=deno-aarch64-unknown-linux-gnu.zip ;;
    *) die "chưa hỗ trợ CPU $(uname -m)" ;;
    esac
    if [[ ! -x /usr/local/bin/yt-dlp ]]; then
        say "Tải yt-dlp"
        curl -fsSL -o /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/$ytdlp"
        chmod +x /usr/local/bin/yt-dlp
    fi
    if ! command -v deno >/dev/null 2>&1; then
        say "Tải Deno (yt-dlp cần nó)"
        curl -fsSL -o /tmp/deno.zip "https://github.com/denoland/deno/releases/latest/download/$deno"
        unzip -o -q /tmp/deno.zip -d /usr/local/bin && rm -f /tmp/deno.zip
    fi
}

install_service() {
    need_packages cc:build-essential pkg-config:pkg-config curl:curl unzip:unzip
    export HOME=/root CARGO_HOME=/root/.cargo RUSTUP_HOME=/root/.rustup
    if [[ ! -x /root/.cargo/bin/cargo ]]; then
        say "Cài Rust (rustup)"
        curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal >/dev/null
    fi
    install_tools
    # Sources into $DIR/src (the build cache in target/ stays between updates)
    mkdir -p "$DIR/src"
    if [[ "$(realpath "$SRC")" != "$(realpath "$DIR/src")" ]]; then
        find "$DIR/src" -mindepth 1 -maxdepth 1 ! -name target -exec rm -rf {} +
        tar -C "$SRC" --exclude=./target --exclude=./data --exclude=./config.toml -cf - . | tar --no-same-owner -xf - -C "$DIR/src"
    fi
    say "Build tubemini-server (lần đầu 5–10 phút)…"
    (cd "$DIR/src" && /root/.cargo/bin/cargo build --release -q) || die "build lỗi"
    id "$NAME" >/dev/null 2>&1 || useradd --system --home-dir /var/lib/$NAME --create-home --shell /usr/sbin/nologin "$NAME"
    install -m 755 "$DIR/src/target/release/tubemini-server" "$DIR/tubemini-server.new"
    mv -f "$DIR/tubemini-server.new" "$DIR/tubemini-server"
    write_config
    chown -R "$NAME:$NAME" "$DIR/data"
    # Free the port: the other way may be installed
    systemctl disable --now "$NAME-container.service" >/dev/null 2>&1 || true
    rm -f "$UNIT_DIR/$NAME-container.service"
    for engine in docker podman; do
        command -v "$engine" >/dev/null 2>&1 && "$engine" rm -f "$NAME" >/dev/null 2>&1 || true
    done
    cat >"$UNIT_DIR/$NAME.service" <<UNIT
[Unit]
Description=TubeMini server (GData + /tm/v1 for old YouTube apps and TubeMini on iOS 6)
After=network-online.target
Wants=network-online.target

[Service]
User=$NAME
WorkingDirectory=$DIR
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=$DIR/tubemini-server --config $DIR/config.toml
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT
    ytdlp_timer "/usr/local/bin/yt-dlp -U"
    systemctl daemon-reload
    systemctl enable --now "$NAME-ytdlp-update.timer" >/dev/null 2>&1
    systemctl enable "$NAME" >/dev/null 2>&1
    systemctl restart "$NAME"
    wait_ready
    summary "journalctl -u $NAME -f"
}

# ---------------------------------------------------------------- main

if [[ $STATUS -eq 1 ]]; then show_status; exit 0; fi
if [[ $EUID -ne 0 && $AUTOSTART -eq 1 ]]; then die "chạy bằng sudo: sudo $0 ${ARGS[*]:-}"; fi
if [[ $UNINSTALL -eq 1 ]]; then uninstall; exit 0; fi
[[ -n "$SRC" && -f "$SRC/Cargo.toml" ]] || die "không thấy thư mục server/ cạnh script"
choose
case "$MODE" in
docker) install_docker ;;
service) install_service ;;
esac
