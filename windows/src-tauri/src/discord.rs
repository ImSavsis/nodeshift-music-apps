use std::path::PathBuf;
use std::time::Duration;

use nsm_core::engine::Engine;
use nsm_core::presence::{build_activity, decode_header, encode_frame, parse_poll, DiscordConfig, Presence};
use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::windows::named_pipe::{ClientOptions, NamedPipeClient};

struct Ipc {
    pipe: NamedPipeClient,
    app_id: String,
}

impl Ipc {
    async fn connect(app_id: &str) -> Option<Ipc> {
        for index in 0..10 {
            let name = format!(r"\.\pipe\discord-ipc-{index}");
            let Ok(pipe) = ClientOptions::new().open(&name) else {
                continue;
            };
            let mut ipc = Ipc { pipe, app_id: app_id.to_string() };
            if ipc.write(0, &json!({ "v": 1, "client_id": app_id })).await.is_err() {
                continue;
            }
            match ipc.read().await {
                Some((_, value)) if value.get("evt").and_then(Value::as_str) == Some("READY") => return Some(ipc),
                _ => continue,
            }
        }
        None
    }

    async fn write(&mut self, opcode: u32, payload: &Value) -> std::io::Result<()> {
        self.pipe.write_all(&encode_frame(opcode, payload)).await
    }

    async fn read(&mut self) -> Option<(u32, Value)> {
        let mut header = [0u8; 8];
        self.pipe.read_exact(&mut header).await.ok()?;
        let (opcode, length) = decode_header(header);
        let mut body = vec![0u8; length];
        self.pipe.read_exact(&mut body).await.ok()?;
        Some((opcode, serde_json::from_slice(&body).ok()?))
    }

    async fn set_activity(&mut self, activity: Option<&Value>, nonce: u64) -> bool {
        let payload = json!({
            "cmd": "SET_ACTIVITY",
            "args": { "pid": std::process::id(), "activity": activity },
            "nonce": format!("nsm-{nonce}"),
        });
        if self.write(1, &payload).await.is_err() {
            return false;
        }
        self.read().await.is_some()
    }
}

pub fn spawn(engine: Engine, base: PathBuf) {
    tauri::async_runtime::spawn(async move {
        run(engine, base).await;
    });
}

async fn apply(ipc: &mut Option<Ipc>, config: &DiscordConfig, state: Option<&Presence>, nonce: &mut u64) {
    if ipc.as_ref().is_some_and(|client| client.app_id != config.app_id) {
        *ipc = None;
    }
    if ipc.is_none() {
        *ipc = Ipc::connect(&config.app_id).await;
    }
    let Some(client) = ipc.as_mut() else {
        return;
    };
    let activity = state.map(|presence| build_activity(presence, &config.name));
    *nonce += 1;
    if !client.set_activity(activity.as_ref(), *nonce).await {
        *ipc = None;
    }
}

async fn run(engine: Engine, base: PathBuf) {
    let mut ipc: Option<Ipc> = None;
    let mut version: i64 = -1;
    let mut shown: Option<Presence> = None;
    let mut nonce = 0u64;
    loop {
        let config = DiscordConfig::load(&base);
        if !config.enabled || !engine.site().has_session() {
            if shown.take().is_some() {
                apply(&mut ipc, &config, None, &mut nonce).await;
            }
            version = -1;
            tokio::time::sleep(Duration::from_secs(20)).await;
            continue;
        }
        let text = match engine.site().presence_poll(version).await {
            Ok(text) => text,
            Err(_) => {
                tokio::time::sleep(Duration::from_secs(10)).await;
                continue;
            }
        };
        let Some((next, state)) = parse_poll(&text) else {
            tokio::time::sleep(Duration::from_secs(5)).await;
            continue;
        };
        version = next as i64;
        shown = state;
        apply(&mut ipc, &config, shown.as_ref(), &mut nonce).await;
    }
}
