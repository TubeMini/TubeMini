//! `/getvideo/{id}`: hands the iPad a googlevideo link or playlist. Video bytes never pass through
//! the server.
//!
//! - no resolution prefix (and `medium_quality = true`): 307 redirect to the 360p progressive MP4
//!   (HLS when the video has no such format);
//! - with a prefix (`/720/getvideo/...`) or `medium_quality = false`: an HLS master playlist,
//!   filtered for iOS 6 ([`hls::filter_master`]); variant playlists and segments stay on googlevideo.

pub mod hls;

use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use axum::Router;
use axum::extract::{Path, Query, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use serde::Deserialize;

use crate::gdata::Ctx;
use crate::state::AppState;
use crate::youtube::VideoId;
use crate::youtube::streams::StreamInfo;

/// The A5 decodes 1080p30; 60 fps variants are skipped like TubeRepair does.
const MAX_FPS: f64 = 30.0;
/// Filtered playlists live as long as the links inside them are cached.
pub const PLAYLIST_TTL: Duration = Duration::from_secs(5 * 60);
/// Longest a request is held while YouTube's pre-roll ad window runs out.
const MAX_AD_WAIT_MS: i64 = 30_000;

/// Sleeps until `available_at` (Unix seconds) plus a small margin: before that moment
/// googlevideo answers 403 for videos with a pre-roll ad.
async fn wait_until_available(available_at: i64) {
    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    let wait_ms = (available_at * 1000 + 300 - now_ms).min(MAX_AD_WAIT_MS);
    if available_at > 0 && wait_ms > 0 {
        tracing::debug!("waiting {wait_ms} ms for the ad window");
        tokio::time::sleep(Duration::from_millis(wait_ms as u64)).await;
    }
}

/// Starts resolving a video's streams in the background (the old app opens the video page —
/// related, comments — a moment before it asks `/getvideo`). Shares the run with `/getvideo`.
pub fn prefetch(st: &AppState, id: &VideoId) {
    let (st, id) = (st.clone(), id.clone());
    tokio::spawn(async move {
        if let Err(e) = st.streams.resolve(&id, false).await {
            tracing::debug!("prefetch {id}: {e:#}");
        }
    });
}

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/getvideo/{id}", get(getvideo))
        // `<content src>` of the classic app's feed (TubeRepair's classic templates point here)
        .route("/video/sd/{id}", get(getvideo))
}

#[derive(Deserialize)]
struct GetVideoQuery {
    fresh: Option<String>,
}

fn redirect(url: &str) -> Response {
    (
        StatusCode::TEMPORARY_REDIRECT,
        [(header::LOCATION, url), (header::CACHE_CONTROL, "no-store")],
    )
        .into_response()
}

fn no_stream() -> Response {
    (StatusCode::BAD_GATEWAY, "no playable stream").into_response()
}

async fn getvideo(
    State(st): State<AppState>,
    ctx: Ctx,
    Path(id): Path<String>,
    Query(q): Query<GetVideoQuery>,
) -> Response {
    let Some(id) = VideoId::parse(id.trim_end_matches(".mp4")) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let fresh = q.fresh.as_deref().is_some_and(|f| f == "1" || f == "true");
    let streams = match st.streams.resolve(&id, fresh).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("getvideo {id}: {e:#}");
            return no_stream();
        }
    };

    let want_hls = ctx.res.is_some() || !st.cfg.medium_quality;
    if !want_hls
        && !streams.progressive_dubbed
        && let Some(url) = &streams.progressive
    {
        wait_until_available(streams.progressive_at).await;
        return redirect(url);
    }
    // A dubbed 360p MP4 is replaced by 360p HLS with the original audio track
    let res = match ctx.res {
        Some(r) => r,
        None if want_hls => st.cfg.hls_resolution,
        None => 360,
    }
    .clamp(144, 2160);
    match hls_playlist(&st, &id, &streams, res, fresh).await {
        Ok(playlist) => {
            wait_until_available(streams.hls_at).await;
            (
                [
                    (header::CONTENT_TYPE, "application/vnd.apple.mpegurl"),
                    (header::CACHE_CONTROL, "no-store"),
                ],
                playlist.as_str().to_owned(),
            )
                .into_response()
        }
        Err(e) => {
            tracing::warn!("getvideo {id} HLS: {e:#}");
            // No usable HLS: the progressive MP4 is still better than nothing
            match streams.progressive.as_deref() {
                Some(url) => {
                    wait_until_available(streams.progressive_at).await;
                    redirect(url)
                }
                None => no_stream(),
            }
        }
    }
}

/// Downloads YouTube's master playlist (a few KB) and filters it; cached per (video, res).
pub(crate) async fn hls_playlist(
    st: &AppState,
    id: &VideoId,
    streams: &StreamInfo,
    res: u32,
    fresh: bool,
) -> Result<Arc<String>> {
    let mut all = hls_playlists(st, id, streams, &[res], fresh).await?;
    Ok(all.remove(0))
}

/// [`hls_playlist`] for several resolutions, fetching YouTube's master playlist at most once.
pub(crate) async fn hls_playlists(
    st: &AppState,
    id: &VideoId,
    streams: &StreamInfo,
    levels: &[u32],
    fresh: bool,
) -> Result<Vec<Arc<String>>> {
    let mut out = Vec::with_capacity(levels.len());
    let mut master: Option<String> = None;
    for &res in levels {
        let key = (id.clone(), res);
        if !fresh && let Some(hit) = st.playlists.get(&key).await {
            out.push(hit);
            continue;
        }
        if master.is_none() {
            let Some(url) = &streams.hls_manifest else {
                bail!("no HLS manifest");
            };
            let text = st
                .http
                .get(url)
                .send()
                .await
                .context("fetching HLS master")?
                .error_for_status()?
                .text()
                .await?;
            master = Some(text);
        }
        let filtered = hls::filter_master(master.as_deref().unwrap_or_default(), res, MAX_FPS)
            .map(Arc::new)
            .context("no H.264/AAC variant in HLS master")?;
        st.playlists.insert(key, filtered.clone()).await;
        out.push(filtered);
    }
    Ok(out)
}
