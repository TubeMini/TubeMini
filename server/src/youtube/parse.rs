//! Parsing of InnerTube JSON (WEB client) into [`Video`] lists.
//!
//! YouTube reshuffles its layout often, so items are found by a deep scan for the renderer
//! names (`videoRenderer`, `lockupViewModel`, …) instead of fixed paths. Localized numbers and
//! relative dates are parsed for Vietnamese and English.

use serde_json::Value;

use super::{Page, Video};

/// Collects every value stored under `key`, anywhere below `v` (does not descend into matches).
pub fn find_all<'a>(v: &'a Value, key: &str, out: &mut Vec<&'a Value>) {
    match v {
        Value::Object(map) => {
            for (k, child) in map {
                if k == key {
                    out.push(child);
                } else {
                    find_all(child, key, out);
                }
            }
        }
        Value::Array(items) => items.iter().for_each(|c| find_all(c, key, out)),
        _ => {}
    }
}

/// First value stored under `key`, anywhere below `v`.
pub fn find_first<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    match v {
        Value::Object(map) => map.iter().find_map(|(k, child)| {
            if k == key {
                Some(child)
            } else {
                find_first(child, key)
            }
        }),
        Value::Array(items) => items.iter().find_map(|c| find_first(c, key)),
        _ => None,
    }
}

/// Text of `{simpleText}`, `{runs:[{text}]}` or `{content}` objects.
pub fn text(v: Option<&Value>) -> String {
    let Some(v) = v else { return String::new() };
    if let Some(s) = v.get("simpleText").and_then(Value::as_str) {
        return s.to_owned();
    }
    if let Some(s) = v.get("content").and_then(Value::as_str) {
        return s.to_owned();
    }
    if let Some(runs) = v.get("runs").and_then(Value::as_array) {
        return runs
            .iter()
            .filter_map(|r| r.get("text").and_then(Value::as_str))
            .collect();
    }
    v.as_str().unwrap_or_default().to_owned()
}

fn str_at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a str> {
    path.iter()
        .try_fold(v, |cur, key| cur.get(*key))
        .and_then(Value::as_str)
}

/// "1:21:40" → 4900. Anything else (LIVE, empty) → None.
pub fn parse_duration(s: &str) -> Option<u32> {
    let s = s.trim();
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit() || b == b':') {
        return None;
    }
    s.split(':')
        .try_fold(0u32, |acc, part| Some(acc * 60 + part.parse::<u32>().ok()?))
}

/// View counts: "164.638 lượt xem", "6,9 Tr lượt xem", "159 N", "1,234 views", "17M", "1.2K views".
pub fn parse_views(s: &str) -> Option<u64> {
    let s = s.replace('\u{a0}', " ");
    let s = s.trim();
    let lower = s.to_lowercase();
    if lower.starts_with("no views") || lower.starts_with("không có lượt xem") {
        return Some(0);
    }
    let start = s.find(|c: char| c.is_ascii_digit())?;
    let rest = &s[start..];
    let num_end = rest
        .find(|c: char| !(c.is_ascii_digit() || c == '.' || c == ','))
        .unwrap_or(rest.len());
    let number = &rest[..num_end];
    let after = rest[num_end..].trim_start();
    let suffix: String = after.chars().take_while(|c| c.is_alphabetic()).collect();
    let multiplier = match suffix.as_str() {
        "K" | "N" => 1e3,
        "M" | "Tr" => 1e6,
        "B" | "T" => 1e9,
        _ => 1.0,
    };
    if multiplier == 1.0 {
        let digits: String = number.chars().filter(char::is_ascii_digit).collect();
        return digits.parse().ok();
    }
    // Abbreviated: a single separator is the decimal mark ("6,9 Tr", "1.2K")
    let value: f64 = number.replace(',', ".").parse().ok()?;
    Some((value * multiplier).round() as u64)
}

/// Relative dates: "4 ngày trước", "Đã phát trực tiếp 3 tuần trước", "2 days ago", "9y ago".
/// Returns the age in seconds.
pub fn parse_relative_age(s: &str) -> Option<i64> {
    let s = s.replace('\u{a0}', " ").to_lowercase();
    let start = s.find(|c: char| c.is_ascii_digit())?;
    let rest = &s[start..];
    let num_end = rest
        .find(|c: char| !c.is_ascii_digit())
        .unwrap_or(rest.len());
    let n: i64 = rest[..num_end].parse().ok()?;
    let unit = rest[num_end..].trim_start();
    if !(unit.contains("trước") || unit.contains("ago")) {
        return None;
    }
    const MIN: i64 = 60;
    const HOUR: i64 = 3600;
    const DAY: i64 = 86_400;
    let secs = if unit.starts_with("giây") || unit.starts_with("sec") || unit.starts_with("s ") {
        1
    } else if unit.starts_with("phút") || unit.starts_with("min") {
        MIN
    } else if unit.starts_with("giờ") || unit.starts_with("hour") || unit.starts_with("h ") {
        HOUR
    } else if unit.starts_with("ngày") || unit.starts_with("day") || unit.starts_with("d ") {
        DAY
    } else if unit.starts_with("tuần") || unit.starts_with("week") || unit.starts_with("w ") {
        7 * DAY
    } else if unit.starts_with("tháng") || unit.starts_with("mo") {
        30 * DAY
    } else if unit.starts_with("năm") || unit.starts_with("year") || unit.starts_with("y ") {
        365 * DAY
    } else if unit.starts_with('m') {
        MIN
    } else {
        return None;
    };
    Some(n * secs)
}

/// Unix seconds → `2026-11-15T08:03:22.000Z` (the exact shape the old YouTube app accepts).
pub fn iso8601(unix: i64) -> String {
    let days = unix.div_euclid(86_400);
    let secs = unix.rem_euclid(86_400);
    // Civil-from-days (Howard Hinnant)
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}.000Z",
        secs / 3600,
        secs % 3600 / 60,
        secs % 60
    )
}

/// Current Unix time in seconds.
pub fn now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn channel_id_in(v: &Value) -> Option<String> {
    let mut found = Vec::new();
    find_all(v, "browseId", &mut found);
    found
        .into_iter()
        .filter_map(Value::as_str)
        .find(|id| super::is_channel_id(id))
        .map(str::to_owned)
}

/// `videoRenderer`, `compactVideoRenderer`, `gridVideoRenderer`.
pub fn video_from_renderer(r: &Value, now: i64) -> Option<Video> {
    let id = r.get("videoId")?.as_str()?.to_owned();
    let owner = r
        .get("ownerText")
        .or_else(|| r.get("longBylineText"))
        .or_else(|| r.get("shortBylineText"));
    let views = parse_views(&text(r.get("viewCountText")))
        .or_else(|| parse_views(&text(r.get("shortViewCountText"))))
        .unwrap_or(0);
    let age = parse_relative_age(&text(r.get("publishedTimeText")));
    let mut description = text(r.get("descriptionSnippet"));
    if description.is_empty()
        && let Some(snippets) = r.get("detailedMetadataSnippets").and_then(Value::as_array)
    {
        description = snippets
            .iter()
            .map(|s| text(s.get("snippetText")))
            .collect::<Vec<_>>()
            .join(" ");
    }
    Some(Video {
        id,
        title: text(r.get("title")),
        author: text(owner),
        author_id: owner.and_then(channel_id_in).unwrap_or_default(),
        duration: parse_duration(&text(r.get("lengthText"))).unwrap_or(0),
        views,
        published: age.map_or(0, |a| now - a),
        description,
    })
}

/// `lockupViewModel` with `contentType: LOCKUP_CONTENT_TYPE_VIDEO` (related, channel tabs, topic pages).
pub fn video_from_lockup(l: &Value, now: i64) -> Option<Video> {
    if l.get("contentType").and_then(Value::as_str) != Some("LOCKUP_CONTENT_TYPE_VIDEO") {
        return None;
    }
    let id = l.get("contentId")?.as_str()?.to_owned();
    let meta = l.get("metadata")?.get("lockupMetadataViewModel")?;
    let mut video = Video {
        id,
        title: text(meta.get("title")),
        author_id: channel_id_in(meta).unwrap_or_default(),
        ..Video::default()
    };
    let mut badges = Vec::new();
    if let Some(image) = l.get("contentImage") {
        find_all(image, "thumbnailBadgeViewModel", &mut badges);
    }
    video.duration = badges
        .iter()
        .find_map(|b| parse_duration(str_at(b, &["text"])?))
        .unwrap_or(0);

    // Metadata rows hold, in order: channel name, then "views | date" (channel pages omit the name)
    let mut parts = Vec::new();
    if let Some(rows) = find_first(meta, "metadataRows").and_then(Value::as_array) {
        for row in rows {
            if let Some(ps) = row.get("metadataParts").and_then(Value::as_array) {
                parts.extend(ps.iter().map(|p| text(p.get("text"))));
            }
        }
    }
    for part in parts.iter().filter(|p| !p.trim().is_empty()) {
        if let Some(age) = parse_relative_age(part) {
            video.published = now - age;
        } else if part.chars().next().is_some_and(|c| c.is_ascii_digit())
            && let Some(v) = parse_views(part)
        {
            video.views = v;
        } else if video.author.is_empty() {
            video.author = part.clone();
        }
    }
    Some(video)
}

/// All videos below `v` (renderers and video lockups), de-duplicated, in document order.
pub fn videos_in(v: &Value, now: i64) -> Vec<Video> {
    let mut nodes = Vec::new();
    collect_items(v, &mut nodes);
    let mut seen = std::collections::HashSet::new();
    nodes
        .into_iter()
        .filter_map(|(kind, node)| match kind {
            ItemKind::Renderer => video_from_renderer(node, now),
            ItemKind::Lockup => video_from_lockup(node, now),
        })
        .filter(|video| seen.insert(video.id.clone()))
        .collect()
}

enum ItemKind {
    Renderer,
    Lockup,
}

fn collect_items<'a>(v: &'a Value, out: &mut Vec<(ItemKind, &'a Value)>) {
    match v {
        Value::Object(map) => {
            for (k, child) in map {
                match k.as_str() {
                    "videoRenderer" | "compactVideoRenderer" | "gridVideoRenderer" => {
                        out.push((ItemKind::Renderer, child));
                    }
                    "lockupViewModel" => out.push((ItemKind::Lockup, child)),
                    _ => collect_items(child, out),
                }
            }
        }
        Value::Array(items) => items.iter().for_each(|c| collect_items(c, out)),
        _ => {}
    }
}

/// Token of the first `continuationItemRenderer` below `v`.
pub fn continuation_in(v: &Value) -> Option<String> {
    let mut renderers = Vec::new();
    find_all(v, "continuationItemRenderer", &mut renderers);
    renderers.into_iter().find_map(|r| {
        let mut tokens = Vec::new();
        find_all(r, "token", &mut tokens);
        tokens
            .into_iter()
            .find_map(Value::as_str)
            .map(str::to_owned)
    })
}

/// A page of videos + continuation from any response (or sub-tree).
pub fn page_in(v: &Value, now: i64) -> Page {
    Page {
        videos: videos_in(v, now),
        continuation: continuation_in(v),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn durations() {
        assert_eq!(parse_duration("4:53"), Some(293));
        assert_eq!(parse_duration("1:21:40"), Some(4900));
        assert_eq!(parse_duration("0:07"), Some(7));
        assert_eq!(parse_duration("TRỰC TIẾP"), None);
        assert_eq!(parse_duration(""), None);
    }

    #[test]
    fn views_vietnamese() {
        assert_eq!(parse_views("164.638 lượt xem"), Some(164_638));
        assert_eq!(parse_views("159\u{a0}N lượt xem"), Some(159_000));
        assert_eq!(parse_views("6,9\u{a0}Tr lượt xem"), Some(6_900_000));
        assert_eq!(parse_views("7,2\u{a0}Tr"), Some(7_200_000));
        assert_eq!(parse_views("1,2 T lượt xem"), Some(1_200_000_000));
        assert_eq!(parse_views("Không có lượt xem"), Some(0));
    }

    #[test]
    fn views_english() {
        assert_eq!(parse_views("1,234 views"), Some(1234));
        assert_eq!(parse_views("17M"), Some(17_000_000));
        assert_eq!(parse_views("1.2K views"), Some(1200));
        assert_eq!(parse_views("No views"), Some(0));
        assert_eq!(parse_views("Hinl"), None);
    }

    #[test]
    fn relative_ages() {
        assert_eq!(parse_relative_age("4 ngày trước"), Some(4 * 86_400));
        assert_eq!(parse_relative_age("3 năm trước"), Some(3 * 365 * 86_400));
        assert_eq!(
            parse_relative_age("Đã phát trực tiếp 3 tuần trước"),
            Some(21 * 86_400)
        );
        assert_eq!(parse_relative_age("5 tháng trước"), Some(150 * 86_400));
        assert_eq!(parse_relative_age("23 giờ trước"), Some(23 * 3600));
        assert_eq!(parse_relative_age("2 days ago"), Some(2 * 86_400));
        assert_eq!(parse_relative_age("9y ago"), Some(9 * 365 * 86_400));
        assert_eq!(parse_relative_age("5mo ago"), Some(150 * 86_400));
        assert_eq!(parse_relative_age("17M"), None);
        assert_eq!(parse_relative_age("6,9 Tr lượt xem"), None);
    }

    const NOW: i64 = 1_794_700_000;

    fn fixture(name: &str) -> Value {
        let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    #[test]
    fn search_fixture() {
        let page = page_in(&fixture("search_vi.json"), NOW);
        assert_eq!(page.videos.len(), 3);
        for v in &page.videos {
            assert_eq!(v.id.len(), 11);
            assert!(!v.title.is_empty() && !v.author.is_empty(), "{v:?}");
            assert!(super::super::is_channel_id(&v.author_id), "{v:?}");
            assert!(
                v.duration > 0 && v.views > 0 && v.published > 0 && v.published < NOW,
                "{v:?}"
            );
        }
        assert!(page.continuation.is_some());
    }

    #[test]
    fn related_fixture_uses_side_column() {
        let json = fixture("next_vi.json");
        let scope = find_first(&json, "secondaryResults").unwrap();
        let page = page_in(scope, NOW);
        assert_eq!(page.videos.len(), 3);
        for v in &page.videos {
            assert!(!v.title.is_empty() && !v.author.is_empty(), "{v:?}");
            assert!(v.duration > 0 && v.views > 0 && v.published > 0, "{v:?}");
        }
        let token = page.continuation.unwrap();
        assert_ne!(token, "COMMENTS_TOKEN");
    }

    #[test]
    fn channel_tab_fixture() {
        let page = page_in(&fixture("channel_videos_vi.json"), NOW);
        assert_eq!(page.videos.len(), 3);
        for v in &page.videos {
            assert!(!v.title.is_empty(), "{v:?}");
            assert!(v.duration > 0 && v.views > 0 && v.published > 0, "{v:?}");
            // Channel tabs have no channel name on items; the caller fills it in
            assert!(v.author.is_empty(), "{v:?}");
        }
        assert!(page.continuation.is_some());
    }

    #[test]
    fn iso_dates() {
        assert_eq!(iso8601(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(iso8601(1_794_703_968), "2026-11-15T00:52:48.000Z");
        assert_eq!(iso8601(951_782_400), "2000-02-29T00:00:00.000Z");
    }
}
