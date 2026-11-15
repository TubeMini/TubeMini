# tubemini-server in a container (docs/SETUP.md section 7). x86_64 and ARM64 (Raspberry Pi, Apple Silicon).
#   Ubuntu:          sudo scripts/install.sh --docker       (builds this image, autostart, daily yt-dlp update)
#   Windows / macOS: docker compose up -d --build           (docker-compose.yml at the repository root)
#   By hand:         docker build -t tubemini server/
#                    docker run -d --name tubemini -p 8080:8080 -v tubemini-data:/data --restart unless-stopped tubemini
# Settings: /data/config.toml (created from config.example.toml on first start). On a VPS set auth_token.

FROM rust:1-slim-bookworm AS build
# The label lets install.sh remove old build stages (about 1.6 GB each) after an update
LABEL org.tubemini.image=build
WORKDIR /src
COPY . .
RUN cargo build --release --locked

FROM debian:bookworm-slim
LABEL org.tubemini.image=server
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
# yt-dlp (standalone build, no Python needed) and Deno (yt-dlp needs it for YouTube's JavaScript), for this CPU
RUN set -e; \
    case "$(uname -m)" in \
    x86_64) ytdlp=yt-dlp_linux; deno=deno-x86_64-unknown-linux-gnu.zip ;; \
    aarch64) ytdlp=yt-dlp_linux_aarch64; deno=deno-aarch64-unknown-linux-gnu.zip ;; \
    *) echo "unsupported CPU: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/$ytdlp"; \
    chmod +x /usr/local/bin/yt-dlp; \
    curl -fsSL -o /tmp/deno.zip "https://github.com/denoland/deno/releases/latest/download/$deno"; \
    unzip -o /tmp/deno.zip -d /usr/local/bin; \
    rm /tmp/deno.zip
COPY --from=build /src/target/release/tubemini-server /usr/local/bin/tubemini-server
COPY config.example.toml /usr/local/share/tubemini/config.example.toml
WORKDIR /data
VOLUME /data
EXPOSE 8080
# YouTube changes often: update yt-dlp at every start
CMD ["sh", "-c", "yt-dlp -U >/dev/null 2>&1; [ -f /data/config.toml ] || sed 's#^yt_dlp_path = .*#yt_dlp_path = \"/usr/local/bin/yt-dlp\"#' /usr/local/share/tubemini/config.example.toml > /data/config.toml; exec tubemini-server --config /data/config.toml"]
