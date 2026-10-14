#[cfg(windows)]
mod discord;
mod secure;

use std::path::PathBuf;
use std::sync::Arc;

use nsm_core::engine::{CatalogPage, CatalogSource, Decision, Emit, Engine, EngineConfig, Event, ImportSnapshot, LyricsDto, SiteSnapshot};
use nsm_core::media_server::{self, MediaServer};
use nsm_core::model::{Playlist, Track};
use nsm_core::paths::Paths;
use nsm_core::update::{self, UpdateManifest};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_opener::OpenerExt;

const BUILD: &str = match option_env!("NSM_BUILD") {
    Some(value) => value,
    None => "0",
};

struct AppState {
    engine: Engine,
    media: MediaServer,
}

fn build_number() -> i64 {
    BUILD.parse().unwrap_or(0)
}

fn text<T, E: std::fmt::Display>(result: Result<T, E>) -> Result<T, String> {
    result.map_err(|error| error.to_string())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppInfo {
    version: String,
    build: i64,
    media_base: String,
    muted: bool,
}

#[tauri::command]
fn app_info(state: State<AppState>) -> AppInfo {
    AppInfo {
        version: env!("CARGO_PKG_VERSION").to_string(),
        build: build_number(),
        media_base: state.media.base(),
        muted: std::env::var_os("NSM_MUTE").is_some(),
    }
}

#[tauri::command]
fn library_all(state: State<AppState>) -> Result<Vec<Track>, String> {
    text(state.engine.library())
}

#[tauri::command]
fn playlists_all(state: State<AppState>) -> Result<Vec<Playlist>, String> {
    text(state.engine.playlists())
}

#[tauri::command]
fn track_favorite(state: State<AppState>, id: String, value: bool) -> Result<(), String> {
    text(state.engine.set_favorite(&id, value))
}

#[tauri::command]
fn track_played(state: State<AppState>, id: String) -> Result<(), String> {
    text(state.engine.mark_played(&id))
}

#[tauri::command]
fn track_delete(state: State<AppState>, id: String) -> Result<(), String> {
    text(state.engine.delete_track(&id))
}

#[tauri::command]
fn track_update(
    state: State<AppState>,
    id: String,
    title: String,
    artist: String,
    album: Option<String>,
    track_number: Option<i64>,
) -> Result<Track, String> {
    text(state.engine.update_track(&id, &title, &artist, album, track_number))
}

#[tauri::command]
fn playlist_create(state: State<AppState>, name: String) -> Result<Playlist, String> {
    text(state.engine.create_playlist(&name))
}

#[tauri::command]
fn playlist_add(state: State<AppState>, playlist_id: String, track_id: String) -> Result<(), String> {
    text(state.engine.playlist_add(&playlist_id, &track_id))
}

#[tauri::command]
fn playlist_remove(state: State<AppState>, playlist_id: String, track_id: String) -> Result<(), String> {
    text(state.engine.playlist_remove(&playlist_id, &track_id))
}

#[tauri::command]
fn playlist_rename(state: State<AppState>, playlist_id: String, name: String) -> Result<(), String> {
    text(state.engine.rename_playlist(&playlist_id, &name))
}

#[tauri::command]
fn playlist_delete(state: State<AppState>, playlist_id: String) -> Result<(), String> {
    text(state.engine.delete_playlist(&playlist_id))
}

#[tauri::command]
fn import_start(state: State<AppState>, paths: Vec<String>) {
    state.engine.start_import(paths.into_iter().map(PathBuf::from).collect());
}

#[tauri::command]
fn import_snapshot(state: State<AppState>) -> ImportSnapshot {
    state.engine.import_snapshot()
}

#[tauri::command]
fn import_decide(state: State<AppState>, id: String, decision: String) {
    if let Some(parsed) = Decision::parse(&decision) {
        state.engine.import_decide(&id, parsed);
    }
}

#[tauri::command]
fn import_skip_all(state: State<AppState>) {
    state.engine.import_skip_all_duplicates();
}

#[tauri::command]
fn import_clear(state: State<AppState>) {
    state.engine.import_clear();
}

#[tauri::command]
async fn lyrics_get(state: State<'_, AppState>, track_id: String, force: bool) -> Result<LyricsDto, String> {
    text(state.engine.lyrics(&track_id, force).await)
}

#[tauri::command]
async fn cover_palette(state: State<'_, AppState>, name: String) -> Result<Vec<[u8; 3]>, String> {
    Ok(state.engine.palette_any(&name).await)
}

#[tauri::command]
async fn catalog_page(
    state: State<'_, AppState>,
    search: String,
    sort: String,
    format: Option<String>,
    limit: u32,
    offset: u32,
) -> Result<CatalogPage, String> {
    text(state.engine.catalog_page(&search, &sort, format.as_deref(), limit, offset).await)
}

#[tauri::command]
async fn catalog_wave(state: State<'_, AppState>, limit: u32) -> Result<Vec<Track>, String> {
    text(state.engine.catalog_wave(limit).await)
}

#[tauri::command]
async fn catalog_likes(state: State<'_, AppState>) -> Result<Vec<String>, String> {
    text(state.engine.catalog_likes().await)
}

#[tauri::command]
async fn catalog_like(state: State<'_, AppState>, site_id: String, value: bool) -> Result<(), String> {
    text(state.engine.catalog_set_like(&site_id, value).await)
}

#[tauri::command]
async fn catalog_played(state: State<'_, AppState>, site_id: String) -> Result<(), String> {
    state.engine.catalog_register_play(&site_id).await;
    Ok(())
}

#[tauri::command]
async fn presence_publish(state: State<'_, AppState>, body: serde_json::Value) -> Result<(), String> {
    text(state.engine.site().publish_presence(&body).await)
}

#[tauri::command]
async fn site_lyrics_get(state: State<'_, AppState>, site_id: String) -> Result<LyricsDto, String> {
    Ok(state.engine.site_lyrics(&site_id).await)
}

#[tauri::command]
fn site_snapshot(state: State<AppState>) -> SiteSnapshot {
    state.engine.site_snapshot()
}

#[tauri::command]
async fn site_login(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    let url = text(state.engine.site_login_url().await)?;
    text(app.opener().open_url(url, None::<&str>))
}

#[tauri::command]
fn site_cancel_login(state: State<AppState>) {
    state.engine.site_cancel_login();
}

#[tauri::command]
fn site_logout(state: State<AppState>) {
    state.engine.site_logout();
}

#[tauri::command]
async fn site_refresh(state: State<'_, AppState>) -> Result<(), String> {
    state.engine.site_refresh().await;
    Ok(())
}

#[tauri::command]
async fn site_download_favorites(state: State<'_, AppState>) -> Result<(), String> {
    state.engine.site_download_favorites().await;
    Ok(())
}

#[tauri::command]
async fn site_download_playlist(state: State<'_, AppState>, id: String) -> Result<(), String> {
    state.engine.site_download_playlist(&id).await;
    Ok(())
}

#[tauri::command]
fn set_lossless(state: State<AppState>, value: bool) {
    state.engine.set_lossless(value);
}

#[tauri::command]
fn set_motion_auto(state: State<AppState>, value: bool) {
    state.engine.set_motion_auto(value);
}

#[tauri::command]
async fn update_check(state: State<'_, AppState>) -> Result<Option<UpdateManifest>, String> {
    text(update::check(&state.engine.http(), env!("CARGO_PKG_VERSION"), build_number()).await)
}

#[tauri::command]
async fn update_install(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    let http = state.engine.http();
    let manifest = text(update::check(&http, env!("CARGO_PKG_VERSION"), build_number()).await)?;
    let Some(manifest) = manifest else {
        return Ok(());
    };
    let installer = text(update::download(&http, &manifest, &state.engine.paths().updates).await)?;
    let current = text(std::env::current_exe())?;
    let command = format!("\"{}\" /S && start \"\" \"{}\"", installer.display(), current.display());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const DETACHED: u32 = 0x00000008 | 0x08000000;
        text(std::process::Command::new("cmd").args(["/C", &command]).creation_flags(DETACHED).spawn())?;
    }
    #[cfg(not(windows))]
    {
        let _ = command;
    }
    app.exit(0);
    Ok(())
}

fn forward(app: &AppHandle, event: Event) {
    match event {
        Event::Library => {
            let _ = app.emit("nsm:library", ());
        }
        Event::Import => {
            let _ = app.emit("nsm:import", ());
        }
        Event::Site => {
            let _ = app.emit("nsm:site", ());
        }
        Event::Toast(message) => {
            let _ = app.emit("nsm:toast", message);
        }
    }
}

fn focus_main(app: &AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.unminimize();
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn audio_args(args: &[String]) -> Vec<PathBuf> {
    args.iter().skip(1).map(PathBuf::from).filter(|path| path.exists()).collect()
}

fn handle_url(app: &AppHandle, link: &str) {
    if !link.starts_with("nodeshiftmusic://auth/callback") {
        return;
    }
    let engine = app.state::<AppState>().engine.clone();
    let link = link.to_string();
    tauri::async_runtime::spawn(async move {
        let _ = engine.site_complete_login(&link).await;
    });
    focus_main(app);
}

fn open_main_window(app: &tauri::App) -> tauri::Result<()> {
    let Some(config) = app.config().app.windows.first().cloned() else {
        return Ok(());
    };
    #[allow(unused_mut)]
    let mut builder = tauri::WebviewWindowBuilder::from_config(app.handle(), &config)?;
    #[cfg(windows)]
    if let Some(port) = std::env::var("NSM_DEBUG_PORT").ok().filter(|value| !value.is_empty()) {
        builder = builder.additional_browser_args(&format!(
            "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --remote-debugging-port={port} --remote-allow-origins=* --disable-gpu"
        ));
    }
    builder.build()?;
    Ok(())
}

fn install_panic_log() {
    std::panic::set_hook(Box::new(|info| {
        let path = std::env::temp_dir().join("nodeshift-music-panic.log");
        let line = format!("{info}\n");
        if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
            use std::io::Write;
            let _ = file.write_all(line.as_bytes());
        }
    }));
}

pub fn run() {
    install_panic_log();
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
            focus_main(app);
            let files = audio_args(&args);
            if !files.is_empty() {
                app.state::<AppState>().engine.start_import(files);
            }
            for argument in &args {
                handle_url(app, argument);
            }
        }))
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .setup(|app| {
            let base = match std::env::var_os("NSM_DATA_DIR") {
                Some(custom) => PathBuf::from(custom),
                None => app.path().app_data_dir()?,
            };
            let paths = Paths::new(&base)?;
            let handle = app.handle().clone();
            let emit: Emit = Arc::new(move |event| forward(&handle, event));
            let tokens = Arc::new(secure::DpapiStore::open(base.join("tokens.dat")));
            let runtime = tauri::async_runtime::handle().inner().clone();
            let catalog = if std::env::var_os("NSM_OFFLINE").is_some() { CatalogSource::None } else { CatalogSource::Network };
            let engine = Engine::new(EngineConfig { paths, catalog, tokens, emit, runtime })?;
            let media = tauri::async_runtime::block_on(media_server::start(engine.clone()))?;
            app.manage(AppState { engine: engine.clone(), media });
            open_main_window(app)?;

            let deep = app.deep_link();
            #[cfg(any(windows, target_os = "linux"))]
            {
                let _ = deep.register_all();
            }
            let handle = app.handle().clone();
            deep.on_open_url(move |event| {
                for link in event.urls() {
                    handle_url(&handle, link.as_str());
                }
            });
            if let Ok(Some(urls)) = deep.get_current() {
                for link in urls {
                    handle_url(app.handle(), link.as_str());
                }
            }

            let files = audio_args(&std::env::args().collect::<Vec<_>>());
            if !files.is_empty() {
                engine.start_import(files);
            }
            let restore = engine.clone();
            tauri::async_runtime::spawn(async move {
                restore.site_restore().await;
            });
            #[cfg(windows)]
            discord::spawn(engine.clone(), base.clone());
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            app_info,
            library_all,
            playlists_all,
            track_favorite,
            track_played,
            track_delete,
            track_update,
            playlist_create,
            playlist_add,
            playlist_remove,
            playlist_rename,
            playlist_delete,
            import_start,
            import_snapshot,
            import_decide,
            import_skip_all,
            import_clear,
            lyrics_get,
            cover_palette,
            catalog_page,
            catalog_wave,
            catalog_likes,
            catalog_like,
            catalog_played,
            presence_publish,
            site_lyrics_get,
            site_snapshot,
            site_login,
            site_cancel_login,
            site_logout,
            site_refresh,
            site_download_favorites,
            site_download_playlist,
            set_lossless,
            set_motion_auto,
            update_check,
            update_install,
        ])
        .run(tauri::generate_context!())
        .expect("run");
}
