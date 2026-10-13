use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anyhow::{anyhow, Result};
use serde::Serialize;
use uuid::Uuid;

use crate::algo::duplicates::{DuplicateIndex, DuplicateKind, TrackFingerprint};
use crate::algo::filename_parser::{self, ParsedName};
use crate::algo::lrc::{self, LyricLine, LyricsKind};
use crate::algo::palette;
use crate::algo::text_matching;
use crate::db::Db;
use crate::import_support::{self, Candidate};
use crate::model::{now_ms, LyricsRecord, Playlist, Track};
use crate::net::catalog::{Catalog, CatalogMatch, CatalogQuery};
use crate::net::site::{self, Site, SiteError, SitePlaylist, SiteTrack, SiteUser, TokenStore};
use crate::net::{self, lyrics_client, motion, RateLimiter};
use crate::paths::Paths;
use crate::tags::{self, WriteTags};

#[derive(Debug, Clone)]
pub enum Event {
    Library,
    Import,
    Site,
    Toast(String),
}

pub type Emit = Arc<dyn Fn(Event) + Send + Sync>;

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum ItemState {
    Waiting,
    Working { text: String },
    Done,
    Duplicate { existing_id: String, dup_kind: String, better_quality: bool },
    Skipped { text: String },
    Failed { text: String },
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportItem {
    pub id: String,
    pub name: String,
    pub state: ItemState,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub cover_name: Option<String>,
    pub track_id: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportSummary {
    pub added: usize,
    pub duplicates: usize,
    pub failed: usize,
    pub ignored: usize,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportSnapshot {
    pub items: Vec<ImportItem>,
    pub summary: ImportSummary,
    pub running: bool,
    pub pending_duplicates: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    Skip,
    KeepBoth,
    Replace,
}

impl Decision {
    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "skip" => Some(Decision::Skip),
            "keepBoth" => Some(Decision::KeepBoth),
            "replace" => Some(Decision::Replace),
            _ => None,
        }
    }
}

struct Pending {
    track: Track,
    replacing: String,
}

#[derive(Default)]
struct ImportState {
    items: Vec<ImportItem>,
    summary: ImportSummary,
    running: bool,
    pending: HashMap<String, Pending>,
    index: DuplicateIndex,
    album_covers: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(tag = "phase", rename_all = "camelCase")]
pub enum SyncPhase {
    Idle,
    Loading,
    Downloading,
    Done,
    Failed { text: String },
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ListState {
    pub id: String,
    pub name: String,
    pub total: usize,
    pub done: usize,
    pub phase: SyncPhase,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SiteSnapshot {
    pub user: Option<SiteUser>,
    pub busy: bool,
    pub last_error: Option<String>,
    pub favorites: ListState,
    pub playlists: Vec<ListState>,
    pub refreshing: bool,
    pub needs_login: bool,
    pub lossless: bool,
}

struct SiteState {
    user: Option<SiteUser>,
    busy: bool,
    last_error: Option<String>,
    favorites: ListState,
    playlists: Vec<ListState>,
    refreshing: bool,
    needs_login: bool,
    running: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "state", rename_all = "camelCase")]
pub enum LyricsDto {
    Synced { lines: Vec<LyricLine>, source: Option<String>, kind: LyricsKind },
    Plain { text: String, source: Option<String> },
    None,
}

struct Inner {
    paths: Paths,
    db: Db,
    http: reqwest::Client,
    limiter: Arc<RateLimiter>,
    catalog: Option<Catalog>,
    emit: Emit,
    import: Mutex<ImportState>,
    run_lock: tokio::sync::Mutex<()>,
    site: Site,
    site_state: Mutex<SiteState>,
    palettes: Mutex<HashMap<String, Vec<[u8; 3]>>>,
    lossless: Mutex<bool>,
    motion_auto: Mutex<bool>,
    lyrics_inflight: Mutex<std::collections::HashSet<String>>,
}

#[derive(Clone)]
pub struct Engine {
    inner: Arc<Inner>,
}

pub enum CatalogSource {
    None,
    Network,
    Custom(Catalog),
}

pub struct EngineConfig {
    pub paths: Paths,
    pub catalog: CatalogSource,
    pub tokens: Arc<dyn TokenStore>,
    pub emit: Emit,
}

fn fingerprint(track: &Track) -> TrackFingerprint {
    TrackFingerprint {
        id: track.id.clone(),
        artist: track.artist.clone(),
        title: track.title.clone(),
        duration_ms: Some(track.duration_ms),
        file_hash: track.file_hash.clone(),
        format: track.format.clone(),
        bitrate_kbps: track.bitrate_kbps,
    }
}

fn idle_list(id: &str, name: &str) -> ListState {
    ListState { id: id.into(), name: name.into(), total: 0, done: 0, phase: SyncPhase::Idle }
}

impl Engine {
    pub fn new(config: EngineConfig) -> Result<Self> {
        let db = Db::open(&config.paths.database)?;
        let http = net::client();
        let limiter = RateLimiter::shared();
        let site = Site::new(http.clone(), config.tokens);
        let catalog = match config.catalog {
            CatalogSource::None => None,
            CatalogSource::Network => Some(Catalog::network(http.clone(), limiter.clone())),
            CatalogSource::Custom(custom) => Some(custom),
        };
        let inner = Inner {
            paths: config.paths,
            db,
            http,
            limiter,
            catalog,
            emit: config.emit,
            import: Mutex::new(ImportState::default()),
            run_lock: tokio::sync::Mutex::new(()),
            site,
            site_state: Mutex::new(SiteState {
                user: None,
                busy: false,
                last_error: None,
                favorites: idle_list("favorites", "Понравившиеся"),
                playlists: Vec::new(),
                refreshing: false,
                needs_login: false,
                running: false,
            }),
            palettes: Mutex::new(HashMap::new()),
            lossless: Mutex::new(true),
            motion_auto: Mutex::new(true),
            lyrics_inflight: Mutex::new(Default::default()),
        };
        Ok(Self { inner: Arc::new(inner) })
    }

    pub fn paths(&self) -> &Paths {
        &self.inner.paths
    }

    pub fn db(&self) -> &Db {
        &self.inner.db
    }

    pub fn http(&self) -> reqwest::Client {
        self.inner.http.clone()
    }

    pub fn site(&self) -> &Site {
        &self.inner.site
    }

    fn emit(&self, event: Event) {
        (self.inner.emit)(event);
    }

    pub fn library(&self) -> Result<Vec<Track>> {
        Ok(self.inner.db.all_tracks()?)
    }

    pub fn playlists(&self) -> Result<Vec<Playlist>> {
        Ok(self.inner.db.playlists()?)
    }

    pub fn set_favorite(&self, id: &str, value: bool) -> Result<()> {
        self.inner.db.set_favorite(id, value)?;
        self.emit(Event::Library);
        Ok(())
    }

    pub fn mark_played(&self, id: &str) -> Result<()> {
        self.inner.db.mark_played(id, now_ms())?;
        self.emit(Event::Library);
        Ok(())
    }

    pub fn delete_track(&self, id: &str) -> Result<()> {
        let Some(track) = self.inner.db.track(id)? else {
            return Ok(());
        };
        let others: Vec<Track> = self.inner.db.all_tracks()?.into_iter().filter(|other| other.id != id).collect();
        let _ = std::fs::remove_file(self.inner.paths.track_file(&track.file_name));
        if let Some(cover) = &track.cover_name {
            if !others.iter().any(|other| other.cover_name.as_ref() == Some(cover)) {
                let _ = std::fs::remove_file(self.inner.paths.cover_file(cover));
            }
        }
        if let Some(motion_name) = &track.motion_name {
            if !others.iter().any(|other| other.motion_name.as_ref() == Some(motion_name)) {
                let _ = std::fs::remove_file(self.inner.paths.motion_file(motion_name));
            }
        }
        self.inner.db.delete_track(id)?;
        if let Ok(mut state) = self.inner.import.lock() {
            state.index.remove(id);
        }
        self.emit(Event::Library);
        Ok(())
    }

    pub fn update_track(&self, id: &str, title: &str, artist: &str, album: Option<String>, track_number: Option<i64>) -> Result<Track> {
        let mut track = self.inner.db.track(id)?.ok_or_else(|| anyhow!("no track"))?;
        track.title = title.trim().to_string();
        track.artist = artist.trim().to_string();
        track.album = album.filter(|value| !value.trim().is_empty());
        track.track_number = track_number;
        self.inner.db.save_track(&track)?;
        let path = self.inner.paths.track_file(&track.file_name);
        let write = WriteTags {
            title: track.title.clone(),
            artist: track.artist.clone(),
            album: track.album.clone(),
            track_number: track.track_number.map(|value| value as u32),
            ..Default::default()
        };
        let _ = tags::write(&path, &write);
        self.emit(Event::Library);
        Ok(track)
    }

    pub fn create_playlist(&self, name: &str) -> Result<Playlist> {
        let playlist = Playlist { id: Uuid::new_v4().to_string(), name: name.trim().to_string(), created_at: now_ms(), ..Default::default() };
        self.inner.db.save_playlist(&playlist)?;
        self.emit(Event::Library);
        Ok(playlist)
    }

    pub fn playlist_add(&self, playlist_id: &str, track_id: &str) -> Result<()> {
        let mut playlist = self.inner.db.playlists()?.into_iter().find(|item| item.id == playlist_id).ok_or_else(|| anyhow!("no playlist"))?;
        if !playlist.track_ids.iter().any(|id| id == track_id) {
            playlist.track_ids.push(track_id.to_string());
            self.inner.db.save_playlist(&playlist)?;
            self.emit(Event::Library);
        }
        Ok(())
    }

    pub fn playlist_remove(&self, playlist_id: &str, track_id: &str) -> Result<()> {
        let mut playlist = self.inner.db.playlists()?.into_iter().find(|item| item.id == playlist_id).ok_or_else(|| anyhow!("no playlist"))?;
        playlist.track_ids.retain(|id| id != track_id);
        self.inner.db.save_playlist(&playlist)?;
        self.emit(Event::Library);
        Ok(())
    }

    pub fn rename_playlist(&self, playlist_id: &str, name: &str) -> Result<()> {
        let mut playlist = self.inner.db.playlists()?.into_iter().find(|item| item.id == playlist_id).ok_or_else(|| anyhow!("no playlist"))?;
        playlist.name = name.trim().to_string();
        self.inner.db.save_playlist(&playlist)?;
        self.emit(Event::Library);
        Ok(())
    }

    pub fn delete_playlist(&self, playlist_id: &str) -> Result<()> {
        self.inner.db.delete_playlist(playlist_id)?;
        self.emit(Event::Library);
        Ok(())
    }

    pub fn import_snapshot(&self) -> ImportSnapshot {
        let state = self.inner.import.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        ImportSnapshot {
            items: state.items.clone(),
            summary: state.summary.clone(),
            running: state.running,
            pending_duplicates: state.pending.len(),
        }
    }

    pub fn import_clear(&self) {
        {
            let mut state = self.inner.import.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            state.items.retain(|item| !matches!(item.state, ItemState::Done | ItemState::Skipped { .. } | ItemState::Failed { .. }));
            if state.items.is_empty() {
                state.summary = ImportSummary::default();
            }
        }
        self.emit(Event::Import);
    }

    pub fn import_decide(&self, id: &str, decision: Decision) {
        let waiting = {
            let mut state = self.inner.import.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            state.pending.remove(id)
        };
        let Some(waiting) = waiting else {
            return;
        };
        match decision {
            Decision::Skip => {
                self.discard(&waiting.track);
                self.update_item(id, |item| item.state = ItemState::Skipped { text: "Пропущен: уже есть".into() });
                self.with_state(|state| state.summary.duplicates += 1);
            }
            Decision::KeepBoth => self.commit(id, waiting.track, None),
            Decision::Replace => {
                let replacing = waiting.replacing.clone();
                self.commit(id, waiting.track, Some(replacing));
            }
        }
        self.emit(Event::Import);
    }

    pub fn import_skip_all_duplicates(&self) {
        let ids: Vec<String> = {
            let state = self.inner.import.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            state.pending.keys().cloned().collect()
        };
        for id in ids {
            self.import_decide(&id, Decision::Skip);
        }
    }

    fn with_state<R>(&self, change: impl FnOnce(&mut ImportState) -> R) -> R {
        let mut state = self.inner.import.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        change(&mut state)
    }

    fn update_item(&self, id: &str, change: impl FnOnce(&mut ImportItem)) {
        self.with_state(|state| {
            if let Some(item) = state.items.iter_mut().find(|item| item.id == id) {
                change(item);
            }
        });
        self.emit(Event::Import);
    }

    fn discard(&self, track: &Track) {
        let _ = std::fs::remove_file(self.inner.paths.track_file(&track.file_name));
        if let Some(cover) = &track.cover_name {
            let shared = self.with_state(|state| state.album_covers.values().any(|name| name == cover));
            if !shared {
                let _ = std::fs::remove_file(self.inner.paths.cover_file(cover));
            }
        }
    }

    pub fn start_import(&self, roots: Vec<PathBuf>) {
        if roots.is_empty() {
            return;
        }
        let engine = self.clone();
        tokio::spawn(async move {
            engine.run_import(roots).await;
        });
    }

    pub async fn run_import(&self, roots: Vec<PathBuf>) {
        let _guard = self.inner.run_lock.lock().await;
        self.with_state(|state| state.running = true);
        self.emit(Event::Import);
        let scratch = self.inner.paths.scratch.join(Uuid::new_v4().to_string());
        let scan_scratch = scratch.clone();
        let scan = tokio::task::spawn_blocking(move || import_support::scan(&roots, &scan_scratch)).await.unwrap_or_default();
        self.with_state(|state| state.summary.ignored += scan.skipped);
        match self.inner.db.all_tracks() {
            Ok(tracks) => {
                let index = DuplicateIndex::new(tracks.iter().map(fingerprint).collect());
                self.with_state(|state| state.index = index);
            }
            Err(_) => {}
        }
        let mut groups: HashMap<String, Vec<usize>> = HashMap::new();
        for (position, candidate) in scan.candidates.iter().enumerate() {
            groups.entry(candidate.group.clone()).or_default().push(position);
        }
        let mut parsed: Vec<ParsedName> = vec![ParsedName::default(); scan.candidates.len()];
        for positions in groups.values() {
            let names: Vec<String> = positions.iter().map(|position| scan.candidates[*position].name.clone()).collect();
            for (position, result) in positions.iter().zip(filename_parser::parse_batch(&names)) {
                parsed[*position] = result;
            }
        }
        let mut ids: Vec<String> = Vec::new();
        self.with_state(|state| {
            for (position, candidate) in scan.candidates.iter().enumerate() {
                let id = Uuid::new_v4().to_string();
                ids.push(id.clone());
                state.items.push(ImportItem {
                    id,
                    name: candidate.name.clone(),
                    state: ItemState::Waiting,
                    title: parsed[position].title.clone(),
                    artist: parsed[position].artist.clone(),
                    cover_name: None,
                    track_id: None,
                });
            }
        });
        self.emit(Event::Import);
        for (position, candidate) in scan.candidates.iter().enumerate() {
            self.process(candidate, &ids[position], &parsed[position]).await;
        }
        let cleanup = scratch.clone();
        let _ = tokio::task::spawn_blocking(move || std::fs::remove_dir_all(cleanup)).await;
        self.with_state(|state| state.running = false);
        self.emit(Event::Import);
        self.emit(Event::Library);
    }

    async fn process(&self, candidate: &Candidate, id: &str, parsed: &ParsedName) {
        let extension = import_support::extension_of(&candidate.path);
        let track_id = Uuid::new_v4().to_string();
        let file_name = format!("{track_id}.{extension}");
        let destination = self.inner.paths.track_file(&file_name);
        self.update_item(id, |item| item.state = ItemState::Working { text: "Копируем".into() });

        let source = candidate.path.clone();
        let target = destination.clone();
        let copied = tokio::task::spawn_blocking(move || import_support::copy_and_hash(&source, &target)).await;
        let (hash, size) = match copied {
            Ok(Ok(result)) => result,
            _ => {
                let _ = std::fs::remove_file(&destination);
                self.update_item(id, |item| item.state = ItemState::Failed { text: "Не удалось скопировать".into() });
                self.with_state(|state| state.summary.failed += 1);
                return;
            }
        };

        if self.with_state(|state| state.index.existing_id(&hash)).is_some() {
            let _ = std::fs::remove_file(&destination);
            self.update_item(id, |item| item.state = ItemState::Skipped { text: "Уже есть в библиотеке".into() });
            self.with_state(|state| state.summary.duplicates += 1);
            return;
        }

        self.update_item(id, |item| item.state = ItemState::Working { text: "Читаем теги".into() });
        let read_path = destination.clone();
        let tags = tokio::task::spawn_blocking(move || tags::read(&read_path)).await.ok().flatten();
        let Some(tags) = tags else {
            let _ = std::fs::remove_file(&destination);
            self.update_item(id, |item| item.state = ItemState::Failed { text: "Формат не читается".into() });
            self.with_state(|state| state.summary.failed += 1);
            return;
        };

        let stem = candidate.path.file_stem().map(|value| value.to_string_lossy().to_string()).unwrap_or_default();
        let mut title = tags.title.clone().or_else(|| parsed.title.clone()).unwrap_or(stem);
        let mut artist = tags.artist.clone().or_else(|| parsed.artist.clone()).unwrap_or_default();
        let mut album = tags.album.clone();
        let mut album_artist = tags.album_artist.clone();
        let mut track_number = tags.track_number.or(parsed.track);
        let mut disc_number = tags.disc_number.or(parsed.disc);
        let mut year = tags.year;
        let mut genre = tags.genre.clone();
        let mut isrc: Option<String> = None;
        let mut cover_data = tags.cover.clone();
        let duration = tags.duration.unwrap_or(0.0);

        if let Some(catalog) = &self.inner.catalog {
            self.update_item(id, |item| item.state = ItemState::Working { text: "Ищем в каталоге".into() });
            let query = CatalogQuery {
                title: title.clone(),
                artist: artist.clone(),
                album: album.clone(),
                duration: if duration > 0.0 { Some(duration) } else { None },
            };
            if let Some(found) = (catalog.lookup)(query).await {
                apply_match(&found, &tags.title, &tags.artist, &mut title, &mut artist);
                album = album.or(found.album.clone());
                album_artist = album_artist.or(found.album_artist.clone());
                track_number = track_number.or(found.track_number);
                disc_number = disc_number.or(found.disc_number);
                year = year.or(found.year);
                genre = genre.or(found.genre.clone());
                isrc = found.isrc.clone();
                if cover_data.is_none() {
                    if let Some(url) = found.cover_url.clone() {
                        cover_data = (catalog.cover)(url).await;
                    }
                }
            }
        }

        if artist.is_empty() {
            artist = "Неизвестный исполнитель".into();
        }

        let album_key = album.as_ref().map(|album| format!("{}|{}", artist.to_lowercase(), album.to_lowercase()));
        let mut cover_name: Option<String> = None;
        let mut jpeg: Option<Vec<u8>> = None;
        let known = album_key.as_ref().and_then(|key| self.with_state(|state| state.album_covers.get(key).cloned()));
        if let Some(known) = known {
            cover_name = Some(known);
        } else if let Some(data) = cover_data {
            jpeg = tokio::task::spawn_blocking(move || import_support::normalized_jpeg(&data, 1400)).await.ok().flatten();
            if jpeg.is_some() {
                cover_name = Some(format!("{}.jpg", Uuid::new_v4()));
            }
        }

        self.update_item(id, |item| item.state = ItemState::Working { text: "Пишем теги".into() });
        let write = WriteTags {
            title: title.clone(),
            artist: artist.clone(),
            album: album.clone(),
            album_artist: album_artist.clone(),
            genre: genre.clone(),
            track_number,
            disc_number,
            year,
            isrc,
            cover: jpeg.clone(),
        };
        let write_path = destination.clone();
        let _ = tokio::task::spawn_blocking(move || tags::write(&write_path, &write)).await;

        if let (Some(data), Some(name)) = (&jpeg, &cover_name) {
            let _ = std::fs::write(self.inner.paths.cover_file(name), data);
            if let Some(key) = &album_key {
                self.with_state(|state| {
                    state.album_covers.insert(key.clone(), name.clone());
                });
            }
        }

        let final_size = std::fs::metadata(&destination).map(|meta| meta.len()).unwrap_or(size);
        let mut track = Track::blank(track_id);
        track.title = title.clone();
        track.artist = artist.clone();
        track.album = album;
        track.album_artist = album_artist;
        track.track_number = track_number.map(i64::from);
        track.disc_number = disc_number.map(i64::from);
        track.year = year.map(i64::from);
        track.genre = genre;
        track.duration_ms = (duration * 1000.0).round() as i64;
        track.format = extension;
        track.bitrate_kbps = tags.bitrate_kbps.map(i64::from);
        track.sample_rate = tags.sample_rate.map(i64::from);
        track.bit_depth = tags.bit_depth.map(i64::from);
        track.file_name = file_name;
        track.file_size = final_size as i64;
        track.file_hash = Some(hash);
        track.cover_name = cover_name.clone();

        let duplicates = self.with_state(|state| state.index.matches(&fingerprint(&track)));
        self.update_item(id, |item| {
            item.title = Some(title.clone());
            item.artist = Some(artist.clone());
            item.cover_name = cover_name.clone();
        });
        if let Some(hit) = duplicates.iter().find(|hit| hit.kind != DuplicateKind::SameFile) {
            let existing = hit.existing_id.clone();
            let kind = hit.kind.as_str().to_string();
            let better = hit.candidate_is_better_quality;
            self.with_state(|state| {
                state.pending.insert(id.to_string(), Pending { track: track.clone(), replacing: existing.clone() });
            });
            self.update_item(id, |item| item.state = ItemState::Duplicate { existing_id: existing, dup_kind: kind, better_quality: better });
            return;
        }
        self.commit(id, track, None);
    }

    fn commit(&self, id: &str, track: Track, replacing: Option<String>) {
        if let Some(old_id) = replacing.filter(|value| !value.is_empty()) {
            if let Ok(Some(old)) = self.inner.db.track(&old_id) {
                let _ = std::fs::remove_file(self.inner.paths.track_file(&old.file_name));
            }
            let _ = self.inner.db.delete_track(&old_id);
            self.with_state(|state| state.index.remove(&old_id));
        }
        if self.inner.db.save_track(&track).is_err() {
            self.update_item(id, |item| item.state = ItemState::Failed { text: "Не удалось сохранить".into() });
            self.with_state(|state| state.summary.failed += 1);
            return;
        }
        self.with_state(|state| {
            state.index.add(fingerprint(&track));
            state.summary.added += 1;
        });
        let track_id = track.id.clone();
        self.update_item(id, |item| {
            item.state = ItemState::Done;
            item.track_id = Some(track_id.clone());
        });
        self.emit(Event::Library);
        self.enrich(track);
    }

    fn enrich(&self, track: Track) {
        let engine = self.clone();
        tokio::spawn(async move {
            let _ = engine.lyrics(&track.id, false).await;
            engine.find_motion(&track).await;
        });
    }

    fn checks_path(&self) -> PathBuf {
        self.inner.paths.base.join("motion_checked.json")
    }

    fn album_key(track: &Track) -> Option<String> {
        let album = track.album.as_ref().filter(|value| !value.is_empty())?;
        let artist = track.album_artist.clone().unwrap_or_else(|| track.artist.clone());
        Some(format!("{}|{}", text_matching::artist_key(&artist), text_matching::normalize(album)))
    }

    async fn find_motion(&self, track: &Track) {
        if !*self.inner.motion_auto.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) {
            return;
        }
        let Some(key) = Self::album_key(track) else {
            return;
        };
        let Some(album) = track.album.clone() else {
            return;
        };
        if track.motion_name.is_some() {
            return;
        }
        let mut checks: HashMap<String, i64> = std::fs::read_to_string(self.checks_path())
            .ok()
            .and_then(|text| serde_json::from_str(&text).ok())
            .unwrap_or_default();
        if checks.get(&key).map(|stamp| now_ms() - stamp < 30 * 86_400_000).unwrap_or(false) {
            return;
        }
        let artist = track.album_artist.clone().unwrap_or_else(|| track.artist.clone());
        let file_key = {
            use sha2::{Digest, Sha256};
            hex::encode(&Sha256::digest(key.as_bytes())[..8])
        };
        let files = motion::find(&self.inner.http, &self.inner.limiter, &artist, &album, &self.inner.paths.motion, &file_key).await;
        checks.insert(key.clone(), now_ms());
        if let Ok(text) = serde_json::to_string(&checks) {
            let _ = std::fs::write(self.checks_path(), text);
        }
        let Some(files) = files else {
            return;
        };
        if let Ok(all) = self.inner.db.all_tracks() {
            for mut sibling in all.into_iter().filter(|other| Self::album_key(other).as_deref() == Some(key.as_str())) {
                sibling.motion_name = files.square.as_ref().and_then(|path| path.file_name()).map(|name| name.to_string_lossy().to_string());
                sibling.motion3x4_name = files.tall.as_ref().and_then(|path| path.file_name()).map(|name| name.to_string_lossy().to_string());
                let _ = self.inner.db.save_track(&sibling);
            }
            self.emit(Event::Library);
        }
    }

    pub fn palette(&self, cover_name: &str) -> Vec<[u8; 3]> {
        if let Some(hit) = self.inner.palettes.lock().ok().and_then(|map| map.get(cover_name).cloned()) {
            return hit;
        }
        let computed = self.compute_palette(cover_name);
        if let Ok(mut map) = self.inner.palettes.lock() {
            map.insert(cover_name.to_string(), computed.clone());
        }
        computed
    }

    fn compute_palette(&self, cover_name: &str) -> Vec<[u8; 3]> {
        let fallback = || palette::FALLBACK.iter().map(|color| [color.r, color.g, color.b]).collect::<Vec<_>>();
        let path = self.inner.paths.cover_file(cover_name);
        let Ok(image) = image::open(path) else {
            return fallback();
        };
        let small = image.resize_exact(48, 48, image::imageops::FilterType::Triangle).to_rgba8();
        palette::extract(small.as_raw()).iter().map(|color| [color.r, color.g, color.b]).collect()
    }

    pub async fn lyrics(&self, track_id: &str, force: bool) -> Result<LyricsDto> {
        let Some(track) = self.inner.db.track(track_id)? else {
            return Ok(LyricsDto::None);
        };
        if !force {
            if let Some(record) = self.inner.db.lyrics(track_id)? {
                if let Some(stored) = stored_lyrics(&record) {
                    return Ok(stored);
                }
            }
        }
        {
            let mut inflight = self.inner.lyrics_inflight.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            if !inflight.insert(track_id.to_string()) {
                return Ok(LyricsDto::None);
            }
        }
        let result = self.resolve_lyrics(&track, force).await;
        self.inner.lyrics_inflight.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).remove(track_id);
        result
    }

    fn save_lyrics(&self, track: &Track, kind: &str, source: &str, lrc: Option<String>, plain: Option<String>) {
        let _ = self.inner.db.save_lyrics(&LyricsRecord {
            track_id: track.id.clone(),
            kind: kind.into(),
            source: source.into(),
            lrc,
            plain,
            checked_at: now_ms(),
        });
    }

    async fn resolve_lyrics(&self, track: &Track, force: bool) -> Result<LyricsDto> {
        if !force {
            let path = self.inner.paths.track_file(&track.file_name);
            let embedded = tokio::task::spawn_blocking(move || tags::read(&path).and_then(|tags| tags.lyrics)).await.ok().flatten();
            if let Some(text) = embedded.filter(|text| !text.is_empty()) {
                let lines = lrc::parse(&text);
                if lines.len() >= 2 {
                    let kind = lrc::kind(&lines);
                    let label = if kind == LyricsKind::Word { "word" } else { "line" };
                    self.save_lyrics(track, label, "embedded", Some(text), None);
                    return Ok(LyricsDto::Synced { lines, source: Some("embedded".into()), kind });
                }
                self.save_lyrics(track, "plain", "embedded", None, Some(text.clone()));
                return Ok(LyricsDto::Plain { text, source: Some("embedded".into()) });
            }
        }
        let duration = if track.duration_ms > 0 { Some(track.duration_seconds()) } else { None };
        let found =
            lyrics_client::fetch(&self.inner.http, &self.inner.limiter, &track.title, &track.artist, track.album.as_deref(), duration).await;
        let Some(found) = found else {
            self.save_lyrics(track, "none", "none", None, None);
            return Ok(LyricsDto::None);
        };
        match found.kind {
            LyricsKind::Word | LyricsKind::Line => {
                let lines = found.lrc.as_deref().map(lrc::parse).unwrap_or_default();
                if lines.is_empty() {
                    if let Some(plain) = found.plain.clone() {
                        self.save_lyrics(track, "plain", &found.source, None, Some(plain.clone()));
                        return Ok(LyricsDto::Plain { text: plain, source: Some(found.source) });
                    }
                    return Ok(LyricsDto::None);
                }
                let label = if found.kind == LyricsKind::Word { "word" } else { "line" };
                self.save_lyrics(track, label, &found.source, found.lrc.clone(), found.plain.clone());
                Ok(LyricsDto::Synced { lines, source: Some(found.source), kind: found.kind })
            }
            LyricsKind::Plain => {
                let plain = found.plain.unwrap_or_default();
                self.save_lyrics(track, "plain", &found.source, None, Some(plain.clone()));
                Ok(LyricsDto::Plain { text: plain, source: Some(found.source) })
            }
            LyricsKind::None => {
                self.save_lyrics(track, "none", "none", None, None);
                Ok(LyricsDto::None)
            }
        }
    }

    pub fn set_lossless(&self, value: bool) {
        *self.inner.lossless.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = value;
        self.emit(Event::Site);
    }

    pub fn set_motion_auto(&self, value: bool) {
        *self.inner.motion_auto.lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = value;
    }

    pub fn site_snapshot(&self) -> SiteSnapshot {
        let state = self.inner.site_state.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        SiteSnapshot {
            user: state.user.clone(),
            busy: state.busy,
            last_error: state.last_error.clone(),
            favorites: state.favorites.clone(),
            playlists: state.playlists.clone(),
            refreshing: state.refreshing,
            needs_login: state.needs_login,
            lossless: *self.inner.lossless.lock().unwrap_or_else(|poisoned| poisoned.into_inner()),
        }
    }

    fn with_site<R>(&self, change: impl FnOnce(&mut SiteState) -> R) -> R {
        let result = {
            let mut state = self.inner.site_state.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            change(&mut state)
        };
        self.emit(Event::Site);
        result
    }

    pub async fn site_restore(&self) {
        if !self.inner.site.has_session() {
            return;
        }
        match self.inner.site.me().await {
            Ok(user) => self.with_site(|state| state.user = Some(user)),
            Err(error) => {
                if matches!(error.downcast_ref::<SiteError>(), Some(SiteError::Unauthorized)) {
                    self.with_site(|state| state.user = None);
                }
            }
        }
    }

    pub async fn site_login_url(&self) -> Result<String> {
        self.with_site(|state| {
            state.busy = true;
            state.last_error = None;
        });
        match self.inner.site.login_url().await {
            Ok(url) => Ok(url),
            Err(error) => {
                self.with_site(|state| {
                    state.busy = false;
                    state.last_error = Some("Не получилось открыть вход".into());
                });
                Err(error)
            }
        }
    }

    pub async fn site_complete_login(&self, callback: &str) -> Result<()> {
        let parsed = url::Url::parse(callback)?;
        let pairs: HashMap<String, String> = parsed.query_pairs().map(|(key, value)| (key.to_string(), value.to_string())).collect();
        let (Some(token), Some(state_value)) = (pairs.get("sso_token"), pairs.get("state")) else {
            self.with_site(|state| {
                state.busy = false;
                state.last_error = Some("Не получилось войти. Если входишь через Google или Telegram, попробуй почту и пароль.".into());
            });
            return Err(anyhow!("bad callback"));
        };
        match self.inner.site.sso_login(token, state_value).await {
            Ok(user) => {
                self.with_site(|state| {
                    state.user = Some(user);
                    state.busy = false;
                    state.last_error = None;
                });
                Ok(())
            }
            Err(error) => {
                self.with_site(|state| {
                    state.busy = false;
                    state.last_error = Some("Не получилось войти. Если входишь через Google или Telegram, попробуй почту и пароль.".into());
                });
                Err(error)
            }
        }
    }

    pub fn site_cancel_login(&self) {
        self.with_site(|state| state.busy = false);
    }

    pub fn site_logout(&self) {
        self.inner.site.clear();
        self.with_site(|state| {
            state.user = None;
            state.playlists.clear();
            state.favorites = idle_list("favorites", "Понравившиеся");
        });
    }

    pub async fn site_refresh(&self) {
        self.with_site(|state| {
            state.refreshing = true;
            state.needs_login = false;
        });
        let outcome = async {
            let likes = self.inner.site.favorites().await?;
            let remote = self.inner.site.playlists().await?;
            Ok::<_, anyhow::Error>((likes, remote))
        }
        .await;
        match outcome {
            Ok((likes, remote)) => {
                let known: std::collections::HashSet<String> =
                    self.inner.db.all_tracks().unwrap_or_default().into_iter().filter_map(|track| track.site_id).collect();
                let here = likes.iter().filter(|track| known.contains(&track.id)).count();
                self.with_site(|state| {
                    state.favorites.total = likes.len();
                    state.favorites.done = here;
                    state.favorites.phase = if here >= likes.len() && !likes.is_empty() { SyncPhase::Done } else { SyncPhase::Idle };
                    state.playlists = remote.iter().map(playlist_state).collect();
                    state.refreshing = false;
                });
            }
            Err(error) => {
                let unauthorized = matches!(error.downcast_ref::<SiteError>(), Some(SiteError::Unauthorized | SiteError::NoToken));
                self.with_site(|state| {
                    state.refreshing = false;
                    if unauthorized {
                        state.needs_login = true;
                    } else {
                        state.favorites.phase = SyncPhase::Failed { text: "Не получилось загрузить список".into() };
                    }
                });
            }
        }
    }

    fn lossless_now(&self) -> bool {
        *self.inner.lossless.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub async fn site_download_favorites(&self) {
        if self.with_site(|state| std::mem::replace(&mut state.running, true)) {
            return;
        }
        self.with_site(|state| state.favorites.phase = SyncPhase::Loading);
        let result = async {
            let remote = self.inner.site.favorites().await?;
            self.with_site(|state| {
                state.favorites.total = remote.len();
                state.favorites.done = 0;
                state.favorites.phase = SyncPhase::Downloading;
            });
            let ids = self
                .ingest(&remote, |done| {
                    self.with_site(|state| state.favorites.done = done);
                })
                .await;
            for id in &ids {
                let _ = self.inner.db.set_favorite(id, true);
            }
            Ok::<_, anyhow::Error>(())
        }
        .await;
        self.with_site(|state| {
            state.favorites.phase = if result.is_ok() { SyncPhase::Done } else { SyncPhase::Failed { text: "Не получилось скачать".into() } };
            state.running = false;
        });
        self.emit(Event::Library);
    }

    pub async fn site_download_playlist(&self, id: &str) {
        if self.with_site(|state| std::mem::replace(&mut state.running, true)) {
            return;
        }
        let pid = id.to_string();
        self.with_site(|state| {
            if let Some(list) = state.playlists.iter_mut().find(|list| list.id == pid) {
                list.phase = SyncPhase::Loading;
            }
        });
        let result = async {
            let detail = self.inner.site.playlist(id).await?;
            let mut entries = detail.tracks.clone();
            entries.sort_by_key(|entry| entry.position);
            let remote: Vec<SiteTrack> = entries.into_iter().map(|entry| entry.track).collect();
            self.with_site(|state| {
                if let Some(list) = state.playlists.iter_mut().find(|list| list.id == pid) {
                    list.total = remote.len();
                    list.done = 0;
                    list.phase = SyncPhase::Downloading;
                }
            });
            let ids = self
                .ingest(&remote, |done| {
                    self.with_site(|state| {
                        if let Some(list) = state.playlists.iter_mut().find(|list| list.id == pid) {
                            list.done = done;
                        }
                    });
                })
                .await;
            let cover = match &detail.cover_filename {
                Some(name) => self.fetch_cover(name).await,
                None => None,
            };
            let playlist = Playlist {
                id: format!("site-{id}"),
                name: detail.name.clone(),
                cover_name: cover,
                site_id: Some(id.to_string()),
                created_at: now_ms(),
                track_ids: ids,
            };
            self.inner.db.save_playlist(&playlist)?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        self.with_site(|state| {
            if let Some(list) = state.playlists.iter_mut().find(|list| list.id == pid) {
                list.phase = if result.is_ok() { SyncPhase::Done } else { SyncPhase::Failed { text: "Не получилось скачать".into() } };
            }
            state.running = false;
        });
        self.emit(Event::Library);
    }

    async fn fetch_cover(&self, name: &str) -> Option<String> {
        let local = format!("site-{name}");
        let target = self.inner.paths.cover_file(&local);
        if target.exists() {
            return Some(local);
        }
        net::download(&self.inner.http, &site::cover_url(name), &target, None).await.ok().map(|_| local)
    }

    async fn fetch_motion(&self, name: &str) -> Option<String> {
        let local = format!("site-{name}");
        let target = self.inner.paths.motion_file(&local);
        if target.exists() {
            return Some(local);
        }
        net::download(&self.inner.http, &site::motion_url(name), &target, None).await.ok().map(|_| local)
    }

    async fn ingest(&self, remote: &[SiteTrack], progress: impl Fn(usize)) -> Vec<String> {
        let current = self.inner.db.all_tracks().unwrap_or_default();
        let mut by_site: HashMap<String, String> = HashMap::new();
        for track in &current {
            if let Some(site_id) = &track.site_id {
                by_site.insert(site_id.clone(), track.id.clone());
            }
        }
        let mut index = DuplicateIndex::new(current.iter().map(fingerprint).collect());
        let mut ids = Vec::new();
        let mut done = 0usize;
        for item in remote {
            if let Some(existing) = by_site.get(&item.id) {
                ids.push(existing.clone());
            } else {
                let probe = TrackFingerprint {
                    id: format!("site-{}", item.id),
                    artist: item.artist.clone(),
                    title: item.title.clone(),
                    duration_ms: item.duration_seconds.map(|seconds| (seconds * 1000.0) as i64),
                    file_hash: None,
                    format: item.format.clone().unwrap_or_default(),
                    bitrate_kbps: None,
                };
                let matched = index.matches(&probe).into_iter().find(|hit| hit.kind == DuplicateKind::SameTrack);
                if let Some(hit) = matched {
                    let _ = self.inner.db.link_site(&hit.existing_id, &item.id);
                    by_site.insert(item.id.clone(), hit.existing_id.clone());
                    ids.push(hit.existing_id);
                } else if let Ok(saved) = self.download_site_track(item).await {
                    by_site.insert(item.id.clone(), saved.id.clone());
                    index.add(fingerprint(&saved));
                    ids.push(saved.id);
                }
            }
            done += 1;
            progress(done);
        }
        ids
    }

    async fn download_site_track(&self, remote: &SiteTrack) -> Result<Track> {
        let lossless = self.lossless_now();
        let url = site::audio_url(remote, lossless);
        let source_name = if !lossless && remote.stream_filename.is_some() { remote.stream_filename.clone().unwrap_or_default() } else { remote.filename.clone() };
        let extension = source_name.rsplit('.').next().map(|value| value.to_lowercase()).filter(|value| value.len() <= 5).unwrap_or_else(|| "mp3".into());
        let id = Uuid::new_v4().to_string();
        let file_name = format!("{id}.{extension}");
        let destination = self.inner.paths.track_file(&file_name);
        net::download(&self.inner.http, &url, &destination, None).await?;
        let hash_path = destination.clone();
        let hash = tokio::task::spawn_blocking(move || import_support::hash_file(&hash_path)).await??;
        let cover_name = match &remote.cover_filename {
            Some(name) => self.fetch_cover(name).await,
            None => None,
        };
        let motion_name = match &remote.motion_filename {
            Some(name) => self.fetch_motion(name).await,
            None => None,
        };
        let read_path = destination.clone();
        let read = tokio::task::spawn_blocking(move || tags::read(&read_path)).await.ok().flatten();
        let seconds = remote.duration_seconds.or(read.as_ref().and_then(|tags| tags.duration)).unwrap_or(0.0);
        let mut track = Track::blank(id.clone());
        track.title = remote.title.clone();
        track.artist = remote.artist.clone();
        track.album = remote.album.clone();
        track.track_number = read.as_ref().and_then(|tags| tags.track_number).map(i64::from);
        track.disc_number = read.as_ref().and_then(|tags| tags.disc_number).map(i64::from);
        track.year = read.as_ref().and_then(|tags| tags.year).map(i64::from);
        track.genre = read.as_ref().and_then(|tags| tags.genre.clone());
        track.duration_ms = (seconds * 1000.0).round() as i64;
        track.format = remote.format.clone().unwrap_or_else(|| extension.clone()).to_lowercase();
        track.bitrate_kbps = read.as_ref().and_then(|tags| tags.bitrate_kbps).map(i64::from);
        track.sample_rate = read.as_ref().and_then(|tags| tags.sample_rate).map(i64::from);
        track.file_name = file_name;
        track.file_size = std::fs::metadata(&destination).map(|meta| meta.len() as i64).unwrap_or(0);
        track.file_hash = Some(hash);
        track.cover_name = cover_name;
        track.motion_name = motion_name;
        track.site_id = Some(remote.id.clone());
        self.inner.db.save_track(&track)?;
        if let Some(lyrics) = self.inner.site.lyrics(&remote.id).await {
            if let Some(synced) = lyrics.synced.filter(|text| !text.is_empty()) {
                self.save_lyrics(&track, "line", lyrics.source.as_deref().unwrap_or("site"), Some(synced), lyrics.plain.clone());
            } else if let Some(plain) = lyrics.plain.filter(|text| !text.is_empty()) {
                self.save_lyrics(&track, "plain", lyrics.source.as_deref().unwrap_or("site"), None, Some(plain));
            }
        }
        Ok(track)
    }
}

fn apply_match(found: &CatalogMatch, tag_title: &Option<String>, tag_artist: &Option<String>, title: &mut String, artist: &mut String) {
    if tag_title.is_none() || text_matching::title_ratio(title, &found.title) >= 0.95 {
        *title = found.title.clone();
    }
    if tag_artist.is_none() || artist.is_empty() || text_matching::artist_ratio(artist, &found.artist) >= 0.95 {
        *artist = found.artist.clone();
    }
}

fn playlist_state(item: &SitePlaylist) -> ListState {
    ListState {
        id: item.id.clone(),
        name: item.name.clone(),
        total: item.track_count.unwrap_or(0).max(0) as usize,
        done: 0,
        phase: SyncPhase::Idle,
    }
}

fn stored_lyrics(record: &LyricsRecord) -> Option<LyricsDto> {
    match record.kind.as_str() {
        "word" | "line" => {
            let lines = lrc::parse(record.lrc.as_deref()?);
            if lines.is_empty() {
                return None;
            }
            let kind = lrc::kind(&lines);
            Some(LyricsDto::Synced { lines, source: Some(record.source.clone()), kind })
        }
        "plain" => {
            let plain = record.plain.clone().filter(|text| !text.is_empty())?;
            Some(LyricsDto::Plain { text: plain, source: Some(record.source.clone()) })
        }
        _ => {
            if now_ms() - record.checked_at < 12 * 3_600_000 {
                Some(LyricsDto::None)
            } else {
                None
            }
        }
    }
}
