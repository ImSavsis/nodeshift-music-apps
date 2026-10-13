use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Deserialize;
use serde_json::Value;

use crate::algo::text_matching::{artist_ratio, title_ratio};

use super::{download, get_text, RateLimiter, BROWSER_AGENT};

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct AppleAlbumResponse {
    #[serde(default)]
    results: Vec<AppleAlbum>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct AppleAlbum {
    collection_name: Option<String>,
    artist_name: Option<String>,
    collection_view_url: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct MotionFiles {
    pub square: Option<PathBuf>,
    pub tall: Option<PathBuf>,
}

#[derive(Debug, Clone)]
pub struct Variant {
    pub url: String,
    pub width: i64,
    pub bandwidth: i64,
}

pub async fn find(
    http: &reqwest::Client,
    limiter: &RateLimiter,
    artist: &str,
    album: &str,
    directory: &Path,
    key: &str,
) -> Option<MotionFiles> {
    if album.is_empty() {
        return None;
    }
    let pages = candidate_pages(http, limiter, artist, album).await;
    for page in pages.iter().take(6) {
        let Some((square, tall)) = motion_urls(http, limiter, page).await else {
            continue;
        };
        let mut files = MotionFiles::default();
        if let Some(square) = square {
            files.square = fetch_best(http, &square, &directory.join(format!("{key}.mp4"))).await;
        }
        if let Some(tall) = tall {
            files.tall = fetch_best(http, &tall, &directory.join(format!("{key}-tall.mp4"))).await;
        }
        if files.square.is_some() || files.tall.is_some() {
            return Some(files);
        }
    }
    None
}

async fn candidate_pages(http: &reqwest::Client, limiter: &RateLimiter, artist: &str, album: &str) -> Vec<String> {
    let mut pages = Vec::new();
    for country in ["us", "ru"] {
        limiter.wait("itunes", Duration::from_millis(3200)).await;
        let term = format!("{artist} {album}");
        let Ok(url) = url::Url::parse_with_params(
            "https://itunes.apple.com/search",
            &[("term", term.as_str()), ("media", "music"), ("entity", "album"), ("limit", "12"), ("country", country)],
        ) else {
            continue;
        };
        let Ok(text) = get_text(http, url.as_str(), None).await else {
            continue;
        };
        let Ok(response) = serde_json::from_str::<AppleAlbumResponse>(&text) else {
            continue;
        };
        for item in response.results {
            let (Some(name), Some(singer), Some(link)) = (item.collection_name, item.artist_name, item.collection_view_url) else {
                continue;
            };
            if title_ratio(album, &name) >= 0.8 && artist_ratio(artist, &singer) >= 0.7 {
                pages.push(link);
            }
        }
        if !pages.is_empty() {
            break;
        }
    }
    pages
}

pub fn collect_videos(node: &Value, found: &mut std::collections::HashMap<String, String>) {
    match node {
        Value::Object(map) => {
            for (key, value) in map {
                let video = value.get("video").and_then(|video| video.as_str()).map(String::from);
                if (key == "motionDetailSquare" || key == "motionSquareVideo1x1") && video.is_some() && !found.contains_key("square") {
                    found.insert("square".into(), video.unwrap());
                } else if (key == "motionDetailTall" || key == "motionTallVideo3x4") && video.is_some() && !found.contains_key("tall") {
                    found.insert("tall".into(), video.unwrap());
                } else {
                    collect_videos(value, found);
                }
            }
        }
        Value::Array(items) => {
            for item in items {
                collect_videos(item, found);
            }
        }
        _ => {}
    }
}

async fn motion_urls(http: &reqwest::Client, limiter: &RateLimiter, page: &str) -> Option<(Option<String>, Option<String>)> {
    limiter.wait("applepage", Duration::from_millis(1500)).await;
    let html = get_text(http, page, Some(BROWSER_AGENT)).await.ok()?;
    let marker = html.find("id=\"serialized-server-data\"")?;
    let start = html[marker..].find('>')? + marker;
    let end = html[start..].find("</script>")? + start;
    let value: Value = serde_json::from_str(&html[start + 1..end]).ok()?;
    let mut found = std::collections::HashMap::new();
    collect_videos(&value, &mut found);
    let square = found.get("square").cloned();
    let tall = found.get("tall").cloned();
    if square.is_none() && tall.is_none() {
        return None;
    }
    Some((square, tall))
}

fn resolve(base: &str, link: &str) -> Option<String> {
    let base = url::Url::parse(base).ok()?;
    base.join(link).ok().map(|joined| joined.to_string())
}

fn number_after(line: &str, marker: &str) -> i64 {
    let Some(position) = line.find(marker) else {
        return 0;
    };
    line[position + marker.len()..].chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse().unwrap_or(0)
}

pub fn parse_variants(master: &str, base: &str) -> Vec<Variant> {
    let mut variants = Vec::new();
    let lines: Vec<&str> = master.lines().collect();
    let mut index = 0;
    while index < lines.len() {
        let line = lines[index];
        if line.starts_with("#EXT-X-STREAM-INF:") && line.contains("avc1") && index + 1 < lines.len() {
            let uri = lines[index + 1].trim();
            let width = number_after(line, "RESOLUTION=");
            let bandwidth = if line.contains(",BANDWIDTH=") { number_after(line, ",BANDWIDTH=") } else { number_after(line, ":BANDWIDTH=") };
            if let Some(url) = resolve(base, uri) {
                if width > 0 {
                    variants.push(Variant { url, width, bandwidth });
                }
            }
            index += 2;
            continue;
        }
        index += 1;
    }
    variants
}

pub fn pick_variant(variants: &[Variant]) -> Option<Variant> {
    let usable: Vec<&Variant> = variants.iter().filter(|variant| (480..=1100).contains(&variant.width)).collect();
    let pool: Vec<&Variant> = if usable.is_empty() { variants.iter().collect() } else { usable };
    pool.into_iter()
        .min_by_key(|variant| ((variant.width - 960).abs(), variant.bandwidth))
        .cloned()
}

pub fn map_uri(playlist: &str, base: &str) -> Option<String> {
    for line in playlist.lines() {
        if !line.starts_with("#EXT-X-MAP:") {
            continue;
        }
        let Some(start) = line.find("URI=\"") else {
            continue;
        };
        let rest = &line[start + 5..];
        let Some(close) = rest.find('"') else {
            continue;
        };
        return resolve(base, &rest[..close]);
    }
    for line in playlist.lines() {
        let trimmed = line.trim();
        if !trimmed.is_empty() && !trimmed.starts_with('#') {
            return resolve(base, trimmed);
        }
    }
    None
}

async fn fetch_best(http: &reqwest::Client, master: &str, destination: &Path) -> Option<PathBuf> {
    let master_text = get_text(http, master, Some(BROWSER_AGENT)).await.ok()?;
    let variant = pick_variant(&parse_variants(&master_text, master))?;
    let variant_text = get_text(http, &variant.url, Some(BROWSER_AGENT)).await.ok()?;
    let file_url = map_uri(&variant_text, &variant.url)?;
    download(http, &file_url, destination, Some(BROWSER_AGENT)).await.ok()?;
    let data = tokio::fs::read(destination).await.ok()?;
    if data.len() <= 100_000 || data.len() < 8 || &data[4..8] != b"ftyp" {
        let _ = tokio::fs::remove_file(destination).await;
        return None;
    }
    Some(destination.to_path_buf())
}
