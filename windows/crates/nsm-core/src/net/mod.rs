pub mod catalog;
pub mod lyrics_client;
pub mod motion;
pub mod site;

use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use futures_util::StreamExt;
use tokio::io::AsyncWriteExt;

pub const USER_AGENT: &str = "NodeShiftMusic/0.1 (+https://music.nodeshift.space)";
pub const BROWSER_AGENT: &str =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36";

pub fn client() -> reqwest::Client {
    reqwest::Client::builder()
        .user_agent(USER_AGENT)
        .connect_timeout(Duration::from_secs(25))
        .timeout(Duration::from_secs(600))
        .build()
        .expect("http client")
}

#[derive(Default)]
pub struct RateLimiter {
    next: tokio::sync::Mutex<HashMap<&'static str, Instant>>,
}

impl RateLimiter {
    pub fn shared() -> Arc<Self> {
        Arc::new(Self::default())
    }

    pub async fn wait(&self, key: &'static str, interval: Duration) {
        let pause = {
            let mut map = self.next.lock().await;
            let now = Instant::now();
            let slot = map.get(key).copied().filter(|slot| *slot > now).unwrap_or(now);
            map.insert(key, slot + interval);
            slot.saturating_duration_since(now)
        };
        if !pause.is_zero() {
            tokio::time::sleep(pause).await;
        }
    }
}

pub async fn get_text(http: &reqwest::Client, url: &str, agent: Option<&str>) -> Result<String> {
    let mut request = http.get(url);
    if let Some(agent) = agent {
        request = request.header(reqwest::header::USER_AGENT, agent);
    }
    let response = request.send().await?;
    if !response.status().is_success() {
        return Err(anyhow!("http {}", response.status()));
    }
    Ok(response.text().await?)
}

pub async fn get_bytes(http: &reqwest::Client, url: &str, agent: Option<&str>) -> Result<Vec<u8>> {
    let mut request = http.get(url);
    if let Some(agent) = agent {
        request = request.header(reqwest::header::USER_AGENT, agent);
    }
    let response = request.send().await?;
    if !response.status().is_success() {
        return Err(anyhow!("http {}", response.status()));
    }
    Ok(response.bytes().await?.to_vec())
}

pub async fn download(http: &reqwest::Client, url: &str, destination: &Path, agent: Option<&str>) -> Result<u64> {
    let mut request = http.get(url);
    if let Some(agent) = agent {
        request = request.header(reqwest::header::USER_AGENT, agent);
    }
    let response = request.send().await?;
    if !response.status().is_success() {
        return Err(anyhow!("http {}", response.status()));
    }
    if let Some(parent) = destination.parent() {
        tokio::fs::create_dir_all(parent).await?;
    }
    let temporary = destination.with_extension("part");
    let mut file = tokio::fs::File::create(&temporary).await?;
    let mut stream = response.bytes_stream();
    let mut total = 0u64;
    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        total += chunk.len() as u64;
        file.write_all(&chunk).await?;
    }
    file.flush().await?;
    drop(file);
    let _ = tokio::fs::remove_file(destination).await;
    tokio::fs::rename(&temporary, destination).await?;
    Ok(total)
}
