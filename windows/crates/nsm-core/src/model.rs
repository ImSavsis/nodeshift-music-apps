use serde::{Deserialize, Serialize};

pub fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Track {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub track_number: Option<i64>,
    pub disc_number: Option<i64>,
    pub year: Option<i64>,
    pub genre: Option<String>,
    pub duration_ms: i64,
    pub format: String,
    pub bitrate_kbps: Option<i64>,
    pub sample_rate: Option<i64>,
    pub bit_depth: Option<i64>,
    pub file_name: String,
    pub file_size: i64,
    pub file_hash: Option<String>,
    pub cover_name: Option<String>,
    pub motion_name: Option<String>,
    pub motion3x4_name: Option<String>,
    pub is_favorite: bool,
    pub play_count: i64,
    pub last_played_at: Option<i64>,
    pub added_at: i64,
    pub site_id: Option<String>,
    pub bpm: Option<i64>,
    pub palette: Option<String>,
    pub lyrics_kind: Option<String>,
    pub lyrics_source: Option<String>,
    #[serde(default)]
    pub stream_url: Option<String>,
}

impl Track {
    pub fn blank(id: String) -> Self {
        Self { id, added_at: now_ms(), ..Default::default() }
    }

    pub fn duration_seconds(&self) -> f64 {
        self.duration_ms as f64 / 1000.0
    }
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Playlist {
    pub id: String,
    pub name: String,
    pub cover_name: Option<String>,
    pub site_id: Option<String>,
    pub created_at: i64,
    pub track_ids: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LyricsRecord {
    pub track_id: String,
    pub kind: String,
    pub source: String,
    pub lrc: Option<String>,
    pub plain: Option<String>,
    pub checked_at: i64,
}
