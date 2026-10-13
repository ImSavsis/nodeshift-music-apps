use super::lrc::{self, LyricLine, LyricsKind};
use super::text_matching::{artist_ratio, title_ratio};

pub const DURATION_TOLERANCE: f64 = 2.0;
pub const TITLE_THRESHOLD: f64 = 0.9;
pub const ARTIST_THRESHOLD: f64 = 0.88;
pub const TIMELINE_SLACK: f64 = 3.0;

#[derive(Debug, Clone)]
pub struct LyricsQuery {
    pub title: String,
    pub artist: String,
    pub duration: Option<f64>,
}

#[derive(Debug, Clone, Default)]
pub struct LyricsCandidate {
    pub track_name: String,
    pub artist_name: String,
    pub duration: Option<f64>,
    pub synced: Option<String>,
    pub plain: Option<String>,
    pub instrumental: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Verdict {
    Accepted { kind: LyricsKind, score: f64 },
    Rejected(&'static str),
}

pub fn is_garbled(text: &str) -> bool {
    if text.chars().any(|c| c == '\u{FFFD}') {
        return true;
    }
    let visible: Vec<char> = text.chars().filter(|c| !c.is_whitespace()).collect();
    if visible.is_empty() {
        return true;
    }
    let questions = visible.iter().filter(|c| **c == '?').count();
    questions as f64 / visible.len() as f64 > 0.12
}

pub fn timeline_end(lines: &[LyricLine]) -> f64 {
    lines.iter().map(|line| line.time).fold(0.0, f64::max)
}

pub fn verify(candidate: &LyricsCandidate, query: &LyricsQuery) -> Verdict {
    if candidate.instrumental {
        return Verdict::Rejected("instrumental");
    }
    let synced_lines: Vec<LyricLine> = candidate.synced.as_deref().map(lrc::parse).unwrap_or_default();
    let plain = candidate.plain.clone().unwrap_or_default().trim().to_string();
    if synced_lines.is_empty() && plain.is_empty() {
        return Verdict::Rejected("empty");
    }
    let (Some(wanted), Some(got)) = (query.duration, candidate.duration) else {
        return Verdict::Rejected("no-duration");
    };
    if (wanted - got).abs() > DURATION_TOLERANCE {
        return Verdict::Rejected("duration");
    }
    let title_score = title_ratio(&candidate.track_name, &query.title);
    if title_score < TITLE_THRESHOLD {
        return Verdict::Rejected("title");
    }
    let artist_score = artist_ratio(&candidate.artist_name, &query.artist);
    if artist_score < ARTIST_THRESHOLD {
        return Verdict::Rejected("artist");
    }
    if !synced_lines.is_empty() {
        if timeline_end(&synced_lines) > wanted + TIMELINE_SLACK {
            return Verdict::Rejected("timeline");
        }
        if is_garbled(&lrc::plain_text(&synced_lines)) {
            return Verdict::Rejected("garbled");
        }
        let score = (title_score + artist_score) / 2.0 - (wanted - got).abs() * 0.01;
        return Verdict::Accepted { kind: lrc::kind(&synced_lines), score };
    }
    if is_garbled(&plain) {
        return Verdict::Rejected("garbled");
    }
    let score = (title_score + artist_score) / 2.0 - (wanted - got).abs() * 0.01 - 0.5;
    Verdict::Accepted { kind: LyricsKind::Plain, score }
}

fn rank(kind: LyricsKind) -> f64 {
    match kind {
        LyricsKind::Word => 2.0,
        LyricsKind::Line => 1.0,
        LyricsKind::Plain => 0.0,
        LyricsKind::None => -1.0,
    }
}

pub fn best(candidates: &[LyricsCandidate], query: &LyricsQuery) -> Option<(LyricsCandidate, LyricsKind)> {
    let mut winner: Option<(usize, LyricsKind, f64)> = None;
    for (index, candidate) in candidates.iter().enumerate() {
        let Verdict::Accepted { kind, score } = verify(candidate, query) else {
            continue;
        };
        let boosted = score + rank(kind);
        if winner.map(|current| boosted > current.2).unwrap_or(true) {
            winner = Some((index, kind, boosted));
        }
    }
    winner.map(|(index, kind, _)| (candidates[index].clone(), kind))
}
