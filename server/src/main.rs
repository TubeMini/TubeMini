//! tubemini-server — GData-compatible XML server for old YouTube apps on iOS 6, plus the
//! `/tm/v1` extension API for the TubeMini app. Video bytes never pass through this server.

mod config;
mod debug;
mod state;
mod youtube;

use std::path::PathBuf;

use anyhow::{Context, Result};
use axum::Router;
use clap::Parser;
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

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
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
    let app = Router::new()
        .merge(debug::routes())
        .with_state(AppState::new(cfg, tools));

    let listener = tokio::net::TcpListener::bind(&listen)
        .await
        .with_context(|| format!("cannot listen on {listen}"))?;
    tracing::info!(
        "tubemini-server {} listening on http://{listen}",
        env!("CARGO_PKG_VERSION")
    );
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
            tracing::info!("shutting down");
        })
        .await?;
    Ok(())
}
