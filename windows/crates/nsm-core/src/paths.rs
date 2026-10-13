use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct Paths {
    pub base: PathBuf,
    pub tracks: PathBuf,
    pub covers: PathBuf,
    pub motion: PathBuf,
    pub scratch: PathBuf,
    pub updates: PathBuf,
    pub database: PathBuf,
}

impl Paths {
    pub fn new(base: impl AsRef<Path>) -> std::io::Result<Self> {
        let base = base.as_ref().to_path_buf();
        let paths = Self {
            tracks: base.join("tracks"),
            covers: base.join("covers"),
            motion: base.join("motion"),
            scratch: base.join("scratch"),
            updates: base.join("updates"),
            database: base.join("library.sqlite"),
            base,
        };
        for dir in [&paths.base, &paths.tracks, &paths.covers, &paths.motion, &paths.scratch, &paths.updates] {
            fs::create_dir_all(dir)?;
        }
        Ok(paths)
    }

    pub fn track_file(&self, name: &str) -> PathBuf {
        self.tracks.join(name)
    }

    pub fn cover_file(&self, name: &str) -> PathBuf {
        self.covers.join(name)
    }

    pub fn motion_file(&self, name: &str) -> PathBuf {
        self.motion.join(name)
    }
}
