use std::sync::OnceLock;

use regex::Regex;
use unicode_normalization::UnicodeNormalization;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ParsedName {
    pub disc: Option<u32>,
    pub track: Option<u32>,
    pub artist: Option<String>,
    pub title: Option<String>,
}

struct Patterns {
    extension: Regex,
    junk: Regex,
    site: Regex,
    dash: Regex,
    disc_track: Regex,
    strong: Regex,
    weak: fancy_regex::Regex,
    whitespace: Regex,
}

fn patterns() -> &'static Patterns {
    static CELL: OnceLock<Patterns> = OnceLock::new();
    CELL.get_or_init(|| Patterns {
        extension: Regex::new(r"(?i)\.(mp3|flac|wav|ogg|opus|m4a|aac|aiff?|wma)$").unwrap(),
        junk: Regex::new(
            r"(?i)\s*[\[(](?:flac|mp3|320\s*kbps|320|hq|hd|lossless|official\s*(?:audio|video|music\s*video|lyric\s*video))[\])]\s*",
        )
        .unwrap(),
        site: Regex::new(r"(?i)\s*[\[(]?(?:www\.)?[a-z0-9-]+\.(?:com|net|org|ru|me|io|fm)[\])]?\s*$").unwrap(),
        dash: Regex::new(r"(?:\s+[-–—]\s+|\s*[-–—]\s+|\s+[-–—]\s*)").unwrap(),
        disc_track: Regex::new(r"^([0-9]{1,2})[-.]([0-9]{2,3})(?:\s*(?:[-.)_]|\s[-–—]\s)\s*|\s+)").unwrap(),
        strong: Regex::new(r"^([0-9]{1,3})(?:\s*[-.)_]\s*|\s[-–—]\s)").unwrap(),
        weak: fancy_regex::Regex::new(r"^([0-9]{1,3})\s+(?=[^0-9])").unwrap(),
        whitespace: Regex::new(r"[\s\p{Z}]+").unwrap(),
    })
}

struct Lead {
    value: u32,
    raw: String,
    rest: String,
    strong: bool,
}

fn collapse(text: &str) -> String {
    patterns()
        .whitespace
        .split(text)
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

fn clean(stem: &str) -> String {
    let p = patterns();
    let mut text: String = stem.nfc().collect();
    let has_space = text.trim().contains(' ');
    if !has_space && text.chars().filter(|c| *c == '_').count() >= 2 {
        text = text.replace('_', " ");
    }
    let text = p.junk.replace_all(&text, " ").to_string();
    let text = p.site.replace_all(&text, "").to_string();
    collapse(&text)
}

fn stem(name: &str) -> String {
    clean(&patterns().extension.replace_all(name, ""))
}

fn non_empty_parts(text: &str) -> Vec<String> {
    patterns()
        .dash
        .split(text)
        .map(|part| part.trim().to_string())
        .filter(|part| !part.is_empty())
        .collect()
}

fn lead(text: &str) -> Option<Lead> {
    let p = patterns();
    if let Some(found) = p.strong.captures(text) {
        let whole = found.get(0)?;
        let raw = found.get(1)?.as_str().to_string();
        if let Ok(value) = raw.parse::<u32>() {
            return Some(Lead { value, raw, rest: text[whole.end()..].to_string(), strong: true });
        }
    }
    if let Ok(Some(found)) = p.weak.captures(text) {
        let whole = found.get(0)?;
        let raw = found.get(1)?.as_str().to_string();
        if let Ok(value) = raw.parse::<u32>() {
            return Some(Lead { value, raw, rest: text[whole.end()..].to_string(), strong: false });
        }
    }
    None
}

pub fn is_numbered_batch(names: &[String]) -> bool {
    let p = patterns();
    let texts: Vec<String> = names.iter().map(|name| stem(name)).collect();
    let mut found: Vec<Option<u32>> = Vec::new();
    for text in &texts {
        if p.disc_track.is_match(text) {
            found.push(None);
            continue;
        }
        if let Some(info) = lead(text) {
            found.push(Some(info.value));
        }
    }
    if (found.len() as f64) < texts.len() as f64 * 0.8 || texts.len() < 3 {
        return false;
    }
    let plain: Vec<u32> = found.into_iter().flatten().collect();
    if plain.is_empty() || !plain.iter().all(|value| (1..=99).contains(value)) {
        return false;
    }
    let mut unique = plain.clone();
    unique.sort_unstable();
    unique.dedup();
    unique.len() == plain.len()
}

pub fn parse(name: &str, numbered_batch: bool) -> ParsedName {
    let p = patterns();
    let mut text = stem(name);
    let mut disc = None;
    let mut track = None;
    if let Some(found) = p.disc_track.captures(&text) {
        if let (Some(whole), Some(first), Some(second)) = (found.get(0), found.get(1), found.get(2)) {
            disc = first.as_str().parse::<u32>().ok();
            track = second.as_str().parse::<u32>().ok();
            let end = whole.end();
            text = text[end..].to_string();
        }
    } else if let Some(info) = lead(&text) {
        let padded = info.raw.len() == 2 && info.raw.starts_with('0');
        let three_part = info.strong && non_empty_parts(&info.rest).len() >= 2;
        if padded || three_part || numbered_batch {
            track = Some(info.value);
            text = info.rest;
        }
    }
    let parts = non_empty_parts(&text);
    let mut artist = None;
    let mut title = None;
    if parts.len() >= 2 {
        artist = Some(parts[0].clone());
        title = Some(parts[1..].join(" - "));
    } else if let Some(only) = parts.first() {
        title = Some(only.clone());
    }
    ParsedName { disc, track, artist, title }
}

pub fn parse_batch(names: &[String]) -> Vec<ParsedName> {
    let numbered = is_numbered_batch(names);
    names.iter().map(|name| parse(name, numbered)).collect()
}
