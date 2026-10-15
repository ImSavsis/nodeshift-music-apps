use std::io;
use std::path::Path;

const CHOICE_FILE: &str = "autostart.choice";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StartupPlan {
    Leave,
    Enable { first_run: bool },
}

pub fn read_choice(base: &Path) -> Option<bool> {
    match std::fs::read_to_string(base.join(CHOICE_FILE)).ok()?.trim() {
        "on" => Some(true),
        "off" => Some(false),
        _ => None,
    }
}

pub fn write_choice(base: &Path, on: bool) -> io::Result<()> {
    crate::atomic::write_atomic(&base.join(CHOICE_FILE), if on { &b"on"[..] } else { &b"off"[..] })
}

pub fn startup_plan(choice: Option<bool>, managed: bool) -> StartupPlan {
    match (managed, choice) {
        (false, _) | (true, Some(false)) => StartupPlan::Leave,
        (true, None) => StartupPlan::Enable { first_run: true },
        (true, Some(true)) => StartupPlan::Enable { first_run: false },
    }
}

pub fn managed_environment() -> bool {
    !cfg!(debug_assertions) && std::env::var_os("NSM_DATA_DIR").is_none() && std::env::var_os("NSM_OFFLINE").is_none()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_first_managed_run_turns_autostart_on() {
        assert_eq!(startup_plan(None, true), StartupPlan::Enable { first_run: true });
    }

    #[test]
    fn a_remembered_choice_is_respected_and_refreshed() {
        assert_eq!(startup_plan(Some(true), true), StartupPlan::Enable { first_run: false });
        assert_eq!(startup_plan(Some(false), true), StartupPlan::Leave);
    }

    #[test]
    fn unmanaged_runs_never_touch_the_registry() {
        assert_eq!(startup_plan(None, false), StartupPlan::Leave);
        assert_eq!(startup_plan(Some(true), false), StartupPlan::Leave);
        assert_eq!(startup_plan(Some(false), false), StartupPlan::Leave);
    }

    #[test]
    fn the_choice_survives_on_disk() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(read_choice(dir.path()), None);
        write_choice(dir.path(), true).unwrap();
        assert_eq!(read_choice(dir.path()), Some(true));
        write_choice(dir.path(), false).unwrap();
        assert_eq!(read_choice(dir.path()), Some(false));
        std::fs::write(dir.path().join(CHOICE_FILE), "???").unwrap();
        assert_eq!(read_choice(dir.path()), None);
    }
}
