use std::time::Duration;

use serde::Deserialize;

use crate::algo::lrc::LyricsKind;
use crate::algo::lyrics_verifier::{best, LyricsCandidate, LyricsQuery};

use super::{get_text, RateLimiter};

const BASE: &str = "https://lrclib.net/api";

#[derive(Debug, Clone)]
pub struct FoundLyrics {
    pub kind: LyricsKind,
    pub lrc: Option<String>,
    pub plain: Option<String>,
    pub source: String,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct LrclibItem {
    track_name: Option<String>,
    artist_name: Option<String>,
    duration: Option<f64>,
    instrumental: Option<bool>,
    plain_lyrics: Option<String>,
    synced_lyrics: Option<String>,
}

fn candidate(item: LrclibItem) -> Option<LyricsCandidate> {
    Some(LyricsCandidate {
        track_name: item.track_name?,
        artist_name: item.artist_name?,
        duration: item.duration,
        synced: item.synced_lyrics,
        plain: item.plain_lyrics,
        instrumental: item.instrumental.unwrap_or(false),
    })
}

pub async fn fetch(
    http: &reqwest::Client,
    limiter: &RateLimiter,
    title: &str,
    artist: &str,
    album: Option<&str>,
    duration: Option<f64>,
) -> Option<FoundLyrics> {
    let query = LyricsQuery { title: title.to_string(), artist: artist.to_string(), duration };
    let mut candidates: Vec<LyricsCandidate> = Vec::new();
    if let Some(exact) = get(http, limiter, title, artist, album, duration).await {
        candidates.push(exact);
    }
    if best(&candidates, &query).is_none() {
        candidates.extend(search(http, limiter, &[("track_name", title), ("artist_name", artist)]).await);
        if best(&candidates, &query).is_none() {
            let joined = format!("{artist} {title}");
            candidates.extend(search(http, limiter, &[("q", joined.as_str())]).await);
        }
    }
    let (winner, kind) = best(&candidates, &query)?;
    if kind == LyricsKind::Plain {
        return Some(FoundLyrics { kind, lrc: None, plain: winner.plain, source: "lrclib-verified".into() });
    }
    Some(FoundLyrics { kind, lrc: winner.synced, plain: winner.plain, source: "lrclib-verified".into() })
}

async fn get(
    http: &reqwest::Client,
    limiter: &RateLimiter,
    title: &str,
    artist: &str,
    album: Option<&str>,
    duration: Option<f64>,
) -> Option<LyricsCandidate> {
    let mut params: Vec<(&str, String)> = vec![("track_name", title.to_string()), ("artist_name", artist.to_string())];
    if let Some(album) = album.filter(|album| !album.is_empty()) {
        params.push(("album_name", album.to_string()));
    }
    if let Some(duration) = duration {
        params.push(("duration", format!("{}", duration.round() as i64)));
    }
    let url = url::Url::parse_with_params(&format!("{BASE}/get"), params).ok()?;
    limiter.wait("lrclib", Duration::from_millis(350)).await;
    let text = get_text(http, url.as_str(), None).await.ok()?;
    candidate(serde_json::from_str::<LrclibItem>(&text).ok()?)
}

async fn search(http: &reqwest::Client, limiter: &RateLimiter, params: &[(&str, &str)]) -> Vec<LyricsCandidate> {
    let Ok(url) = url::Url::parse_with_params(&format!("{BASE}/search"), params) else {
        return Vec::new();
    };
    limiter.wait("lrclib", Duration::from_millis(350)).await;
    let Ok(text) = get_text(http, url.as_str(), None).await else {
        return Vec::new();
    };
    serde_json::from_str::<Vec<LrclibItem>>(&text).map(|list| list.into_iter().filter_map(candidate).collect()).unwrap_or_default()
}
