use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

const RENAME_ATTEMPTS: u32 = 4;
const RENAME_PAUSE: Duration = Duration::from_millis(25);

fn sibling(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.file_name().map(|name| name.to_os_string()).unwrap_or_default();
    name.push(suffix);
    path.with_file_name(name)
}

pub fn backup_path(path: &Path) -> PathBuf {
    sibling(path, ".bak")
}

fn write_synced(temp: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut file = File::create(temp)?;
    file.write_all(bytes)?;
    file.sync_all()
}

fn replace(temp: &Path, path: &Path) -> io::Result<()> {
    let mut attempt = 1;
    loop {
        match fs::rename(temp, path) {
            Ok(()) => return Ok(()),
            Err(error) if error.kind() == io::ErrorKind::PermissionDenied && attempt < RENAME_ATTEMPTS => {
                attempt += 1;
                std::thread::sleep(RENAME_PAUSE);
            }
            Err(error) => return Err(error),
        }
    }
}

pub fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let temp = sibling(path, ".tmp");
    let outcome = write_synced(&temp, bytes).and_then(|_| replace(&temp, path));
    if outcome.is_err() {
        let _ = fs::remove_file(&temp);
    }
    outcome
}

pub fn write_with_backup(path: &Path, bytes: &[u8]) -> io::Result<()> {
    write_atomic(path, bytes)?;
    let _ = write_atomic(&backup_path(path), bytes);
    Ok(())
}

pub fn read_with_backup<T>(path: &Path, parse: impl Fn(&[u8]) -> Option<T>) -> Option<T> {
    [path.to_path_buf(), backup_path(path)].iter().find_map(|candidate| fs::read(candidate).ok().and_then(|bytes| parse(&bytes)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(bytes: &[u8]) -> Option<String> {
        String::from_utf8(bytes.to_vec()).ok().filter(|value| value.starts_with('{'))
    }

    #[test]
    fn writes_replace_the_file_without_leaving_a_temp() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tokens.dat");
        write_atomic(&path, b"{one}").unwrap();
        write_atomic(&path, b"{two}").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"{two}");
        assert!(!dir.path().join("tokens.dat.tmp").exists());
    }

    #[test]
    fn a_backup_follows_every_write() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tokens.dat");
        write_with_backup(&path, b"{one}").unwrap();
        write_with_backup(&path, b"{two}").unwrap();
        assert_eq!(fs::read(backup_path(&path)).unwrap(), b"{two}");
        assert_eq!(read_with_backup(&path, text).as_deref(), Some("{two}"));
    }

    #[test]
    fn a_truncated_main_file_falls_back_to_the_backup() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tokens.dat");
        write_with_backup(&path, b"{good}").unwrap();
        fs::write(&path, b"").unwrap();
        assert_eq!(read_with_backup(&path, text).as_deref(), Some("{good}"));
        fs::write(&path, b"garbage").unwrap();
        assert_eq!(read_with_backup(&path, text).as_deref(), Some("{good}"));
    }

    #[test]
    fn a_missing_main_file_uses_the_backup_and_nothing_gives_none() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tokens.dat");
        assert!(read_with_backup(&path, text).is_none());
        fs::write(backup_path(&path), b"{kept}").unwrap();
        assert_eq!(read_with_backup(&path, text).as_deref(), Some("{kept}"));
    }

    #[test]
    fn a_failed_write_leaves_the_old_file_and_no_temp() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tokens.dat");
        write_atomic(&path, b"{old}").unwrap();
        fs::create_dir(dir.path().join("tokens.dat.tmp")).unwrap();
        assert!(write_atomic(&path, b"{new}").is_err());
        assert_eq!(fs::read(&path).unwrap(), b"{old}");
    }
}
