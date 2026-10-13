use std::sync::Arc;
use std::time::Duration;

use futures_util::future::BoxFuture;
use serde::Deserialize;

use crate::algo::text_matching::{artist_ratio, strip_featuring, title_ratio};

use super::{get_bytes, get_text, RateLimiter};

#[derive(Debug, Clone, Default)]
pub struct CatalogMatch {
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub year: Option<i32>,
    pub genre: Option<String>,
    pub isrc: Option<String>,
    pub cover_url: Option<String>,
    pub duration_seconds: Option<f64>,
    pub source: String,
}

#[derive(Debug, Clone, Default)]
pub struct CatalogQuery {
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub duration: Option<f64>,
}

pub type LookupFn = Arc<dyn Fn(CatalogQuery) -> BoxFuture<'static, Option<CatalogMatch>> + Send + Sync>;
pub type CoverFn = Arc<dyn Fn(String) -> BoxFuture<'static, Option<Vec<u8>>> + Send + Sync>;

#[derive(Clone)]
pub struct Catalog {
    pub lookup: LookupFn,
    pub cover: CoverFn,
}

impl Catalog {
    pub fn network(http: reqwest::Client, limiter: Arc<RateLimiter>) -> Self {
        let lookup_http = http.clone();
        let lookup_limiter = limiter.clone();
        let lookup: LookupFn = Arc::new(move |query| {
            let http = lookup_http.clone();
            let limiter = lookup_limiter.clone();
            Box::pin(async move { lookup(&http, &limiter, &query).await })
        });
        let cover: CoverFn = Arc::new(move |url| {
            let http = http.clone();
            Box::pin(async move { get_bytes(&http, &url, None).await.ok() })
        });
        Self { lookup, cover }
    }
}

#[derive(Deserialize, Default)]
struct ITunesResponse {
    #[serde(default)]
    results: Vec<ITunesItem>,
}

#[derive(Deserialize, Default, Clone)]
#[serde(rename_all = "camelCase")]
struct ITunesItem {
    wrapper_type: Option<String>,
    track_name: Option<String>,
    artist_name: Option<String>,
    collection_name: Option<String>,
    track_time_millis: Option<i64>,
    track_number: Option<u32>,
    disc_number: Option<u32>,
    release_date: Option<String>,
    primary_genre_name: Option<String>,
    artwork_url100: Option<String>,
}

#[derive(Deserialize, Default)]
struct DeezerSearch {
    #[serde(default)]
    data: Vec<DeezerTrack>,
}

#[derive(Deserialize, Default, Clone)]
struct DeezerArtist {
    #[serde(default)]
    name: String,
}

#[derive(Deserialize, Default, Clone)]
struct DeezerAlbumRef {
    id: Option<i64>,
    title: Option<String>,
    cover_xl: Option<String>,
}

#[derive(Deserialize, Default, Clone)]
struct DeezerTrack {
    #[serde(default)]
    id: i64,
    #[serde(default)]
    title: String,
    duration: Option<i64>,
    #[serde(default)]
    artist: DeezerArtist,
    album: Option<DeezerAlbumRef>,
    track_position: Option<u32>,
    disk_number: Option<u32>,
    release_date: Option<String>,
    isrc: Option<String>,
}

#[derive(Deserialize, Default)]
struct DeezerGenre {
    #[serde(default)]
    name: String,
}

#[derive(Deserialize, Default)]
struct DeezerGenres {
    #[serde(default)]
    data: Vec<DeezerGenre>,
}

#[derive(Deserialize, Default)]
struct DeezerAlbumFull {
    release_date: Option<String>,
    genres: Option<DeezerGenres>,
}

pub fn score(query: &CatalogQuery, title: &str, artist: &str, duration: Option<f64>) -> Option<f64> {
    let title_score = title_ratio(&query.title, title);
    let artist_known = !query.artist.is_empty();
    if title_score < if artist_known { 0.85 } else { 0.95 } {
        return None;
    }
    let mut artist_score = 1.0;
    if artist_known {
        artist_score = artist_ratio(&query.artist, artist);
        if artist_score < 0.8 {
            return None;
        }
    }
    let mut penalty = 0.0;
    if let (Some(wanted), Some(got)) = (query.duration, duration) {
        let diff = (wanted - got).abs();
        if diff > if artist_known { 4.0 } else { 2.0 } {
            return None;
        }
        penalty = diff * 0.02;
    }
    Some(title_score + artist_score - penalty)
}

fn year_of(text: &Option<String>) -> Option<i32> {
    let text = text.as_ref()?;
    if text.len() < 4 {
        return None;
    }
    text.get(..4)?.parse().ok()
}

fn artwork_url(small: &Option<String>) -> Option<String> {
    small.as_ref().map(|url| url.replace("100x100bb", "1400x1400bb"))
}

fn search_term(query: &CatalogQuery) -> String {
    let artist = strip_featuring(&query.artist);
    let title = strip_featuring(&query.title);
    [artist, title].into_iter().filter(|part| !part.is_empty()).collect::<Vec<_>>().join(" ")
}

pub async fn lookup(http: &reqwest::Client, limiter: &RateLimiter, query: &CatalogQuery) -> Option<CatalogMatch> {
    let apple = itunes(http, limiter, query).await;
    if let Some(found) = &apple {
        if found.album.is_some() {
            return apple;
        }
    }
    if let Some(found) = deezer(http, limiter, query).await {
        return Some(found);
    }
    apple
}

async fn itunes(http: &reqwest::Client, limiter: &RateLimiter, query: &CatalogQuery) -> Option<CatalogMatch> {
    for country in ["us", "ru"] {
        limiter.wait("itunes", Duration::from_millis(3200)).await;
        let term = search_term(query);
        let Ok(url) = url::Url::parse_with_params(
            "https://itunes.apple.com/search",
            &[("term", term.as_str()), ("media", "music"), ("entity", "song"), ("limit", "10"), ("country", country)],
        ) else {
            continue;
        };
        let Ok(text) = get_text(http, url.as_str(), None).await else {
            continue;
        };
        let Ok(response) = serde_json::from_str::<ITunesResponse>(&text) else {
            continue;
        };
        let mut best: Option<(ITunesItem, f64)> = None;
        for item in response.results {
            if item.wrapper_type.as_deref() != Some("track") {
                continue;
            }
            let (Some(title), Some(artist)) = (item.track_name.clone(), item.artist_name.clone()) else {
                continue;
            };
            let duration = item.track_time_millis.map(|millis| millis as f64 / 1000.0);
            let Some(value) = score(query, &title, &artist, duration) else {
                continue;
            };
            if best.as_ref().map(|current| value > current.1).unwrap_or(true) {
                best = Some((item, value));
            }
        }
        if let Some((item, _)) = best {
            return Some(CatalogMatch {
                title: item.track_name.unwrap_or_else(|| query.title.clone()),
                artist: item.artist_name.unwrap_or_else(|| query.artist.clone()),
                album: item.collection_name,
                album_artist: None,
                track_number: item.track_number,
                disc_number: item.disc_number,
                year: year_of(&item.release_date),
                genre: item.primary_genre_name,
                isrc: None,
                cover_url: artwork_url(&item.artwork_url100),
                duration_seconds: item.track_time_millis.map(|millis| millis as f64 / 1000.0),
                source: "itunes".into(),
            });
        }
    }
    None
}

async fn deezer(http: &reqwest::Client, limiter: &RateLimiter, query: &CatalogQuery) -> Option<CatalogMatch> {
    limiter.wait("deezer", Duration::from_millis(250)).await;
    let artist = strip_featuring(&query.artist);
    let title = strip_featuring(&query.title);
    let term = if artist.is_empty() { title.clone() } else { format!("artist:\"{artist}\" track:\"{title}\"") };
    let url = url::Url::parse_with_params("https://api.deezer.com/search", &[("q", term.as_str()), ("limit", "10")]).ok()?;
    let text = get_text(http, url.as_str(), None).await.ok()?;
    let response: DeezerSearch = serde_json::from_str(&text).ok()?;
    let mut best: Option<(DeezerTrack, f64)> = None;
    for item in response.data {
        let Some(value) = score(query, &item.title, &item.artist.name, item.duration.map(|seconds| seconds as f64)) else {
            continue;
        };
        if best.as_ref().map(|current| value > current.1).unwrap_or(true) {
            best = Some((item, value));
        }
    }
    let (candidate, _) = best?;
    limiter.wait("deezer", Duration::from_millis(250)).await;
    let mut full = candidate.clone();
    if let Ok(text) = get_text(http, &format!("https://api.deezer.com/track/{}", candidate.id), None).await {
        if let Ok(detail) = serde_json::from_str::<DeezerTrack>(&text) {
            full = detail;
        }
    }
    let mut genre = None;
    let mut release_date = full.release_date.clone();
    let album_id = full.album.as_ref().and_then(|album| album.id).or_else(|| candidate.album.as_ref().and_then(|album| album.id));
    if let Some(album_id) = album_id {
        limiter.wait("deezer", Duration::from_millis(250)).await;
        if let Ok(text) = get_text(http, &format!("https://api.deezer.com/album/{album_id}"), None).await {
            if let Ok(album) = serde_json::from_str::<DeezerAlbumFull>(&text) {
                genre = album.genres.and_then(|genres| genres.data.into_iter().next()).map(|genre| genre.name);
                release_date = release_date.or(album.release_date);
            }
        }
    }
    let album_title = full.album.as_ref().and_then(|album| album.title.clone()).or_else(|| candidate.album.as_ref().and_then(|album| album.title.clone()));
    let cover = full.album.as_ref().and_then(|album| album.cover_xl.clone()).or_else(|| candidate.album.as_ref().and_then(|album| album.cover_xl.clone()));
    Some(CatalogMatch {
        title: full.title,
        artist: full.artist.name,
        album: album_title,
        album_artist: None,
        track_number: full.track_position,
        disc_number: full.disk_number,
        year: year_of(&release_date),
        genre,
        isrc: full.isrc,
        cover_url: cover,
        duration_seconds: full.duration.map(|seconds| seconds as f64),
        source: "deezer".into(),
    })
}
