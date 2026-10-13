use std::path::{Path, PathBuf};

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};

use crate::algo::version::is_newer;
use crate::import_support::hash_file;
use crate::net;

pub const MANIFEST_URL: &str = "https://music.nodeshift.space/app/update/files/win";
pub const DOWNLOAD_URL: &str = "https://music.nodeshift.space/app/files/win/download";

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct UpdateManifest {
    #[serde(default)]
    pub platform: String,
    #[serde(default)]
    pub version: String,
    #[serde(default)]
    pub build: i64,
    #[serde(default)]
    pub file: String,
    #[serde(default)]
    pub size: u64,
    #[serde(default)]
    pub sha256: String,
    pub notes: Option<String>,
    pub built_at: Option<String>,
    pub available: Option<bool>,
}

pub async fn check(http: &reqwest::Client, current_version: &str, current_build: i64) -> Result<Option<UpdateManifest>> {
    let text = net::get_text(http, MANIFEST_URL, None).await?;
    let manifest: UpdateManifest = serde_json::from_str(&text)?;
    if manifest.available == Some(false) || manifest.file.is_empty() {
        return Ok(None);
    }
    if is_newer(&manifest.version, manifest.build, current_version, current_build) {
        Ok(Some(manifest))
    } else {
        Ok(None)
    }
}

pub async fn download(http: &reqwest::Client, manifest: &UpdateManifest, directory: &Path) -> Result<PathBuf> {
    let target = directory.join("NodeShiftMusic-Setup.exe");
    net::download(http, DOWNLOAD_URL, &target, None).await?;
    let check_path = target.clone();
    let hash = tokio::task::spawn_blocking(move || hash_file(&check_path)).await??;
    if !manifest.sha256.is_empty() && !hash.eq_ignore_ascii_case(&manifest.sha256) {
        let _ = std::fs::remove_file(&target);
        return Err(anyhow!("checksum mismatch"));
    }
    Ok(target)
}
