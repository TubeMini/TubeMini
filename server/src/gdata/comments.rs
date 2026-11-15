//! Comments: `/feeds/api/videos/{id}/comments` and `/api/videos/{id}/comments`
//! (TubeRepair `api/video.py`, `comments`). Read-only, top-level comments, paged by `continuation`.

use askama::Template;
use axum::Router;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::get;

use super::{Ctx, Paging, upstream_error, xml};
use crate::state::AppState;
use crate::youtube::{Comment, VideoId, parse};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/feeds/api/videos/{id}/comments", get(comments))
        .route("/api/videos/{id}/comments", get(comments))
}

#[derive(Template)]
#[template(path = "gdata/comments.xml")]
struct CommentsFeed<'a> {
    base: &'a str,
    video_id: &'a str,
    title: &'a str,
    updated: String,
    self_url: String,
    next: Option<String>,
    total: usize,
    start_index: u64,
    items: &'a [Comment],
}

async fn comments(State(st): State<AppState>, ctx: Ctx, Path(id): Path<String>) -> Response {
    let Some(id) = VideoId::parse(&id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    let list = match st.meta.comments(&id, ctx.param("continuation")).await {
        Ok(l) => l,
        Err(e) => return upstream_error("comments", &e),
    };
    let items = ctx.window(&list.items);
    let Paging {
        updated,
        self_url,
        next,
        total,
        start_index,
    } = ctx.paging(
        list.items.len(),
        items.len(),
        list.continuation.as_deref(),
        parse::now(),
    );
    let video_id = id.to_string();
    xml(CommentsFeed {
        base: &ctx.base,
        video_id: &video_id,
        title: "Bình luận",
        updated,
        self_url,
        next,
        total,
        start_index,
        items,
    }
    .render())
}
