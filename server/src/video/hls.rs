//! Filtering of YouTube's HLS master playlist for iOS 6.
//!
//! Same rules as the TubeRepair server (`modules/yt.py`, `data_to_hls_url`): keep only H.264 + AAC
//! variants, at most 30 fps, at most `max_res` (the short side, so vertical videos work), and then
//! only the highest remaining resolution, so the old player cannot get stuck on a low-quality
//! variant. Audio renditions are kept only for the groups the remaining variants use, and within a
//! group only **one**: the original-language track (YouTube adds AI-dubbed tracks such as
//! "American English - dubbed-auto" and the iPad would otherwise pick one of those), forced to
//! DEFAULT=YES. Subtitle renditions are dropped. Variant and segment URLs stay absolute googlevideo URLs.

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
    let mut groups: Vec<&str> = kept.iter().filter_map(|v| v.audio).collect();
    groups.dedup();
    for group in groups {
        let candidates: Vec<&str> = audio_media
            .iter()
            .filter(|(g, _)| *g == group)
            .map(|(_, l)| *l)
            .collect();
        if let Some(line) = pick_audio(&candidates) {
            out.push_str(&as_default(line));
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

/// Audio-only master playlist: one variant pointing at YouTube's audio rendition (original
/// language), AAC-LC 128k (group 234) when present, else HE-AAC (233), else any audio group.
pub fn audio_master(master: &str) -> Option<String> {
    if !master.trim_start().starts_with("#EXTM3U") {
        return None;
    }
    let mut groups: Vec<(&str, Vec<&str>)> = Vec::new();
    for line in master.lines().map(str::trim) {
        let Some(list) = line.strip_prefix("#EXT-X-MEDIA:") else {
            continue;
        };
        let attrs = attributes(list);
        if attr(&attrs, "TYPE") != Some("AUDIO") || attr(&attrs, "URI").is_none() {
            continue;
        }
        let group = attr(&attrs, "GROUP-ID").unwrap_or("");
        match groups.iter_mut().find(|(g, _)| *g == group) {
            Some((_, lines)) => lines.push(line),
            None => groups.push((group, vec![line])),
        }
    }
    let (group, lines) = ["234", "233"]
        .iter()
        .find_map(|want| groups.iter().find(|(g, _)| g == want))
        .or_else(|| groups.first())?;
    let line = pick_audio(lines)?;
    let attrs = attributes(line.strip_prefix("#EXT-X-MEDIA:").unwrap_or(line));
    let uri = attr(&attrs, "URI")?;
    let (bandwidth, codecs) = if *group == "233" {
        (64_000, "mp4a.40.5")
    } else {
        (144_000, "mp4a.40.2")
    };
    Some(format!(
        "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH={bandwidth},CODECS=\"{codecs}\"\n{uri}\n"
    ))
}

/// Rewrites every URI of a playlist with `f`: the URI lines and the `URI="…"` attributes of tags.
pub fn map_uris(playlist: &str, f: impl Fn(&str) -> String) -> String {
    let mut out = String::with_capacity(playlist.len() * 2);
    for line in playlist.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if !trimmed.starts_with('#') {
            out.push_str(&f(trimmed));
        } else if let Some(start) = trimmed.find("URI=\"") {
            let value_start = start + 5;
            match trimmed[value_start..].find('"') {
                Some(len) => {
                    out.push_str(&trimmed[..value_start]);
                    out.push_str(&f(&trimmed[value_start..value_start + len]));
                    out.push_str(&trimmed[value_start + len..]);
                }
                None => out.push_str(trimmed),
            }
        } else {
            out.push_str(trimmed);
        }
        out.push('\n');
    }
    out
}

/// Is this audio rendition YouTube's original-language track (not a dub)?
fn is_original(line: &str) -> bool {
    let attrs = attributes(line.strip_prefix("#EXT-X-MEDIA:").unwrap_or(line));
    let name = attr(&attrs, "NAME").unwrap_or("").to_lowercase();
    name.contains("original")
}

fn is_dubbed(line: &str) -> bool {
    let attrs = attributes(line.strip_prefix("#EXT-X-MEDIA:").unwrap_or(line));
    attr(&attrs, "NAME")
        .unwrap_or("")
        .to_lowercase()
        .contains("dubbed")
}

/// The rendition to keep: the original track, else a non-dubbed one, else DEFAULT=YES, else the first.
fn pick_audio<'a>(candidates: &[&'a str]) -> Option<&'a str> {
    candidates
        .iter()
        .find(|l| is_original(l))
        .or_else(|| candidates.iter().find(|l| !is_dubbed(l)))
        .or_else(|| candidates.iter().find(|l| l.contains("DEFAULT=YES")))
        .or_else(|| candidates.first())
        .copied()
}

/// The single rendition of its group must be the default and auto-selected.
fn as_default(line: &str) -> String {
    let mut out = line
        .replace("DEFAULT=NO", "DEFAULT=YES")
        .replace("AUTOSELECT=NO", "AUTOSELECT=YES");
    if !out.contains("DEFAULT=") {
        out.push_str(",DEFAULT=YES");
    }
    if !out.contains("AUTOSELECT=") {
        out.push_str(",AUTOSELECT=YES");
    }
    out
}

/// Short-side resolution of the best variant in a (filtered) master playlist, e.g. 720.
pub fn best_height(playlist: &str) -> Option<u32> {
    playlist
        .lines()
        .filter_map(|l| l.strip_prefix("#EXT-X-STREAM-INF:"))
        .filter_map(|list| {
            let (w, h) = attr(&attributes(list), "RESOLUTION")?.split_once('x')?;
            Some(w.parse::<u32>().ok()?.min(h.parse().ok()?))
        })
        .max()
}

/// Highest BANDWIDTH (bit/s) among the variants of a (filtered) master playlist.
pub fn best_bandwidth(playlist: &str) -> Option<u64> {
    playlist
        .lines()
        .filter_map(|l| l.strip_prefix("#EXT-X-STREAM-INF:"))
        .filter_map(|list| attr(&attributes(list), "BANDWIDTH")?.parse().ok())
        .max()
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
    fn best_height_of_filtered_playlists() {
        assert_eq!(
            best_height(&filter_master(MASTER_MUSIC, 720, 30.0).unwrap()),
            Some(720)
        );
        assert_eq!(
            best_height(&filter_master(MASTER_BBB, 720, 30.0).unwrap()),
            Some(480)
        );
        assert_eq!(
            best_height(
                "#EXTM3U
"
            ),
            None
        );
    }

    #[test]
    fn bandwidth_of_the_kept_variant() {
        assert_eq!(
            best_bandwidth(&filter_master(MASTER_MUSIC, 1080, 30.0).unwrap()),
            Some(3_899_199)
        );
        assert_eq!(
            best_bandwidth(&filter_master(MASTER_MUSIC, 720, 30.0).unwrap()),
            Some(1_251_049)
        );
        assert_eq!(best_bandwidth("#EXTM3U\n"), None);
    }

    #[test]
    fn level_1080_keeps_the_high_profile_30fps_variant() {
        // avc1.640028 = High profile level 4.0, within the A5's H.264 limit (High 4.1, 1080p30)
        let p = filter_master(MASTER_MUSIC, 1080, 30.0).unwrap();
        assert_eq!(infs(&p), ["1920x1080 avc1.640028,mp4a.40.2 24"]);
        assert_eq!(best_height(&p), Some(1080));
        // 1080p exists only at 60 fps: the 1080 level ends up at the same 480p as the 720 level
        let bbb = filter_master(MASTER_BBB, 1080, 30.0).unwrap();
        assert_eq!(best_height(&bbb), Some(480));
    }

    const MASTER_DUBBED: &str = include_str!("../../tests/fixtures/hls_master_dubbed.m3u8");

    #[test]
    fn keeps_only_the_original_audio_track() {
        // Vietnamese news with an "American English - dubbed-auto" track listed first
        let p = filter_master(MASTER_DUBBED, 720, 30.0).unwrap();
        let media: Vec<_> = p
            .lines()
            .filter(|l| l.starts_with("#EXT-X-MEDIA"))
            .collect();
        assert_eq!(media.len(), 1, "{media:#?}");
        assert!(media[0].contains("NAME=\"Tiếng Việt - original\""));
        assert!(media[0].contains("DEFAULT=YES") && media[0].contains("AUTOSELECT=YES"));
        assert!(!p.contains("dubbed"));
    }

    #[test]
    fn audio_only_master_uses_the_original_aac_lc_track() {
        let p = audio_master(MASTER_DUBBED).unwrap();
        let lines: Vec<_> = p.lines().collect();
        assert_eq!(lines[0], "#EXTM3U");
        assert_eq!(
            lines[1],
            "#EXT-X-STREAM-INF:BANDWIDTH=144000,CODECS=\"mp4a.40.2\""
        );
        assert!(
            lines[2].starts_with("https://manifest.googlevideo.com/")
                && lines[2].contains("/itag/234/")
        );
        assert_eq!(lines.len(), 3);
        // The Vietnamese original, not the English dub listed first
        let original = MASTER_DUBBED
            .lines()
            .find(|l| l.contains("GROUP-ID=\"234\"") && l.contains("original"))
            .unwrap();
        assert!(original.contains(lines[2]));
        assert!(audio_master("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nx\n").is_none());
    }

    #[test]
    fn map_uris_rewrites_lines_and_attributes() {
        let src = "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,URI=\"https://a/1.m3u8\",NAME=\"x\"\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://b/2.m3u8\n\n#EXT-X-ENDLIST\n";
        let out = map_uris(src, |u| format!("P({u})"));
        assert_eq!(
            out,
            "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,URI=\"P(https://a/1.m3u8)\",NAME=\"x\"\n#EXT-X-STREAM-INF:BANDWIDTH=1\nP(https://b/2.m3u8)\n#EXT-X-ENDLIST\n"
        );
    }

    #[test]
    fn audio_pick_order() {
        let dub =
            "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"1\",NAME=\"English - dubbed-auto\",DEFAULT=YES";
        let plain = "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"1\",NAME=\"Default\",DEFAULT=NO";
        assert_eq!(pick_audio(&[dub, plain]), Some(plain));
        assert_eq!(pick_audio(&[dub]), Some(dub));
        assert_eq!(
            as_default(plain),
            "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"1\",NAME=\"Default\",DEFAULT=YES,AUTOSELECT=YES"
        );
    }

    #[test]
    fn strips_subtitle_groups() {
        assert_eq!(
            strip_subtitles(r#"#EXT-X-STREAM-INF:BANDWIDTH=1,SUBTITLES="s1",AUDIO="a""#),
            r#"#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="a""#
        );
    }
}
