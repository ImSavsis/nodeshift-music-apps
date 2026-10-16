use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use aes_gcm::aead::{Aead, OsRng, Payload};
use aes_gcm::{Aes256Gcm, KeyInit, Nonce};
use anyhow::{anyhow, bail, Result};
use base64::Engine as _;
use hkdf::Hkdf;
use p256::ecdh::diffie_hellman;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use p256::{PublicKey, SecretKey};
use serde::{Deserialize, Serialize};
use sha2::Sha256;

use crate::net::site::TokenStore;

pub const HEADER_SIZE: usize = 64;
pub const TAG_SIZE: usize = 16;
pub const KIND_LOSSLESS: u8 = 1;
pub const KIND_LOSSY: u8 = 2;
pub const BATCH_CHUNKS: u64 = 32;

const MAGIC: &[u8; 4] = b"NSML";
const LICENSE_INFO: &[u8] = b"NSM-LICENSE-1";
const LICENSE_CONTEXT: &[u8] = b"NSM-L1";
const SPARE_SECONDS: u64 = 300;
const OFFLINE_SPARE_SECONDS: u64 = 7 * 24 * 3600;

pub fn kind_name(kind: u8) -> &'static str {
    if kind == KIND_LOSSLESS {
        "lossless"
    } else {
        "lossy"
    }
}

pub fn now_seconds() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|elapsed| elapsed.as_secs()).unwrap_or(0)
}

#[derive(Debug, Clone)]
pub struct Header {
    pub kind: u8,
    pub codec: String,
    pub key_id: u32,
    pub chunk_size: u32,
    pub plain_length: u64,
    pub nonce_prefix: [u8; 8],
    raw: [u8; HEADER_SIZE],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Span {
    pub first_chunk: u64,
    pub last_chunk: u64,
    pub offset: u64,
    pub length: u64,
}

impl Header {
    pub fn parse(bytes: &[u8]) -> Result<Header> {
        if bytes.len() < HEADER_SIZE {
            bail!("header is too short");
        }
        if &bytes[0..4] != MAGIC || bytes[4] != 1 || !(1..=2).contains(&bytes[5]) {
            bail!("not a locked audio file");
        }
        let chunk_size = u32::from_be_bytes(bytes[20..24].try_into()?);
        if chunk_size == 0 {
            bail!("bad chunk size");
        }
        let mut raw = [0u8; HEADER_SIZE];
        raw.copy_from_slice(&bytes[..HEADER_SIZE]);
        let mut nonce_prefix = [0u8; 8];
        nonce_prefix.copy_from_slice(&bytes[32..40]);
        Ok(Header {
            kind: bytes[5],
            codec: String::from_utf8_lossy(&bytes[8..16]).trim_end_matches('\0').to_string(),
            key_id: u32::from_be_bytes(bytes[16..20].try_into()?),
            chunk_size,
            plain_length: u64::from_be_bytes(bytes[24..32].try_into()?),
            nonce_prefix,
            raw,
        })
    }

    pub fn stride(&self) -> u64 {
        self.chunk_size as u64 + TAG_SIZE as u64
    }

    pub fn chunk_count(&self) -> u64 {
        self.plain_length.div_ceil(self.chunk_size as u64)
    }

    pub fn mime(&self) -> &'static str {
        mime_for(&self.codec)
    }

    pub fn span(&self, start: u64, end: u64) -> Span {
        let size = self.chunk_size as u64;
        let first = start / size;
        let last = end / size;
        let from = HEADER_SIZE as u64 + first * self.stride();
        let until = (HEADER_SIZE as u64 + (last + 1) * self.stride()).min(HEADER_SIZE as u64 + self.plain_length + self.chunk_count() * TAG_SIZE as u64);
        Span { first_chunk: first, last_chunk: last, offset: from, length: until - from }
    }
}

pub fn mime_for(codec: &str) -> &'static str {
    match codec {
        "flac" => "audio/flac",
        "aac" | "m4a" | "alac" => "audio/mp4",
        "mp3" => "audio/mpeg",
        "wav" => "audio/wav",
        "ogg" | "opus" => "audio/ogg",
        "aiff" | "aif" => "audio/aiff",
        _ => "application/octet-stream",
    }
}

fn open_chunk(cipher: &Aes256Gcm, header: &Header, index: u64, blob: &[u8]) -> Result<Vec<u8>> {
    let index = u32::try_from(index).map_err(|_| anyhow!("too many chunks"))?;
    let mut nonce = [0u8; 12];
    nonce[..8].copy_from_slice(&header.nonce_prefix);
    nonce[8..].copy_from_slice(&index.to_be_bytes());
    let mut aad = header.raw.to_vec();
    aad.extend_from_slice(&index.to_be_bytes());
    cipher.decrypt(Nonce::from_slice(&nonce), Payload { msg: blob, aad: &aad }).map_err(|_| anyhow!("chunk failed authentication"))
}

pub fn decrypt_range(key: &[u8; 32], header: &Header, span: Span, blob: &[u8], start: u64, end: u64) -> Result<Vec<u8>> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|_| anyhow!("bad key"))?;
    let stride = header.stride() as usize;
    let mut plain: Vec<u8> = Vec::with_capacity(((span.last_chunk - span.first_chunk + 1) * header.chunk_size as u64) as usize);
    for (position, piece) in blob.chunks(stride).enumerate() {
        plain.extend_from_slice(&open_chunk(&cipher, header, span.first_chunk + position as u64, piece)?);
    }
    let skip = (start - span.first_chunk * header.chunk_size as u64) as usize;
    let take = (end - start + 1) as usize;
    if plain.len() < skip + take {
        bail!("short data");
    }
    Ok(plain[skip..skip + take].to_vec())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Grant {
    pub track_id: u32,
    pub kind: u8,
    pub key_id: u32,
    pub name: String,
    pub codec: String,
    pub plain_length: u64,
    pub key_hex: String,
    pub expires_at: u64,
}

impl Grant {
    pub fn key(&self) -> Result<[u8; 32]> {
        let bytes = hex::decode(&self.key_hex)?;
        bytes.try_into().map_err(|_| anyhow!("bad key length"))
    }
}

#[derive(Debug, Deserialize)]
pub struct WireItem {
    pub track_id: u32,
    pub kind: String,
    pub key_id: u32,
    pub name: String,
    pub codec: String,
    pub plain_length: u64,
    pub nonce: String,
    pub wrapped: String,
}

#[derive(Debug, Deserialize)]
pub struct WireLicense {
    pub server_pub: String,
    pub expires_at: u64,
    pub items: Vec<WireItem>,
}

pub struct Exchange {
    secret: SecretKey,
}

impl Exchange {
    pub fn random() -> Self {
        Self { secret: SecretKey::random(&mut OsRng) }
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        Ok(Self { secret: SecretKey::from_slice(bytes).map_err(|_| anyhow!("bad private key"))? })
    }

    pub fn public_bytes(&self) -> Vec<u8> {
        self.secret.public_key().to_encoded_point(false).as_bytes().to_vec()
    }

    pub fn public_b64(&self) -> String {
        base64::engine::general_purpose::STANDARD.encode(self.public_bytes())
    }

    pub fn open(&self, license: &WireLicense) -> Result<Vec<Grant>> {
        let standard = base64::engine::general_purpose::STANDARD;
        let server_pub = standard.decode(&license.server_pub)?;
        let public = PublicKey::from_sec1_bytes(&server_pub).map_err(|_| anyhow!("bad server key"))?;
        let shared = diffie_hellman(self.secret.to_nonzero_scalar(), public.as_affine());
        let mut salt = self.public_bytes();
        salt.extend_from_slice(&server_pub);
        let mut wrap_key = [0u8; 32];
        Hkdf::<Sha256>::new(Some(&salt), shared.raw_secret_bytes()).expand(LICENSE_INFO, &mut wrap_key).map_err(|_| anyhow!("key derivation failed"))?;
        let cipher = Aes256Gcm::new_from_slice(&wrap_key).map_err(|_| anyhow!("bad wrap key"))?;
        let mut grants = Vec::new();
        for item in &license.items {
            let kind = if item.kind == "lossless" { KIND_LOSSLESS } else { KIND_LOSSY };
            let mut context = LICENSE_CONTEXT.to_vec();
            context.extend_from_slice(&item.track_id.to_be_bytes());
            context.push(kind);
            context.extend_from_slice(&item.key_id.to_be_bytes());
            context.extend_from_slice(&license.expires_at.to_be_bytes());
            let nonce = standard.decode(&item.nonce)?;
            let wrapped = standard.decode(&item.wrapped)?;
            if nonce.len() != 12 {
                bail!("bad nonce");
            }
            let key = cipher.decrypt(Nonce::from_slice(&nonce), Payload { msg: &wrapped, aad: &context }).map_err(|_| anyhow!("license failed authentication"))?;
            grants.push(Grant {
                track_id: item.track_id,
                kind,
                key_id: item.key_id,
                name: item.name.clone(),
                codec: item.codec.clone(),
                plain_length: item.plain_length,
                key_hex: hex::encode(key),
                expires_at: license.expires_at,
            });
        }
        Ok(grants)
    }
}

pub struct Vault {
    store: Arc<dyn TokenStore>,
    grants: Mutex<HashMap<String, Grant>>,
    headers: Mutex<HashMap<String, Header>>,
}

impl Vault {
    pub fn new(store: Arc<dyn TokenStore>) -> Self {
        Self { store, grants: Mutex::new(HashMap::new()), headers: Mutex::new(HashMap::new()) }
    }

    fn slot(track_id: u32, kind: u8) -> String {
        format!("drm:{track_id}:{kind}")
    }

    pub fn lookup(&self, track_id: u32, kind: u8, offline: bool) -> Option<Grant> {
        let slot = Self::slot(track_id, kind);
        let spare = if offline { OFFLINE_SPARE_SECONDS } else { SPARE_SECONDS };
        let usable = |grant: &Grant| grant.expires_at > now_seconds() + spare;
        if let Some(found) = self.grants.lock().ok().and_then(|map| map.get(&slot).cloned()).filter(usable) {
            return Some(found);
        }
        let stored: Grant = serde_json::from_str(&self.store.get(&slot)?).ok()?;
        if !usable(&stored) {
            return None;
        }
        if let Ok(mut map) = self.grants.lock() {
            map.insert(slot, stored.clone());
        }
        Some(stored)
    }

    pub fn playable(&self, track_id: u32, kind: u8) -> Option<Grant> {
        let slot = Self::slot(track_id, kind);
        let stored: Grant = self.grants.lock().ok().and_then(|map| map.get(&slot).cloned()).or_else(|| serde_json::from_str(&self.store.get(&slot)?).ok())?;
        (stored.expires_at > now_seconds()).then_some(stored)
    }

    pub fn remember(&self, grant: &Grant) {
        let slot = Self::slot(grant.track_id, grant.kind);
        if let Ok(text) = serde_json::to_string(grant) {
            self.store.set(&slot, &text);
        }
        if let Ok(mut map) = self.grants.lock() {
            map.insert(slot, grant.clone());
        }
    }

    pub fn forget(&self, track_id: u32) {
        for kind in [KIND_LOSSLESS, KIND_LOSSY] {
            let slot = Self::slot(track_id, kind);
            self.store.remove(&slot);
            if let Ok(mut map) = self.grants.lock() {
                map.remove(&slot);
            }
        }
    }

    pub fn header(&self, name: &str) -> Option<Header> {
        self.headers.lock().ok().and_then(|map| map.get(name).cloned())
    }

    pub fn keep_header(&self, name: &str, header: &Header) {
        if let Ok(mut map) = self.headers.lock() {
            map.insert(name.to_string(), header.clone());
        }
    }
}

pub fn is_locked_name(name: &str) -> bool {
    name.ends_with(".nlac") || name.ends_with(".np3")
}
