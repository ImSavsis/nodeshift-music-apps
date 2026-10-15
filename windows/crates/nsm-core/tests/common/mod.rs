#![allow(dead_code)]

use std::future::Future;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use nsm_core::bridge::{Connector, HubSource, Timings};
use nsm_core::discord_ipc::{IpcClient, IpcError};
use nsm_core::presence::{encode_frame, encode_raw};
use serde_json::{json, Value};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::Notify;
use tokio::task::JoinHandle;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Behavior {
    Normal,
    Silent,
    RejectAll(i64),
    RejectFancy(i64),
    PingAfterReady,
    OversizeAfterReady,
    CloseAfterReady,
    NoiseBeforeReply,
    RefuseHandshake,
}

#[derive(Default)]
pub struct Recorder {
    pub activities: Mutex<Vec<Value>>,
    pub handshakes: Mutex<Vec<String>>,
    pub pongs: AtomicUsize,
}

impl Recorder {
    pub fn activities(&self) -> Vec<Value> {
        self.activities.lock().unwrap().clone()
    }

    pub fn last(&self) -> Option<Value> {
        self.activities.lock().unwrap().last().cloned()
    }

    pub fn handshakes(&self) -> Vec<String> {
        self.handshakes.lock().unwrap().clone()
    }
}

fn is_fancy(activity: &Value) -> bool {
    activity.get("buttons").is_some() || activity["assets"].get("large_image").is_some()
}

async fn send<S: AsyncWrite + Unpin>(stream: &mut S, opcode: u32, payload: Value) {
    let _ = stream.write_all(&encode_frame(opcode, &payload)).await;
}

pub async fn serve<S: AsyncRead + AsyncWrite + Unpin>(mut stream: S, behavior: Behavior, recorder: Arc<Recorder>) {
    loop {
        let mut header = [0u8; 8];
        if stream.read_exact(&mut header).await.is_err() {
            return;
        }
        let opcode = u32::from_le_bytes([header[0], header[1], header[2], header[3]]);
        let length = u32::from_le_bytes([header[4], header[5], header[6], header[7]]) as usize;
        let mut body = vec![0u8; length];
        if stream.read_exact(&mut body).await.is_err() {
            return;
        }
        match opcode {
            0 => {
                let value: Value = serde_json::from_slice(&body).unwrap();
                recorder.handshakes.lock().unwrap().push(value["client_id"].as_str().unwrap_or("").to_string());
                if behavior == Behavior::Silent {
                    std::future::pending::<()>().await;
                }
                if behavior == Behavior::RefuseHandshake {
                    send(&mut stream, 1, json!({ "cmd": "DISPATCH", "evt": "ERROR", "data": { "code": 4000, "message": "Invalid Client ID" } })).await;
                    continue;
                }
                send(&mut stream, 1, json!({ "cmd": "DISPATCH", "evt": "READY", "data": { "v": 1 } })).await;
                match behavior {
                    Behavior::PingAfterReady => send(&mut stream, 3, json!({ "n": 1 })).await,
                    Behavior::CloseAfterReady => send(&mut stream, 2, json!({ "code": 1000, "message": "bye" })).await,
                    Behavior::OversizeAfterReady => {
                        let mut oversize = encode_raw(1, &[]);
                        oversize[4..8].copy_from_slice(&(2u32 << 20).to_le_bytes());
                        let _ = stream.write_all(&oversize).await;
                    }
                    _ => {}
                }
            }
            1 => {
                let value: Value = serde_json::from_slice(&body).unwrap();
                let activity = value["args"]["activity"].clone();
                recorder.activities.lock().unwrap().push(activity.clone());
                let rejected = match behavior {
                    Behavior::RejectAll(code) => Some(code),
                    Behavior::RejectFancy(code) if is_fancy(&activity) => Some(code),
                    _ => None,
                };
                if behavior == Behavior::NoiseBeforeReply {
                    send(&mut stream, 1, json!({ "cmd": "SET_ACTIVITY", "evt": "ERROR", "data": { "code": 1, "message": "someone else" }, "nonce": "other" })).await;
                }
                let reply = match rejected {
                    Some(code) => json!({ "cmd": "SET_ACTIVITY", "evt": "ERROR", "data": { "code": code, "message": "Invalid payload" }, "nonce": value["nonce"] }),
                    None => json!({ "cmd": "SET_ACTIVITY", "evt": null, "data": activity, "nonce": value["nonce"] }),
                };
                send(&mut stream, 1, reply).await;
            }
            4 => {
                recorder.pongs.fetch_add(1, Ordering::SeqCst);
            }
            _ => {}
        }
    }
}

pub struct DuplexConnector {
    pub recorder: Arc<Recorder>,
    pub behavior: Arc<Mutex<Behavior>>,
    pub failures_left: Arc<AtomicUsize>,
    pub attempts: Arc<AtomicUsize>,
    pub servers: Arc<Mutex<Vec<JoinHandle<()>>>>,
    pub io: Duration,
}

impl DuplexConnector {
    pub fn new(behavior: Behavior) -> Self {
        Self {
            recorder: Arc::new(Recorder::default()),
            behavior: Arc::new(Mutex::new(behavior)),
            failures_left: Arc::new(AtomicUsize::new(0)),
            attempts: Arc::new(AtomicUsize::new(0)),
            servers: Arc::new(Mutex::new(Vec::new())),
            io: Duration::from_millis(300),
        }
    }

    pub fn kill_servers(&self) {
        for server in self.servers.lock().unwrap().drain(..) {
            server.abort();
        }
    }

    pub fn handle(&self) -> DuplexConnector {
        DuplexConnector {
            recorder: self.recorder.clone(),
            behavior: self.behavior.clone(),
            failures_left: self.failures_left.clone(),
            attempts: self.attempts.clone(),
            servers: self.servers.clone(),
            io: self.io,
        }
    }
}

impl Connector for DuplexConnector {
    fn connect(&self, app_id: &str) -> impl Future<Output = Result<IpcClient, IpcError>> + Send {
        self.attempts.fetch_add(1, Ordering::SeqCst);
        let refuse = self
            .failures_left
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |left| left.checked_sub(1))
            .is_ok();
        let behavior = *self.behavior.lock().unwrap();
        let recorder = self.recorder.clone();
        let servers = self.servers.clone();
        let io = self.io;
        let app_id = app_id.to_string();
        async move {
            if refuse {
                return Err(IpcError::NotRunning);
            }
            let (client_side, server_side) = tokio::io::duplex(1 << 16);
            servers.lock().unwrap().push(tokio::spawn(serve(server_side, behavior, recorder)));
            IpcClient::handshake(client_side, &app_id, io).await
        }
    }
}

pub struct HubInner {
    pub session: AtomicBool,
    pub lost_calls: AtomicUsize,
    pub polls: AtomicUsize,
    state: Mutex<(u64, Option<Value>, bool)>,
    changed: Notify,
}

#[derive(Clone)]
pub struct FakeHub(pub Arc<HubInner>);

impl FakeHub {
    pub fn new() -> Self {
        Self(Arc::new(HubInner {
            session: AtomicBool::new(true),
            lost_calls: AtomicUsize::new(0),
            polls: AtomicUsize::new(0),
            state: Mutex::new((1, None, false)),
            changed: Notify::new(),
        }))
    }

    pub fn publish(&self, state: Option<Value>) {
        {
            let mut guard = self.0.state.lock().unwrap();
            guard.0 += 1;
            guard.1 = state;
        }
        self.0.changed.notify_waiters();
    }

    pub fn set_down(&self, down: bool) {
        self.0.state.lock().unwrap().2 = down;
        self.0.changed.notify_waiters();
    }

    pub fn drop_session(&self) {
        self.0.session.store(false, Ordering::SeqCst);
    }

    pub fn lost_calls(&self) -> usize {
        self.0.lost_calls.load(Ordering::SeqCst)
    }

    fn reply(&self) -> String {
        let guard = self.0.state.lock().unwrap();
        json!({ "version": guard.0, "state": guard.1 }).to_string()
    }
}

impl HubSource for FakeHub {
    fn has_session(&self) -> bool {
        self.0.session.load(Ordering::SeqCst)
    }

    fn session_lost(&self) {
        self.0.lost_calls.fetch_add(1, Ordering::SeqCst);
    }

    fn poll(&self, since: i64) -> impl Future<Output = Result<String, String>> + Send {
        let hub = self.clone();
        async move {
            hub.0.polls.fetch_add(1, Ordering::SeqCst);
            let deadline = tokio::time::Instant::now() + Duration::from_millis(250);
            loop {
                let (version, down) = {
                    let guard = hub.0.state.lock().unwrap();
                    (guard.0, guard.2)
                };
                if down {
                    return Err("hub is down".to_string());
                }
                if version as i64 != since || tokio::time::Instant::now() >= deadline {
                    return Ok(hub.reply());
                }
                tokio::select! {
                    _ = hub.0.changed.notified() => {}
                    _ = tokio::time::sleep(Duration::from_millis(25)) => {}
                }
            }
        }
    }
}

pub fn quick() -> Timings {
    Timings {
        min_send_gap: Duration::from_millis(150),
        connect_min: Duration::from_millis(40),
        connect_max: Duration::from_millis(160),
        poll_min: Duration::from_millis(20),
        poll_max: Duration::from_millis(80),
        poll_gap: Duration::from_millis(100),
        idle_recheck: Duration::from_millis(100),
        stale_after: Duration::from_millis(700),
    }
}

pub fn playing(title: &str) -> Value {
    json!({
        "device": "phone",
        "platform": "ios",
        "playing": true,
        "title": title,
        "artist": "Artist",
        "album": "Album",
        "position_ms": 10_000,
        "duration_ms": 240_000,
        "cover": "https://burmalda.savsis.xyz/covers/a.jpg",
        "site_id": "183",
        "ts": 1,
        "age_ms": 2_500,
    })
}

pub async fn eventually<F: FnMut() -> bool>(what: &str, mut condition: F) {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(10);
    while tokio::time::Instant::now() < deadline {
        if condition() {
            return;
        }
        tokio::time::sleep(Duration::from_millis(15)).await;
    }
    panic!("timed out waiting for {what}");
}

pub fn write_config(base: &Path, text: &str) {
    std::fs::write(base.join("discord.json"), text).unwrap();
}
