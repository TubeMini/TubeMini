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

/// `2014-11-10T06:05:55-08:00` (or `...Z`, or a bare date) → Unix seconds.
pub fn parse_rfc3339(s: &str) -> Option<i64> {
    let s = s.trim();
    let num = |a: usize, b: usize| s.get(a..b)?.parse::<i64>().ok();
    let (y, m, d) = (num(0, 4)?, num(5, 7)?, num(8, 10)?);
    let (mut hh, mut mm, mut ss, mut offset) = (0, 0, 0, 0);
    if s.len() >= 19 {
        hh = num(11, 13)?;
        mm = num(14, 16)?;
        ss = num(17, 19)?;
        let tz = s[19..].trim_start_matches(|c: char| c == '.' || c.is_ascii_digit());
        if let Some(sign) = tz.chars().next().filter(|c| *c == '+' || *c == '-') {
            let oh: i64 = tz.get(1..3)?.parse().ok()?;
            let om: i64 = tz.get(4..6).and_then(|v| v.parse().ok()).unwrap_or(0);
            offset = (oh * 3600 + om * 60) * if sign == '-' { -1 } else { 1 };
        }
    }
    // Days from civil (Howard Hinnant)
    let y2 = if m <= 2 { y - 1 } else { y };
    let era = y2.div_euclid(400);
    let yoe = y2 - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(days * 86_400 + hh * 3600 + mm * 60 + ss - offset)
}

/// One video from a `player` response (`videoDetails` + `microformat`).
pub fn video_from_player(resp: &Value) -> Option<Video> {
    let d = resp.get("videoDetails")?;
    let s = |k: &str| {
        d.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    let micro = resp
        .get("microformat")
        .and_then(|m| m.get("playerMicroformatRenderer"));
    let date = micro
        .and_then(|m| m.get("publishDate").or_else(|| m.get("uploadDate")))
        .and_then(Value::as_str)
        .and_then(parse_rfc3339)
        .unwrap_or(0);
    Some(Video {
        id: d.get("videoId")?.as_str()?.to_owned(),
        title: s("title"),
        author: s("author"),
        author_id: s("channelId"),
        duration: s("lengthSeconds").parse().unwrap_or(0),
        views: s("viewCount").parse().unwrap_or(0),
        published: date,
        description: s("shortDescription"),
    })
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

/// Avatar URL → small JPEG (`=s88`), absolute https (`//yt3…` → `https://yt3…`).
pub fn small_avatar(url: &str) -> String {
    let url = if url.starts_with("//") {
        format!("https:{url}")
    } else {
        url.to_owned()
    };
    if let Some(pos) = url.rfind("=s") {
        let tail = &url[pos + 2..];
        let digits = tail.bytes().take_while(u8::is_ascii_digit).count();
        if digits > 0 {
            return format!("{}=s88{}", &url[..pos], &tail[digits..]);
        }
    }
    url
}

fn mentions(text: &str, words: &[&str]) -> bool {
    let lower = text.to_lowercase();
    words.iter().any(|w| lower.contains(w))
}

const SUBSCRIBER_WORDS: &[&str] = &["người đăng ký", "subscriber"];
const VIDEO_WORDS: &[&str] = &["video"];

/// Fills subscriber / video counts from free-form texts ("1,26 Tr người đăng ký", "1,5 N video").
fn channel_counts<'a>(ch: &mut super::Channel, texts: impl IntoIterator<Item = &'a str>) {
    for t in texts {
        if mentions(t, SUBSCRIBER_WORDS) {
            ch.subscribers = parse_views(t).unwrap_or(ch.subscribers);
        } else if mentions(t, VIDEO_WORDS) {
            ch.videos = parse_views(t).unwrap_or(ch.videos);
        }
    }
}

/// Channel page header from a `browse` response of the channel.
pub fn channel_from_browse(resp: &Value) -> Option<super::Channel> {
    let md = find_first(resp, "channelMetadataRenderer")?;
    let s = |k: &str| {
        md.get(k)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    let avatar = md
        .get("avatar")
        .and_then(|a| find_first(a, "url"))
        .and_then(Value::as_str)
        .map(small_avatar)
        .unwrap_or_default();
    let mut ch = super::Channel {
        id: s("externalId"),
        name: s("title"),
        description: s("description"),
        avatar,
        ..Default::default()
    };
    let mut texts = Vec::new();
    if let Some(header) = find_first(resp, "pageHeaderViewModel") {
        let mut parts = Vec::new();
        find_all(header, "metadataParts", &mut parts);
        for list in parts.into_iter().filter_map(Value::as_array) {
            texts.extend(list.iter().map(|p| text(p.get("text"))));
        }
    }
    if let Some(c4) = find_first(resp, "c4TabbedHeaderRenderer") {
        texts.push(text(c4.get("subscriberCountText")));
        texts.push(text(c4.get("videosCountText")));
    }
    channel_counts(&mut ch, texts.iter().map(String::as_str));
    (!ch.id.is_empty()).then_some(ch)
}

/// `params` of a channel tab (`/playlists`, `/videos`, …) as listed in the channel's own response.
pub fn channel_tab_params(resp: &Value, suffix: &str) -> Option<String> {
    let mut tabs = Vec::new();
    find_all(resp, "tabRenderer", &mut tabs);
    tabs.into_iter().find_map(|t| {
        let ep = t.get("endpoint")?;
        let url = find_first(ep, "url")?.as_str()?;
        if !url.ends_with(suffix) {
            return None;
        }
        find_first(ep, "params")?.as_str().map(str::to_owned)
    })
}

/// `channelRenderer` (channel search results).
pub fn channel_from_renderer(r: &Value) -> Option<super::Channel> {
    let mut ch = super::Channel {
        id: r.get("channelId")?.as_str()?.to_owned(),
        name: text(r.get("title")),
        description: text(r.get("descriptionSnippet")),
        avatar: r
            .get("thumbnail")
            .and_then(|t| find_first(t, "url"))
            .and_then(Value::as_str)
            .map(small_avatar)
            .unwrap_or_default(),
        ..Default::default()
    };
    // YouTube now puts "@handle" in subscriberCountText and the count in videoCountText
    let texts = [
        text(r.get("subscriberCountText")),
        text(r.get("videoCountText")),
    ];
    channel_counts(&mut ch, texts.iter().map(String::as_str));
    Some(ch)
}

pub fn channels_in(v: &Value) -> super::Listing<super::Channel> {
    let mut nodes = Vec::new();
    find_all(v, "channelRenderer", &mut nodes);
    super::Listing {
        items: nodes
            .into_iter()
            .filter_map(channel_from_renderer)
            .collect(),
        continuation: continuation_in(v),
    }
}

/// Labels that are not a channel name in playlist lockups.
const PLAYLIST_LABELS: &[&str] = &[
    "danh sách phát",
    "xem toàn bộ danh sách",
    "playlist",
    "view full playlist",
];

fn video_id_in_thumb(v: &Value) -> String {
    let mut urls = Vec::new();
    find_all(v, "url", &mut urls);
    urls.into_iter()
        .filter_map(Value::as_str)
        .find_map(|u| {
            let rest = u.split("i.ytimg.com/vi/").nth(1)?;
            let id = rest.split('/').next()?;
            super::VideoId::parse(id).map(|v| v.to_string())
        })
        .unwrap_or_default()
}

/// `lockupViewModel` with `contentType: LOCKUP_CONTENT_TYPE_PLAYLIST`.
pub fn playlist_from_lockup(l: &Value) -> Option<super::Playlist> {
    if l.get("contentType").and_then(Value::as_str) != Some("LOCKUP_CONTENT_TYPE_PLAYLIST") {
        return None;
    }
    let meta = l.get("metadata")?.get("lockupMetadataViewModel")?;
    let mut badges = Vec::new();
    if let Some(image) = l.get("contentImage") {
        find_all(image, "text", &mut badges);
    }
    let count = badges
        .into_iter()
        .filter_map(Value::as_str)
        .find(|t| t.chars().next().is_some_and(|c| c.is_ascii_digit()))
        .and_then(parse_views)
        .unwrap_or(0);
    let mut parts = Vec::new();
    find_all(meta, "metadataParts", &mut parts);
    let author = parts
        .into_iter()
        .filter_map(Value::as_array)
        .flatten()
        .map(|p| text(p.get("text")))
        .find(|t| !t.trim().is_empty() && !mentions(t, PLAYLIST_LABELS))
        .unwrap_or_default();
    Some(super::Playlist {
        id: l.get("contentId")?.as_str()?.to_owned(),
        title: text(meta.get("title")),
        author,
        author_id: channel_id_in(meta).unwrap_or_default(),
        count,
        thumb_video: l
            .get("contentImage")
            .map(video_id_in_thumb)
            .unwrap_or_default(),
    })
}

/// `playlistRenderer` (older search results).
pub fn playlist_from_renderer(r: &Value) -> Option<super::Playlist> {
    let byline = r.get("shortBylineText").or_else(|| r.get("longBylineText"));
    Some(super::Playlist {
        id: r.get("playlistId")?.as_str()?.to_owned(),
        title: text(r.get("title")),
        author: text(byline),
        author_id: byline.and_then(channel_id_in).unwrap_or_default(),
        count: r
            .get("videoCount")
            .and_then(Value::as_str)
            .and_then(|c| c.parse().ok())
            .unwrap_or(0),
        thumb_video: video_id_in_thumb(r),
    })
}

pub fn playlists_in(v: &Value) -> super::Listing<super::Playlist> {
    let mut lockups = Vec::new();
    find_all(v, "lockupViewModel", &mut lockups);
    let mut renderers = Vec::new();
    find_all(v, "playlistRenderer", &mut renderers);
    let items = lockups
        .into_iter()
        .filter_map(playlist_from_lockup)
        .chain(renderers.into_iter().filter_map(playlist_from_renderer))
        .collect();
    super::Listing {
        items,
        continuation: continuation_in(v),
    }
}

/// Token that loads the comments of a `next` (watch page) response.
pub fn comments_token(next: &Value) -> Option<String> {
    let mut sections = Vec::new();
    find_all(next, "itemSectionRenderer", &mut sections);
    sections
        .into_iter()
        .find(|s| {
            s.get("sectionIdentifier").and_then(Value::as_str) == Some("comment-item-section")
        })
        .and_then(continuation_in)
}

/// Top-level comments of a comments continuation response (new entity format + legacy renderer).
pub fn comments_in(resp: &Value, now: i64) -> super::Listing<super::Comment> {
    let mut items = Vec::new();
    let mut payloads = Vec::new();
    find_all(resp, "commentEntityPayload", &mut payloads);
    for p in payloads {
        let s = |path: &[&str]| str_at(p, path).unwrap_or_default().to_owned();
        let id = s(&["properties", "commentId"]);
        if id.is_empty() {
            continue;
        }
        // Verified authors come with an empty displayName; fall back to the a11y label or the handle
        let author = [
            s(&["author", "displayName"]),
            s(&["properties", "authorButtonA11y"]),
            s(&[
                "author",
                "channelCommand",
                "innertubeCommand",
                "browseEndpoint",
                "canonicalBaseUrl",
            ])
            .trim_start_matches('/')
            .to_owned(),
        ]
        .into_iter()
        .map(|a| a.trim().to_owned())
        .find(|a| !a.is_empty())
        .unwrap_or_default();
        items.push(super::Comment {
            id,
            author,
            author_id: s(&["author", "channelId"]),
            text: s(&["properties", "content", "content"]),
            published: parse_relative_age(&s(&["properties", "publishedTime"]))
                .map_or(0, |a| now - a),
            likes: parse_views(&s(&["toolbar", "likeCountNotliked"])).unwrap_or(0),
            replies: parse_views(&s(&["toolbar", "replyCount"])).unwrap_or(0),
        });
    }
    if items.is_empty() {
        let mut legacy = Vec::new();
        find_all(resp, "commentRenderer", &mut legacy);
        for r in legacy {
            let Some(id) = r.get("commentId").and_then(Value::as_str) else {
                continue;
            };
            items.push(super::Comment {
                id: id.to_owned(),
                author: text(r.get("authorText")),
                author_id: r
                    .get("authorEndpoint")
                    .and_then(|e| find_first(e, "browseId"))
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_owned(),
                text: text(r.get("contentText")),
                published: parse_relative_age(&text(r.get("publishedTimeText")))
                    .map_or(0, |a| now - a),
                likes: parse_views(&text(r.get("voteCount"))).unwrap_or(0),
                replies: r.get("replyCount").and_then(Value::as_u64).unwrap_or(0),
            });
        }
    }
    super::Listing {
        items,
        continuation: top_level_continuation(resp),
    }
}

/// The page continuation of an `onResponseReceivedEndpoints` response: the `continuationItemRenderer`
/// that is a direct item of the action list (reply continuations are nested deeper and ignored).
pub fn top_level_continuation(resp: &Value) -> Option<String> {
    let actions = resp.get("onResponseReceivedEndpoints")?.as_array()?;
    actions.iter().rev().find_map(|a| {
        let list = a
            .get("reloadContinuationItemsCommand")
            .or_else(|| a.get("appendContinuationItemsAction"))?
            .get("continuationItems")?
            .as_array()?;
        list.iter().rev().find_map(|item| {
            let r = item.get("continuationItemRenderer")?;
            find_first(r, "token")?.as_str().map(str::to_owned)
        })
    })
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
    fn channel_home_fixture() {
        let json = fixture("channel_home_vi.json");
        let ch = channel_from_browse(&json).unwrap();
        assert_eq!(ch.id, "UCSMOQeBJ2RAnuFungnQOxLg");
        assert_eq!(ch.name, "Blender");
        assert!(ch.subscribers > 1_000_000, "{ch:?}");
        assert!(ch.videos > 1000, "{ch:?}");
        assert!(
            ch.avatar.starts_with("https://yt3.") && ch.avatar.contains("=s88"),
            "{ch:?}"
        );
        let params = channel_tab_params(&json, "/playlists").unwrap();
        assert!(params.starts_with("Eg"), "{params}");
        assert_eq!(
            channel_tab_params(&json, "/videos").as_deref(),
            Some("EgZ2aWRlb3PyBgQKAjoA")
        );
    }

    #[test]
    fn channel_search_fixture() {
        let list = channels_in(&fixture("channel_search_vi.json"));
        assert_eq!(list.items.len(), 3);
        for c in &list.items {
            assert!(
                super::super::is_channel_id(&c.id) && !c.name.is_empty(),
                "{c:?}"
            );
            assert!(
                c.subscribers > 0 && c.avatar.starts_with("https://"),
                "{c:?}"
            );
        }
        assert!(list.continuation.is_some());
    }

    #[test]
    fn channel_playlists_fixture() {
        let list = playlists_in(&fixture("channel_playlists_vi.json"));
        assert_eq!(list.items.len(), 3);
        for p in &list.items {
            assert!(
                super::super::is_playlist_id(&p.id) && !p.title.is_empty(),
                "{p:?}"
            );
            assert!(p.count > 0 && p.thumb_video.len() == 11, "{p:?}");
            assert_eq!(p.author_id, "UCSMOQeBJ2RAnuFungnQOxLg");
            // Channel tab rows hold only labels ("Danh sách phát"); the caller fills the name in
            assert!(p.author.is_empty(), "{p:?}");
        }
        assert!(list.continuation.is_some());
    }

    #[test]
    fn comments_fixture() {
        let list = comments_in(&fixture("comments_vi.json"), NOW);
        assert_eq!(list.items.len(), 3);
        for c in &list.items {
            assert!(
                !c.id.is_empty() && !c.author.is_empty() && !c.text.is_empty(),
                "{c:?}"
            );
            assert!(super::super::is_channel_id(&c.author_id), "{c:?}");
            assert!(c.published > 0 && c.published < NOW, "{c:?}");
        }
        assert!(list.items.iter().any(|c| c.likes > 0 && c.replies > 0));
        assert!(list.continuation.is_some());
    }

    #[test]
    fn avatars_become_small_jpeg_urls() {
        assert_eq!(
            small_avatar("//yt3.ggpht.com/abc=s176-c-k-c0x00ffffff-no-rj-mo"),
            "https://yt3.ggpht.com/abc=s88-c-k-c0x00ffffff-no-rj-mo"
        );
        assert_eq!(
            small_avatar("https://yt3.ggpht.com/abc=s900"),
            "https://yt3.ggpht.com/abc=s88"
        );
        assert_eq!(small_avatar("https://x/y.jpg"), "https://x/y.jpg");
    }

    #[test]
    fn rfc3339_dates() {
        assert_eq!(parse_rfc3339("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(
            parse_rfc3339("2014-11-10T06:05:55-08:00"),
            Some(1_415_628_355)
        );
        assert_eq!(
            parse_rfc3339("2026-11-15T08:00:00+07:00"),
            Some(1_794_704_400)
        );
        assert_eq!(parse_rfc3339("2014-11-10"), Some(1_415_577_600));
        assert_eq!(parse_rfc3339("garbage"), None);
        assert_eq!(
            iso8601(parse_rfc3339("2000-02-29T12:34:56Z").unwrap()),
            "2000-02-29T12:34:56.000Z"
        );
    }

    #[test]
    fn player_details() {
        let resp = serde_json::json!({
            "videoDetails": { "videoId": "aqz-KE-bpKQ", "title": "Big Buck Bunny", "lengthSeconds": "635",
                "channelId": "UCSMOQeBJ2RAnuFungnQOxLg", "author": "Blender", "viewCount": "23542023",
                "shortDescription": "UHD" },
            "microformat": { "playerMicroformatRenderer": { "publishDate": "2014-11-10T06:05:55-08:00" } }
        });
        let v = video_from_player(&resp).unwrap();
        assert_eq!(
            (v.duration, v.views, v.published),
            (635, 23_542_023, 1_415_628_355)
        );
        assert_eq!(v.author_id, "UCSMOQeBJ2RAnuFungnQOxLg");
    }

    #[test]
    fn iso_dates() {
        assert_eq!(iso8601(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(iso8601(1_794_703_968), "2026-11-15T00:52:48.000Z");
        assert_eq!(iso8601(951_782_400), "2000-02-29T00:00:00.000Z");
    }
}
