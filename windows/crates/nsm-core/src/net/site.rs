use std::sync::{Arc, Mutex};

use anyhow::{anyhow, Result};
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::{json, Value};

pub const BASE: &str = "https://music.nodeshift.space";
pub const MEDIA: &str = "https://burmalda.savsis.xyz";

pub trait TokenStore: Send + Sync {
    fn get(&self, key: &str) -> Option<String>;
    fn set(&self, key: &str, value: &str);
    fn remove(&self, key: &str);
}

#[derive(Default)]
pub struct MemoryTokenStore {
    values: Mutex<std::collections::HashMap<String, String>>,
}

impl TokenStore for MemoryTokenStore {
    fn get(&self, key: &str) -> Option<String> {
        self.values.lock().ok()?.get(key).cloned()
    }

    fn set(&self, key: &str, value: &str) {
        if let Ok(mut map) = self.values.lock() {
            map.insert(key.to_string(), value.to_string());
        }
    }

    fn remove(&self, key: &str) {
        if let Ok(mut map) = self.values.lock() {
            map.remove(key);
        }
    }
}

fn flexible_id<'de, D: Deserializer<'de>>(deserializer: D) -> std::result::Result<String, D::Error> {
    let value = Value::deserialize(deserializer)?;
    match value {
        Value::String(text) => Ok(text),
        Value::Number(number) => Ok(number.to_string()),
        other => Err(serde::de::Error::custom(format!("bad id {other}"))),
    }
}

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SiteUser {
    #[serde(deserialize_with = "flexible_id", default)]
    pub id: String,
    pub email: Option<String>,
    pub username: Option<String>,
    pub handle: Option<String>,
    #[serde(alias = "avatar_url")]
    pub avatar_url: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct SiteTrack {
    #[serde(deserialize_with = "flexible_id", default)]
    pub id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub artist: String,
    pub album: Option<String>,
    pub duration_seconds: Option<f64>,
    #[serde(default)]
    pub filename: String,
    pub cover_filename: Option<String>,
    pub motion_filename: Option<String>,
    pub stream_filename: Option<String>,
    pub format: Option<String>,
    pub play_count: Option<i64>,
    pub media_kind: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SitePlaylist {
    #[serde(deserialize_with = "flexible_id", default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(alias = "cover_filename")]
    pub cover_filename: Option<String>,
    #[serde(alias = "track_count")]
    pub track_count: Option<i64>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct SitePlaylistEntry {
    #[serde(default)]
    pub position: i64,
    pub track: SiteTrack,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct SitePlaylistDetail {
    #[serde(deserialize_with = "flexible_id", default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    pub cover_filename: Option<String>,
    #[serde(default)]
    pub tracks: Vec<SitePlaylistEntry>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct SiteLyrics {
    pub synced: Option<String>,
    pub plain: Option<String>,
    pub source: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum SiteError {
    #[error("unauthorized")]
    Unauthorized,
    #[error("no token")]
    NoToken,
    #[error("server {0}")]
    Server(u16),
    #[error("{0}")]
    Other(String),
}

pub struct Site {
    http: reqwest::Client,
    store: Arc<dyn TokenStore>,
    access: Mutex<Option<String>>,
    refresh: Mutex<Option<String>>,
}

impl Site {
    pub fn new(http: reqwest::Client, store: Arc<dyn TokenStore>) -> Self {
        let access = store.get("access");
        let refresh = store.get("refresh");
        Self { http, store, access: Mutex::new(access), refresh: Mutex::new(refresh) }
    }

    pub fn has_session(&self) -> bool {
        self.refresh.lock().map(|value| value.is_some()).unwrap_or(false)
    }

    pub fn set_tokens(&self, access: Option<&str>, refresh: Option<&str>) {
        if let Some(access) = access {
            if let Ok(mut value) = self.access.lock() {
                *value = Some(access.to_string());
            }
            self.store.set("access", access);
        }
        if let Some(refresh) = refresh {
            if let Ok(mut value) = self.refresh.lock() {
                *value = Some(refresh.to_string());
            }
            self.store.set("refresh", refresh);
        }
    }

    pub fn clear(&self) {
        if let Ok(mut value) = self.access.lock() {
            *value = None;
        }
        if let Ok(mut value) = self.refresh.lock() {
            *value = None;
        }
        self.store.remove("access");
        self.store.remove("refresh");
    }

    fn url(path: &str) -> String {
        format!("{BASE}{path}")
    }

    pub async fn login_url(&self) -> Result<String> {
        let text = self.http.get(Self::url("/api/auth/login-url?client=native")).send().await?.text().await?;
        let value: Value = serde_json::from_str(&text)?;
        value.get("url").and_then(|url| url.as_str()).map(String::from).ok_or_else(|| anyhow!("no login url"))
    }

    pub async fn sso_login(&self, token: &str, state: &str) -> Result<SiteUser> {
        let response = self
            .http
            .post(Self::url("/api/auth/sso-login"))
            .json(&json!({ "sso_token": token, "state": state }))
            .send()
            .await?;
        if !response.status().is_success() {
            return Err(SiteError::Server(response.status().as_u16()).into());
        }
        let value: Value = response.json().await?;
        let access = value.get("access_token").and_then(|v| v.as_str()).ok_or_else(|| anyhow!("no access token"))?;
        let refresh = value.get("refresh_token").and_then(|v| v.as_str()).ok_or_else(|| anyhow!("no refresh token"))?;
        self.set_tokens(Some(access), Some(refresh));
        let user = value.get("user").cloned().unwrap_or(Value::Null);
        Ok(serde_json::from_value(user).unwrap_or_default())
    }

    pub async fn refresh_access(&self) -> Result<String> {
        let refresh = self.refresh.lock().ok().and_then(|value| value.clone()).ok_or(SiteError::NoToken)?;
        let response = self
            .http
            .post(Self::url("/api/auth/refresh"))
            .json(&json!({ "refresh_token": refresh }))
            .send()
            .await?;
        let status = response.status();
        if status.as_u16() == 401 || status.as_u16() == 400 {
            self.clear();
            return Err(SiteError::Unauthorized.into());
        }
        if !status.is_success() {
            return Err(SiteError::Server(status.as_u16()).into());
        }
        let value: Value = response.json().await?;
        let token = value.get("access_token").and_then(|v| v.as_str()).ok_or_else(|| anyhow!("no access token"))?.to_string();
        self.set_tokens(Some(&token), None);
        Ok(token)
    }

    async fn authorized(&self, path: &str) -> Result<String> {
        self.authorized_with(path, reqwest::Method::GET).await
    }

    async fn authorized_with(&self, path: &str, method: reqwest::Method) -> Result<String> {
        let existing = self.access.lock().ok().and_then(|value| value.clone());
        let mut token = match existing {
            Some(token) => token,
            None => self.refresh_access().await?,
        };
        for attempt in 0..2 {
            let response = self.http.request(method.clone(), Self::url(path)).bearer_auth(&token).send().await?;
            let status = response.status();
            if status.as_u16() == 401 && attempt == 0 {
                token = self.refresh_access().await?;
                continue;
            }
            if !status.is_success() {
                return Err(if status.as_u16() == 401 { SiteError::Unauthorized } else { SiteError::Server(status.as_u16()) }.into());
            }
            return Ok(response.text().await?);
        }
        Err(SiteError::Unauthorized.into())
    }

    pub async fn me(&self) -> Result<SiteUser> {
        Ok(serde_json::from_str(&self.authorized("/api/auth/me").await?)?)
    }

    pub async fn favorites(&self) -> Result<Vec<SiteTrack>> {
        Ok(serde_json::from_str(&self.authorized("/api/music/favorites").await?)?)
    }

    pub async fn playlists(&self) -> Result<Vec<SitePlaylist>> {
        Ok(serde_json::from_str(&self.authorized("/api/music/playlists").await?)?)
    }

    pub async fn playlist(&self, id: &str) -> Result<SitePlaylistDetail> {
        Ok(serde_json::from_str(&self.authorized(&format!("/api/music/playlists/{id}")).await?)?)
    }

    pub async fn lyrics(&self, track_id: &str) -> Option<SiteLyrics> {
        let text = self.http.get(Self::url(&format!("/api/music/lyrics/{track_id}"))).send().await.ok()?.text().await.ok()?;
        serde_json::from_str(&text).ok()
    }

    pub async fn catalog(&self, search: &str, sort: &str, format: Option<&str>, limit: u32, offset: u32) -> Result<Vec<SiteTrack>> {
        let mut query: Vec<(&str, String)> = vec![("sort", sort.to_string()), ("limit", limit.to_string()), ("offset", offset.to_string())];
        if !search.is_empty() {
            query.push(("search", search.to_string()));
        }
        if let Some(format) = format {
            query.push(("format", format.to_string()));
        }
        let link = url::Url::parse_with_params(&Self::url("/api/music/tracks"), &query)?;
        let response = self.http.get(link).send().await?;
        if !response.status().is_success() {
            return Err(SiteError::Server(response.status().as_u16()).into());
        }
        Ok(serde_json::from_str(&response.text().await?)?)
    }

    pub async fn wave(&self, limit: u32) -> Result<Vec<SiteTrack>> {
        let link = url::Url::parse_with_params(&Self::url("/api/music/wave"), &[("limit", limit.to_string())])?;
        let response = self.http.get(link).send().await?;
        if !response.status().is_success() {
            return Err(SiteError::Server(response.status().as_u16()).into());
        }
        Ok(serde_json::from_str(&response.text().await?)?)
    }

    pub async fn register_play(&self, track_id: &str) {
        let _ = self.http.post(Self::url(&format!("/api/music/tracks/{track_id}/play"))).send().await;
    }

    pub async fn liked_ids(&self) -> Result<Vec<String>> {
        let value: Value = serde_json::from_str(&self.authorized("/api/music/me/library").await?)?;
        let ids = value.get("favorite_ids").and_then(|ids| ids.as_array()).cloned().unwrap_or_default();
        Ok(ids
            .into_iter()
            .filter_map(|id| match id {
                Value::String(text) => Some(text),
                Value::Number(number) => Some(number.to_string()),
                _ => None,
            })
            .collect())
    }

    pub async fn set_liked(&self, track_id: &str, value: bool) -> Result<()> {
        let method = if value { reqwest::Method::POST } else { reqwest::Method::DELETE };
        self.authorized_with(&format!("/api/music/favorites/{track_id}"), method).await?;
        Ok(())
    }

    pub async fn access_token(&self) -> Result<String> {
        let existing = self.access.lock().ok().and_then(|value| value.clone());
        match existing {
            Some(token) => Ok(token),
            None => self.refresh_access().await,
        }
    }

    pub async fn publish_presence(&self, body: &Value) -> Result<()> {
        let mut token = self.access_token().await?;
        for attempt in 0..2 {
            let response = self
                .http
                .post(format!("{BASE}/app/bump/presence"))
                .timeout(std::time::Duration::from_secs(10))
                .bearer_auth(&token)
                .json(body)
                .send()
                .await?;
            if response.status().as_u16() == 401 && attempt == 0 {
                token = self.refresh_access().await?;
                continue;
            }
            return Ok(());
        }
        Ok(())
    }

    pub async fn presence_poll(&self, since: i64) -> Result<String> {
        let mut token = self.access_token().await?;
        for attempt in 0..2 {
            let response = self
                .http
                .get(format!("{BASE}/app/bump/presence/poll?since={since}&wait=25"))
                .timeout(std::time::Duration::from_secs(40))
                .bearer_auth(&token)
                .send()
                .await?;
            if response.status().as_u16() == 401 && attempt == 0 {
                token = self.refresh_access().await?;
                continue;
            }
            if !response.status().is_success() {
                return Err(SiteError::Server(response.status().as_u16()).into());
            }
            return Ok(response.text().await?);
        }
        Err(SiteError::Unauthorized.into())
    }
}

fn media(folder: &str, name: &str) -> String {
    let encoded = percent_encoding::utf8_percent_encode(name, percent_encoding::NON_ALPHANUMERIC).to_string();
    format!("{MEDIA}/{folder}/{encoded}")
}

pub fn audio_url(track: &SiteTrack, lossless: bool) -> String {
    if !lossless {
        if let Some(stream) = &track.stream_filename {
            return media("stream", stream);
        }
    }
    media("tracks", &track.filename)
}

pub fn cover_url(name: &str) -> String {
    media("covers", name)
}

pub fn thumb_url(name: &str) -> String {
    let stem = match name.rfind('.') {
        Some(position) => &name[..position],
        None => name,
    };
    media("thumbs", &format!("{stem}.webp"))
}

pub fn motion_url(name: &str) -> String {
    media("motion", name)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track(stream: Option<&str>) -> SiteTrack {
        SiteTrack {
            id: "53".into(),
            title: "T".into(),
            artist: "A".into(),
            filename: "x.flac".into(),
            stream_filename: stream.map(String::from),
            ..Default::default()
        }
    }

    #[test]
    fn thumbnail_swaps_the_extension_for_webp() {
        assert_eq!(thumb_url("0123456789abcdef0123456789abcdef.jpg"), format!("{MEDIA}/thumbs/0123456789abcdef0123456789abcdef%2Ewebp"));
        assert_eq!(thumb_url("noext"), format!("{MEDIA}/thumbs/noext%2Ewebp"));
    }

    #[test]
    fn stream_file_is_preferred_unless_lossless() {
        assert!(audio_url(&track(Some("x.m4a")), false).contains("/stream/"));
        assert!(audio_url(&track(Some("x.m4a")), true).contains("/tracks/"));
        assert!(audio_url(&track(None), false).contains("/tracks/"));
    }

    #[test]
    fn site_track_decodes_numeric_ids_and_play_counts() {
        let list: Vec<SiteTrack> = serde_json::from_str(
            r#"[{"id": 7, "title": "A", "artist": "B", "filename": "a.mp3", "play_count": 12, "media_kind": "audio"},
                {"id": "x1", "title": "C", "artist": "D", "filename": "c.mp3", "media_kind": "video"}]"#,
        )
        .unwrap();
        assert_eq!(list[0].id, "7");
        assert_eq!(list[0].play_count, Some(12));
        assert_eq!(list[1].id, "x1");
        assert_eq!(list[1].media_kind.as_deref(), Some("video"));
    }
}
