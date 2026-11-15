//! `/getvideo/{id}`: hands the iPad a googlevideo link. Video bytes never pass through the server.
//!
//! - no resolution prefix (and `medium_quality = true`): 307 redirect to the 360p progressive MP4;
//! - with a prefix (`/720/getvideo/...`) or when there is no progressive MP4: the HLS manifest.
//!   Phase 1 redirects to YouTube's manifest as-is (iOS 6 skips the VP9 variants itself);
//!   Phase 2 replaces this with a filtered playlist (avc1 + AAC, ≤ res, ≤ 30 fps).

use axum::Router;
use axum::extract::{Path, Query, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use serde::Deserialize;

use crate::gdata::Ctx;
use crate::state::AppState;
use crate::youtube::VideoId;

pub fn routes() -> Router<AppState> {
    Router::new().route("/getvideo/{id}", get(getvideo))
}

#[derive(Deserialize)]
struct GetVideoQuery {
    fresh: Option<String>,
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
            return (StatusCode::BAD_GATEWAY, "no playable stream").into_response();
        }
    };
    let want_progressive = ctx.res.is_none() && st.cfg.medium_quality;
    let target = if want_progressive {
        streams
            .progressive
            .as_ref()
            .or(streams.hls_manifest.as_ref())
    } else {
        streams
            .hls_manifest
            .as_ref()
            .or(streams.progressive.as_ref())
    };
    match target {
        Some(url) => (
            StatusCode::TEMPORARY_REDIRECT,
            [
                (header::LOCATION, url.as_str()),
                (header::CACHE_CONTROL, "no-store"),
            ],
        )
            .into_response(),
        None => (StatusCode::BAD_GATEWAY, "no playable stream").into_response(),
    }
}
