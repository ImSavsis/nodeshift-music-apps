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
        let existing = self.access.lock().ok().and_then(|value| value.clone());
        let mut token = match existing {
            Some(token) => token,
            None => self.refresh_access().await?,
        };
        for attempt in 0..2 {
            let response = self.http.get(Self::url(path)).bearer_auth(&token).send().await?;
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

pub fn motion_url(name: &str) -> String {
    media("motion", name)
}
