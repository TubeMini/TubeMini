//! `/tm/v1` subscriptions, subscription feed and watch history (docs/API.md). Lists reuse the GData
//! Atom formats so the app parses them with the same parser.

use askama::Template;
use axum::body::Bytes;
use axum::extract::{Path, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use serde::Deserialize;

use super::{XML, tm_error, xml_ok};
use crate::gdata::{Ctx, Paging};
use crate::state::AppState;
use crate::store::{HistoryEntry, Subscription};
use crate::youtube::{Channel, Page, Video, VideoId, is_channel_id, parse};

fn internal(e: &anyhow::Error) -> Response {
    tracing::error!("store: {e:#}");
    tm_error(
        StatusCode::INTERNAL_SERVER_ERROR,
        "internal",
        "Máy chủ không đọc / ghi được dữ liệu (SQLite).",
    )
}

fn bad_request(message: &str) -> Response {
    tm_error(StatusCode::BAD_REQUEST, "bad_request", message)
}

fn ok() -> Response {
    (
        [(header::CONTENT_TYPE, XML)],
        "<?xml version='1.0' encoding='UTF-8'?>\n<tm:ok xmlns:tm=\"urn:tubemini:1\"/>\n",
    )
        .into_response()
}

// ---- Subscriptions

pub async fn subscriptions(State(st): State<AppState>, ctx: Ctx) -> Response {
    match st.store.subscriptions().await {
        Ok(subs) => {
            let items: Vec<Channel> = subs
                .into_iter()
                .map(|s| Channel {
                    id: s.channel_id,
                    name: s.name,
                    avatar: s.avatar,
                    subscribers: s.subscribers,
                    ..Default::default()
                })
                .collect();
            crate::gdata::channel_list(&ctx, "Kênh đã theo dõi", &items)
        }
        Err(e) => internal(&e),
    }
}

#[derive(Deserialize)]
struct SubscribeForm {
    #[serde(default)]
    channel_id: String,
}

#[derive(Template)]
#[template(path = "tm/subscription.xml")]
struct SubscriptionXml<'a> {
    channel_id: &'a str,
    name: &'a str,
    avatar: &'a str,
}

pub async fn subscribe(State(st): State<AppState>, body: Bytes) -> Response {
    let id = serde_urlencoded::from_bytes::<SubscribeForm>(&body)
        .map(|f| f.channel_id.trim().to_owned())
        .unwrap_or_default();
    if !is_channel_id(&id) {
        return bad_request("Mã kênh không hợp lệ.");
    }
    let channel = match st.meta.channel(&id).await {
        Ok(c) => c,
        Err(e) => {
            tracing::warn!("subscribe {id}: {e:#}");
            return tm_error(
                StatusCode::BAD_GATEWAY,
                "upstream",
                "Không lấy được thông tin kênh từ YouTube. Thử lại sau.",
            );
        }
    };
    let sub = Subscription {
        name: if channel.name.is_empty() {
            id.clone()
        } else {
            channel.name
        },
        channel_id: id,
        avatar: channel.avatar,
        subscribers: channel.subscribers,
        added_at: parse::now(),
    };
    if let Err(e) = st.store.subscribe(sub.clone()).await {
        return internal(&e);
    }
    crate::feed::invalidate(&st);
    xml_ok(
        SubscriptionXml {
            channel_id: &sub.channel_id,
            name: &sub.name,
            avatar: &sub.avatar,
        }
        .render(),
    )
}

pub async fn unsubscribe(State(st): State<AppState>, Path(id): Path<String>) -> Response {
    match st.store.unsubscribe(&id).await {
        Ok(_) => {
            crate::feed::invalidate(&st);
            ok()
        }
        Err(e) => internal(&e),
    }
}

// ---- Feed

pub async fn feed(State(st): State<AppState>, ctx: Ctx) -> Response {
    let fresh = ctx.param("fresh").is_some_and(|f| f == "1" || f == "true");
    match crate::feed::subscription_feed(&st, fresh).await {
        Ok(videos) => crate::gdata::feed(
            &ctx,
            "tm:feed",
            "Video mới từ kênh đã theo dõi",
            &Page {
                videos: videos.to_vec(),
                continuation: None,
            },
        ),
        Err(e) => {
            tracing::warn!("feed: {e:#}");
            tm_error(
                StatusCode::BAD_GATEWAY,
                "upstream",
                "Không tải được video mới của các kênh đã theo dõi. Thử lại sau.",
            )
        }
    }
}

// ---- History

#[derive(Template)]
#[template(path = "tm/history.xml")]
struct HistoryFeed<'a> {
    base: &'a str,
    updated: String,
    self_url: String,
    next: Option<String>,
    total: usize,
    start_index: u64,
    /// (video, position, watched ISO time)
    items: &'a [(Video, u32, String)],
}

#[derive(Template)]
#[template(path = "tm/history_item.xml")]
struct HistoryItemXml<'a> {
    video_id: &'a str,
    position: u32,
    duration: u32,
    watched: String,
}

fn watched_iso(at: i64) -> String {
    if at > 0 {
        parse::iso8601(at)
    } else {
        String::new()
    }
}

fn history_item(h: &HistoryEntry) -> Response {
    xml_ok(
        HistoryItemXml {
            video_id: &h.video_id,
            position: h.position,
            duration: h.duration,
            watched: watched_iso(h.watched_at),
        }
        .render(),
    )
}

pub async fn history(State(st): State<AppState>, ctx: Ctx) -> Response {
    let all = match st.store.history().await {
        Ok(h) => h,
        Err(e) => return internal(&e),
    };
    let items: Vec<(Video, u32, String)> = ctx
        .window(&all)
        .iter()
        .map(|h| {
            let video = Video {
                id: h.video_id.clone(),
                title: h.title.clone(),
                author: h.author.clone(),
                author_id: h.author_id.clone(),
                duration: h.duration,
                ..Default::default()
            };
            (video, h.position, watched_iso(h.watched_at))
        })
        .collect();
    let Paging {
        updated,
        self_url,
        next,
        total,
        start_index,
    } = ctx.paging(all.len(), items.len(), None, parse::now());
    crate::gdata::xml(
        HistoryFeed {
            base: &ctx.base,
            updated,
            self_url,
            next,
            total,
            start_index,
            items: &items,
        }
        .render(),
    )
}

pub async fn history_entry(State(st): State<AppState>, Path(id): Path<String>) -> Response {
    let Some(id) = VideoId::parse(&id) else {
        return bad_request("Mã video không hợp lệ.");
    };
    let id = id.to_string();
    match st.store.history_entry(&id).await {
        Ok(Some(h)) => history_item(&h),
        Ok(None) => history_item(&HistoryEntry {
            video_id: id,
            ..Default::default()
        }),
        Err(e) => internal(&e),
    }
}

#[derive(Deserialize)]
struct SaveForm {
    #[serde(default)]
    video_id: String,
    position: Option<f64>,
    duration: Option<f64>,
    #[serde(default)]
    title: String,
    #[serde(default)]
    author: String,
    #[serde(default)]
    author_id: String,
}

/// Whole seconds from a form value (`754` or `754.3`); `None` for negative or not-a-number.
fn seconds(x: f64) -> Option<u32> {
    (x.is_finite() && x >= 0.0).then(|| x.min(f64::from(u32::MAX)).round() as u32)
}

pub async fn save_position(State(st): State<AppState>, body: Bytes) -> Response {
    let Ok(form) = serde_urlencoded::from_bytes::<SaveForm>(&body) else {
        return bad_request("Dữ liệu lịch sử không hợp lệ.");
    };
    let Some(id) = VideoId::parse(form.video_id.trim()) else {
        return bad_request("Mã video không hợp lệ.");
    };
    let Some(position) = form.position.and_then(seconds) else {
        return bad_request("Thiếu hoặc sai vị trí đang xem (position).");
    };
    let mut entry = HistoryEntry {
        video_id: id.to_string(),
        title: form.title.trim().to_owned(),
        author: form.author.trim().to_owned(),
        author_id: form.author_id.trim().to_owned(),
        duration: form.duration.and_then(seconds).unwrap_or(0),
        position,
        watched_at: parse::now(),
    };
    if entry.title.is_empty() {
        // The app sent no title: ask YouTube once, when the video is new to the history
        match st.store.history_entry(&entry.video_id).await {
            Ok(Some(old)) if !old.title.is_empty() => {}
            Ok(_) => match st.meta.video(&id).await {
                Ok(v) => {
                    entry.title = v.title;
                    if entry.author.is_empty() {
                        entry.author = v.author;
                    }
                    if entry.author_id.is_empty() {
                        entry.author_id = v.author_id;
                    }
                    if entry.duration == 0 {
                        entry.duration = v.duration;
                    }
                }
                Err(e) => tracing::warn!("history {id}: {e:#}"),
            },
            Err(e) => return internal(&e),
        }
    }
    match st.store.save_position(entry).await {
        Ok(h) => history_item(&h),
        Err(e) => internal(&e),
    }
}

pub async fn forget(State(st): State<AppState>, Path(id): Path<String>) -> Response {
    match st.store.forget(Some(&id)).await {
        Ok(()) => ok(),
        Err(e) => internal(&e),
    }
}

pub async fn clear_history(State(st): State<AppState>) -> Response {
    match st.store.forget(None).await {
        Ok(()) => ok(),
        Err(e) => internal(&e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seconds_from_form_values() {
        assert_eq!(seconds(754.0), Some(754));
        assert_eq!(seconds(754.6), Some(755));
        assert_eq!(seconds(-1.0), None);
        assert_eq!(seconds(f64::NAN), None);
        assert_eq!(seconds(1e12), Some(u32::MAX));
    }
}
