use std::path::Path;

use serde::Deserialize;
use serde_json::{json, Value};

pub const DEFAULT_APP_ID: &str = "1543000586209853490";
pub const DEFAULT_NAME: &str = "Burmalda";
const SITE: &str = "https://music.nodeshift.space";

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct Presence {
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub artist: String,
    #[serde(default)]
    pub album: String,
    #[serde(default)]
    pub position_ms: u64,
    #[serde(default)]
    pub duration_ms: u64,
    #[serde(default)]
    pub cover: String,
    #[serde(default)]
    pub site_id: String,
    #[serde(default)]
    pub playing: bool,
    #[serde(default)]
    pub platform: String,
    #[serde(default)]
    pub ts: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DiscordConfig {
    pub app_id: String,
    pub name: String,
    pub enabled: bool,
}

impl Default for DiscordConfig {
    fn default() -> Self {
        Self { app_id: DEFAULT_APP_ID.to_string(), name: DEFAULT_NAME.to_string(), enabled: true }
    }
}

impl DiscordConfig {
    pub fn load(base: &Path) -> Self {
        let mut config = Self::default();
        if let Some(from_env) = std::env::var("NSM_DISCORD_APP_ID").ok().filter(|value| !value.trim().is_empty()) {
            config.app_id = from_env.trim().to_string();
        }
        let Ok(text) = std::fs::read_to_string(base.join("discord.json")) else {
            return config;
        };
        let Ok(value) = serde_json::from_str::<Value>(&text) else {
            return config;
        };
        if let Some(id) = value.get("app_id").and_then(Value::as_str).filter(|id| !id.trim().is_empty()) {
            config.app_id = id.trim().to_string();
        }
        if let Some(name) = value.get("name").and_then(Value::as_str).filter(|name| !name.trim().is_empty()) {
            config.name = name.trim().to_string();
        }
        if let Some(enabled) = value.get("enabled").and_then(Value::as_bool) {
            config.enabled = enabled;
        }
        config
    }
}

pub fn parse_poll(text: &str) -> Option<(u64, Option<Presence>)> {
    let value: Value = serde_json::from_str(text).ok()?;
    let version = value.get("version")?.as_u64()?;
    let state = value.get("state").filter(|state| !state.is_null()).and_then(|state| serde_json::from_value(state.clone()).ok());
    Some((version, state))
}

fn limit(text: &str, count: usize) -> String {
    let trimmed = text.trim();
    let mut value: String = trimmed.chars().take(count).collect();
    if value.chars().count() < 2 {
        value.push_str("  ");
    }
    value
}

pub fn build_activity(presence: &Presence, name: &str) -> Value {
    let artist = if presence.artist.trim().is_empty() { "Burmalda".to_string() } else { limit(&presence.artist, 128) };
    let mut assets = json!({
        "large_text": limit(if presence.album.trim().is_empty() { &presence.title } else { &presence.album }, 128),
        "small_text": if presence.playing { "Играет" } else { "Пауза" },
    });
    if presence.cover.starts_with("https://") {
        assets["large_image"] = json!(presence.cover);
    }
    let mut activity = json!({
        "name": name,
        "type": 2,
        "details": limit(&presence.title, 128),
        "state": artist,
        "assets": assets,
    });
    if presence.playing && presence.duration_ms > 0 {
        let start = (presence.ts.saturating_sub(presence.position_ms)) / 1000;
        let end = start + presence.duration_ms / 1000;
        activity["timestamps"] = json!({ "start": start, "end": end });
    }
    if !presence.site_id.is_empty() {
        activity["buttons"] = json!([{ "label": "Слушать на NodeShift", "url": format!("{SITE}/track/{}", presence.site_id) }]);
    }
    activity
}

pub fn encode_frame(opcode: u32, payload: &Value) -> Vec<u8> {
    let body = serde_json::to_vec(payload).unwrap_or_default();
    let mut frame = Vec::with_capacity(8 + body.len());
    frame.extend_from_slice(&opcode.to_le_bytes());
    frame.extend_from_slice(&(body.len() as u32).to_le_bytes());
    frame.extend_from_slice(&body);
    frame
}

pub fn decode_header(header: [u8; 8]) -> (u32, usize) {
    let opcode = u32::from_le_bytes([header[0], header[1], header[2], header[3]]);
    let length = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
    (opcode, length.min(1 << 20))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Presence {
        Presence {
            title: "Everyday (Remastered 2016)".into(),
            artist: "Jamiroquai".into(),
            album: "Travelling Without Moving".into(),
            position_ms: 10_000,
            duration_ms: 240_000,
            cover: "https://burmalda.savsis.xyz/covers/a.jpg".into(),
            site_id: "183".into(),
            playing: true,
            platform: "ios".into(),
            ts: 1_700_000_100_000,
        }
    }

    #[test]
    fn activity_is_listening_with_progress() {
        let activity = build_activity(&sample(), "Burmalda");
        assert_eq!(activity["type"], 2);
        assert_eq!(activity["name"], "Burmalda");
        assert_eq!(activity["details"], "Everyday (Remastered 2016)");
        assert_eq!(activity["state"], "Jamiroquai");
        assert_eq!(activity["assets"]["large_image"], "https://burmalda.savsis.xyz/covers/a.jpg");
        assert_eq!(activity["timestamps"]["start"], 1_700_000_090u64);
        assert_eq!(activity["timestamps"]["end"], 1_700_000_330u64);
        assert_eq!(activity["buttons"][0]["url"], "https://music.nodeshift.space/track/183");
    }

    #[test]
    fn paused_has_no_timestamps_and_no_cover_without_https() {
        let mut presence = sample();
        presence.playing = false;
        presence.cover = "http://x/y.jpg".into();
        presence.site_id.clear();
        let activity = build_activity(&presence, "Burmalda");
        assert!(activity.get("timestamps").is_none());
        assert!(activity["assets"].get("large_image").is_none());
        assert!(activity.get("buttons").is_none());
        assert_eq!(activity["assets"]["small_text"], "Пауза");
    }

    #[test]
    fn short_text_is_padded() {
        let mut presence = sample();
        presence.title = "A".into();
        let activity = build_activity(&presence, "Burmalda");
        assert_eq!(activity["details"].as_str().unwrap().chars().count(), 3);
    }

    #[test]
    fn frames_roundtrip() {
        let frame = encode_frame(1, &json!({"cmd": "SET_ACTIVITY"}));
        let (opcode, length) = decode_header(frame[..8].try_into().unwrap());
        assert_eq!(opcode, 1);
        assert_eq!(length, frame.len() - 8);
    }

    #[test]
    fn poll_parsing() {
        let text = r#"{"version": 3, "state": {"title": "T", "artist": "A", "playing": true, "position_ms": 5, "duration_ms": 9, "ts": 7}}"#;
        let (version, state) = parse_poll(text).unwrap();
        assert_eq!(version, 3);
        assert_eq!(state.unwrap().title, "T");
        let (version, state) = parse_poll(r#"{"version": 4, "state": null}"#).unwrap();
        assert_eq!(version, 4);
        assert!(state.is_none());
        assert!(parse_poll("nope").is_none());
    }

    #[test]
    fn config_file_overrides_defaults() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(DiscordConfig::load(dir.path()).app_id, DEFAULT_APP_ID);
        std::fs::write(dir.path().join("discord.json"), r#"{"app_id": " 42 ", "name": "Mine", "enabled": false}"#).unwrap();
        let config = DiscordConfig::load(dir.path());
        assert_eq!(config.app_id, "42");
        assert_eq!(config.name, "Mine");
        assert!(!config.enabled);
    }
}
