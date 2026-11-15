//! tubemini-server — GData-compatible XML server for old YouTube apps on iOS 6, plus the
//! `/tm/v1` extension API for the TubeMini app. Video bytes never pass through this server.

mod config;
mod debug;
mod ext;
mod feed;
mod gdata;
mod state;
mod store;
mod video;
mod youtube;

use std::path::PathBuf;
use std::time::Instant;

use anyhow::{Context, Result};
use axum::extract::Request;
use axum::middleware::Next;
use axum::response::Response;
use axum::{Router, ServiceExt};
use clap::Parser;
use tower::Layer;
use tower_http::compression::CompressionLayer;
use tracing_subscriber::EnvFilter;

use crate::config::Config;
use crate::state::AppState;
use crate::youtube::ytdlp::ToolStatus;

#[derive(Parser)]
#[command(version, about = "TubeMini server")]
struct Cli {
    /// Path to config.toml (default: next to the executable).
    #[arg(long)]
    config: Option<PathBuf>,
}

/// One log line per request: method, path, status, time. Query strings (search terms) are not logged.
async fn log_request(req: Request, next: Next) -> Response {
    let method = req.method().clone();
    let path = req.uri().path().to_owned();
    let res = req
        .extensions()
        .get::<gdata::ResPrefix>()
        .and_then(|r| r.0)
        .map(|r| format!("/{r}"))
        .unwrap_or_default();
    // Short User-Agent ("YouTube/1.3.0", "YouTube v1.0.0", "TubeMini/0.1") tells which app asked
    let agent: String = req
        .headers()
        .get(axum::http::header::USER_AGENT)
        .and_then(|h| h.to_str().ok())
        .unwrap_or("-")
        .split(" CFNetwork")
        .next()
        .unwrap_or("-")
        .chars()
        .take(40)
        .collect();
    let t0 = Instant::now();
    let resp = next.run(req).await;
    tracing::info!(
        "{method} {res}{path} → {} ({} ms) [{agent}]",
        resp.status().as_u16(),
        t0.elapsed().as_millis()
    );
    resp
}

#[tokio::main]
async fn main() -> Result<()> {
    // No colour codes when logging to journald / a file
    let ansi = std::io::IsTerminal::is_terminal(&std::io::stdout());
    tracing_subscriber::fmt()
        .with_ansi(ansi)
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .init();

    let cli = Cli::parse();
    let path = cli.config.unwrap_or_else(config::default_path);
    let (cfg, found) = Config::load(&path)?;
    if found {
        tracing::info!("config: {}", path.display());
    } else {
        tracing::warn!("{} not found, using defaults", path.display());
    }

    let tools = ToolStatus::check(&cfg.yt_dlp_path).await;
    tools.log();

    let listen = cfg.listen.clone();
    let state = AppState::new(cfg, tools)?;
    tracing::info!("data: {}", state.cfg.data_dir.join("tubemini.db").display());
    let router = Router::new()
        .merge(debug::routes())
        .merge(gdata::routes())
        .merge(video::routes())
        .merge(ext::routes(state.clone()))
        .layer(axum::middleware::from_fn(log_request))
        .layer(CompressionLayer::new().gzip(true))
        .with_state(state);
    // The resolution prefix must be stripped before routing, so it wraps the whole router
    let app = tower::util::MapRequestLayer::new(gdata::strip_res_prefix).layer(router);

    let listener = tokio::net::TcpListener::bind(&listen)
        .await
        .with_context(|| format!("cannot listen on {listen}"))?;
    tracing::info!(
        "tubemini-server {} listening on http://{listen}",
        env!("CARGO_PKG_VERSION")
    );
    axum::serve(listener, ServiceExt::<Request>::into_make_service(app))
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
            tracing::info!("shutting down");
        })
        .await?;
    Ok(())
}
