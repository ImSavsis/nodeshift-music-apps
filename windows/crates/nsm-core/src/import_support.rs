use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use anyhow::Result;
use sha2::{Digest, Sha256};
use uuid::Uuid;

pub const AUDIO_EXTENSIONS: [&str; 8] = ["mp3", "flac", "m4a", "aac", "ogg", "oga", "opus", "wav"];
pub const ARCHIVE_EXTENSIONS: [&str; 2] = ["zip", "7z"];

#[derive(Debug, Clone)]
pub struct Candidate {
    pub path: PathBuf,
    pub name: String,
    pub group: String,
}

#[derive(Debug, Default)]
pub struct ScanResult {
    pub candidates: Vec<Candidate>,
    pub skipped: usize,
}

pub fn extension_of(path: &Path) -> String {
    path.extension().and_then(|value| value.to_str()).unwrap_or("").to_lowercase()
}

pub fn copy_and_hash(source: &Path, destination: &Path) -> Result<(String, u64)> {
    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut input = File::open(source)?;
    let mut output = File::create(destination)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 1 << 20];
    let mut total = 0u64;
    loop {
        let read = input.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        output.write_all(&buffer[..read])?;
        total += read as u64;
    }
    output.flush()?;
    Ok((hex::encode(hasher.finalize()), total))
}

pub fn hash_file(path: &Path) -> Result<String> {
    let mut input = File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 1 << 20];
    loop {
        let read = input.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(hex::encode(hasher.finalize()))
}

pub fn sanitize(path: &str) -> String {
    path.replace('\\', "/")
        .split('/')
        .filter(|part| !part.is_empty() && *part != "." && *part != "..")
        .collect::<Vec<_>>()
        .join("/")
}

fn safe_target(directory: &Path, entry_name: &str) -> Option<PathBuf> {
    let safe = sanitize(entry_name);
    if safe.is_empty() {
        return None;
    }
    let target = directory.join(&safe);
    if !target.starts_with(directory) {
        return None;
    }
    Some(target)
}

fn decode_zip_name(raw: &[u8], fallback: &str) -> String {
    match std::str::from_utf8(raw) {
        Ok(text) => text.to_string(),
        Err(_) => {
            let (text, _, failed) = encoding_rs::IBM866.decode(raw);
            if failed {
                fallback.to_string()
            } else {
                text.into_owned()
            }
        }
    }
}

pub fn extract_archive(archive: &Path, directory: &Path) -> Result<()> {
    fs::create_dir_all(directory)?;
    match extension_of(archive).as_str() {
        "zip" => {
            let file = File::open(archive)?;
            let mut zip = zip::ZipArchive::new(file)?;
            for index in 0..zip.len() {
                let mut entry = zip.by_index(index)?;
                if entry.is_dir() {
                    continue;
                }
                let name = decode_zip_name(entry.name_raw(), entry.name());
                let Some(target) = safe_target(directory, &name) else {
                    continue;
                };
                if let Some(parent) = target.parent() {
                    fs::create_dir_all(parent)?;
                }
                let mut output = File::create(target)?;
                std::io::copy(&mut entry, &mut output)?;
            }
        }
        "7z" => {
            let mut reader = sevenz_rust2::ArchiveReader::open(archive, sevenz_rust2::Password::empty())?;
            reader.for_each_entries(|entry, data| {
                if entry.is_directory() {
                    return Ok(true);
                }
                if let Some(target) = safe_target(directory, entry.name()) {
                    if let Some(parent) = target.parent() {
                        fs::create_dir_all(parent)?;
                    }
                    let mut output = File::create(target)?;
                    std::io::copy(data, &mut output)?;
                }
                Ok(true)
            })?;
        }
        _ => {}
    }
    Ok(())
}

pub fn scan(roots: &[PathBuf], scratch: &Path) -> ScanResult {
    let mut result = ScanResult::default();
    for root in roots {
        let group = root.parent().map(|parent| parent.to_string_lossy().to_string()).unwrap_or_default();
        visit(root, &group, scratch, &mut result);
    }
    result
}

fn visit(path: &Path, group: &str, scratch: &Path, result: &mut ScanResult) {
    if path.is_dir() {
        let mut children: Vec<PathBuf> = match fs::read_dir(path) {
            Ok(entries) => entries.filter_map(|entry| entry.ok().map(|entry| entry.path())).collect(),
            Err(_) => return,
        };
        children.sort_by_key(|child| child.file_name().map(|name| name.to_string_lossy().to_lowercase()));
        let own = path.to_string_lossy().to_string();
        for child in children {
            let hidden = child.file_name().map(|name| name.to_string_lossy().starts_with('.')).unwrap_or(false);
            if hidden {
                continue;
            }
            visit(&child, &own, scratch, result);
        }
        return;
    }
    if !path.is_file() {
        return;
    }
    let extension = extension_of(path);
    if ARCHIVE_EXTENSIONS.contains(&extension.as_str()) {
        let target = scratch.join(Uuid::new_v4().to_string());
        match extract_archive(path, &target) {
            Ok(()) => {
                let own = target.to_string_lossy().to_string();
                visit(&target, &own, scratch, result);
            }
            Err(_) => result.skipped += 1,
        }
    } else if AUDIO_EXTENSIONS.contains(&extension.as_str()) {
        let name = path.file_name().map(|name| name.to_string_lossy().to_string()).unwrap_or_default();
        result.candidates.push(Candidate { path: path.to_path_buf(), name, group: group.to_string() });
    } else {
        result.skipped += 1;
    }
}

pub fn normalized_jpeg(data: &[u8], max_side: u32) -> Option<Vec<u8>> {
    let is_jpeg = data.len() > 2 && data[0] == 0xFF && data[1] == 0xD8;
    let image = image::load_from_memory(data).ok()?;
    let longest = image.width().max(image.height());
    if longest <= max_side && is_jpeg {
        return Some(data.to_vec());
    }
    let resized = if longest > max_side { image.resize(max_side, max_side, image::imageops::FilterType::Lanczos3) } else { image };
    let mut output = Vec::new();
    let rgb = resized.to_rgb8();
    let encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut output, 90);
    rgb.write_with_encoder(encoder).ok()?;
    Some(output)
}
