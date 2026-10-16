use std::path::PathBuf;
use std::sync::Arc;

use base64::Engine as _;
use nsm_core::drm::{now_seconds, Grant, KIND_LOSSLESS};
use nsm_core::engine::{CatalogSource, Engine, EngineConfig};
use nsm_core::media_server::{self, MediaServer};
use nsm_core::model::Track;
use nsm_core::net::site::MemoryTokenStore;
use nsm_core::paths::Paths;
use serde_json::Value;
use sha2::{Digest, Sha256};

struct Setup {
    _dir: tempfile::TempDir,
    server: MediaServer,
    sample: Value,
}

fn sample() -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../shared/testdata/nlac.json");
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

async fn setup(with_grant: bool) -> Setup {
    let dir = tempfile::tempdir().unwrap();
    let paths = Paths::new(dir.path()).unwrap();
    let sample = sample();
    let locked = base64::engine::general_purpose::STANDARD.decode(sample["locked_b64"].as_str().unwrap()).unwrap();
    std::fs::write(paths.track_file("a.nlac"), locked).unwrap();
    let engine = Engine::new(EngineConfig {
        paths,
        catalog: CatalogSource::None,
        tokens: Arc::new(MemoryTokenStore::default()),
        emit: Arc::new(|_| {}),
        runtime: tokio::runtime::Handle::current(),
    })
    .unwrap();
    let mut track = Track::blank("t1".into());
    track.file_name = "a.nlac".into();
    track.site_id = Some("42".into());
    engine.db().save_track(&track).unwrap();
    if with_grant {
        engine.vault().remember(&Grant {
            track_id: 42,
            kind: KIND_LOSSLESS,
            key_id: sample["key_id"].as_u64().unwrap() as u32,
            name: "a.nlac".into(),
            codec: "flac".into(),
            plain_length: sample["plain_length"].as_u64().unwrap(),
            key_hex: sample["key_hex"].as_str().unwrap().to_string(),
            expires_at: now_seconds() + 86400,
        });
    }
    let server = media_server::start(engine).await.unwrap();
    Setup { _dir: dir, server, sample }
}

fn digest(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

#[tokio::test]
async fn a_locked_file_is_served_as_plain_audio_with_ranges() {
    let setup = setup(true).await;
    let client = reqwest::Client::new();
    let url = format!("{}/track/t1", setup.server.base());

    let whole = client.get(&url).send().await.unwrap();
    assert_eq!(whole.status().as_u16(), 200);
    assert_eq!(whole.headers()["content-type"], "audio/flac");
    assert_eq!(whole.headers()["accept-ranges"], "bytes");
    let body = whole.bytes().await.unwrap();
    assert_eq!(body.len(), 70000);
    assert_eq!(digest(&body), setup.sample["plain_sha256"].as_str().unwrap());

    let ranges = setup.sample["ranges"].as_array().unwrap();
    let hashes = setup.sample["range_sha256"].as_array().unwrap();
    for (range, expected) in ranges.iter().zip(hashes) {
        let (start, end) = (range[0].as_u64().unwrap(), range[1].as_u64().unwrap());
        let part = client.get(&url).header("range", format!("bytes={start}-{end}")).send().await.unwrap();
        assert_eq!(part.status().as_u16(), 206);
        assert_eq!(part.headers()["content-range"], format!("bytes {start}-{end}/70000"));
        assert_eq!(digest(&part.bytes().await.unwrap()), expected.as_str().unwrap());
    }

    let tail = client.get(&url).header("range", "bytes=69900-").send().await.unwrap();
    assert_eq!(tail.status().as_u16(), 206);
    assert_eq!(tail.bytes().await.unwrap().len(), 100);

    let beyond = client.get(&url).header("range", "bytes=99999-").send().await.unwrap();
    assert_eq!(beyond.status().as_u16(), 416);
}

#[tokio::test]
async fn without_a_license_the_file_is_not_served() {
    let setup = setup(false).await;
    let response = reqwest::get(format!("{}/track/t1", setup.server.base())).await.unwrap();
    assert_eq!(response.status().as_u16(), 403);
}

#[tokio::test]
async fn the_wrong_token_gets_nothing() {
    let setup = setup(true).await;
    let response = reqwest::get(format!("http://127.0.0.1:{}/wrong/track/t1", setup.server.port)).await.unwrap();
    assert_eq!(response.status().as_u16(), 404);
}

#[tokio::test]
async fn a_site_track_without_a_session_redirects_to_the_public_preview() {
    let setup = setup(false).await;
    let client = reqwest::Client::builder().redirect(reqwest::redirect::Policy::none()).build().unwrap();
    let response = client.get(format!("{}/site/42", setup.server.base())).send().await.unwrap();
    assert_eq!(response.status().as_u16(), 307);
    assert_eq!(response.headers()["location"], "https://music.nodeshift.space/api/music/preview/42");
}
