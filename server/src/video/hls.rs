//! Filtering of YouTube's HLS master playlist for iOS 6.
//!
//! Same rules as the TubeRepair server (`modules/yt.py`, `data_to_hls_url`): keep only H.264 + AAC
//! variants, at most 30 fps, at most `max_res` (the short side, so vertical videos work), and then
//! only the highest remaining resolution, so the old player cannot get stuck on a low-quality
//! variant. Audio renditions are kept only for the groups the remaining variants use; subtitle
//! renditions are dropped. Variant and segment URLs stay absolute googlevideo URLs.

/// Splits an HLS attribute list (`A=1,B="x,y",C=z`) into pairs, honouring quotes.
pub fn attributes(list: &str) -> Vec<(&str, &str)> {
    let mut out = Vec::new();
    let mut rest = list;
    while !rest.is_empty() {
        let Some(eq) = rest.find('=') else { break };
        let key = rest[..eq].trim();
        let after = &rest[eq + 1..];
        let (value, tail) = if let Some(q) = after.strip_prefix('"') {
            match q.find('"') {
                Some(end) => (&q[..end], &q[end + 1..]),
                None => (q, ""),
            }
        } else {
            match after.find(',') {
                Some(end) => (&after[..end], &after[end..]),
                None => (after, ""),
            }
        };
        out.push((key, value));
        rest = tail.trim_start_matches(',');
    }
    out
}

fn attr<'a>(attrs: &[(&str, &'a str)], key: &str) -> Option<&'a str> {
    attrs.iter().find(|(k, _)| *k == key).map(|(_, v)| *v)
}

struct Variant<'a> {
    inf: &'a str,
    uri: &'a str,
    res: u32,
    audio: Option<&'a str>,
}

/// iOS 6 can only decode these (and HLS fMP4 is not supported at all).
fn codecs_ok(codecs: &str) -> bool {
    let list: Vec<&str> = codecs.split(',').map(str::trim).collect();
    list.iter().any(|c| c.starts_with("avc1"))
        && list
            .iter()
            .all(|c| c.starts_with("avc1") || c.starts_with("mp4a"))
}

/// Returns the filtered master playlist, or `None` when no variant is playable.
pub fn filter_master(master: &str, max_res: u32, max_fps: f64) -> Option<String> {
    if !master.trim_start().starts_with("#EXTM3U") {
        return None;
    }
    let mut header = Vec::new();
    let mut audio_media = Vec::new(); // (group id, line)
    let mut variants = Vec::new();
    let mut lines = master.lines().map(str::trim).filter(|l| !l.is_empty());
    while let Some(line) = lines.next() {
        if let Some(list) = line.strip_prefix("#EXT-X-STREAM-INF:") {
            let Some(uri) = lines.by_ref().find(|l| !l.starts_with('#')) else {
                break;
            };
            let attrs = attributes(list);
            let fps: f64 = attr(&attrs, "FRAME-RATE")
                .and_then(|f| f.parse().ok())
                .unwrap_or(0.0);
            let res = attr(&attrs, "RESOLUTION")
                .and_then(|r| r.split_once('x'))
                .and_then(|(w, h)| Some(w.parse::<u32>().ok()?.min(h.parse().ok()?)));
            let ok = attr(&attrs, "CODECS").is_some_and(codecs_ok) && fps <= max_fps;
            if let (true, Some(res)) = (ok, res) {
                variants.push(Variant {
                    inf: line,
                    uri,
                    res,
                    audio: attr(&attrs, "AUDIO"),
                });
            }
        } else if let Some(list) = line.strip_prefix("#EXT-X-MEDIA:") {
            let attrs = attributes(list);
            if attr(&attrs, "TYPE") == Some("AUDIO")
                && let Some(group) = attr(&attrs, "GROUP-ID")
            {
                audio_media.push((group, line));
            }
        } else if line.starts_with('#') {
            header.push(line);
        }
    }

    let fitting: Vec<&Variant> = variants.iter().filter(|v| v.res <= max_res).collect();
    // Nothing small enough: fall back to the smallest playable variant rather than failing
    let best = match fitting.iter().map(|v| v.res).max() {
        Some(best) => best,
        None => variants.iter().map(|v| v.res).min()?,
    };
    let kept: Vec<&Variant> = variants.iter().filter(|v| v.res == best).collect();

    let mut out = String::new();
    for line in &header {
        out.push_str(line);
        out.push('\n');
    }
    for (group, line) in &audio_media {
        if kept.iter().any(|v| v.audio == Some(*group)) {
            out.push_str(line);
            out.push('\n');
        }
    }
    for v in kept {
        out.push_str(&strip_subtitles(v.inf));
        out.push('\n');
        out.push_str(v.uri);
        out.push('\n');
    }
    Some(out)
}

/// Removes a `SUBTITLES="..."` attribute (its renditions are dropped).
fn strip_subtitles(inf: &str) -> String {
    match inf.find(",SUBTITLES=\"") {
        Some(start) => {
            let rest = &inf[start + 12..];
            let end = rest.find('"').map_or(inf.len(), |e| start + 12 + e + 1);
            format!("{}{}", &inf[..start], &inf[end..])
        }
        None => inf.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const MASTER_BBB: &str = include_str!("../../tests/fixtures/hls_master_1.m3u8");
    const MASTER_MUSIC: &str = include_str!("../../tests/fixtures/hls_master_2.m3u8");

    fn infs(p: &str) -> Vec<String> {
        p.lines()
            .filter(|l| l.starts_with("#EXT-X-STREAM-INF"))
            .map(|l| {
                let a = attributes(&l["#EXT-X-STREAM-INF:".len()..]);
                format!(
                    "{} {} {}",
                    attr(&a, "RESOLUTION").unwrap_or(""),
                    attr(&a, "CODECS").unwrap_or(""),
                    attr(&a, "FRAME-RATE").unwrap_or("")
                )
            })
            .collect()
    }

    #[test]
    fn attribute_parser_keeps_quoted_commas() {
        let a =
            attributes(r#"URI="https://x/rms/aub,aub/y",TYPE=AUDIO,GROUP-ID="234",DEFAULT=YES"#);
        assert_eq!(attr(&a, "URI"), Some("https://x/rms/aub,aub/y"));
        assert_eq!(attr(&a, "GROUP-ID"), Some("234"));
        assert_eq!(attr(&a, "DEFAULT"), Some("YES"));
    }

    #[test]
    fn music_720_keeps_only_avc_720() {
        let p = filter_master(MASTER_MUSIC, 720, 30.0).unwrap();
        assert!(p.starts_with("#EXTM3U\n"));
        assert_eq!(infs(&p), ["1280x720 avc1.4D401F,mp4a.40.2 24"]);
        assert!(!p.contains("vp09"));
        // Only the audio group used by the kept variant (234), and every variant has its URI line
        let media: Vec<_> = p
            .lines()
            .filter(|l| l.starts_with("#EXT-X-MEDIA"))
            .collect();
        assert_eq!(media.len(), 1);
        assert!(media[0].contains("GROUP-ID=\"234\""));
        let lines: Vec<_> = p.lines().collect();
        let i = lines
            .iter()
            .position(|l| l.starts_with("#EXT-X-STREAM-INF"))
            .unwrap();
        assert!(lines[i + 1].starts_with("https://manifest.googlevideo.com/"));
    }

    #[test]
    fn lower_caps() {
        assert_eq!(
            infs(&filter_master(MASTER_MUSIC, 480, 30.0).unwrap()),
            ["854x480 avc1.4D401E,mp4a.40.2 24"]
        );
        assert_eq!(
            infs(&filter_master(MASTER_MUSIC, 360, 30.0).unwrap()),
            ["640x360 avc1.4D401E,mp4a.40.2 24"]
        );
    }

    #[test]
    fn sixty_fps_variants_are_dropped() {
        // Big Buck Bunny: 720p/1080p exist only at 60 fps → best ≤30 fps variant is 480p
        let p = filter_master(MASTER_BBB, 720, 30.0).unwrap();
        assert_eq!(infs(&p), ["854x480 avc1.4D401F,mp4a.40.2 30"]);
        // Allowing 60 fps keeps the 720p60 variant
        let p60 = filter_master(MASTER_BBB, 720, 60.0).unwrap();
        assert_eq!(infs(&p60), ["1280x720 avc1.4D4020,mp4a.40.2 60"]);
    }

    #[test]
    fn falls_back_to_smallest_when_cap_is_tiny() {
        let p = filter_master(MASTER_MUSIC, 100, 30.0).unwrap();
        assert_eq!(infs(&p), ["256x144 avc1.4D400C,mp4a.40.5 24"]);
    }

    #[test]
    fn rejects_garbage_and_vp9_only() {
        assert!(filter_master("<html>", 720, 30.0).is_none());
        let vp9 = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS=\"vp09.00.31.08,mp4a.40.2\",RESOLUTION=1280x720\nhttps://x\n";
        assert!(filter_master(vp9, 720, 30.0).is_none());
    }

    #[test]
    fn strips_subtitle_groups() {
        assert_eq!(
            strip_subtitles(r#"#EXT-X-STREAM-INF:BANDWIDTH=1,SUBTITLES="s1",AUDIO="a""#),
            r#"#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="a""#
        );
    }
}
