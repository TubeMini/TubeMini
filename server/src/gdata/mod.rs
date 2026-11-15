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

mod channels;
mod comments;

pub(crate) use channels::channel_list;

use crate::config::HomeFeed;
use crate::state::AppState;
use crate::youtube::{Category, Page, SearchFilter, Video, VideoId, is_channel_id, parse};

pub fn routes() -> Router<AppState> {
    Router::new()
        .merge(channels::routes())
        .merge(comments::routes())
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
        .route("/feeds/api/videos/{id}", get(single_video))
        .route("/feeds/player/videos/{id}", get(single_video))
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
    /// Apple's built-in "classic" YouTube app (iOS ≤ 5), which gets its own feed format.
    pub classic: bool,
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

    pub(crate) fn self_url(&self) -> String {
        let mut url = format!("{}{}", self.base, self.path);
        if !self.query.is_empty() {
            url.push('?');
            url.push_str(&serde_urlencoded::to_string(&self.query).unwrap_or_default());
        }
        url
    }

    /// Items of the current YouTube page already shown by earlier GData pages.
    fn skip(&self) -> usize {
        self.param("skip").and_then(|s| s.parse().ok()).unwrap_or(0)
    }

    /// The slice of a YouTube page this GData request shows (`skip` .. `skip + max-results`).
    pub(crate) fn window<'a, T>(&self, items: &'a [T]) -> &'a [T] {
        let start = self.skip().min(items.len());
        let end = (start + self.max_results()).min(items.len());
        &items[start..end]
    }

    /// The next GData page: same YouTube page further on (`skip`), or the next YouTube page
    /// (`continuation`). `start-index` only advances for display.
    fn next_url(&self, continuation: Option<&str>, skip: usize, shown: usize) -> String {
        let mut query: Vec<(String, String)> = self
            .query
            .iter()
            // `fresh` (reload everything) only applies to the first page
            .filter(|(k, _)| {
                !matches!(
                    k.as_str(),
                    "continuation" | "start-index" | "skip" | "fresh"
                )
            })
            .cloned()
            .collect();
        query.push((
            "start-index".into(),
            (self.start_index() + shown as u64).to_string(),
        ));
        if let Some(token) = continuation.or_else(|| self.param("continuation")) {
            query.push(("continuation".into(), token.to_owned()));
        }
        if skip > 0 {
            query.push(("skip".into(), skip.to_string()));
        }
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
            classic: is_classic_app(&parts.headers),
            path: parts.uri.path().to_owned(),
            query: parts
                .uri
                .query()
                .and_then(|q| serde_urlencoded::from_str(q).ok())
                .unwrap_or_default(),
        })
    }
}

/// Same check as TubeRepair: the classic app sends `YouTube v1.0.0` (or `youtube/1.0.0`).
pub fn is_classic_app(headers: &HeaderMap) -> bool {
    headers
        .get(header::USER_AGENT)
        .and_then(|h| h.to_str().ok())
        .map(str::to_lowercase)
        .is_some_and(|ua| ua.contains("youtube/1.0.0") || ua.contains("youtube v1.0.0"))
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

#[derive(Template)]
#[template(path = "gdata/classic_videos.xml")]
struct ClassicFeed<'a> {
    base: &'a str,
    title: &'a str,
    self_url: String,
    total: usize,
    start_index: u64,
    videos: &'a [Video],
}

#[derive(Template)]
#[template(path = "gdata/entry.xml")]
struct SingleEntry<'a> {
    base: &'a str,
    v: &'a Video,
}

const ATOM: &str = "application/atom+xml; charset=UTF-8";

/// Feed header values shared by every list template.
pub(crate) struct Paging {
    pub updated: String,
    pub self_url: String,
    pub next: Option<String>,
    pub total: usize,
    pub start_index: u64,
}

impl Ctx {
    /// Header values for a GData page showing `shown` items of a YouTube page of `page_len` items.
    pub(crate) fn paging(
        &self,
        page_len: usize,
        shown: usize,
        continuation: Option<&str>,
        now: i64,
    ) -> Paging {
        let end = self.skip().min(page_len) + shown;
        let next = if shown == 0 {
            None
        } else if end < page_len {
            Some(self.next_url(None, end, shown))
        } else {
            continuation.map(|t| self.next_url(Some(t), 0, shown))
        };
        let start_index = self.start_index();
        Paging {
            updated: parse::iso8601(now),
            self_url: self.self_url(),
            total: start_index as usize - 1 + shown + if next.is_some() { 1000 } else { 0 },
            next,
            start_index,
        }
    }
}

/// A rendered template as an Atom response (500 if rendering failed).
pub(crate) fn xml(rendered: askama::Result<String>) -> Response {
    match rendered {
        Ok(xml) => ([(header::CONTENT_TYPE, ATOM)], xml).into_response(),
        Err(e) => {
            tracing::error!("template: {e}");
            StatusCode::INTERNAL_SERVER_ERROR.into_response()
        }
    }
}

/// Renders a page of videos as GData XML (with `<link rel='next'>` when there is more).
fn render_feed(
    ctx: &Ctx,
    feed_id: &str,
    title: &str,
    page: &Page,
    now: i64,
) -> askama::Result<String> {
    let videos = ctx.window(&page.videos);
    let Paging {
        updated,
        self_url,
        next,
        total,
        start_index,
    } = ctx.paging(
        page.videos.len(),
        videos.len(),
        page.continuation.as_deref(),
        now,
    );
    VideosFeed {
        base: &ctx.base,
        feed_id,
        title,
        updated,
        self_url,
        next,
        total,
        start_index,
        videos,
    }
    .render()
}

/// Home, search and related: the classic app gets its own format (like TubeRepair), at most
/// `classic_max` items and no `rel='next'`.
fn feed_for_app(
    ctx: &Ctx,
    feed_id: &str,
    title: &str,
    page: &Page,
    classic_max: usize,
) -> Response {
    if !ctx.classic {
        return feed(ctx, feed_id, title, page);
    }
    let videos = &page.videos[..page.videos.len().min(classic_max)];
    xml(ClassicFeed {
        base: &ctx.base,
        title,
        self_url: ctx.self_url(),
        total: videos.len(),
        start_index: 1,
        videos,
    }
    .render())
}

pub(crate) fn feed(ctx: &Ctx, feed_id: &str, title: &str, page: &Page) -> Response {
    xml(render_feed(ctx, feed_id, title, page, parse::now()))
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

/// Home / standard feeds. With `home_feed = "subscriptions"` the feeds without a category show the
/// subscription feed (popular again while nothing is subscribed or the feed fails).
async fn home(State(st): State<AppState>, ctx: Ctx, name: &str) -> Response {
    let category = Category::from_feed(name);
    if st.cfg.home_feed == HomeFeed::Subscriptions && category == Category::All {
        match crate::feed::subscription_feed(&st, false).await {
            Ok(videos) if !videos.is_empty() => {
                let page = Page {
                    videos: videos.to_vec(),
                    continuation: None,
                };
                return feed_for_app(
                    &ctx,
                    "standardfeed:subscriptions",
                    "Kênh đã theo dõi",
                    &page,
                    15,
                );
            }
            Ok(_) => {}
            Err(e) => tracing::warn!("home: subscription feed: {e:#}"),
        }
    }
    match st.meta.popular(category).await {
        Ok(page) => feed_for_app(&ctx, &format!("standardfeed:{name}"), "Phổ biến", &page, 15),
        Err(e) => upstream_error("popular", &e),
    }
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
        Ok(page) => feed_for_app(&ctx, "videos", "Kết quả tìm kiếm", &page, 25),
        Err(e) => upstream_error("search", &e),
    }
}

/// One video entry. YouTube 1.3.0 asks `/feeds/player/videos/{id}` when a video is opened by id.
async fn single_video(State(st): State<AppState>, ctx: Ctx, Path(id): Path<String>) -> Response {
    let Some(id) = VideoId::parse(&id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    crate::video::prefetch(&st, &id);
    let video = match st.meta.video(&id).await {
        Ok(v) => v,
        Err(e) => return upstream_error("video", &e),
    };
    xml(SingleEntry {
        base: &ctx.base,
        v: &video,
    }
    .render())
}

async fn related(State(st): State<AppState>, ctx: Ctx, Path(id): Path<String>) -> Response {
    let Some(id) = VideoId::parse(&id) else {
        return StatusCode::NOT_FOUND.into_response();
    };
    if ctx.param("continuation").is_none() {
        crate::video::prefetch(&st, &id);
    }
    match st.meta.related(&id, ctx.param("continuation")).await {
        Ok(page) => feed_for_app(&ctx, &format!("related:{id}"), "Video liên quan", &page, 25),
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
        Ok(page) => feed(&ctx, &format!("uploads:{id}"), "Video tải lên", &page),
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
            classic: false,
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
        let next = c.next_url(Some("TOKEN=a+b/c"), 0, 20);
        assert_eq!(
            next,
            "http://localhost:8080/720/feeds/api/videos?q=nh%E1%BA%A1c+tr%E1%BA%BB&max-results=20&start-index=21&continuation=TOKEN%3Da%2Bb%2Fc"
        );
    }

    /// A YouTube page larger than max-results is shown in several GData pages before moving on.
    #[test]
    fn paging_walks_a_long_page_then_continues() {
        let items: Vec<u32> = (0..30).collect();
        // First GData page: items 0..25, next stays on the same YouTube page with skip=25
        let c = ctx("q=x", None);
        assert_eq!(c.window(&items).len(), 25);
        let p = c.paging(30, 25, Some("NEXT"), 0);
        assert_eq!(
            p.next.as_deref(),
            Some("http://localhost:8080/feeds/api/videos?q=x&start-index=26&skip=25")
        );
        // Second GData page: items 25..30, then the YouTube continuation
        let c2 = ctx("q=x&start-index=26&skip=25", None);
        assert_eq!(c2.window(&items), &[25, 26, 27, 28, 29]);
        let p2 = c2.paging(30, 5, Some("NEXT"), 0);
        assert_eq!(
            p2.next.as_deref(),
            Some("http://localhost:8080/feeds/api/videos?q=x&start-index=31&continuation=NEXT")
        );
        // Same YouTube page reached through a continuation keeps that continuation while skipping
        let c3 = ctx("q=x&continuation=TOK", None);
        assert_eq!(
            c3.paging(30, 25, None, 0).next.as_deref(),
            Some(
                "http://localhost:8080/feeds/api/videos?q=x&start-index=26&continuation=TOK&skip=25"
            )
        );
        // Last page without a continuation: no next link
        assert!(c2.paging(30, 5, None, 0).next.is_none());
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
        let xml = render_feed(&c, "videos", "Kết quả tìm kiếm", &page, 1_794_700_000).unwrap();

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
    fn classic_app_gets_classic_feed() {
        let mut h = HeaderMap::new();
        h.insert(
            header::USER_AGENT,
            "YouTube v1.0.0 CFNetwork/548.1.4".parse().unwrap(),
        );
        assert!(is_classic_app(&h));
        h.insert(
            header::USER_AGENT,
            "YouTube/1.3.0 CFNetwork/609".parse().unwrap(),
        );
        assert!(!is_classic_app(&h));

        let json: serde_json::Value =
            serde_json::from_str(include_str!("../../tests/fixtures/search_vi.json")).unwrap();
        let page = parse::page_in(&json, 1_794_700_000);
        let mut c = ctx("q=x", None);
        c.classic = true;
        let resp = feed_for_app(&c, "videos", "t", &page, 2);
        assert_eq!(resp.status(), StatusCode::OK);
        let xml = ClassicFeed {
            base: &c.base,
            title: "t",
            self_url: c.self_url(),
            total: 2,
            start_index: 1,
            videos: &page.videos[..2],
        }
        .render()
        .unwrap();
        assert!(xml.contains("xmlns:yt='http://gdata.youtube.com/schemas/2007'"));
        assert!(xml.contains("/video/sd/"));
        assert!(!xml.contains("rel='next'"));
        let mut reader = quick_xml::Reader::from_str(&xml);
        reader.config_mut().check_end_names = true;
        while !matches!(
            reader.read_event().expect("well-formed"),
            quick_xml::events::Event::Eof
        ) {}
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
