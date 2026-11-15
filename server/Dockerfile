# tubemini-server in a container, for a VPS (docs/SETUP.md section 9).
#   docker build -t tubemini server/
#   docker run -d --name tubemini -p 8080:8080 -v tubemini-data:/data --restart unless-stopped tubemini
# Settings: /data/config.toml (copy of config.example.toml). On a VPS set auth_token.
# mDNS does not cross Docker's bridge network; it is meant for the home network anyway.

FROM rust:1-slim-bookworm AS build
WORKDIR /src
COPY . .
RUN cargo build --release --locked

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip \
    && rm -rf /var/lib/apt/lists/*
# yt-dlp (standalone build, no Python needed) and Deno (yt-dlp needs it for YouTube's JavaScript)
RUN curl -fsSL -o /usr/local/bin/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux \
    && chmod +x /usr/local/bin/yt-dlp \
    && curl -fsSL -o /tmp/deno.zip https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip \
    && unzip -o /tmp/deno.zip -d /usr/local/bin \
    && rm /tmp/deno.zip
COPY --from=build /src/target/release/tubemini-server /usr/local/bin/tubemini-server
COPY config.example.toml /usr/local/share/tubemini/config.example.toml
WORKDIR /data
VOLUME /data
EXPOSE 8080
# YouTube changes often: update yt-dlp at every start
CMD ["sh", "-c", "yt-dlp -U >/dev/null 2>&1; [ -f /data/config.toml ] || sed 's#^yt_dlp_path = .*#yt_dlp_path = \"/usr/local/bin/yt-dlp\"#' /usr/local/share/tubemini/config.example.toml > /data/config.toml; exec tubemini-server --config /data/config.toml"]
