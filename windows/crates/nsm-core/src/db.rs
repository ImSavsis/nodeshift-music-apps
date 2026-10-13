use std::path::Path;
use std::sync::Mutex;

use rusqlite::{params, Connection, OptionalExtension, Row};

use crate::model::{LyricsRecord, Playlist, Track};

pub struct Db {
    connection: Mutex<Connection>,
}

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS track (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT,
    albumArtist TEXT,
    trackNumber INTEGER,
    discNumber INTEGER,
    year INTEGER,
    genre TEXT,
    durationMs INTEGER NOT NULL,
    format TEXT NOT NULL,
    bitrateKbps INTEGER,
    sampleRate INTEGER,
    bitDepth INTEGER,
    fileName TEXT NOT NULL,
    fileSize INTEGER NOT NULL,
    fileHash TEXT,
    coverName TEXT,
    motionName TEXT,
    motion3x4Name TEXT,
    isFavorite INTEGER NOT NULL DEFAULT 0,
    playCount INTEGER NOT NULL DEFAULT 0,
    lastPlayedAt INTEGER,
    addedAt INTEGER NOT NULL,
    siteId TEXT,
    bpm INTEGER,
    palette TEXT,
    lyricsKind TEXT,
    lyricsSource TEXT
);
CREATE INDEX IF NOT EXISTS track_hash ON track(fileHash);
CREATE INDEX IF NOT EXISTS track_site ON track(siteId);
CREATE TABLE IF NOT EXISTS playlist (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    coverName TEXT,
    siteId TEXT,
    createdAt INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS playlistTrack (
    playlistId TEXT NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
    trackId TEXT NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    PRIMARY KEY (playlistId, trackId)
);
CREATE TABLE IF NOT EXISTS lyrics (
    trackId TEXT PRIMARY KEY NOT NULL REFERENCES track(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    source TEXT NOT NULL,
    lrc TEXT,
    plain TEXT,
    checkedAt INTEGER NOT NULL
);
";

const TRACK_COLUMNS: &str = "id, title, artist, album, albumArtist, trackNumber, discNumber, year, genre, durationMs, format, bitrateKbps, sampleRate, bitDepth, fileName, fileSize, fileHash, coverName, motionName, motion3x4Name, isFavorite, playCount, lastPlayedAt, addedAt, siteId, bpm, palette, lyricsKind, lyricsSource";

fn track_from_row(row: &Row) -> rusqlite::Result<Track> {
    Ok(Track {
        id: row.get(0)?,
        title: row.get(1)?,
        artist: row.get(2)?,
        album: row.get(3)?,
        album_artist: row.get(4)?,
        track_number: row.get(5)?,
        disc_number: row.get(6)?,
        year: row.get(7)?,
        genre: row.get(8)?,
        duration_ms: row.get(9)?,
        format: row.get(10)?,
        bitrate_kbps: row.get(11)?,
        sample_rate: row.get(12)?,
        bit_depth: row.get(13)?,
        file_name: row.get(14)?,
        file_size: row.get(15)?,
        file_hash: row.get(16)?,
        cover_name: row.get(17)?,
        motion_name: row.get(18)?,
        motion3x4_name: row.get(19)?,
        is_favorite: row.get::<_, i64>(20)? != 0,
        play_count: row.get(21)?,
        last_played_at: row.get(22)?,
        added_at: row.get(23)?,
        site_id: row.get(24)?,
        bpm: row.get(25)?,
        palette: row.get(26)?,
        lyrics_kind: row.get(27)?,
        lyrics_source: row.get(28)?,
    })
}

impl Db {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        let connection = Connection::open(path)?;
        Self::prepare(connection)
    }

    pub fn memory() -> rusqlite::Result<Self> {
        Self::prepare(Connection::open_in_memory()?)
    }

    fn prepare(connection: Connection) -> rusqlite::Result<Self> {
        connection.pragma_update(None, "foreign_keys", true)?;
        let _ = connection.pragma_update(None, "journal_mode", "WAL");
        connection.execute_batch(SCHEMA)?;
        Ok(Self { connection: Mutex::new(connection) })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.connection.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub fn all_tracks(&self) -> rusqlite::Result<Vec<Track>> {
        let connection = self.lock();
        let mut statement = connection.prepare(&format!("SELECT {TRACK_COLUMNS} FROM track"))?;
        let rows = statement.query_map([], track_from_row)?;
        rows.collect()
    }

    pub fn track(&self, id: &str) -> rusqlite::Result<Option<Track>> {
        let connection = self.lock();
        connection
            .query_row(&format!("SELECT {TRACK_COLUMNS} FROM track WHERE id = ?1"), params![id], track_from_row)
            .optional()
    }

    pub fn save_track(&self, track: &Track) -> rusqlite::Result<()> {
        let connection = self.lock();
        connection.execute(
            &format!(
                "INSERT INTO track ({TRACK_COLUMNS}) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20,?21,?22,?23,?24,?25,?26,?27,?28,?29)
                 ON CONFLICT(id) DO UPDATE SET
                    title=excluded.title, artist=excluded.artist, album=excluded.album, albumArtist=excluded.albumArtist,
                    trackNumber=excluded.trackNumber, discNumber=excluded.discNumber, year=excluded.year, genre=excluded.genre,
                    durationMs=excluded.durationMs, format=excluded.format, bitrateKbps=excluded.bitrateKbps,
                    sampleRate=excluded.sampleRate, bitDepth=excluded.bitDepth, fileName=excluded.fileName,
                    fileSize=excluded.fileSize, fileHash=excluded.fileHash, coverName=excluded.coverName,
                    motionName=excluded.motionName, motion3x4Name=excluded.motion3x4Name, isFavorite=excluded.isFavorite,
                    playCount=excluded.playCount, lastPlayedAt=excluded.lastPlayedAt, addedAt=excluded.addedAt,
                    siteId=excluded.siteId, bpm=excluded.bpm, palette=excluded.palette, lyricsKind=excluded.lyricsKind,
                    lyricsSource=excluded.lyricsSource"
            ),
            params![
                track.id,
                track.title,
                track.artist,
                track.album,
                track.album_artist,
                track.track_number,
                track.disc_number,
                track.year,
                track.genre,
                track.duration_ms,
                track.format,
                track.bitrate_kbps,
                track.sample_rate,
                track.bit_depth,
                track.file_name,
                track.file_size,
                track.file_hash,
                track.cover_name,
                track.motion_name,
                track.motion3x4_name,
                track.is_favorite as i64,
                track.play_count,
                track.last_played_at,
                track.added_at,
                track.site_id,
                track.bpm,
                track.palette,
                track.lyrics_kind,
                track.lyrics_source,
            ],
        )?;
        Ok(())
    }

    pub fn delete_track(&self, id: &str) -> rusqlite::Result<()> {
        self.lock().execute("DELETE FROM track WHERE id = ?1", params![id])?;
        Ok(())
    }

    pub fn set_favorite(&self, id: &str, value: bool) -> rusqlite::Result<()> {
        self.lock().execute("UPDATE track SET isFavorite = ?1 WHERE id = ?2", params![value as i64, id])?;
        Ok(())
    }

    pub fn link_site(&self, track_id: &str, site_id: &str) -> rusqlite::Result<()> {
        self.lock().execute("UPDATE track SET siteId = ?1 WHERE id = ?2", params![site_id, track_id])?;
        Ok(())
    }

    pub fn mark_played(&self, id: &str, at: i64) -> rusqlite::Result<()> {
        self.lock().execute(
            "UPDATE track SET playCount = playCount + 1, lastPlayedAt = ?1 WHERE id = ?2",
            params![at, id],
        )?;
        Ok(())
    }

    pub fn lyrics(&self, track_id: &str) -> rusqlite::Result<Option<LyricsRecord>> {
        self.lock()
            .query_row(
                "SELECT trackId, kind, source, lrc, plain, checkedAt FROM lyrics WHERE trackId = ?1",
                params![track_id],
                |row| {
                    Ok(LyricsRecord {
                        track_id: row.get(0)?,
                        kind: row.get(1)?,
                        source: row.get(2)?,
                        lrc: row.get(3)?,
                        plain: row.get(4)?,
                        checked_at: row.get(5)?,
                    })
                },
            )
            .optional()
    }

    pub fn save_lyrics(&self, record: &LyricsRecord) -> rusqlite::Result<()> {
        self.lock().execute(
            "INSERT INTO lyrics (trackId, kind, source, lrc, plain, checkedAt) VALUES (?1,?2,?3,?4,?5,?6)
             ON CONFLICT(trackId) DO UPDATE SET kind=excluded.kind, source=excluded.source, lrc=excluded.lrc, plain=excluded.plain, checkedAt=excluded.checkedAt",
            params![record.track_id, record.kind, record.source, record.lrc, record.plain, record.checked_at],
        )?;
        Ok(())
    }

    pub fn playlists(&self) -> rusqlite::Result<Vec<Playlist>> {
        let connection = self.lock();
        let mut statement =
            connection.prepare("SELECT id, name, coverName, siteId, createdAt FROM playlist ORDER BY createdAt DESC")?;
        let mut playlists: Vec<Playlist> = statement
            .query_map([], |row| {
                Ok(Playlist {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    cover_name: row.get(2)?,
                    site_id: row.get(3)?,
                    created_at: row.get(4)?,
                    track_ids: Vec::new(),
                })
            })?
            .collect::<rusqlite::Result<_>>()?;
        let mut members = connection.prepare("SELECT trackId FROM playlistTrack WHERE playlistId = ?1 ORDER BY position")?;
        for playlist in &mut playlists {
            playlist.track_ids = members.query_map(params![playlist.id], |row| row.get::<_, String>(0))?.collect::<rusqlite::Result<_>>()?;
        }
        Ok(playlists)
    }

    pub fn save_playlist(&self, playlist: &Playlist) -> rusqlite::Result<()> {
        let mut connection = self.lock();
        let transaction = connection.transaction()?;
        transaction.execute(
            "INSERT INTO playlist (id, name, coverName, siteId, createdAt) VALUES (?1,?2,?3,?4,?5)
             ON CONFLICT(id) DO UPDATE SET name=excluded.name, coverName=excluded.coverName, siteId=excluded.siteId",
            params![playlist.id, playlist.name, playlist.cover_name, playlist.site_id, playlist.created_at],
        )?;
        transaction.execute("DELETE FROM playlistTrack WHERE playlistId = ?1", params![playlist.id])?;
        for (position, track_id) in playlist.track_ids.iter().enumerate() {
            transaction.execute(
                "INSERT OR IGNORE INTO playlistTrack (playlistId, trackId, position) VALUES (?1,?2,?3)",
                params![playlist.id, track_id, position as i64],
            )?;
        }
        transaction.commit()
    }

    pub fn delete_playlist(&self, id: &str) -> rusqlite::Result<()> {
        self.lock().execute("DELETE FROM playlist WHERE id = ?1", params![id])?;
        Ok(())
    }
}
