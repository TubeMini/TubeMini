#!/usr/bin/env bash
# Packs what an Ubuntu machine needs to install the server into dist/tubemini-server-<version>.tar.gz:
# server/ (sources), install.sh, docker-compose.yml, HUONG-DAN.txt. On the machine:
#   tar xzf tubemini-server-<version>.tar.gz && cd tubemini-server-<version> && sudo ./install.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n -E 's/^version = "([^"]+)"/\1/p' "$ROOT/server/Cargo.toml" | head -n1)"
NAME="tubemini-server-$VERSION"
OUT="$ROOT/dist/$NAME"
rm -rf "$OUT" && mkdir -p "$OUT/server"
tar -C "$ROOT/server" --exclude=./target --exclude=./data --exclude=./config.toml -cf - . | tar -xf - -C "$OUT/server"
install -m 755 "$ROOT/scripts/install.sh" "$OUT/install.sh"
cp "$ROOT/docker-compose.yml" "$OUT/"
cat >"$OUT/HUONG-DAN.txt" <<TXT
TubeMini server $VERSION

Ubuntu / Debian (có systemd):
    sudo ./install.sh
  Script hỏi cách cài:
    1) Docker  - chạy trong container (Docker hoặc Podman), tự khởi động cùng máy
    2) Service - build từ mã nguồn, chạy như dịch vụ systemd của Ubuntu
  rồi hỏi cổng (mặc định 8080) và mã truy cập (để trống nếu chỉ dùng trong mạng nhà).
  Không hỏi gì: sudo ./install.sh --docker --yes   (hoặc --service --yes)
  Cập nhật: giải nén bản mới, chạy lại install.sh. Gỡ: sudo ./install.sh --uninstall
  Xem trạng thái: ./install.sh --status

Windows / macOS (Docker Desktop):
    docker compose up -d --build

Sau khi cài: trên iPad, TubeMini -> Cài đặt -> địa chỉ máy chủ http://<IP máy>:8080
TXT
tar -C "$ROOT/dist" -czf "$ROOT/dist/$NAME.tar.gz" "$NAME"
echo "$ROOT/dist/$NAME.tar.gz ($(du -h "$ROOT/dist/$NAME.tar.gz" | cut -f1))"
