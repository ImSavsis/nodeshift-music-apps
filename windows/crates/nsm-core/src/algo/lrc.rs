use std::sync::OnceLock;

use regex::Regex;
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct LyricWord {
    pub text: String,
    pub start: f64,
    pub end: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct LyricLine {
    pub time: f64,
    pub text: String,
    pub words: Option<Vec<LyricWord>>,
}

impl LyricLine {
    pub fn has_word_timing(&self) -> bool {
        self.words.as_ref().map(|words| !words.is_empty()).unwrap_or(false)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum LyricsKind {
    Word,
    Line,
    Plain,
    None,
}

fn line_tag() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"\[([0-9]{1,3}):([0-9]{2}(?:[.:][0-9]{1,3})?)\]").unwrap())
}

fn word_tag() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"<([0-9]{1,3}):([0-9]{2}(?:[.:][0-9]{1,3})?)>").unwrap())
}

fn offset_tag() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"(?i)^\s*\[offset:\s*([+-]?[0-9]+)\s*\]\s*$").unwrap())
}

fn newline() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"\r\n|\r|\n").unwrap())
}

fn seconds(minutes: &str, rest: &str) -> Option<f64> {
    let m: f64 = minutes.parse().ok()?;
    let s: f64 = rest.replace(':', ".").parse().ok()?;
    Some(m * 60.0 + s)
}

pub fn parse(lrc: &str) -> Vec<LyricLine> {
    let mut offset = 0.0f64;
    let mut result: Vec<LyricLine> = Vec::new();
    for raw in newline().split(lrc) {
        if let Some(found) = offset_tag().captures(raw) {
            offset = found[1].parse::<f64>().unwrap_or(0.0) / 1000.0;
            continue;
        }
        let tags: Vec<_> = line_tag().captures_iter(raw).collect();
        if tags.is_empty() {
            continue;
        }
        let body = line_tag().replace_all(raw, "").to_string();
        let times: Vec<f64> = tags.iter().filter_map(|tag| seconds(&tag[1], &tag[2])).collect();
        let words = parse_words(&body);
        let plain = word_tag().replace_all(&body, "").trim().to_string();
        if plain.is_empty() {
            continue;
        }
        for time in times {
            result.push(LyricLine { time: time - offset, text: plain.clone(), words: words.clone() });
        }
    }
    result.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap_or(std::cmp::Ordering::Equal));
    apply_word_ends(&mut result);
    result
}

fn parse_words(body: &str) -> Option<Vec<LyricWord>> {
    let tags: Vec<_> = word_tag().captures_iter(body).collect();
    if tags.is_empty() {
        return None;
    }
    let mut starts: Vec<f64> = Vec::new();
    let mut texts: Vec<String> = Vec::new();
    let mut ends: Vec<f64> = Vec::new();
    for (index, tag) in tags.iter().enumerate() {
        let Some(start) = seconds(&tag[1], &tag[2]) else {
            continue;
        };
        let whole = tag.get(0).unwrap();
        let next_lower = if index + 1 < tags.len() { tags[index + 1].get(0).unwrap().start() } else { body.len() };
        let segment = &body[whole.end()..next_lower];
        if segment.trim().is_empty() {
            if let Some(last) = ends.last_mut() {
                *last = start;
            }
            continue;
        }
        starts.push(start);
        texts.push(segment.to_string());
        ends.push(start);
    }
    if texts.is_empty() {
        return None;
    }
    for index in 0..texts.len() - 1 {
        if ends[index] <= starts[index] {
            ends[index] = starts[index + 1];
        }
    }
    Some(
        texts
            .into_iter()
            .enumerate()
            .map(|(index, text)| LyricWord { text, start: starts[index], end: ends[index] })
            .collect(),
    )
}

fn apply_word_ends(lines: &mut [LyricLine]) {
    for index in 0..lines.len() {
        let line_end = if index + 1 < lines.len() { Some(lines[index + 1].time) } else { None };
        let Some(words) = lines[index].words.as_mut() else {
            continue;
        };
        let Some(last) = words.last_mut() else {
            continue;
        };
        if last.end <= last.start {
            let fallback = line_end.unwrap_or(last.start + 1.5);
            last.end = fallback.max(last.start + 0.3);
        }
    }
}

pub fn with_timed_words(plain: Vec<LyricLine>, timed: Vec<LyricLine>) -> Vec<LyricLine> {
    let same_shape = !timed.is_empty()
        && timed.len() == plain.len()
        && timed.iter().zip(&plain).all(|(a, b)| a.text == b.text && (a.time - b.time).abs() < 0.05);
    if same_shape {
        timed
    } else {
        plain
    }
}

pub fn kind(lines: &[LyricLine]) -> LyricsKind {
    if lines.is_empty() {
        return LyricsKind::None;
    }
    let timed = lines.iter().filter(|line| line.has_word_timing()).count();
    if timed as f64 >= lines.len() as f64 * 0.6 {
        LyricsKind::Word
    } else {
        LyricsKind::Line
    }
}

pub fn plain_text(lines: &[LyricLine]) -> String {
    lines.iter().map(|line| line.text.as_str()).collect::<Vec<_>>().join("\n")
}
