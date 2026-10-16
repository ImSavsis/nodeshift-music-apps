use std::sync::Arc;

use nsm_core::drm::KIND_LOSSY;
use nsm_core::engine::{CatalogSource, Engine, EngineConfig};
use nsm_core::media_server;
use nsm_core::net::site::{MemoryTokenStore, TokenStore};
use nsm_core::paths::Paths;
use sha2::{Digest, Sha256};

#[tokio::test]
#[ignore]
async fn a_site_track_streams_through_the_local_decrypting_server() {
    let access = std::env::var("NSM_TEST_ACCESS").unwrap();
    let site_id = std::env::var("NSM_TEST_TRACK").unwrap();
    let expected = std::env::var("NSM_TEST_SHA256").unwrap();
    let length: usize = std::env::var("NSM_TEST_LENGTH").unwrap().parse().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let tokens = Arc::new(MemoryTokenStore::default());
    tokens.set("access", &access);
    let engine = Engine::new(EngineConfig {
        paths: Paths::new(dir.path()).unwrap(),
        catalog: CatalogSource::None,
        tokens,
        emit: Arc::new(|_| {}),
        runtime: tokio::runtime::Handle::current(),
    })
    .unwrap();
    let grant = engine.grant(&site_id, KIND_LOSSY, false).await.unwrap();
    assert_eq!(grant.plain_length as usize, length);
    let server = media_server::start(engine).await.unwrap();
    let client = reqwest::Client::new();
    let url = format!("{}/site/{}", server.base(), site_id);
    let whole = client.get(&url).send().await.unwrap();
    assert_eq!(whole.status().as_u16(), 200);
    let body = whole.bytes().await.unwrap();
    assert_eq!(body.len(), length);
    assert_eq!(hex::encode(Sha256::digest(&body)), expected);
    let middle = client.get(&url).header("range", "bytes=100000-100999").send().await.unwrap();
    assert_eq!(middle.status().as_u16(), 206);
    assert_eq!(middle.bytes().await.unwrap().as_ref(), &body[100000..101000]);
}
