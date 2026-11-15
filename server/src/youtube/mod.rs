//! Everything that talks to YouTube: metadata providers and stream resolvers.

pub mod ytdlp;

use std::fmt;

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
