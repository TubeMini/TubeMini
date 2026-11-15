//! GData v2 compatibility layer for the old YouTube app + TubeRepair tweak.
//!
//! Routes and behaviour follow the TubeRepair server (`api/*.py`); the XML shape follows its
//! templates. Every route also exists under a resolution prefix (`/720/feeds/...`), which is
//! stripped by [`strip_res_prefix`] and kept in generated links via [`Ctx::base`].

use askama::Template;
use axum::Router;
use axum::extract::{FromRequestParts, Path, State};
use axum::http::request::Parts;
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};

use crate::state::AppState;
use crate::youtube::{Category, Page, SearchFilter, Video, VideoId, is_channel_id, parse};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/schemas/2007/categories.cat", get(categories))
        .route("/youtube/accounts/applelogin1", post(applelogin1))
        .route("/youtube/accounts/applelogin2", post(applelogin2))
        .route("/youtube/accounts/registerDevice", post(register_device))
        .route("/feeds/api/standardfeeds/{feed}", get(standard_feed))
        .route(
            "/feeds/api/standardfeeds/{region}/{feed}",
            get(standard_feed_region),
        )
        .route("/feeds/api/videos", get(search))
        .route("/feeds/api/videos/", get(search))
        .route("/feeds/api/videos/{id}/related", get(related))
        .route("/feeds/api/users/{id}/uploads", get(uploads))
}

/// Resolution prefix found in the request path (`/720/...` → `Some(720)`).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct ResPrefix(pub Option<u32>);

/// Wraps the whole router: turns `/720/feeds/api/videos` into `/feeds/api/videos` + [`ResPrefix`].
pub fn strip_res_prefix(mut req: axum::extract::Request) -> axum::extract::Request {
    let (res, rest) = split_res_prefix(req.uri().path());
    if res.is_some() {
        let mut path_and_query = rest.to_owned();
        if let Some(q) = req.uri().query() {
            path_and_query.push('?');
            path_and_query.push_str(q);
        }
        if let Ok(pq) = path_and_query.parse() {
            let mut parts = req.uri().clone().into_parts();
            parts.path_and_query = Some(pq);
            if let Ok(uri) = axum::http::Uri::from_parts(parts) {
                *req.uri_mut() = uri;
            }
        }
    }
    req.extensions_mut().insert(ResPrefix(res));
    req
}

/// `/720/feeds/x` → (Some(720), "/feeds/x"); `/720` → (Some(720), "/"); other paths unchanged.
pub fn split_res_prefix(path: &str) -> (Option<u32>, &str) {
    let Some(rest) = path.strip_prefix('/') else {
        return (None, path);
    };
    let (first, tail_start) = match rest.find('/') {
        Some(i) => (&rest[..i], i + 1),
        None => (rest, rest.len() + 1),
    };
    if first.is_empty() || first.len() > 5 || !first.bytes().all(|b| b.is_ascii_digit()) {
        return (None, path);
    }
    let res = first.parse().ok();
    let tail = &path[tail_start.min(path.len())..];
    (res, if tail.is_empty() { "/" } else { tail })
}

/// Per-request context: the base URL every generated link must start with, plus the query.
pub struct Ctx {
    /// `http://<host>` or `http://<host>/<res>` — exactly what the user typed as Custom URL.
    pub base: String,
    pub res: Option<u32>,
    pub path: String,
    pub query: Vec<(String, String)>,
}

impl Ctx {
    pub fn param(&self, name: &str) -> Option<&str> {
        self.query
            .iter()
            .find(|(k, _)| k == name)
            .map(|(_, v)| v.as_str())
    }

    fn start_index(&self) -> u64 {
        self.param("start-index")
            .and_then(|s| s.parse().ok())
            .filter(|&n| n >= 1)
            .unwrap_or(1)
    }

    fn max_results(&self) -> usize {
        self.param("max-results")
            .and_then(|s| s.parse().ok())
            .map_or(25, |n: usize| n.clamp(1, 50))
    }

    fn self_url(&self) -> String {
        let mut url = format!("{}{}", self.base, self.path);
        if !self.query.is_empty() {
            url.push('?');
            url.push_str(&serde_urlencoded::to_string(&self.query).unwrap_or_default());
        }
        url
    }

    /// Same URL with `continuation` and `start-index` advanced to the next page.
    fn next_url(&self, token: &str, shown: usize) -> String {
        let mut query: Vec<(String, String)> = self
            .query
            .iter()
            .filter(|(k, _)| k != "continuation" && k != "start-index")
            .cloned()
            .collect();
        query.push((
            "start-index".into(),
            (self.start_index() + shown as u64).to_string(),
        ));
        query.push(("continuation".into(), token.to_owned()));
        format!(
            "{}{}?{}",
            self.base,
            self.path,
            serde_urlencoded::to_string(&query).unwrap_or_default()
        )
    }
}

impl<S: Send + Sync> FromRequestParts<S> for Ctx {
    type Rejection = std::convert::Infallible;

    async fn from_request_parts(parts: &mut Parts, _: &S) -> Result<Self, Self::Rejection> {
        let res = parts
            .extensions
            .get::<ResPrefix>()
            .copied()
            .unwrap_or_default()
            .0;
        Ok(Self {
            base: base_url(&parts.headers, res),
            res,
            path: parts.uri.path().to_owned(),
            query: parts
                .uri
                .query()
                .and_then(|q| serde_urlencoded::from_str(q).ok())
                .unwrap_or_default(),
        })
    }
}

pub fn base_url(headers: &HeaderMap, res: Option<u32>) -> String {
    let host = headers
        .get(header::HOST)
        .and_then(|h| h.to_str().ok())
        .filter(|h| !h.is_empty() && !h.contains(['/', ' ', '\'', '"', '<', '>']))
        .unwrap_or("localhost:8080");
    match res {
        Some(r) => format!("http://{host}/{r}"),
        None => format!("http://{host}"),
    }
}

#[derive(Template)]
#[template(path = "gdata/videos.xml")]
struct VideosFeed<'a> {
    base: &'a str,
    feed_id: &'a str,
    title: &'a str,
    updated: String,
    self_url: String,
    next: Option<String>,
    total: usize,
    start_index: u64,
    videos: &'a [Video],
}

const ATOM: &str = "application/atom+xml; charset=UTF-8";

/// Renders a page of videos as GData XML (with `<link rel='next'>` when there is more).
fn render_feed(
    ctx: &Ctx,
    feed_id: &str,
    title: &str,
    page: &Page,
    paged: bool,
    now: i64,
) -> askama::Result<String> {
    let videos = &page.videos[..page.videos.len().min(ctx.max_results())];
    let next = page
        .continuation
        .as_deref()
        .filter(|_| paged && !videos.is_empty())
        .map(|t| ctx.next_url(t, videos.len()));
    let start = ctx.start_index();
    let total = start as usize - 1 + videos.len() + if next.is_some() { 1000 } else { 0 };
    VideosFeed {
        base: &ctx.base,
        feed_id,
        title,
        updated: parse::iso8601(now),
        self_url: ctx.self_url(),
        next,
        total,
        start_index: start,
        videos,
    }
    .render()
}

fn feed(ctx: &Ctx, feed_id: &str, title: &str, page: &Page, paged: bool) -> Response {
    match render_feed(ctx, feed_id, title, page, paged, parse::now()) {
        Ok(xml) => ([(header::CONTENT_TYPE, ATOM)], xml).into_response(),
        Err(e) => {
            tracing::error!("template: {e}");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

fn upstream_error(what: &str, e: &anyhow::Error) -> Response {
    tracing::warn!("{what}: {e:#}");
    (StatusCode::BAD_GATEWAY, "upstream error").into_response()
}

async fn categories() -> Response {
    (
        [(
            header::CONTENT_TYPE,
            "application/atomcat+xml; charset=UTF-8",
        )],
        include_str!("../../static/categories.cat"),
    )
        .into_response()
}

// Fake login answers so the app skips sign-in (same strings as TubeRepair).
async fn applelogin1(State(st): State<AppState>) -> String {
    format!("r2={k}\nhmackr2={k}", k = st.device_key)
}

async fn applelogin2(State(st): State<AppState>) -> String {
    format!("Auth={}", st.device_key)
}

async fn register_device(State(st): State<AppState>) -> String {
    format!("DeviceId={k}\nDeviceKey={k}", k = st.device_key)
}

async fn standard_feed(st: State<AppState>, ctx: Ctx, Path(feed): Path<String>) -> Response {
    home(st, ctx, &feed).await
}

async fn standard_feed_region(
    st: State<AppState>,
    ctx: Ctx,
    Path((_region, feed)): Path<(String, String)>,
) -> Response {
    home(st, ctx, &feed).await
}

/// Home / standard feeds. `home_feed = "subscriptions"` is handled in Phase 4.
async fn home(State(st): State<AppState>, ctx: Ctx, feed: &str) -> Response {
    let category = Category::from_feed(feed);
    match st.meta.popular(category).await {
        Ok(page) => feed_response(&ctx, &format!("standardfeed:{feed}"), "Phổ biến", &page),
        Err(e) => upstream_error("popular", &e),
    }
}

fn feed_response(ctx: &Ctx, id: &str, title: &str, page: &Page) -> Response {
    feed(ctx, id, title, page, false)
}

async fn search(State(st): State<AppState>, ctx: Ctx) -> Response {
    let Some(q) = ctx.param("q").map(str::trim).filter(|q| !q.is_empty()) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if st.cfg.log_queries {
        tracing::info!("search: {q}");
    }
    let filter = SearchFilter::from_gdata(
        ctx.param("orderby"),
        ctx.param("time"),
        ctx.param("duration"),
        ctx.param("caption"),
    );
    match st.meta.search(q, filter, ctx.param("continuation")).await {
        Ok(page) => feed(&ctx, "videos", "Kết quả tìm kiếm", &page, true),
        Err(e) => upstream_error("search", &e),
    }
}

async fn related(State(st): State<AppState>, ctx: Ctx, Path(id): Path<String>) -> Response {
    let Some(id) = VideoId::parse(&id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    match st.meta.related(&id, ctx.param("continuation")).await {
        Ok(page) => feed(
            &ctx,
            &format!("related:{id}"),
            "Video liên quan",
            &page,
            true,
        ),
        Err(e) => upstream_error("related", &e),
    }
}

async fn uploads(State(st): State<AppState>, ctx: Ctx, Path(id): Path<String>) -> Response {
    if !is_channel_id(&id) {
        return StatusCode::NOT_FOUND.into_response();
    }
    match st
        .meta
        .channel_uploads(&id, ctx.param("continuation"))
        .await
    {
        Ok(page) => feed(&ctx, &format!("uploads:{id}"), "Video tải lên", &page, true),
        Err(e) => upstream_error("uploads", &e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_resolution_prefix() {
        assert_eq!(
            split_res_prefix("/720/feeds/api/videos"),
            (Some(720), "/feeds/api/videos")
        );
        assert_eq!(split_res_prefix("/720"), (Some(720), "/"));
        assert_eq!(split_res_prefix("/720/"), (Some(720), "/"));
        assert_eq!(
            split_res_prefix("/feeds/api/videos"),
            (None, "/feeds/api/videos")
        );
        assert_eq!(split_res_prefix("/getvideo/abc"), (None, "/getvideo/abc"));
        assert_eq!(split_res_prefix("/"), (None, "/"));
        assert_eq!(split_res_prefix("/1234567/x"), (None, "/1234567/x"));
    }

    fn ctx(query: &str, res: Option<u32>) -> Ctx {
        Ctx {
            base: base_url(&HeaderMap::new(), res),
            res,
            path: "/feeds/api/videos".into(),
            query: serde_urlencoded::from_str(query).unwrap(),
        }
    }

    #[test]
    fn next_url_keeps_prefix_and_advances() {
        let c = ctx(
            "q=nhạc trẻ&start-index=1&max-results=20&continuation=old",
            Some(720),
        );
        let next = c.next_url("TOKEN=a+b/c", 20);
        assert_eq!(
            next,
            "http://localhost:8080/720/feeds/api/videos?q=nh%E1%BA%A1c+tr%E1%BA%BB&max-results=20&start-index=21&continuation=TOKEN%3Da%2Bb%2Fc"
        );
    }

    /// Search fixture (real InnerTube response, trimmed) → GData XML, with a hostile title.
    #[test]
    fn search_feed_snapshot() {
        let json: serde_json::Value =
            serde_json::from_str(include_str!("../../tests/fixtures/search_vi.json")).unwrap();
        let mut page = parse::page_in(&json, 1_794_700_000);
        page.videos[0].title = "Tom & Jerry <3 \"Tiếng Việt\" 'quote' 🎵".into();
        let mut c = ctx("q=nhac tre&max-results=20", Some(720));
        c.base = "http://192.168.1.10:8080/720".into();
        let xml =
            render_feed(&c, "videos", "Kết quả tìm kiếm", &page, true, 1_794_700_000).unwrap();

        // Well-formed (every start tag closed, every entity valid) and correctly escaped
        let mut reader = quick_xml::Reader::from_str(&xml);
        reader.config_mut().check_end_names = true;
        let mut entries = 0;
        loop {
            match reader.read_event().expect("well-formed XML") {
                quick_xml::events::Event::Start(e) if e.local_name().as_ref() == "entry" => {
                    entries += 1;
                }
                quick_xml::events::Event::Eof => break,
                _ => {}
            }
        }
        assert_eq!(entries, 3);
        // askama escapes with numeric references; valid XML that NSXMLParser (libxml2) decodes
        assert!(xml.contains(
            "<title>Tom &#38; Jerry &#60;3 &#34;Tiếng Việt&#34; &#39;quote&#39; 🎵</title>"
        ));
        assert!(xml.contains("http://192.168.1.10:8080/720/getvideo/"));
        assert!(xml.contains("rel='next'"));
        insta::assert_snapshot!(xml);
    }

    #[test]
    fn base_url_rejects_bad_host() {
        let mut h = HeaderMap::new();
        h.insert(header::HOST, "192.168.1.10:8080".parse().unwrap());
        assert_eq!(base_url(&h, None), "http://192.168.1.10:8080");
        h.insert(header::HOST, "evil'><x".parse().unwrap());
        assert_eq!(base_url(&h, Some(360)), "http://localhost:8080/360");
    }
}
