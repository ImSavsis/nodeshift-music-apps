use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};

use nsm_core::autostart;
use nsm_core::bridge::Bridge;
use nsm_core::presence::DiscordConfig;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager, Wry};
use tauri_plugin_autostart::ManagerExt;

const TRAY_ID: &str = "main";
const NO_BRIDGE: &str = "Discord: недоступен";

#[derive(Default)]
pub struct TrayFlag(AtomicBool);

impl TrayFlag {
    pub fn set(&self, active: bool) {
        self.0.store(active, Ordering::SeqCst);
    }

    fn active(&self) -> bool {
        self.0.load(Ordering::SeqCst)
    }
}

pub fn resident(app: &AppHandle) -> bool {
    app.try_state::<TrayFlag>().is_some_and(|flag| flag.active())
}

fn autostart_enabled(app: &AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}

fn toggle_discord(base: &Path, bridge: Option<&Bridge>, item: &CheckMenuItem<Wry>) {
    let enabled = !DiscordConfig::load(base).enabled;
    let _ = DiscordConfig::save_enabled(base, enabled);
    let _ = item.set_checked(DiscordConfig::load(base).enabled);
    if let Some(bridge) = bridge {
        bridge.wake();
    }
}

fn toggle_autostart(app: &AppHandle, base: &Path, item: &CheckMenuItem<Wry>) {
    let want = !autostart_enabled(app);
    let manager = app.autolaunch();
    let applied = if want { manager.enable() } else { manager.disable() };
    if applied.is_ok() {
        let _ = autostart::write_choice(base, want);
    }
    let _ = item.set_checked(autostart_enabled(app));
}

fn watch_status(tray: tauri::tray::TrayIcon<Wry>, line: MenuItem<Wry>, bridge: Bridge) {
    let mut watcher = bridge.watch();
    tauri::async_runtime::spawn(async move {
        loop {
            let label = watcher.borrow_and_update().label();
            let _ = line.set_text(label);
            let _ = tray.set_tooltip(Some(format!("NS Music\n{label}")));
            if watcher.changed().await.is_err() {
                break;
            }
        }
    });
}

pub fn install(app: &AppHandle, base: PathBuf, bridge: Option<Bridge>) -> tauri::Result<()> {
    let first_line = bridge.as_ref().map_or(NO_BRIDGE, |bridge| bridge.status().label());
    let open = MenuItem::with_id(app, "open", "Открыть", true, None::<&str>)?;
    let line = MenuItem::with_id(app, "status", first_line, false, None::<&str>)?;
    let discord = CheckMenuItem::with_id(app, "discord", "Показывать в Discord", true, DiscordConfig::load(&base).enabled, None::<&str>)?;
    let launch = CheckMenuItem::with_id(app, "autostart", "Запускать с Windows", true, autostart_enabled(app), None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "Выйти", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&open, &line, &discord, &launch, &separator, &quit])?;

    let menu_bridge = bridge.clone();
    let menu_base = base.clone();
    let mut builder = TrayIconBuilder::with_id(TRAY_ID)
        .tooltip(format!("NS Music\n{first_line}"))
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(move |app, event| match event.id().as_ref() {
            "open" => crate::focus_main(app),
            "discord" => toggle_discord(&menu_base, menu_bridge.as_ref(), &discord),
            "autostart" => toggle_autostart(app, &menu_base, &launch),
            "quit" => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                crate::focus_main(tray.app_handle());
            }
        });
    if let Some(icon) = app.default_window_icon().cloned() {
        builder = builder.icon(icon);
    }
    let tray = builder.build(app)?;
    if let Some(bridge) = bridge {
        watch_status(tray, line, bridge);
    }
    Ok(())
}
