use std::future::Future;
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::Value;
use tokio::sync::{watch, Notify};
use tokio::task::AbortHandle;
use tokio::time::Instant;

use crate::discord_ipc::{IpcClient, IpcError, SetOutcome};
use crate::engine::Engine;
use crate::model::now_ms;
use crate::presence::{build_activity, parse_poll, plain_activity, DiscordConfig, Presence};

const LOG_LIMIT: u64 = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum BridgeStatus {
    Disabled,
    NeedsLogin,
    HubUnreachable,
    WaitingForDiscord,
    Idle,
    Showing,
}

impl BridgeStatus {
    pub fn code(self) -> &'static str {
        match self {
            Self::Disabled => "disabled",
            Self::NeedsLogin => "needs_login",
            Self::HubUnreachable => "hub_unreachable",
            Self::WaitingForDiscord => "waiting_for_discord",
            Self::Idle => "idle",
            Self::Showing => "showing",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Disabled => "Discord: выключен",
            Self::NeedsLogin => "Discord: нужно войти в аккаунт",
            Self::HubUnreachable => "Discord: нет связи с сервером",
            Self::WaitingForDiscord => "Discord: не найден, жду",
            Self::Idle => "Discord: ничего не играет",
            Self::Showing => "Discord: показывает трек",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Desired {
    pub app_id: String,
    pub activity: Value,
}

#[derive(Debug, Clone)]
pub struct Timings {
    pub min_send_gap: Duration,
    pub connect_min: Duration,
    pub connect_max: Duration,
    pub poll_min: Duration,
    pub poll_max: Duration,
    pub poll_gap: Duration,
    pub idle_recheck: Duration,
    pub stale_after: Duration,
}

impl Default for Timings {
    fn default() -> Self {
        Self {
            min_send_gap: Duration::from_secs(4),
            connect_min: Duration::from_secs(5),
            connect_max: Duration::from_secs(30),
            poll_min: Duration::from_secs(2),
            poll_max: Duration::from_secs(60),
            poll_gap: Duration::from_secs(1),
            idle_recheck: Duration::from_secs(20),
            stale_after: Duration::from_secs(120),
        }
    }
}

pub trait Connector: Send + Sync + 'static {
    fn connect(&self, app_id: &str) -> impl Future<Output = Result<IpcClient, IpcError>> + Send;
}

pub trait HubSource: Send + Sync + 'static {
    fn has_session(&self) -> bool;
    fn session_lost(&self);
    fn poll(&self, since: i64) -> impl Future<Output = Result<String, String>> + Send;
}

impl HubSource for Engine {
    fn has_session(&self) -> bool {
        self.site().has_session()
    }

    fn session_lost(&self) {
        self.site_session_lost();
    }

    fn poll(&self, since: i64) -> impl Future<Output = Result<String, String>> + Send {
        let engine = self.clone();
        async move { engine.site().presence_poll(since).await.map_err(|error| error.to_string()) }
    }
}

#[cfg(windows)]
pub struct PipeConnector {
    prefix: String,
    io: Duration,
}

#[cfg(windows)]
impl PipeConnector {
    pub fn discord() -> Self {
        Self::with_prefix(crate::presence::PIPE_PREFIX, crate::discord_ipc::IO_TIMEOUT)
    }

    pub fn with_prefix(prefix: &str, io: Duration) -> Self {
        Self { prefix: prefix.to_string(), io }
    }
}

#[cfg(windows)]
impl Connector for PipeConnector {
    fn connect(&self, app_id: &str) -> impl Future<Output = Result<IpcClient, IpcError>> + Send {
        let prefix = self.prefix.clone();
        let io = self.io;
        let app_id = app_id.to_string();
        async move { crate::discord_ipc::connect_slots(&prefix, &app_id, io).await }
    }
}

#[derive(Clone, Copy, PartialEq)]
enum PollerState {
    Disabled,
    NeedsLogin,
    HubDown,
    Ready,
}

#[derive(Clone, Copy, PartialEq)]
enum SinkState {
    Idle,
    Searching,
    Showing,
}

fn combine(poller: PollerState, sink: SinkState) -> BridgeStatus {
    match (poller, sink) {
        (PollerState::Disabled, _) => BridgeStatus::Disabled,
        (PollerState::NeedsLogin, _) => BridgeStatus::NeedsLogin,
        (_, SinkState::Searching) => BridgeStatus::WaitingForDiscord,
        (PollerState::HubDown, _) => BridgeStatus::HubUnreachable,
        (_, SinkState::Showing) => BridgeStatus::Showing,
        (_, SinkState::Idle) => BridgeStatus::Idle,
    }
}

struct StatusBoard {
    states: Mutex<(PollerState, SinkState)>,
    sender: watch::Sender<BridgeStatus>,
}

impl StatusBoard {
    fn new() -> (Arc<Self>, watch::Receiver<BridgeStatus>) {
        let (sender, receiver) = watch::channel(BridgeStatus::Idle);
        (Arc::new(Self { states: Mutex::new((PollerState::Ready, SinkState::Idle)), sender }), receiver)
    }

    fn update(&self, change: impl FnOnce(&mut (PollerState, SinkState))) {
        let status = {
            let mut states = self.states.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
            change(&mut states);
            combine(states.0, states.1)
        };
        self.sender.send_if_modified(|current| {
            let changed = *current != status;
            *current = status;
            changed
        });
    }

    fn poller(&self, state: PollerState) {
        self.update(|states| states.0 = state);
    }

    fn sink(&self, state: SinkState) {
        self.update(|states| states.1 = state);
    }
}

pub struct BridgeLog {
    path: PathBuf,
    limit: u64,
}

impl BridgeLog {
    pub fn new(path: PathBuf) -> Self {
        Self { path, limit: LOG_LIMIT }
    }

    pub fn with_limit(path: PathBuf, limit: u64) -> Self {
        Self { path, limit }
    }

    fn roll(&self) {
        let size = std::fs::metadata(&self.path).map(|meta| meta.len()).unwrap_or(0);
        if size <= self.limit {
            return;
        }
        let old = self.path.with_extension("log.old");
        let _ = std::fs::remove_file(&old);
        let _ = std::fs::rename(&self.path, &old);
    }

    pub fn line(&self, text: &str) {
        self.roll();
        if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(&self.path) {
            let _ = writeln!(file, "{} {}", format_utc(now_ms()), text);
        }
    }
}

pub fn format_utc(ms: i64) -> String {
    let seconds = ms.div_euclid(1000);
    let days = seconds.div_euclid(86_400);
    let rest = seconds.rem_euclid(86_400);
    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097);
    let year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    format!("{year:04}-{month:02}-{day:02} {:02}:{:02}:{:02}", rest / 3600, rest % 3600 / 60, rest % 60)
}

pub fn next_backoff(current: Duration, max: Duration) -> Duration {
    (current * 2).min(max)
}

fn jittered(delay: Duration) -> Duration {
    delay.mul_f64(rand::random_range(0.8..1.2))
}

async fn pause(wake: &Notify, delay: Duration) {
    tokio::select! {
        _ = tokio::time::sleep(delay) => {}
        _ = wake.notified() => {}
    }
}

fn set_desired(sender: &watch::Sender<Option<Desired>>, value: Option<Desired>) {
    sender.send_if_modified(|current| {
        if *current == value {
            return false;
        }
        *current = value;
        true
    });
}

fn make_desired(config: &DiscordConfig, latest: &Option<(Presence, u64)>) -> Option<Desired> {
    latest.as_ref().map(|(presence, received)| Desired {
        app_id: config.app_id.clone(),
        activity: build_activity(presence, &config.name, *received),
    })
}

fn earliest(current: Option<Instant>, candidate: Instant) -> Option<Instant> {
    Some(current.map_or(candidate, |value| value.min(candidate)))
}

#[derive(Debug, Clone, PartialEq)]
enum Shown {
    Cleared,
    Activity(Value),
    Refused(Value),
}

fn needs_push(want: &Option<Desired>, shown: &Shown) -> bool {
    match (want, shown) {
        (None, Shown::Cleared) => false,
        (None, _) => true,
        (Some(target), Shown::Activity(sent)) | (Some(target), Shown::Refused(sent)) => *sent != target.activity,
        (Some(_), Shown::Cleared) => true,
    }
}

async fn push(client: &mut IpcClient, target: Option<&Desired>, log: &BridgeLog) -> Result<Shown, IpcError> {
    match client.set_activity(target.map(|desired| &desired.activity)).await? {
        SetOutcome::Accepted => Ok(match target {
            Some(desired) => Shown::Activity(desired.activity.clone()),
            None => Shown::Cleared,
        }),
        SetOutcome::Rejected { code, message } => {
            log.line(&format!("discord rejected the activity: {code} {message}"));
            let Some(desired) = target else {
                return Ok(Shown::Cleared);
            };
            let plain = plain_activity(&desired.activity);
            if code == 4000 && plain != desired.activity {
                match client.set_activity(Some(&plain)).await? {
                    SetOutcome::Accepted => {
                        log.line("accepted without buttons and cover");
                        return Ok(Shown::Activity(desired.activity.clone()));
                    }
                    SetOutcome::Rejected { code, message } => log.line(&format!("discord rejected the plain activity too: {code} {message}")),
                }
            }
            Ok(Shown::Refused(desired.activity.clone()))
        }
    }
}

async fn run_sink<C: Connector>(
    connector: C,
    mut desired: watch::Receiver<Option<Desired>>,
    board: Arc<StatusBoard>,
    log: Arc<BridgeLog>,
    timings: Timings,
) {
    let mut client: Option<IpcClient> = None;
    let mut shown = Shown::Cleared;
    let mut last_send: Option<Instant> = None;
    let mut next_connect: Option<Instant> = None;
    let mut connect_delay = timings.connect_min;
    let mut connect_error: Option<String> = None;
    loop {
        let want = desired.borrow_and_update().clone();
        let mut lost: Option<String> = None;
        if let Some(current) = &client {
            if current.is_closed() {
                lost = Some(format!("discord connection lost: {}", current.closed().await));
            } else if want.as_ref().is_some_and(|target| target.app_id != current.app_id()) {
                lost = Some("application id changed, reconnecting".to_string());
            }
        }
        if let Some(reason) = lost {
            log.line(&reason);
            client = None;
        }
        if client.is_none() {
            shown = Shown::Cleared;
        }

        let mut wake_at: Option<Instant> = None;
        if needs_push(&want, &shown) {
            if client.is_none() {
                if let Some(target) = &want {
                    match next_connect {
                        Some(at) if Instant::now() < at => wake_at = Some(at),
                        _ => match connector.connect(&target.app_id).await {
                            Ok(connected) => {
                                log.line("connected to discord");
                                client = Some(connected);
                                connect_delay = timings.connect_min;
                                next_connect = None;
                                connect_error = None;
                            }
                            Err(error) => {
                                let text = error.to_string();
                                if connect_error.as_deref() != Some(text.as_str()) {
                                    log.line(&format!("discord unavailable: {text}"));
                                    connect_error = Some(text);
                                }
                                let at = Instant::now() + connect_delay;
                                next_connect = Some(at);
                                connect_delay = next_backoff(connect_delay, timings.connect_max);
                                wake_at = Some(at);
                            }
                        },
                    }
                }
            }
            if let Some(active) = client.as_mut() {
                let ready_at = last_send.map(|at| at + timings.min_send_gap);
                match ready_at {
                    Some(at) if Instant::now() < at => wake_at = earliest(wake_at, at),
                    _ => {
                        let result = push(active, want.as_ref(), &log).await;
                        last_send = Some(Instant::now());
                        match result {
                            Ok(outcome) => shown = outcome,
                            Err(error) => {
                                log.line(&format!("discord update failed: {error}"));
                                client = None;
                                shown = Shown::Cleared;
                                next_connect = Some(Instant::now() + connect_delay);
                                connect_delay = next_backoff(connect_delay, timings.connect_max);
                            }
                        }
                        continue;
                    }
                }
            }
        }

        let state = if client.is_none() && want.is_some() {
            SinkState::Searching
        } else if matches!(shown, Shown::Activity(_)) {
            SinkState::Showing
        } else {
            SinkState::Idle
        };
        board.sink(state);

        let timer = async {
            match wake_at {
                Some(at) => tokio::time::sleep_until(at).await,
                None => std::future::pending::<()>().await,
            }
        };
        let dropped = async {
            match &client {
                Some(active) => active.closed().await,
                None => std::future::pending::<String>().await,
            }
        };
        tokio::select! {
            changed = desired.changed() => {
                if changed.is_err() {
                    return;
                }
            }
            reason = dropped => {
                log.line(&format!("discord connection lost: {reason}"));
                client = None;
            }
            _ = timer => {}
        }
    }
}

async fn run_poller<H: HubSource>(
    hub: Arc<H>,
    base: PathBuf,
    desired: watch::Sender<Option<Desired>>,
    board: Arc<StatusBoard>,
    log: Arc<BridgeLog>,
    wake: Arc<Notify>,
    timings: Timings,
) {
    let mut version: i64 = -1;
    let mut published: Option<u64> = None;
    let mut latest: Option<(Presence, u64)> = None;
    let mut applied: Option<(String, String)> = None;
    let mut backoff = timings.poll_min;
    let mut last_ok: Option<Instant> = None;
    let mut last_failure: Option<String> = None;
    let mut had_session = hub.has_session();
    loop {
        let config = DiscordConfig::load(&base);
        let has_session = hub.has_session();
        if had_session && !has_session {
            log.line("session lost, login needed");
            hub.session_lost();
        }
        had_session = has_session;
        if !config.enabled || !has_session {
            board.poller(if config.enabled { PollerState::NeedsLogin } else { PollerState::Disabled });
            set_desired(&desired, None);
            version = -1;
            published = None;
            latest = None;
            applied = None;
            last_ok = None;
            backoff = timings.poll_min;
            pause(&wake, timings.idle_recheck).await;
            continue;
        }

        let identity = (config.app_id.clone(), config.name.clone());
        if published.is_some() && applied.as_ref() != Some(&identity) {
            set_desired(&desired, make_desired(&config, &latest));
            applied = Some(identity.clone());
        }

        let started = Instant::now();
        let reply = tokio::select! {
            reply = hub.poll(version) => reply,
            _ = wake.notified() => continue,
        };
        match reply.and_then(|text| parse_poll(&text).ok_or_else(|| "unreadable reply".to_string())) {
            Ok((next, state)) => {
                backoff = timings.poll_min;
                last_ok = Some(Instant::now());
                last_failure = None;
                board.poller(PollerState::Ready);
                let unchanged = version == next as i64;
                version = next as i64;
                if published != Some(next) {
                    latest = state.map(|presence| (presence, now_ms().max(0) as u64));
                    published = Some(next);
                    applied = Some(identity);
                    set_desired(&desired, make_desired(&config, &latest));
                } else if unchanged {
                    pause(&wake, timings.poll_gap.saturating_sub(started.elapsed())).await;
                }
            }
            Err(reason) => {
                board.poller(PollerState::HubDown);
                if last_failure.as_deref() != Some(reason.as_str()) {
                    log.line(&format!("hub poll failed: {reason}"));
                    last_failure = Some(reason);
                }
                let mut delay = jittered(backoff);
                backoff = next_backoff(backoff, timings.poll_max);
                if let Some(at) = last_ok {
                    let silent = at.elapsed();
                    if silent >= timings.stale_after {
                        if desired.borrow().is_some() {
                            log.line("hub silent for too long, clearing the activity");
                            set_desired(&desired, None);
                        }
                        published = None;
                        latest = None;
                    } else {
                        delay = delay.min(timings.stale_after - silent + Duration::from_millis(50));
                    }
                }
                pause(&wake, delay).await;
            }
        }
    }
}

#[derive(Clone)]
pub struct Bridge {
    status: watch::Receiver<BridgeStatus>,
    wake: Arc<Notify>,
    tasks: Arc<[AbortHandle]>,
}

impl Bridge {
    pub fn status(&self) -> BridgeStatus {
        *self.status.borrow()
    }

    pub fn watch(&self) -> watch::Receiver<BridgeStatus> {
        self.status.clone()
    }

    pub fn wake(&self) {
        self.wake.notify_one();
    }

    pub fn stop(&self) {
        for task in self.tasks.iter() {
            task.abort();
        }
    }
}

pub fn start<H: HubSource, C: Connector>(runtime: &tokio::runtime::Handle, hub: H, connector: C, base: PathBuf, timings: Timings) -> Bridge {
    let (board, status) = StatusBoard::new();
    let log = Arc::new(BridgeLog::new(base.join("bridge.log")));
    let (desired_tx, desired_rx) = watch::channel(None);
    let wake = Arc::new(Notify::new());
    let poller = runtime.spawn(run_poller(Arc::new(hub), base, desired_tx, board.clone(), log.clone(), wake.clone(), timings.clone()));
    let sink = runtime.spawn(run_sink(connector, desired_rx, board, log, timings));
    Bridge { status, wake, tasks: Arc::from([poller.abort_handle(), sink.abort_handle()]) }
}

#[cfg(windows)]
pub fn start_discord(runtime: &tokio::runtime::Handle, engine: Engine, base: PathBuf) -> Bridge {
    start(runtime, engine, PipeConnector::discord(), base, Timings::default())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_codes_are_unique_and_stable() {
        let all = [
            BridgeStatus::Disabled,
            BridgeStatus::NeedsLogin,
            BridgeStatus::HubUnreachable,
            BridgeStatus::WaitingForDiscord,
            BridgeStatus::Idle,
            BridgeStatus::Showing,
        ];
        let mut codes: Vec<&str> = all.iter().map(|status| status.code()).collect();
        codes.sort_unstable();
        codes.dedup();
        assert_eq!(codes.len(), all.len());
        assert_eq!(BridgeStatus::Showing.code(), "showing");
        assert_eq!(BridgeStatus::WaitingForDiscord.code(), "waiting_for_discord");
    }

    #[test]
    fn utc_formatting() {
        assert_eq!(format_utc(0), "1970-01-01 00:00:00");
        assert_eq!(format_utc(1_700_000_000_000), "2023-11-14 22:13:20");
        assert_eq!(format_utc(1_709_164_800_000), "2024-02-29 00:00:00");
        assert_eq!(format_utc(1_760_000_000_999), "2025-10-09 08:53:20");
    }

    #[test]
    fn backoff_doubles_up_to_the_cap() {
        let max = Duration::from_secs(60);
        let mut delay = Duration::from_secs(2);
        let mut seen = Vec::new();
        for _ in 0..7 {
            seen.push(delay.as_secs());
            delay = next_backoff(delay, max);
        }
        assert_eq!(seen, vec![2, 4, 8, 16, 32, 60, 60]);
    }

    #[test]
    fn jitter_stays_near_the_delay() {
        for _ in 0..200 {
            let value = jittered(Duration::from_secs(10));
            assert!(value >= Duration::from_secs(8) && value <= Duration::from_secs(12), "{value:?}");
        }
    }

    #[test]
    fn status_priority() {
        assert_eq!(combine(PollerState::Disabled, SinkState::Showing), BridgeStatus::Disabled);
        assert_eq!(combine(PollerState::NeedsLogin, SinkState::Searching), BridgeStatus::NeedsLogin);
        assert_eq!(combine(PollerState::Ready, SinkState::Searching), BridgeStatus::WaitingForDiscord);
        assert_eq!(combine(PollerState::HubDown, SinkState::Idle), BridgeStatus::HubUnreachable);
        assert_eq!(combine(PollerState::HubDown, SinkState::Showing), BridgeStatus::HubUnreachable);
        assert_eq!(combine(PollerState::Ready, SinkState::Showing), BridgeStatus::Showing);
        assert_eq!(combine(PollerState::Ready, SinkState::Idle), BridgeStatus::Idle);
    }

    #[test]
    fn every_status_has_its_own_line() {
        let all = [
            BridgeStatus::Disabled,
            BridgeStatus::NeedsLogin,
            BridgeStatus::HubUnreachable,
            BridgeStatus::WaitingForDiscord,
            BridgeStatus::Idle,
            BridgeStatus::Showing,
        ];
        let lines: std::collections::HashSet<_> = all.iter().map(|status| status.label()).collect();
        assert_eq!(lines.len(), all.len());
        assert!(lines.iter().all(|line| line.starts_with("Discord: ")));
    }

    #[test]
    fn push_decisions() {
        let desired = Desired { app_id: "1".into(), activity: serde_json::json!({ "a": 1 }) };
        let other = serde_json::json!({ "a": 2 });
        assert!(!needs_push(&None, &Shown::Cleared));
        assert!(needs_push(&None, &Shown::Activity(other.clone())));
        assert!(needs_push(&None, &Shown::Refused(other.clone())));
        assert!(needs_push(&Some(desired.clone()), &Shown::Cleared));
        assert!(!needs_push(&Some(desired.clone()), &Shown::Activity(desired.activity.clone())));
        assert!(!needs_push(&Some(desired.clone()), &Shown::Refused(desired.activity.clone())));
        assert!(needs_push(&Some(desired), &Shown::Activity(other)));
    }

    #[test]
    fn log_rolls_over_when_it_grows() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("bridge.log");
        let log = BridgeLog::with_limit(path.clone(), 200);
        for index in 0..20 {
            log.line(&format!("line number {index} with some padding to grow the file"));
        }
        let size = std::fs::metadata(&path).unwrap().len();
        assert!(size <= 400, "{size}");
        assert!(dir.path().join("bridge.log.old").exists());
        let text = std::fs::read_to_string(&path).unwrap();
        assert!(text.contains("line number 19"));
    }
}
