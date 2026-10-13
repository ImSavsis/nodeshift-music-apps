use std::path::Path;

use anyhow::{anyhow, Result};
use lofty::config::WriteOptions;
use lofty::file::{AudioFile, TaggedFileExt};
use lofty::picture::{MimeType, Picture, PictureType};
use lofty::probe::Probe;
use lofty::tag::{Accessor, ItemKey, Tag};

#[derive(Debug, Clone, Default)]
pub struct ReadTags {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub genre: Option<String>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub year: Option<i32>,
    pub duration: Option<f64>,
    pub sample_rate: Option<u32>,
    pub bit_depth: Option<u8>,
    pub bitrate_kbps: Option<u32>,
    pub cover: Option<Vec<u8>>,
    pub lyrics: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct WriteTags {
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub genre: Option<String>,
    pub track_number: Option<u32>,
    pub disc_number: Option<u32>,
    pub year: Option<i32>,
    pub isrc: Option<String>,
    pub cover: Option<Vec<u8>>,
}

fn clean(text: Option<&str>) -> Option<String> {
    let trimmed = text?.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

pub fn read(path: &Path) -> Option<ReadTags> {
    let tagged = Probe::open(path).ok()?.guess_file_type().ok()?.read().ok()?;
    let properties = tagged.properties();
    let mut tags = ReadTags {
        duration: Some(properties.duration().as_secs_f64()),
        sample_rate: properties.sample_rate(),
        bit_depth: properties.bit_depth(),
        bitrate_kbps: properties.audio_bitrate().or_else(|| properties.overall_bitrate()),
        ..Default::default()
    };
    if let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) {
        tags.title = clean(tag.title().as_deref());
        tags.artist = clean(tag.artist().as_deref());
        tags.album = clean(tag.album().as_deref());
        tags.genre = clean(tag.genre().as_deref());
        tags.album_artist = clean(tag.get_string(ItemKey::AlbumArtist));
        tags.track_number = tag.track();
        tags.disc_number = tag.disk();
        tags.year = tag.date().map(|date| date.year as i32).filter(|year| *year > 0);
        tags.lyrics = clean(tag.get_string(ItemKey::Lyrics).or_else(|| tag.get_string(ItemKey::UnsyncLyrics)));
        let pictures = tag.pictures();
        let front = pictures.iter().find(|picture| picture.pic_type() == PictureType::CoverFront).or_else(|| pictures.first());
        tags.cover = front.map(|picture| picture.data().to_vec());
    }
    Some(tags)
}

pub fn write(path: &Path, tags: &WriteTags) -> Result<()> {
    let mut tagged = Probe::open(path)?.guess_file_type()?.read()?;
    if tagged.primary_tag().is_none() {
        let tag_type = tagged.primary_tag_type();
        tagged.insert_tag(Tag::new(tag_type));
    }
    let tag = tagged.primary_tag_mut().ok_or_else(|| anyhow!("no tag"))?;
    tag.set_title(tags.title.clone());
    tag.set_artist(tags.artist.clone());
    if let Some(album) = &tags.album {
        tag.set_album(album.clone());
    }
    if let Some(album_artist) = &tags.album_artist {
        tag.insert_text(ItemKey::AlbumArtist, album_artist.clone());
    }
    if let Some(genre) = &tags.genre {
        tag.set_genre(genre.clone());
    }
    if let Some(number) = tags.track_number {
        tag.set_track(number);
    }
    if let Some(number) = tags.disc_number {
        tag.set_disk(number);
    }
    if let Some(year) = tags.year {
        tag.insert_text(ItemKey::RecordingDate, year.to_string());
    }
    if let Some(isrc) = &tags.isrc {
        tag.insert_text(ItemKey::Isrc, isrc.clone());
    }
    if let Some(cover) = &tags.cover {
        tag.remove_picture_type(PictureType::CoverFront);
        tag.push_picture(Picture::unchecked(cover.clone()).pic_type(PictureType::CoverFront).mime_type(MimeType::Jpeg).build());
    }
    tagged.save_to_path(path, WriteOptions::default())?;
    Ok(())
}
