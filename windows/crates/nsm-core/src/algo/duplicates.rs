use std::collections::HashMap;

use super::similarity::ratio_str;
use super::text_matching::{artist_key, title_key};

pub const SAME_TRACK_TOLERANCE_MS: i64 = 2000;
pub const SIMILAR_TOLERANCE_MS: i64 = 3000;
pub const SIMILAR_TITLE_THRESHOLD: f64 = 0.92;

#[derive(Debug, Clone, Default)]
pub struct TrackFingerprint {
    pub id: String,
    pub artist: String,
    pub title: String,
    pub duration_ms: Option<i64>,
    pub file_hash: Option<String>,
    pub format: String,
    pub bitrate_kbps: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DuplicateKind {
    SameFile,
    SameTrack,
    Similar,
}

impl DuplicateKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            DuplicateKind::SameFile => "sameFile",
            DuplicateKind::SameTrack => "sameTrack",
            DuplicateKind::Similar => "similar",
        }
    }
}

#[derive(Debug, Clone)]
pub struct DuplicateMatch {
    pub existing_id: String,
    pub kind: DuplicateKind,
    pub candidate_is_better_quality: bool,
}

fn quality(format: &str, bitrate: Option<i64>) -> i64 {
    const LOSSLESS: [&str; 8] = ["flac", "wav", "aiff", "aif", "alac", "ape", "wv", "dsf"];
    if LOSSLESS.contains(&format.to_lowercase().as_str()) {
        return 10_000;
    }
    bitrate.unwrap_or(128)
}

#[derive(Default)]
pub struct DuplicateIndex {
    by_hash: HashMap<String, Vec<TrackFingerprint>>,
    by_key: HashMap<String, Vec<TrackFingerprint>>,
    by_artist: HashMap<String, Vec<TrackFingerprint>>,
}

fn key_of(track: &TrackFingerprint) -> String {
    format!("{}|{}", artist_key(&track.artist), title_key(&track.title))
}

fn close_enough(a: Option<i64>, b: Option<i64>, tolerance: i64) -> bool {
    match (a, b) {
        (Some(x), Some(y)) => (x - y).abs() <= tolerance,
        _ => true,
    }
}

impl DuplicateIndex {
    pub fn new(tracks: Vec<TrackFingerprint>) -> Self {
        let mut index = Self::default();
        for track in tracks {
            index.add(track);
        }
        index
    }

    pub fn add(&mut self, track: TrackFingerprint) {
        if let Some(hash) = track.file_hash.as_ref().filter(|hash| !hash.is_empty()) {
            self.by_hash.entry(hash.clone()).or_default().push(track.clone());
        }
        self.by_key.entry(key_of(&track)).or_default().push(track.clone());
        self.by_artist.entry(artist_key(&track.artist)).or_default().push(track);
    }

    pub fn remove(&mut self, id: &str) {
        for list in self.by_hash.values_mut() {
            list.retain(|track| track.id != id);
        }
        for list in self.by_key.values_mut() {
            list.retain(|track| track.id != id);
        }
        for list in self.by_artist.values_mut() {
            list.retain(|track| track.id != id);
        }
    }

    pub fn existing_id(&self, hash: &str) -> Option<String> {
        self.by_hash.get(hash).and_then(|list| list.first()).map(|track| track.id.clone())
    }

    pub fn matches(&self, candidate: &TrackFingerprint) -> Vec<DuplicateMatch> {
        let mut seen: Vec<String> = Vec::new();
        let mut result: Vec<DuplicateMatch> = Vec::new();
        let candidate_quality = quality(&candidate.format, candidate.bitrate_kbps);
        let better = |existing: &TrackFingerprint| candidate_quality > quality(&existing.format, existing.bitrate_kbps);
        if let Some(hash) = candidate.file_hash.as_ref() {
            if let Some(list) = self.by_hash.get(hash) {
                for hit in list {
                    if hit.id != candidate.id && !seen.contains(&hit.id) {
                        seen.push(hit.id.clone());
                        result.push(DuplicateMatch {
                            existing_id: hit.id.clone(),
                            kind: DuplicateKind::SameFile,
                            candidate_is_better_quality: false,
                        });
                    }
                }
            }
        }
        if let Some(list) = self.by_key.get(&key_of(candidate)) {
            for hit in list {
                if hit.id != candidate.id
                    && close_enough(hit.duration_ms, candidate.duration_ms, SAME_TRACK_TOLERANCE_MS)
                    && !seen.contains(&hit.id)
                {
                    seen.push(hit.id.clone());
                    result.push(DuplicateMatch {
                        existing_id: hit.id.clone(),
                        kind: DuplicateKind::SameTrack,
                        candidate_is_better_quality: better(hit),
                    });
                }
            }
        }
        if result.is_empty() {
            let wanted = title_key(&candidate.title);
            if let Some(list) = self.by_artist.get(&artist_key(&candidate.artist)) {
                for hit in list {
                    if hit.id != candidate.id
                        && close_enough(hit.duration_ms, candidate.duration_ms, SIMILAR_TOLERANCE_MS)
                        && ratio_str(&title_key(&hit.title), &wanted) >= SIMILAR_TITLE_THRESHOLD
                        && !seen.contains(&hit.id)
                    {
                        seen.push(hit.id.clone());
                        result.push(DuplicateMatch {
                            existing_id: hit.id.clone(),
                            kind: DuplicateKind::Similar,
                            candidate_is_better_quality: better(hit),
                        });
                    }
                }
            }
        }
        result
    }
}
