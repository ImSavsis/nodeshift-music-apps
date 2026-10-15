use std::path::Path;

use percent_encoding::{utf8_percent_encode, NON_ALPHANUMERIC};
use serde::Deserialize;
use serde_json::{json, Value};

pub const DEFAULT_APP_ID: &str = "1498024819675889704";
pub const DEFAULT_NAME: &str = "Burmalda";
pub const PIPE_PREFIX: &str = r"\\.\pipe\discord-ipc-";
pub const OP_HANDSHAKE: u32 = 0;
pub const OP_FRAME: u32 = 1;
pub const OP_CLOSE: u32 = 2;
pub const OP_PING: u32 = 3;
pub const OP_PONG: u32 = 4;
pub const MAX_FRAME_BYTES: usize = 1 << 20;
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
    #[serde(default)]
    pub device: String,
    #[serde(default)]
    pub age_ms: Option<u64>,
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

    pub fn save_enabled(base: &Path, enabled: bool) -> std::io::Result<()> {
        let path = base.join("discord.json");
        let mut value = std::fs::read_to_string(&path)
            .ok()
            .and_then(|text| serde_json::from_str::<Value>(&text).ok())
            .filter(Value::is_object)
            .unwrap_or_else(|| json!({}));
        value["enabled"] = json!(enabled);
        crate::atomic::write_atomic(&path, &serde_json::to_vec_pretty(&value).unwrap_or_default())
    }
}

pub fn pipe_path(index: u32) -> String {
    format!("{PIPE_PREFIX}{index}")
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

pub fn start_seconds(presence: &Presence, local_now_ms: u64) -> u64 {
    let origin = match presence.age_ms {
        Some(age) => local_now_ms.saturating_sub(age),
        None => presence.ts,
    };
    origin.saturating_sub(presence.position_ms) / 1000
}

pub fn track_link(presence: &Presence) -> (String, &'static str) {
    if !presence.site_id.trim().is_empty() {
        return (format!("{SITE}/track/{}", presence.site_id.trim()), "Слушать на NodeShift");
    }
    let query: String = format!("{} {}", presence.artist.trim(), presence.title.trim()).chars().take(60).collect();
    (format!("https://music.apple.com/search?term={}", utf8_percent_encode(query.trim(), NON_ALPHANUMERIC)), "Найти трек в Apple Music")
}

pub fn build_activity(presence: &Presence, name: &str, local_now_ms: u64) -> Value {
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
        let start = start_seconds(presence, local_now_ms);
        let end = start + presence.duration_ms / 1000;
        activity["timestamps"] = json!({ "start": start, "end": end });
    }
    let (link, label) = track_link(presence);
    activity["details_url"] = json!(link);
    activity["buttons"] = json!([{ "label": label, "url": link }]);
    activity
}

pub fn plain_activity(activity: &Value) -> Value {
    let mut plain = activity.clone();
    if let Some(object) = plain.as_object_mut() {
        object.remove("buttons");
        object.remove("details_url");
    }
    if let Some(assets) = plain.get_mut("assets").and_then(Value::as_object_mut) {
        assets.remove("large_image");
    }
    plain
}

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
pub enum FrameError {
    #[error("frame of {0} bytes is larger than the limit")]
    TooLarge(usize),
}

pub fn encode_raw(opcode: u32, body: &[u8]) -> Vec<u8> {
    let mut frame = Vec::with_capacity(8 + body.len());
    frame.extend_from_slice(&opcode.to_le_bytes());
    frame.extend_from_slice(&(body.len() as u32).to_le_bytes());
    frame.extend_from_slice(body);
    frame
}

pub fn encode_frame(opcode: u32, payload: &Value) -> Vec<u8> {
    encode_raw(opcode, &serde_json::to_vec(payload).unwrap_or_default())
}

pub fn decode_header(header: [u8; 8]) -> Result<(u32, usize), FrameError> {
    let opcode = u32::from_le_bytes([header[0], header[1], header[2], header[3]]);
    let length = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
    if length > MAX_FRAME_BYTES {
        return Err(FrameError::TooLarge(length));
    }
    Ok((opcode, length))
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
            device: "phone".into(),
            age_ms: Some(2_500),
        }
    }

    const NOW: u64 = 1_700_000_100_000;

    #[test]
    fn activity_is_listening_with_progress() {
        let activity = build_activity(&sample(), "Burmalda", NOW);
        assert_eq!(activity["type"], 2);
        assert_eq!(activity["name"], "Burmalda");
        assert_eq!(activity["details"], "Everyday (Remastered 2016)");
        assert_eq!(activity["state"], "Jamiroquai");
        assert_eq!(activity["assets"]["large_image"], "https://burmalda.savsis.xyz/covers/a.jpg");
        assert_eq!(activity["timestamps"]["start"], 1_700_000_087u64);
        assert_eq!(activity["timestamps"]["end"], 1_700_000_327u64);
        assert_eq!(activity["buttons"][0]["url"], "https://music.nodeshift.space/track/183");
        assert_eq!(activity["buttons"][0]["label"], "Слушать на NodeShift");
        assert_eq!(activity["details_url"], "https://music.nodeshift.space/track/183");
    }

    #[test]
    fn tracks_outside_the_site_link_to_an_apple_music_search() {
        let mut presence = sample();
        presence.site_id.clear();
        presence.artist = "Jamiroquai".into();
        presence.title = "Alright (Remastered 2013)".into();
        let activity = build_activity(&presence, "Burmalda", NOW);
        let url = activity["buttons"][0]["url"].as_str().unwrap();
        assert_eq!(url, "https://music.apple.com/search?term=Jamiroquai%20Alright%20%28Remastered%202013%29");
        assert_eq!(activity["details_url"], url);
        assert_eq!(activity["buttons"][0]["label"], "Найти трек в Apple Music");
    }

    #[test]
    fn long_titles_keep_the_link_short() {
        let mut presence = sample();
        presence.site_id.clear();
        presence.title = "ё".repeat(300);
        let (link, _) = track_link(&presence);
        assert!(link.len() < 512, "{}", link.len());
    }

    #[test]
    fn start_follows_age_not_the_hub_clock() {
        let mut presence = sample();
        presence.ts = 1_650_000_000_000;
        let skewed = build_activity(&presence, "Burmalda", NOW);
        assert_eq!(skewed["timestamps"]["start"], 1_700_000_087u64);
        presence.age_ms = Some(0);
        assert_eq!(start_seconds(&presence, NOW), 1_700_000_090);
        presence.age_ms = Some(12_000);
        assert_eq!(start_seconds(&presence, NOW), 1_700_000_078);
        presence.age_ms = Some(u64::MAX);
        assert_eq!(start_seconds(&presence, NOW), 0);
    }

    #[test]
    fn start_falls_back_to_the_hub_timestamp_without_age() {
        let mut presence = sample();
        presence.age_ms = None;
        let activity = build_activity(&presence, "Burmalda", NOW + 99_000);
        assert_eq!(activity["timestamps"]["start"], 1_700_000_090u64);
        assert_eq!(activity["timestamps"]["end"], 1_700_000_330u64);
    }

    #[test]
    fn paused_has_no_timestamps_and_no_cover_without_https() {
        let mut presence = sample();
        presence.playing = false;
        presence.cover = "http://x/y.jpg".into();
        presence.site_id.clear();
        let activity = build_activity(&presence, "Burmalda", NOW);
        assert!(activity.get("timestamps").is_none());
        assert!(activity["assets"].get("large_image").is_none());
        assert!(activity["buttons"][0]["url"].as_str().unwrap().starts_with("https://music.apple.com/search?term=Jamiroquai"));
        assert_eq!(activity["assets"]["small_text"], "Пауза");
    }

    #[test]
    fn short_text_is_padded() {
        let mut presence = sample();
        presence.title = "A".into();
        let activity = build_activity(&presence, "Burmalda", NOW);
        assert_eq!(activity["details"].as_str().unwrap().chars().count(), 3);
    }

    #[test]
    fn plain_activity_drops_buttons_and_cover() {
        let activity = build_activity(&sample(), "Burmalda", NOW);
        let plain = plain_activity(&activity);
        assert!(plain.get("buttons").is_none());
        assert!(plain.get("details_url").is_none());
        assert!(plain["assets"].get("large_image").is_none());
        assert_eq!(plain["details"], activity["details"]);
        assert_eq!(plain["timestamps"], activity["timestamps"]);
    }

    #[test]
    fn pipe_names_use_the_device_namespace() {
        assert_eq!(pipe_path(0), r"\\.\pipe\discord-ipc-0");
        assert_eq!(pipe_path(9), r"\\.\pipe\discord-ipc-9");
        assert!(pipe_path(3).starts_with(r"\\.\pipe\"));
    }

    #[test]
    fn frames_roundtrip() {
        let frame = encode_frame(1, &json!({"cmd": "SET_ACTIVITY"}));
        let (opcode, length) = decode_header(frame[..8].try_into().unwrap()).unwrap();
        assert_eq!((opcode, length), (1, frame.len() - 8));
        let raw = encode_raw(OP_PONG, b"abc");
        assert_eq!(decode_header(raw[..8].try_into().unwrap()), Ok((OP_PONG, 3)));
        assert_eq!(&raw[8..], b"abc");
    }

    #[test]
    fn oversize_frames_are_rejected() {
        let mut header = [0u8; 8];
        header[4..].copy_from_slice(&((MAX_FRAME_BYTES as u32) + 1).to_le_bytes());
        assert_eq!(decode_header(header), Err(FrameError::TooLarge(MAX_FRAME_BYTES + 1)));
        header[4..].copy_from_slice(&(MAX_FRAME_BYTES as u32).to_le_bytes());
        assert!(decode_header(header).is_ok());
    }

    #[test]
    fn poll_parsing() {
        let text = r#"{"version": 3, "state": {"title": "T", "artist": "A", "playing": true, "position_ms": 5, "duration_ms": 9, "ts": 7}}"#;
        let (version, state) = parse_poll(text).unwrap();
        assert_eq!(version, 3);
        let state = state.unwrap();
        assert_eq!(state.title, "T");
        assert_eq!(state.age_ms, None);
        assert_eq!(state.device, "");
        let (version, state) = parse_poll(r#"{"version": 4, "state": null}"#).unwrap();
        assert_eq!(version, 4);
        assert!(state.is_none());
        assert!(parse_poll("nope").is_none());
    }

    #[test]
    fn poll_state_carries_device_and_age() {
        let text = r#"{"version": 1760000000, "state": {"title": "T", "device": "abc", "age_ms": 1234, "ts": 7}}"#;
        let (version, state) = parse_poll(text).unwrap();
        assert_eq!(version, 1_760_000_000);
        let state = state.unwrap();
        assert_eq!(state.device, "abc");
        assert_eq!(state.age_ms, Some(1234));
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

    #[test]
    fn saving_the_switch_keeps_other_keys() {
        let dir = tempfile::tempdir().unwrap();
        DiscordConfig::save_enabled(dir.path(), false).unwrap();
        assert!(!DiscordConfig::load(dir.path()).enabled);
        std::fs::write(dir.path().join("discord.json"), r#"{"app_id": "42", "enabled": false}"#).unwrap();
        DiscordConfig::save_enabled(dir.path(), true).unwrap();
        let config = DiscordConfig::load(dir.path());
        assert!(config.enabled);
        assert_eq!(config.app_id, "42");
        assert!(!dir.path().join("discord.json.tmp").exists());
    }
}
