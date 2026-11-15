//! Minimal InnerTube client (YouTube's internal web API) for list metadata.
//!
//! Endpoints, client constants and request parameters are copied from yt-dlp 2026.10.26
//! (`yt_dlp/extractor/youtube/_base.py`) and rustypipe 0.11.4 (`src/client/channel.rs`,
//! `src/param/search_filter.rs`); nothing here is guessed. See docs/DECISIONS.md (D11).

use std::net::{IpAddr, Ipv4Addr};
use std::time::Duration;

use anyhow::{Context, Result, bail};
use base64::Engine as _;
use serde_json::{Value, json};

use super::parse::{self, find_first};
use super::{BoxFut, Category, MetadataProvider, Page, SearchFilter, VideoId};
use crate::config::Config;

const API_BASE: &str = "https://www.youtube.com/youtubei/v1/";
/// `INNERTUBE_CLIENTS['web']['INNERTUBE_CONTEXT']['client']['clientVersion']` in yt-dlp 2026.10.26.
const WEB_CLIENT_VERSION: &str = "2.20260708.00.00";
const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 \
                          (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36";
/// Channel "Videos" tab (`ChannelVideoTab::Videos` in rustypipe 0.11.4).
const CHANNEL_VIDEOS_PARAMS: &str = "EgZ2aWRlb3PyBgQKAjoA";

/// YouTube topic channels ("Explore" destinations). They list popular videos for the `gl` region.
const TOPIC_MUSIC: &str = "UC-9-kyTW8ZkZNDHQJ6FgpwQ";
const TOPIC_NEWS: &str = "UCYfdidRxbB8Qhf0Nx7ioOYw";
const TOPIC_SPORTS: &str = "UCEgdi0XIXXZ-qJOFPf4JSKw";
const TOPIC_GAMING: &str = "UCOpNcN46UbXVtpKMrmU4Abg";

/// Cache lifetime for list metadata.
const CACHE_TTL: Duration = Duration::from_secs(30 * 60);

pub struct InnerTube {
    http: reqwest::Client,
    hl: String,
    gl: String,
    cache: moka::future::Cache<String, Page>,
}

impl InnerTube {
    pub fn new(cfg: &Config) -> Result<Self> {
        let mut builder = reqwest::Client::builder()
            .user_agent(USER_AGENT)
            .timeout(Duration::from_secs(20))
            .gzip(true);
        if cfg.force_ipv4 {
            builder = builder.local_address(IpAddr::V4(Ipv4Addr::UNSPECIFIED));
        }
        Ok(Self {
            http: builder.build()?,
            hl: cfg.language.clone(),
            gl: cfg.region.clone(),
            cache: moka::future::Cache::builder()
                .max_capacity(500)
                .time_to_live(CACHE_TTL)
                .build(),
        })
    }

    /// POSTs `body` (plus the client context) to `/youtubei/v1/<endpoint>`.
    async fn call(&self, endpoint: &str, mut body: Value) -> Result<Value> {
        body["context"] = json!({
            "client": {
                "clientName": "WEB",
                "clientVersion": WEB_CLIENT_VERSION,
                "hl": self.hl,
                "gl": self.gl,
            }
        });
        let resp = self
            .http
            .post(format!("{API_BASE}{endpoint}?prettyPrint=false"))
            .header("X-Youtube-Client-Name", "1")
            .header("X-Youtube-Client-Version", WEB_CLIENT_VERSION)
            .header("Origin", "https://www.youtube.com")
            .json(&body)
            .send()
            .await
            .with_context(|| format!("InnerTube {endpoint}: request failed"))?;
        let status = resp.status();
        if !status.is_success() {
            bail!("InnerTube {endpoint}: HTTP {status}");
        }
        resp.json()
            .await
            .with_context(|| format!("InnerTube {endpoint}: invalid JSON"))
    }

    /// Runs `fetch` unless `key` is cached; empty pages are not cached.
    async fn cached<F>(&self, key: String, fetch: F) -> Result<Page>
    where
        F: Future<Output = Result<Page>>,
    {
        if let Some(page) = self.cache.get(&key).await {
            return Ok(page);
        }
        let page = fetch.await?;
        if !page.videos.is_empty() {
            self.cache.insert(key, page.clone()).await;
        }
        Ok(page)
    }

    async fn search_page(
        &self,
        query: &str,
        filter: SearchFilter,
        continuation: Option<&str>,
    ) -> Result<Page> {
        let body = match continuation {
            Some(token) => json!({ "continuation": token }),
            None => json!({ "query": query, "params": search_params(filter) }),
        };
        let resp = self.call("search", body).await?;
        Ok(parse::page_in(&resp, parse::now()))
    }

    async fn related_page(&self, id: &VideoId, continuation: Option<&str>) -> Result<Page> {
        let resp = match continuation {
            Some(token) => self.call("next", json!({ "continuation": token })).await?,
            None => {
                self.call("next", json!({ "videoId": id.to_string() }))
                    .await?
            }
        };
        // First page: only the side column (the main column also has a comments continuation)
        let scope = find_first(&resp, "secondaryResults").unwrap_or(&resp);
        Ok(parse::page_in(scope, parse::now()))
    }

    async fn uploads_page(&self, channel_id: &str, continuation: Option<&str>) -> Result<Page> {
        let body = match continuation {
            Some(token) => json!({ "continuation": token }),
            None => json!({ "browseId": channel_id, "params": CHANNEL_VIDEOS_PARAMS }),
        };
        let resp = self.call("browse", body).await?;
        let mut page = parse::page_in(&resp, parse::now());
        // Channel tabs omit the channel on each item: take it from the page header
        let name = channel_name(&resp);
        for v in &mut page.videos {
            if v.author_id.is_empty() {
                v.author_id = channel_id.to_owned();
            }
            if v.author.is_empty() {
                v.author.clone_from(&name);
            }
        }
        Ok(page)
    }

    async fn topic_page(&self, browse_id: &str) -> Result<Page> {
        let resp = self
            .call("browse", json!({ "browseId": browse_id }))
            .await?;
        let mut page = parse::page_in(&resp, parse::now());
        page.continuation = None;
        Ok(page)
    }

    async fn popular_page(&self, category: Category) -> Result<Page> {
        let topics: &[&str] = match category {
            Category::All => &[TOPIC_MUSIC, TOPIC_NEWS, TOPIC_SPORTS],
            Category::Music => &[TOPIC_MUSIC],
            Category::News => &[TOPIC_NEWS],
            Category::Sports => &[TOPIC_SPORTS],
            Category::Gaming => &[TOPIC_GAMING],
            Category::Film => &[],
        };
        let mut lists = Vec::new();
        for topic in topics {
            match self.topic_page(topic).await {
                Ok(p) => lists.push(p.videos),
                Err(e) => tracing::warn!("topic {topic}: {e:#}"),
            }
        }
        let mut videos = interleave(lists);
        // Topic pages can be empty for a region (Gaming in VN): fall back to a popular-this-week search
        if videos.is_empty() {
            let keyword = match category {
                Category::Gaming => "game",
                Category::Film => "phim",
                Category::Sports => "thể thao",
                Category::News => "tin tức",
                Category::Music | Category::All => "nhạc",
            };
            let filter = SearchFilter {
                order: Some(super::SearchOrder::Views),
                upload: Some(super::UploadDate::Week),
                ..SearchFilter::default()
            };
            videos = self.search_page(keyword, filter, None).await?.videos;
        }
        Ok(Page {
            videos,
            continuation: None,
        })
    }
}

impl MetadataProvider for InnerTube {
    fn search<'a>(
        &'a self,
        query: &'a str,
        filter: SearchFilter,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Page> {
        let key = format!("search|{query}|{filter:?}|{}", continuation.unwrap_or(""));
        Box::pin(self.cached(key, self.search_page(query, filter, continuation)))
    }

    fn related<'a>(&'a self, id: &'a VideoId, continuation: Option<&'a str>) -> BoxFut<'a, Page> {
        let key = format!("related|{id}|{}", continuation.unwrap_or(""));
        Box::pin(self.cached(key, self.related_page(id, continuation)))
    }

    fn channel_uploads<'a>(
        &'a self,
        channel_id: &'a str,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Page> {
        let key = format!("uploads|{channel_id}|{}", continuation.unwrap_or(""));
        Box::pin(self.cached(key, self.uploads_page(channel_id, continuation)))
    }

    fn popular(&self, category: Category) -> BoxFut<'_, Page> {
        let key = format!("popular|{category:?}");
        Box::pin(self.cached(key, self.popular_page(category)))
    }
}

/// Channel title from a browse response header.
fn channel_name(resp: &Value) -> String {
    find_first(resp, "channelMetadataRenderer")
        .and_then(|m| m.get("title"))
        .and_then(Value::as_str)
        .or_else(|| {
            find_first(resp, "pageHeaderViewModel")
                .and_then(|h| h.get("title"))
                .and_then(|t| find_first(t, "content"))
                .and_then(Value::as_str)
        })
        .unwrap_or_default()
        .to_owned()
}

/// Round-robin merge of several lists, skipping duplicate ids.
fn interleave(lists: Vec<Vec<super::Video>>) -> Vec<super::Video> {
    let mut iters: Vec<_> = lists.into_iter().map(Vec::into_iter).collect();
    let mut seen = std::collections::HashSet::new();
    let mut out = Vec::new();
    loop {
        let mut progressed = false;
        for it in &mut iters {
            if let Some(v) = it.next() {
                progressed = true;
                if seen.insert(v.id.clone()) {
                    out.push(v);
                }
            }
        }
        if !progressed {
            return out;
        }
    }
}

/// Tiny protobuf writer (varints and embedded messages only).
#[derive(Default)]
struct Proto(Vec<u8>);

impl Proto {
    fn raw_varint(&mut self, mut v: u64) {
        loop {
            let byte = (v & 0x7f) as u8;
            v >>= 7;
            if v == 0 {
                self.0.push(byte);
                return;
            }
            self.0.push(byte | 0x80);
        }
    }
    fn varint(&mut self, field: u32, v: u64) {
        self.raw_varint(u64::from(field) << 3);
        self.raw_varint(v);
    }
    fn embedded(&mut self, field: u32, inner: Proto) {
        self.raw_varint((u64::from(field) << 3) | 2);
        self.raw_varint(inner.0.len() as u64);
        self.0.extend(inner.0);
    }
}

/// Search `params` exactly as rustypipe's `SearchFilter::encode` (videos only, plus GData filters).
pub fn search_params(f: SearchFilter) -> String {
    let mut filters = Proto::default();
    if let Some(date) = f.upload {
        filters.varint(1, date as u64);
    }
    filters.varint(2, 1); // item type: video
    if let Some(length) = f.length {
        filters.varint(3, length as u64);
    }
    if f.subtitles {
        filters.varint(5, 1);
    }
    let mut pb = Proto::default();
    if let Some(order) = f.order {
        pb.varint(1, order as u64);
    }
    pb.embedded(2, filters);
    pb.varint(30, 1); // do not hide "sensitive topic" results
    base64::engine::general_purpose::URL_SAFE
        .encode(&pb.0)
        .replace('=', "%3D")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::youtube::{Length, SearchOrder, UploadDate};

    #[test]
    fn search_params_match_rustypipe() {
        // rustypipe 0.11.4 test case: SearchFilter::new().item_type(ItemType::Video)
        assert_eq!(search_params(SearchFilter::default()), "EgIQAfABAQ%3D%3D");
        let all = SearchFilter {
            order: Some(SearchOrder::Views),
            upload: Some(UploadDate::Week),
            length: Some(Length::Long),
            subtitles: true,
        };
        // sort=3, filters{date=3,type=1,length=2,subtitles=1}, 30=1
        let bytes = base64::engine::general_purpose::URL_SAFE
            .decode(search_params(all).replace("%3D", "="))
            .unwrap();
        assert_eq!(
            bytes,
            [
                0x08, 0x03, 0x12, 0x08, 0x08, 0x03, 0x10, 0x01, 0x18, 0x02, 0x28, 0x01, 0xf0, 0x01,
                0x01
            ]
        );
    }

    #[test]
    fn interleaves_without_duplicates() {
        let v = |id: &str| super::super::Video {
            id: id.into(),
            ..Default::default()
        };
        let out = interleave(vec![vec![v("a"), v("b"), v("c")], vec![v("x"), v("a")]]);
        let ids: Vec<_> = out.iter().map(|v| v.id.as_str()).collect();
        assert_eq!(ids, ["a", "x", "b", "c"]);
    }
}
