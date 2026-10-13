use std::path::{Path, PathBuf};
use std::sync::Arc;

use futures_util::FutureExt;
use nsm_core::engine::{CatalogSource, Decision, Emit, Engine, EngineConfig, ItemState};
use nsm_core::net::catalog::{Catalog, CatalogMatch};
use nsm_core::net::site::MemoryTokenStore;
use nsm_core::paths::Paths;
use nsm_core::tags;

fn write_wav(path: &Path, seconds: f64, frequency: f64) {
    let rate = 44100u32;
    let frames = (rate as f64 * seconds) as u32;
    let mut data: Vec<u8> = Vec::new();
    data.extend_from_slice(b"RIFF");
    data.extend_from_slice(&(36 + frames * 2).to_le_bytes());
    data.extend_from_slice(b"WAVEfmt ");
    data.extend_from_slice(&16u32.to_le_bytes());
    data.extend_from_slice(&1u16.to_le_bytes());
    data.extend_from_slice(&1u16.to_le_bytes());
    data.extend_from_slice(&rate.to_le_bytes());
    data.extend_from_slice(&(rate * 2).to_le_bytes());
    data.extend_from_slice(&2u16.to_le_bytes());
    data.extend_from_slice(&16u16.to_le_bytes());
    data.extend_from_slice(b"data");
    data.extend_from_slice(&(frames * 2).to_le_bytes());
    for index in 0..frames {
        let sample = (10_000.0 * (2.0 * std::f64::consts::PI * frequency * index as f64 / rate as f64).sin()) as i16;
        data.extend_from_slice(&sample.to_le_bytes());
    }
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(path, data).unwrap();
}

fn fake_catalog() -> Catalog {
    Catalog {
        lookup: Arc::new(|query| {
            async move {
                if query.title.to_lowercase().contains("ratha") {
                    Some(CatalogMatch {
                        title: "Ratha Be Ya Nigga".into(),
                        artist: "2Pac".into(),
                        album: Some("All Eyez On Me".into()),
                        album_artist: Some("2Pac".into()),
                        track_number: Some(9),
                        disc_number: Some(2),
                        year: Some(1996),
                        genre: Some("Hip-Hop/Rap".into()),
                        isrc: Some("USKO10404424".into()),
                        cover_url: None,
                        duration_seconds: None,
                        source: "fake".into(),
                    })
                } else {
                    None
                }
            }
            .boxed()
        }),
        cover: Arc::new(|_| async { None }.boxed()),
    }
}

struct Fixture {
    _root: tempfile::TempDir,
    inputs: PathBuf,
    engine: Engine,
}

fn fixture(catalog: CatalogSource) -> Fixture {
    let root = tempfile::tempdir().unwrap();
    let paths = Paths::new(root.path().join("data")).unwrap();
    let emit: Emit = Arc::new(|_| {});
    let runtime = tokio::runtime::Handle::current();
    let engine = Engine::new(EngineConfig { paths, catalog, tokens: Arc::new(MemoryTokenStore::default()), emit, runtime }).unwrap();
    let inputs = root.path().join("inputs");
    std::fs::create_dir_all(&inputs).unwrap();
    Fixture { _root: root, inputs, engine }
}

#[tokio::test]
async fn filename_import_writes_tags() {
    let fx = fixture(CatalogSource::Custom(fake_catalog()));
    let wav = fx.inputs.join("09 - 2pac - Ratha Be Ya Nigga.wav");
    write_wav(&wav, 2.0, 440.0);
    fx.engine.run_import(vec![wav]).await;

    let saved = fx.engine.library().unwrap();
    assert_eq!(saved.len(), 1);
    let track = &saved[0];
    assert_eq!(track.title, "Ratha Be Ya Nigga");
    assert_eq!(track.artist, "2Pac");
    assert_eq!(track.album.as_deref(), Some("All Eyez On Me"));
    assert_eq!(track.track_number, Some(9));
    assert_eq!(track.disc_number, Some(2));
    assert!((track.duration_ms - 2000).abs() < 80, "{}", track.duration_ms);
    assert_eq!(fx.engine.import_snapshot().summary.added, 1);

    let written = tags::read(&fx.engine.paths().track_file(&track.file_name)).unwrap();
    assert_eq!(written.title.as_deref(), Some("Ratha Be Ya Nigga"));
    assert_eq!(written.artist.as_deref(), Some("2Pac"));
    assert_eq!(written.album.as_deref(), Some("All Eyez On Me"));
    assert_eq!(written.track_number, Some(9));
}

#[tokio::test]
async fn batch_numbering_without_catalog() {
    let fx = fixture(CatalogSource::None);
    let names = ["01. Intro.wav", "02. Hurt.wav", "03. Dear Mama.wav"];
    let mut files = Vec::new();
    for (index, name) in names.iter().enumerate() {
        let path = fx.inputs.join(name);
        write_wav(&path, 1.0, 300.0 + 200.0 * index as f64);
        files.push(path);
    }
    fx.engine.run_import(files).await;
    let mut saved = fx.engine.library().unwrap();
    saved.sort_by_key(|track| track.track_number.unwrap_or(0));
    assert_eq!(saved.iter().map(|track| track.title.as_str()).collect::<Vec<_>>(), vec!["Intro", "Hurt", "Dear Mama"]);
    assert_eq!(saved.iter().map(|track| track.track_number).collect::<Vec<_>>(), vec![Some(1), Some(2), Some(3)]);
    assert!(saved.iter().all(|track| track.artist == "Неизвестный исполнитель"));
}

#[tokio::test]
async fn same_file_is_skipped() {
    let fx = fixture(CatalogSource::None);
    let wav = fx.inputs.join("Artist - Song.wav");
    write_wav(&wav, 2.0, 440.0);
    fx.engine.run_import(vec![wav.clone()]).await;
    assert_eq!(fx.engine.library().unwrap().len(), 1);
    fx.engine.run_import(vec![wav]).await;
    assert_eq!(fx.engine.library().unwrap().len(), 1);
    assert_eq!(fx.engine.import_snapshot().summary.duplicates, 1);
    assert_eq!(std::fs::read_dir(&fx.engine.paths().tracks).unwrap().count(), 1);
}

#[tokio::test]
async fn same_track_different_bytes_asks_for_decision() {
    let fx = fixture(CatalogSource::None);
    let original = fx.inputs.join("Artist - Song.wav");
    write_wav(&original, 2.0, 440.0);
    fx.engine.run_import(vec![original]).await;

    let again = fx.inputs.join("again").join("Artist - Song.wav");
    write_wav(&again, 2.0, 880.0);
    fx.engine.run_import(vec![again]).await;

    assert_eq!(fx.engine.library().unwrap().len(), 1);
    let snapshot = fx.engine.import_snapshot();
    assert_eq!(snapshot.pending_duplicates, 1);
    let waiting = snapshot.items.last().unwrap().clone();
    assert!(matches!(waiting.state, ItemState::Duplicate { .. }), "{:?}", waiting.state);
    fx.engine.import_decide(&waiting.id, Decision::KeepBoth);
    assert_eq!(fx.engine.library().unwrap().len(), 2);
}

#[tokio::test]
async fn folder_import_groups_by_folder() {
    let fx = fixture(CatalogSource::None);
    let album = fx.inputs.join("Album");
    for (index, name) in ["Alpha", "Beta", "Gamma"].iter().enumerate() {
        write_wav(&album.join(format!("{:02} - Band - {name}.wav", index + 1)), 1.0, 300.0 + 100.0 * index as f64);
    }
    fx.engine.run_import(vec![album]).await;
    let mut saved = fx.engine.library().unwrap();
    saved.sort_by_key(|track| track.track_number.unwrap_or(0));
    assert_eq!(saved.iter().map(|track| track.title.as_str()).collect::<Vec<_>>(), vec!["Alpha", "Beta", "Gamma"]);
    assert!(saved.iter().all(|track| track.artist == "Band"));
}

#[tokio::test]
async fn zip_archive_import() {
    let fx = fixture(CatalogSource::None);
    let wav = fx.inputs.join("Pack").join("Band - Tune.wav");
    write_wav(&wav, 1.0, 500.0);
    let archive = fx.inputs.join("pack.zip");
    {
        let file = std::fs::File::create(&archive).unwrap();
        let mut zip = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default();
        zip.start_file("inner/Band - Tune.wav", options).unwrap();
        use std::io::Write;
        zip.write_all(&std::fs::read(&wav).unwrap()).unwrap();
        zip.finish().unwrap();
    }
    fx.engine.run_import(vec![archive]).await;
    let saved = fx.engine.library().unwrap();
    assert_eq!(saved.len(), 1);
    assert_eq!(saved[0].title, "Tune");
    assert_eq!(saved[0].artist, "Band");
}

#[tokio::test]
async fn media_server_serves_ranges() {
    let fx = fixture(CatalogSource::None);
    let wav = fx.inputs.join("Band - Tune.wav");
    write_wav(&wav, 1.0, 500.0);
    fx.engine.run_import(vec![wav]).await;
    let track = fx.engine.library().unwrap().remove(0);
    let server = nsm_core::media_server::start(fx.engine.clone()).await.unwrap();
    let http = reqwest::Client::new();
    let url = format!("{}/track/{}", server.base(), track.id);
    let response = http.get(&url).header("Range", "bytes=0-99").send().await.unwrap();
    assert_eq!(response.status().as_u16(), 206);
    assert_eq!(response.bytes().await.unwrap().len(), 100);
    let denied = http.get(format!("http://127.0.0.1:{}/wrong/track/{}", server.port, track.id)).send().await.unwrap();
    assert_eq!(denied.status().as_u16(), 404);
}
