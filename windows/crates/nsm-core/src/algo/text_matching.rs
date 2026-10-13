use std::sync::OnceLock;

use regex::Regex;
use unicode_normalization::UnicodeNormalization;

use super::similarity::ratio_str;

fn marks() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"\p{M}+").unwrap())
}

fn bracket_pattern() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"[(\[][^)\]]*[)\]]").unwrap())
}

fn non_word_pattern() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"[^\p{L}\p{N}\p{M}_\s]").unwrap())
}

fn whitespace() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"[\s\p{Z}]+").unwrap())
}

fn featuring_pattern() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"(?i)\s*[(\[]?\s*(?-u:\b)(?:feat|ft|featuring)(?-u:\b)\.?\s+.*$").unwrap())
}

fn artist_split_pattern() -> &'static Regex {
    static CELL: OnceLock<Regex> = OnceLock::new();
    CELL.get_or_init(|| Regex::new(r"(?i)\s*(?:,|;|&|/|\bx\b|×|\band\b|\bи\b)\s*").unwrap())
}

fn collapse(text: &str) -> String {
    whitespace().split(text).filter(|part| !part.is_empty()).collect::<Vec<_>>().join(" ")
}

pub fn normalize(text: &str) -> String {
    let decomposed: String = text.nfkd().collect();
    let stripped = marks().replace_all(&decomposed, "");
    let lowered = stripped.to_lowercase();
    let without_brackets = bracket_pattern().replace_all(&lowered, " ");
    let spaced = non_word_pattern().replace_all(&without_brackets, " ");
    collapse(&spaced)
}

pub fn strip_featuring(text: &str) -> String {
    collapse(&featuring_pattern().replace_all(text, ""))
}

pub fn title_key(title: &str) -> String {
    normalize(&strip_featuring(title))
}

pub fn artist_key(artist: &str) -> String {
    normalize(&strip_featuring(artist))
}

pub fn artist_parts(artist: &str) -> Vec<String> {
    let stripped = strip_featuring(artist);
    artist_split_pattern()
        .split(&stripped)
        .map(normalize)
        .filter(|part| !part.is_empty())
        .collect()
}

pub fn title_ratio(a: &str, b: &str) -> f64 {
    ratio_str(&title_key(a), &title_key(b))
}

pub fn artist_ratio(a: &str, b: &str) -> f64 {
    let whole = ratio_str(&artist_key(a), &artist_key(b));
    if whole >= 0.999 {
        return whole;
    }
    let mut best = whole;
    let right = artist_parts(b);
    for x in artist_parts(a) {
        for y in &right {
            best = best.max(ratio_str(&x, y));
        }
    }
    best
}

pub fn words(text: &str) -> Vec<String> {
    whitespace().split(text).filter(|part| !part.is_empty()).map(String::from).collect()
}
