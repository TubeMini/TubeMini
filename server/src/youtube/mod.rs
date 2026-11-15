//! Everything that talks to YouTube: metadata providers and stream resolvers.

pub mod innertube;
pub mod parse;
pub mod streams;
pub mod ytdlp;

use std::fmt;
use std::future::Future;
use std::pin::Pin;

/// Boxed future used by the provider traits (keeps them object-safe).
pub type BoxFut<'a, T> = Pin<Box<dyn Future<Output = anyhow::Result<T>> + Send + 'a>>;

/// One video as shown in a list. Unknown numbers are 0.
#[derive(Debug, Clone, Default, PartialEq, serde::Serialize)]
pub struct Video {
    pub id: String,
    pub title: String,
    pub author: String,
    pub author_id: String,
    /// Seconds; 0 = unknown or live.
    pub duration: u32,
    pub views: u64,
    /// Unix seconds (approximate when YouTube only gives "3 days ago"); 0 = unknown.
    pub published: i64,
    pub description: String,
}

impl Video {
    /// `published` as GData wants it (`1970-01-01T00:00:00.000Z` when unknown).
    pub fn published_iso(&self) -> String {
        parse::iso8601(self.published.max(0))
    }
}

/// A page of videos plus the token for the next page.
#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Page {
    pub videos: Vec<Video>,
    pub continuation: Option<String>,
}

/// Search options mapped from GData query parameters.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub struct SearchFilter {
    pub order: Option<SearchOrder>,
    pub upload: Option<UploadDate>,
    pub length: Option<Length>,
    pub subtitles: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SearchOrder {
    Rating = 1,
    Date = 2,
    Views = 3,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum UploadDate {
    Day = 2,
    Week = 3,
    Month = 4,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Length {
    /// < 4 min
    Short = 1,
    /// > 20 min
    Long = 2,
    /// 4–20 min
    Medium = 3,
}

impl SearchFilter {
    /// From GData `orderby`, `time`, `duration`, `caption`.
    pub fn from_gdata(
        orderby: Option<&str>,
        time: Option<&str>,
        duration: Option<&str>,
        caption: Option<&str>,
    ) -> Self {
        Self {
            order: match orderby {
                Some("published") => Some(SearchOrder::Date),
                Some("viewCount") => Some(SearchOrder::Views),
                Some("rating") => Some(SearchOrder::Rating),
                _ => None,
            },
            upload: match time {
                Some("today") => Some(UploadDate::Day),
                Some("this_week") => Some(UploadDate::Week),
                Some("this_month") => Some(UploadDate::Month),
                _ => None,
            },
            length: match duration {
                Some("short") => Some(Length::Short),
                Some("medium") => Some(Length::Medium),
                Some("long") => Some(Length::Long),
                _ => None,
            },
            subtitles: caption.is_some_and(|c| c.eq_ignore_ascii_case("true")),
        }
    }
}

/// Home-feed categories of the old app (`/feeds/api/standardfeeds/[region/]<feed>`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Category {
    /// Default "most popular": a mix of the topic pages below.
    All,
    Music,
    News,
    Sports,
    Gaming,
    Film,
}

impl Category {
    /// Maps a standard feed name such as `most_popular_Music`.
    pub fn from_feed(feed: &str) -> Self {
        match feed.rsplit_once('_').map(|(_, c)| c) {
            Some("Music") => Self::Music,
            Some("News") => Self::News,
            Some("Sports") => Self::Sports,
            Some("Games") => Self::Gaming,
            Some("Film") => Self::Film,
            _ => Self::All,
        }
    }
}

/// Where list metadata comes from (InnerTube today; yt-dlp as a fallback later).
pub trait MetadataProvider: Send + Sync {
    fn search<'a>(
        &'a self,
        query: &'a str,
        filter: SearchFilter,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Page>;
    /// One video's details (for single-entry routes such as `/feeds/player/videos/{id}`).
    fn video<'a>(&'a self, id: &'a VideoId) -> BoxFut<'a, Video>;
    fn related<'a>(&'a self, id: &'a VideoId, continuation: Option<&'a str>) -> BoxFut<'a, Page>;
    fn channel_uploads<'a>(
        &'a self,
        channel_id: &'a str,
        continuation: Option<&'a str>,
    ) -> BoxFut<'a, Page>;
    fn popular(&self, category: Category) -> BoxFut<'_, Page>;
}

/// Is this a plausible channel id (`UC` + 22 chars)?
pub fn is_channel_id(s: &str) -> bool {
    s.len() == 24
        && s.starts_with("UC")
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// A validated 11-character YouTube video id (`[A-Za-z0-9_-]{11}`).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct VideoId(String);

impl VideoId {
    pub fn parse(s: &str) -> Option<Self> {
        let ok = s.len() == 11
            && s.bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-');
        ok.then(|| Self(s.to_owned()))
    }

    /// Accepts a bare id or a common YouTube link (`watch?v=`, `youtu.be/`, `/shorts/`, `/embed/`).
    pub fn from_input(input: &str) -> Option<Self> {
        let input = input.trim();
        if let Some(id) = Self::parse(input) {
            return Some(id);
        }
        if let Some(pos) = input.find("v=") {
            let rest = &input[pos + 2..];
            return Self::parse(rest.get(..11)?);
        }
        for marker in ["youtu.be/", "/shorts/", "/embed/", "/live/"] {
            if let Some(pos) = input.find(marker) {
                let rest = &input[pos + marker.len()..];
                return Self::parse(rest.get(..11)?);
            }
        }
        None
    }

    pub fn watch_url(&self) -> String {
        format!("https://www.youtube.com/watch?v={}", self.0)
    }
}

impl fmt::Display for VideoId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_bare_id() {
        assert_eq!(
            VideoId::parse("dQw4w9WgXcQ").unwrap().to_string(),
            "dQw4w9WgXcQ"
        );
        assert!(VideoId::parse("dQw4w9WgXc").is_none());
        assert!(VideoId::parse("dQw4w9WgXc!").is_none());
        assert!(VideoId::parse("dQw4w9WgXcQQ").is_none());
    }

    #[test]
    fn parses_links() {
        for link in [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10",
            "https://youtu.be/dQw4w9WgXcQ?si=abc",
            "https://www.youtube.com/shorts/dQw4w9WgXcQ",
            "https://www.youtube.com/embed/dQw4w9WgXcQ",
            "  dQw4w9WgXcQ  ",
        ] {
            assert_eq!(
                VideoId::from_input(link).map(|v| v.to_string()),
                Some("dQw4w9WgXcQ".into()),
                "{link}"
            );
        }
        assert!(VideoId::from_input("https://example.com/").is_none());
        assert!(VideoId::from_input("watch?v=short").is_none());
    }
}
