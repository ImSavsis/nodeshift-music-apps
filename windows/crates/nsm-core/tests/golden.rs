use std::path::PathBuf;

use base64::Engine;
use nsm_core::algo::duplicates::{DuplicateIndex, DuplicateKind, TrackFingerprint};
use nsm_core::algo::filename_parser::{is_numbered_batch, parse};
use nsm_core::algo::lrc::{self, LyricsKind};
use nsm_core::algo::lyrics_verifier::{best, verify, LyricsCandidate, LyricsQuery, Verdict};
use nsm_core::algo::palette;
use nsm_core::algo::similarity::{ratio, ratio_str};
use nsm_core::algo::text_matching::{artist_parts, artist_ratio, normalize, strip_featuring, words};
use nsm_core::algo::version::{is_newer, AppVersion};
use serde_json::Value;

fn vector(name: &str) -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../shared/testdata").join(name);
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

fn optional_u32(value: &Value) -> Option<u32> {
    value.as_u64().map(|number| number as u32)
}

fn optional_string(value: &Value) -> Option<String> {
    value.as_str().map(String::from)
}

#[test]
fn filename_vectors_match_other_platforms() {
    let cases = vector("filename-parser.json");
    let cases = cases.as_array().unwrap();
    assert!(cases.len() > 10);
    for case in cases {
        let label = case["label"].as_str().unwrap();
        let names: Vec<String> = case["names"].as_array().unwrap().iter().map(|name| name.as_str().unwrap().to_string()).collect();
        let numbered = is_numbered_batch(&names);
        assert_eq!(case["numbered"].as_bool().unwrap(), numbered, "{label}");
        let expected = case["expected"].as_array().unwrap();
        assert_eq!(names.len(), expected.len(), "{label}");
        for (name, want) in names.iter().zip(expected) {
            let got = parse(name, numbered);
            assert_eq!(optional_u32(&want["disc"]), got.disc, "{label}: {name} disc");
            assert_eq!(optional_u32(&want["track"]), got.track, "{label}: {name} track");
            assert_eq!(optional_string(&want["artist"]), got.artist, "{label}: {name} artist");
            assert_eq!(optional_string(&want["title"]), got.title, "{label}: {name} title");
        }
    }
}

#[test]
fn user_example_is_parsed() {
    let parsed = parse("09 - 2pac - Ratha Be Ya Nigga.flac", false);
    assert_eq!(parsed.track, Some(9));
    assert_eq!(parsed.artist.as_deref(), Some("2pac"));
    assert_eq!(parsed.title.as_deref(), Some("Ratha Be Ya Nigga"));
}

#[test]
fn similarity_matches_difflib() {
    let cases = vector("similarity.json");
    let cases = cases.as_array().unwrap();
    assert!(cases.len() > 20);
    for case in cases {
        let a = case["a"].as_str().unwrap();
        let b = case["b"].as_str().unwrap();
        let got = if case["mode"].as_str().unwrap() == "words" {
            ratio(&words(a), &words(b))
        } else {
            ratio_str(a, b)
        };
        let want = case["ratio"].as_f64().unwrap();
        assert!((want - got).abs() < 1e-6, "{}: {want} vs {got}", case["name"]);
    }
}

#[test]
fn text_helpers() {
    assert_eq!(normalize("Beyoncé — Halo (Live)"), "beyonce halo");
    assert_eq!(normalize("  Hit 'Em  Up [Dirty] "), "hit em up");
    assert_eq!(strip_featuring("Song (feat. Someone)"), "Song");
    assert_eq!(strip_featuring("Eminem feat. Rihanna"), "Eminem");
    assert_eq!(strip_featuring("Track ft. Guest"), "Track");
    assert_eq!(strip_featuring("Defeat Of Me"), "Defeat Of Me");
    assert!(artist_ratio("Eminem feat. Rihanna", "Eminem") > 0.99);
    assert!(artist_ratio("Eminem & Dr. Dre", "Dr Dre") > 0.9);
    assert!(artist_ratio("Eminem", "Metallica") < 0.5);
    assert_eq!(artist_parts("A & B, C"), vec!["a", "b", "c"]);
}

#[test]
fn lrc_vectors() {
    let cases = vector("lrc.json");
    for case in cases.as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let got = lrc::parse(case["lrc"].as_str().unwrap());
        let expected = case["expected"].as_array().unwrap();
        assert_eq!(expected.len(), got.len(), "{name}");
        for (line, want) in got.iter().zip(expected) {
            assert!((want["time"].as_f64().unwrap() - line.time).abs() < 1e-9, "{name}");
            assert_eq!(want["text"].as_str().unwrap(), line.text, "{name}");
            assert!(line.words.is_none(), "{name}");
        }
    }
}

#[test]
fn enhanced_lrc_word_timing() {
    let lines = lrc::parse("[00:12.00]<00:12.00>Hello <00:12.50>big <00:13.20>world<00:14.00>\n[00:15.00]plain line");
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0].text, "Hello big world");
    let words = lines[0].words.as_ref().unwrap();
    assert_eq!(words.len(), 3);
    assert!((words[0].start - 12.0).abs() < 1e-9);
    assert!((words[0].end - 12.5).abs() < 1e-9);
    assert!((words[2].end - 14.0).abs() < 1e-9);
    assert!(lines[1].words.is_none());
    assert_eq!(lrc::kind(&lines), LyricsKind::Line);
    assert_eq!(lrc::kind(&lines[..1]), LyricsKind::Word);
}

#[test]
fn timed_words_replace_plain_lines_only_when_they_match() {
    let plain = lrc::parse("[00:12.00]Hello big world
[00:15.00]second line");
    let timed = lrc::parse("[00:12.00]<00:12.10>Hello <00:12.40><00:12.50>big <00:12.90><00:13.20>world<00:14.00>
[00:15.00]second line");
    let merged = lrc::with_timed_words(plain.clone(), timed.clone());
    assert!(merged[0].words.is_some());
    assert!((merged[0].words.as_ref().unwrap()[0].end - 12.4).abs() < 1e-9);
    assert_eq!(lrc::kind(&merged), LyricsKind::Line);

    let moved = lrc::parse("[00:13.00]<00:13.10>Hello <00:13.40><00:13.50>big <00:13.90><00:14.20>world<00:15.00>
[00:15.00]second line");
    assert!(lrc::with_timed_words(plain.clone(), moved)[0].words.is_none());
    assert!(lrc::with_timed_words(plain.clone(), timed[..1].to_vec())[0].words.is_none());
    assert!(lrc::with_timed_words(plain, Vec::new())[0].words.is_none());
}

#[test]
fn lrc_offset() {
    let lines = lrc::parse("[offset:+500]\n[00:10.00]line");
    assert!((lines[0].time - 9.5).abs() < 1e-9);
}

fn candidate(title: &str, artist: &str, duration: Option<f64>, synced: Option<&str>, plain: Option<&str>) -> LyricsCandidate {
    LyricsCandidate {
        track_name: title.into(),
        artist_name: artist.into(),
        duration,
        synced: synced.map(String::from),
        plain: plain.map(String::from),
        instrumental: false,
    }
}

#[test]
fn verifier_accepts_and_rejects() {
    let query = LyricsQuery { title: "Ratha Be Ya Nigga".into(), artist: "2Pac".into(), duration: Some(250.0) };
    let synced = Some("[00:10.00]one\n[03:20.00]two");
    let ok = candidate("Ratha Be Ya Nigga", "2Pac", Some(250.4), synced, None);
    assert!(matches!(verify(&ok, &query), Verdict::Accepted { kind: LyricsKind::Line, .. }));
    assert_eq!(verify(&candidate("Ratha Be Ya Nigga", "2Pac", Some(255.0), synced, None), &query), Verdict::Rejected("duration"));
    assert_eq!(verify(&candidate("Changes", "2Pac", Some(250.0), synced, None), &query), Verdict::Rejected("title"));
    assert_eq!(verify(&candidate("Ratha Be Ya Nigga", "Metallica", Some(250.0), synced, None), &query), Verdict::Rejected("artist"));
    assert_eq!(
        verify(&candidate("Ratha Be Ya Nigga", "2Pac", Some(250.0), Some("[05:30.00]late"), None), &query),
        Verdict::Rejected("timeline")
    );
    assert_eq!(verify(&candidate("Ratha Be Ya Nigga", "2Pac", None, synced, None), &query), Verdict::Rejected("no-duration"));
    assert_eq!(verify(&candidate("Ratha Be Ya Nigga", "2Pac", Some(250.0), None, None), &query), Verdict::Rejected("empty"));
    assert_eq!(
        verify(&candidate("Ratha Be Ya Nigga", "2Pac", Some(250.0), None, Some("??? ??? ???? ???")), &query),
        Verdict::Rejected("garbled")
    );
}

#[test]
fn best_prefers_word_then_line_then_plain() {
    let query = LyricsQuery { title: "Ratha Be Ya Nigga".into(), artist: "2Pac".into(), duration: Some(250.0) };
    let plain = candidate("Ratha Be Ya Nigga", "2Pac", Some(250.0), None, Some("words words"));
    let line = candidate("Ratha Be Ya Nigga", "2Pac", Some(250.0), Some("[00:10.00]one\n[03:20.00]two"), None);
    let word = candidate(
        "Ratha Be Ya Nigga",
        "2Pac",
        Some(250.0),
        Some("[00:10.00]<00:10.00>one <00:11.00>two\n[03:20.00]<03:20.00>x <03:21.00>y"),
        None,
    );
    assert_eq!(best(&[plain.clone(), line.clone(), word], &query).unwrap().1, LyricsKind::Word);
    assert_eq!(best(&[plain.clone(), line], &query).unwrap().1, LyricsKind::Line);
    assert_eq!(best(&[plain], &query).unwrap().1, LyricsKind::Plain);
}

#[test]
fn palette_vectors() {
    let cases = vector("palette.json");
    for case in cases.as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let data = base64::engine::general_purpose::STANDARD.decode(case["rgbaBase64"].as_str().unwrap()).unwrap();
        let got: Vec<[u8; 3]> = palette::extract(&data).iter().map(|color| [color.r, color.g, color.b]).collect();
        let want: Vec<[u8; 3]> = case["expected"]
            .as_array()
            .unwrap()
            .iter()
            .map(|row| {
                let row = row.as_array().unwrap();
                [row[0].as_u64().unwrap() as u8, row[1].as_u64().unwrap() as u8, row[2].as_u64().unwrap() as u8]
            })
            .collect();
        assert_eq!(want, got, "{name}");
    }
}

fn fingerprint(id: &str, artist: &str, title: &str, duration: Option<i64>, hash: Option<&str>, format: &str, bitrate: Option<i64>) -> TrackFingerprint {
    TrackFingerprint {
        id: id.into(),
        artist: artist.into(),
        title: title.into(),
        duration_ms: duration,
        file_hash: hash.map(String::from),
        format: format.into(),
        bitrate_kbps: bitrate,
    }
}

#[test]
fn duplicate_detection() {
    let index = DuplicateIndex::new(vec![fingerprint("a", "2Pac", "Ratha Be Ya Nigga", Some(250_000), Some("abc"), "mp3", Some(128))]);
    let same = index.matches(&fingerprint("n", "Other", "Other", None, Some("abc"), "mp3", None));
    assert_eq!(same.len(), 1);
    assert_eq!(same[0].kind, DuplicateKind::SameFile);
    assert_eq!(index.existing_id("abc").as_deref(), Some("a"));

    let hits = index.matches(&fingerprint("n", "2pac", "Ratha Be Ya Nigga (Remastered)", Some(250_800), None, "flac", None));
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].kind, DuplicateKind::SameTrack);
    assert!(hits[0].candidate_is_better_quality);

    let far = index.matches(&fingerprint("n2", "2Pac", "Ratha Be Ya Nigga", Some(300_000), None, "mp3", None));
    assert!(far.is_empty());
}

#[test]
fn versions() {
    assert!(AppVersion::parse("1.10.0").unwrap().compare(&AppVersion::parse("1.9.9").unwrap()).is_gt());
    assert!(AppVersion::parse("1.x").is_none());
    assert!(is_newer("0.2.0", 5, "0.1.0", 99));
    assert!(is_newer("0.2.0", 5, "0.2.0", 4));
    assert!(!is_newer("0.2.0", 5, "0.2.0", 5));
    assert!(!is_newer("0.2.0", 5, "0.3.0", 1));
}
