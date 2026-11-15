//! Metadata fallback through yt-dlp (`--flat-playlist -J`), used when the InnerTube client fails
//! or suddenly finds nothing (the usual symptom of a YouTube layout change). Slower (a few seconds
//! per call) and without upload dates, but maintained by the yt-dlp project.
//!
//! Supported: search, single video, channel uploads, playlist. Pages of the fallback carry their
//! own continuation tokens (`ytdlp:<start>`), which are routed straight back here.

use anyhow::{Context, Result};
use serde_json::Value;

use super::innertube::InnerTube;
use super::ytdlp::YtDlp;
use super::{
    BoxFut, Category, Channel, Comment, Listing, MetadataProvider, Page, Playlist, SearchFilter,
    Video, VideoId,
};

const PAGE: usize = 20;
const TOKEN_PREFIX: &str = "ytdlp:";

fn token(start: usize) -> String {
    format!("{TOKEN_PREFIX}{start}")
}

/// 1-based start index of a fallback continuation token.
pub fn fallback_start(token: Option<&str>) -> Option<usize> {
    token?.strip_prefix(TOKEN_PREFIX)?.parse().ok()
}

/// One entry of yt-dlp's (flat) JSON.
pub fn video_from_ytdlp(e: &Value) -> Option<Video> {
    let s = |k: &str| {
        e.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    let id = VideoId::parse(e.get("id")?.as_str()?)?.to_string();
    let published = e
        .get("timestamp")
        .and_then(Value::as_i64)
        .or_else(|| e.get("release_timestamp").and_then(Value::as_i64))
        .unwrap_or(0);
    Some(Video {
        id,
        title: s("title"),
        author: if s("channel").is_empty() {
            s("uploader")
        } else {
            s("channel")
        },
        author_id: s("channel_id"),
        duration: e.get("duration").and_then(Value::as_f64).unwrap_or(0.0) as u32,
        views: e.get("view_count").and_then(Value::as_u64).unwrap_or(0),
        published,
        description: s("description"),
    })
}

pub struct YtDlpMeta {
    ytdlp: YtDlp,
}

impl YtDlpMeta {
    pub fn new(ytdlp: YtDlp) -> Self {
        Self { ytdlp }
    }

    async fn flat(&self, url: &str, start: usize) -> Result<Page> {
        let range = format!("{start}:{}", start + PAGE - 1);
        let out = self
            .ytdlp
            .run(&["--flat-playlist", "-J", "-I", &range, url])
            .await?;
        let json: Value = serde_json::from_str(&out).context("yt-dlp JSON")?;
        let videos: Vec<Video> = json
            .get("entries")
            .and_then(Value::as_array)
            .map(|es| es.iter().filter_map(video_from_ytdlp).collect())
            .unwrap_or_default();
        let continuation = (videos.len() == PAGE).then(|| token(start + PAGE));
        Ok(Page {
            videos,
            continuation,
        })
    }

    async fn search(&self, query: &str, start: usize) -> Result<Page> {
        // ytsearchN returns the first N results; -I picks this page out of them
        self.flat(&format!("ytsearch{}:{query}", start + PAGE - 1), start)
            .await
    }

    async fn uploads(&self, channel_id: &str, start: usize) -> Result<Page> {
        self.flat(
            &format!("https://www.youtube.com/channel/{channel_id}/videos"),
            start,
        )
        .await
    }

    async fn playlist(&self, playlist_id: &str, start: usize) -> Result<Page> {
        self.flat(
            &format!("https://www.youtube.com/playlist?list={playlist_id}"),
            start,
        )
        .await
    }

    async fn video(&self, id: &VideoId) -> Result<Video> {
        let out = self.ytdlp.run(&["-J", &id.watch_url()]).await?;
        let json: Value = serde_json::from_str(&out).context("yt-dlp JSON")?;
        video_from_ytdlp(&json).context("no video in yt-dlp JSON")
    }
}

/// InnerTube first, yt-dlp when it fails or returns an empty first page.
pub struct Fallback {
    primary: InnerTube,
    backup: YtDlpMeta,
}

impl Fallback {
    pub fn new(primary: InnerTube, backup: YtDlpMeta) -> Self {
        Self { primary, backup }
    }
}

/// Decides whether to use the backup for a first page.
async fn page_or_backup<P, B>(what: &str, primary: P, backup: B) -> Result<Page>
where
    P: Future<Output = Result<Page>>,
    B: Future<Output = Result<Page>>,
{
    let reason = match primary.await {
        Ok(page) if !page.videos.is_empty() => return Ok(page),
        Ok(_) => "empty result".to_owned(),
        Err(e) => format!("{e:#}"),
    };
    tracing::warn!("{what}: InnerTube {reason}; falling back to yt-dlp");
    backup
        .await
        .with_context(|| format!("{what}: InnerTube {reason}, yt-dlp also failed"))
}

impl MetadataProvider for Fallback {
    fn search<'a>(
        &'a self,
        query: &'a str,
        filter: SearchFilter,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Page> {
        Box::pin(async move {
            if let Some(start) = fallback_start(continuation) {
                return self.backup.search(query, start).await;
            }
            if continuation.is_some() {
                return self.primary.search(query, filter, continuation).await;
            }
            page_or_backup(
                "search",
                self.primary.search(query, filter, None),
                self.backup.search(query, 1),
            )
            .await
        })
    }

    fn video<'a>(&'a self, id: &'a VideoId) -> BoxFut<'a, Video> {
        Box::pin(async move {
            match self.primary.video(id).await {
                Ok(v) => Ok(v),
                Err(e) => {
                    tracing::warn!("video {id}: InnerTube {e:#}; falling back to yt-dlp");
                    self.backup.video(id).await
                }
            }
        })
    }

    fn related<'a>(&'a self, id: &'a VideoId, continuation: Option<&'a str>) -> BoxFut<'a, Page> {
        self.primary.related(id, continuation)
    }

    fn channel_uploads<'a>(
        &'a self,
        channel_id: &'a str,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Page> {
        Box::pin(async move {
            if let Some(start) = fallback_start(continuation) {
                return self.backup.uploads(channel_id, start).await;
            }
            if continuation.is_some() {
                return self.primary.channel_uploads(channel_id, continuation).await;
            }
            page_or_backup(
                "uploads",
                self.primary.channel_uploads(channel_id, None),
                self.backup.uploads(channel_id, 1),
            )
            .await
        })
    }

    fn forget_uploads<'a>(&'a self, channel_id: &'a str) -> BoxFut<'a, ()> {
        self.primary.forget_uploads(channel_id)
    }

    fn popular(&self, category: Category) -> BoxFut<'_, Page> {
        self.primary.popular(category)
    }

    fn channel<'a>(&'a self, channel_id: &'a str) -> BoxFut<'a, Channel> {
        self.primary.channel(channel_id)
    }

    fn search_channels<'a>(
        &'a self,
        query: &'a str,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Listing<Channel>> {
        self.primary.search_channels(query, continuation)
    }

    fn channel_playlists<'a>(
        &'a self,
        channel_id: &'a str,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Listing<Playlist>> {
        self.primary.channel_playlists(channel_id, continuation)
    }

    fn search_playlists<'a>(
        &'a self,
        query: &'a str,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Listing<Playlist>> {
        self.primary.search_playlists(query, continuation)
    }

    fn playlist<'a>(
        &'a self,
        playlist_id: &'a str,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Page> {
        Box::pin(async move {
            if let Some(start) = fallback_start(continuation) {
                return self.backup.playlist(playlist_id, start).await;
            }
            if continuation.is_some() {
                return self.primary.playlist(playlist_id, continuation).await;
            }
            page_or_backup(
                "playlist",
                self.primary.playlist(playlist_id, None),
                self.backup.playlist(playlist_id, 1),
            )
            .await
        })
    }

    fn comments<'a>(
        &'a self,
        id: &'a VideoId,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Listing<Comment>> {
        self.primary.comments(id, continuation)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn tokens_round_trip() {
        assert_eq!(fallback_start(Some(&token(21))), Some(21));
        assert_eq!(fallback_start(Some("EqEDEgh")), None);
        assert_eq!(fallback_start(None), None);
    }

    #[test]
    fn flat_entry_to_video() {
        let e = json!({ "_type": "url", "id": "6C6xOz-6ET4", "title": "Nhạc Trẻ", "duration": 4900.0,
            "view_count": 173607, "channel": "Mộng Mơ Ballad", "channel_id": "UCP7iucvn_NtNbqIucAoiIaQ",
            "description": "x" });
        let v = video_from_ytdlp(&e).unwrap();
        assert_eq!((v.duration, v.views, v.published), (4900, 173_607, 0));
        assert_eq!(v.author, "Mộng Mơ Ballad");
        assert!(video_from_ytdlp(&json!({ "id": "not-an-id" })).is_none());
    }

    #[tokio::test]
    #[ignore = "runs yt-dlp (needs yt-dlp and deno on PATH)"]
    async fn live_backup_pages() {
        let m = YtDlpMeta::new(YtDlp::new(&crate::config::Config::default()));
        let p1 = m.search("nhạc trẻ", 1).await.unwrap();
        assert_eq!(p1.videos.len(), PAGE);
        assert!(
            p1.videos
                .iter()
                .all(|v| v.duration > 0 && !v.author.is_empty())
        );
        let start = fallback_start(p1.continuation.as_deref()).unwrap();
        let p2 = m.search("nhạc trẻ", start).await.unwrap();
        assert!(!p2.videos.is_empty() && p2.videos[0].id != p1.videos[0].id);
        let pl = m
            .playlist("PLa1F2ddGya_-I9y1nXALrBqrZNdlUE012", 1)
            .await
            .unwrap();
        assert_eq!(pl.videos.len(), PAGE);
    }

    #[tokio::test]
    async fn backup_used_when_primary_empty_or_failing() {
        let one = || Page {
            videos: vec![Video {
                id: "aqz-KE-bpKQ".into(),
                ..Default::default()
            }],
            continuation: None,
        };
        let empty = async { Ok(Page::default()) };
        let p = page_or_backup("t", empty, async { Ok(one()) })
            .await
            .unwrap();
        assert_eq!(p.videos.len(), 1);
        let failing = async { Err(anyhow::anyhow!("boom")) };
        let p = page_or_backup("t", failing, async { Ok(one()) })
            .await
            .unwrap();
        assert_eq!(p.videos.len(), 1);
        let good = async { Ok(one()) };
        let p = page_or_backup("t", good, async { anyhow::bail!("not called") })
            .await
            .unwrap();
        assert_eq!(p.videos.len(), 1);
    }
}
