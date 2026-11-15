//! Channels and playlists: `/feeds/api/channels…`, `/feeds/api/users/{id}[/playlists]`,
//! `/feeds/api/playlists…` (TubeRepair `api/channel.py`, `api/playlist.py`).

use askama::Template;
use axum::Router;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::get;

use super::{Ctx, Paging, feed, upstream_error, xml};
use crate::state::AppState;
use crate::youtube::{Channel, Playlist, is_channel_id, is_playlist_id, parse};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/feeds/api/channels", get(search_channels))
        .route("/feeds/api/channels/{id}", get(channel_info))
        .route("/feeds/api/users/{id}", get(channel_info))
        .route("/feeds/api/users/{id}/playlists", get(channel_playlists))
        .route("/feeds/api/playlists/snippets", get(search_playlists))
        .route("/feeds/api/playlists/{id}", get(playlist_videos))
}

#[derive(Template)]
#[template(path = "gdata/channel.xml")]
struct ChannelEntry<'a> {
    base: &'a str,
    updated: String,
    c: &'a Channel,
}

#[derive(Template)]
#[template(path = "gdata/channels.xml")]
struct ChannelsFeed<'a> {
    base: &'a str,
    title: &'a str,
    updated: String,
    self_url: String,
    next: Option<String>,
    total: usize,
    start_index: u64,
    items: &'a [Channel],
}

#[derive(Template)]
#[template(path = "gdata/playlists.xml")]
struct PlaylistsFeed<'a> {
    base: &'a str,
    title: &'a str,
    updated: String,
    self_url: String,
    next: Option<String>,
    total: usize,
    start_index: u64,
    items: &'a [Playlist],
}

/// `/feeds/api/channels/{id}` — the old app asks this for every channel in a list (avatars).
async fn channel_info(State(st): State<AppState>, ctx: Ctx, Path(id): Path<String>) -> Response {
    if !is_channel_id(&id) {
        return StatusCode::NOT_FOUND.into_response();
    }
    match st.meta.channel(&id).await {
        Ok(c) => xml(ChannelEntry {
            base: &ctx.base,
            updated: parse::iso8601(parse::now()),
            c: &c,
        }
        .render()),
        Err(e) => upstream_error("channel", &e),
    }
}

/// A complete channel list in one GData feed (no paging), e.g. the subscriptions.
pub(crate) fn channel_list(ctx: &Ctx, title: &str, items: &[Channel]) -> Response {
    xml(ChannelsFeed {
        base: &ctx.base,
        title,
        updated: parse::iso8601(parse::now()),
        self_url: ctx.self_url(),
        next: None,
        total: items.len(),
        start_index: 1,
        items,
    }
    .render())
}

fn channels_feed(
    ctx: &Ctx,
    title: &str,
    items: &[Channel],
    continuation: Option<&str>,
) -> Response {
    let page_len = items.len();
    let items = ctx.window(items);
    let Paging {
        updated,
        self_url,
        next,
        total,
        start_index,
    } = ctx.paging(page_len, items.len(), continuation, parse::now());
    xml(ChannelsFeed {
        base: &ctx.base,
        title,
        updated,
        self_url,
        next,
        total,
        start_index,
        items,
    }
    .render())
}

fn playlists_feed(
    ctx: &Ctx,
    title: &str,
    items: &[Playlist],
    continuation: Option<&str>,
) -> Response {
    let page_len = items.len();
    let items = ctx.window(items);
    let Paging {
        updated,
        self_url,
        next,
        total,
        start_index,
    } = ctx.paging(page_len, items.len(), continuation, parse::now());
    xml(PlaylistsFeed {
        base: &ctx.base,
        title,
        updated,
        self_url,
        next,
        total,
        start_index,
        items,
    }
    .render())
}

fn query(ctx: &Ctx) -> Option<&str> {
    ctx.param("q").map(str::trim).filter(|q| !q.is_empty())
}

async fn search_channels(State(st): State<AppState>, ctx: Ctx) -> Response {
    let Some(q) = query(&ctx) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    match st.meta.search_channels(q, ctx.param("continuation")).await {
        Ok(list) => channels_feed(&ctx, "Kênh", &list.items, list.continuation.as_deref()),
        Err(e) => upstream_error("channel search", &e),
    }
}

async fn channel_playlists(
    State(st): State<AppState>,
    ctx: Ctx,
    Path(id): Path<String>,
) -> Response {
    if !is_channel_id(&id) {
        return StatusCode::NOT_FOUND.into_response();
    }
    match st
        .meta
        .channel_playlists(&id, ctx.param("continuation"))
        .await
    {
        Ok(list) => playlists_feed(
            &ctx,
            "Danh sách phát",
            &list.items,
            list.continuation.as_deref(),
        ),
        Err(e) => upstream_error("channel playlists", &e),
    }
}

async fn search_playlists(State(st): State<AppState>, ctx: Ctx) -> Response {
    let Some(q) = query(&ctx) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    match st.meta.search_playlists(q, ctx.param("continuation")).await {
        Ok(list) => playlists_feed(
            &ctx,
            "Danh sách phát",
            &list.items,
            list.continuation.as_deref(),
        ),
        Err(e) => upstream_error("playlist search", &e),
    }
}

async fn playlist_videos(State(st): State<AppState>, ctx: Ctx, Path(id): Path<String>) -> Response {
    // YouTube 2.0.0 asks max-results=0 and "(null)" when queueing (same handling as TubeRepair)
    if ctx.param("max-results") == Some("0") || !is_playlist_id(&id) {
        return StatusCode::NOT_FOUND.into_response();
    }
    match st.meta.playlist(&id, ctx.param("continuation")).await {
        Ok(page) => feed(&ctx, &format!("playlist:{id}"), "Danh sách phát", &page),
        Err(e) => upstream_error("playlist", &e),
    }
}
