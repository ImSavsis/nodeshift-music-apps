#![cfg(windows)]

mod common;

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use common::{eventually, playing, quick, serve, Behavior, FakeHub, Recorder};
use nsm_core::bridge::{start, BridgeStatus, PipeConnector};
use nsm_core::discord_ipc::{connect_slots, open_pipe, IpcError, SetOutcome};
use nsm_core::presence::{pipe_path, PIPE_PREFIX};
use serde_json::json;
use tokio::net::windows::named_pipe::ServerOptions;
use tokio::task::JoinHandle;

const IO: Duration = Duration::from_millis(400);
static COUNTER: AtomicUsize = AtomicUsize::new(0);

fn unique_prefix() -> String {
    assert!(PIPE_PREFIX.ends_with("discord-ipc-"));
    let tag = format!("nsm-test-{}-{}-", std::process::id(), COUNTER.fetch_add(1, Ordering::SeqCst));
    PIPE_PREFIX.replace("discord-ipc-", &tag)
}

fn listen(name: &str, behavior: Behavior, recorder: Arc<Recorder>) -> JoinHandle<()> {
    let server = ServerOptions::new().first_pipe_instance(true).create(name).expect("create pipe");
    tokio::spawn(async move {
        if server.connect().await.is_ok() {
            serve(server, behavior, recorder).await;
        }
    })
}

#[tokio::test]
async fn a_live_slot_is_found_among_missing_ones() {
    let prefix = unique_prefix();
    let recorder = Arc::new(Recorder::default());
    let _server = listen(&format!("{prefix}4"), Behavior::Normal, recorder.clone());
    let mut client = connect_slots(&prefix, "42", IO).await.expect("connect");
    assert_eq!(recorder.handshakes(), vec!["42".to_string()]);
    let activity = json!({ "details": "Over a real pipe" });
    assert_eq!(client.set_activity(Some(&activity)).await.unwrap(), SetOutcome::Accepted);
    assert_eq!(recorder.last(), Some(activity));
}

#[tokio::test]
async fn no_pipe_at_all_means_discord_is_not_running() {
    let prefix = unique_prefix();
    let failure = connect_slots(&prefix, "42", IO).await.err().expect("must fail");
    assert!(matches!(failure, IpcError::NotRunning), "{failure:?}");
}

#[tokio::test]
async fn the_real_prefix_shape_opens_a_pipe() {
    let prefix = unique_prefix();
    let name = format!("{prefix}0");
    let _server = listen(&name, Behavior::Normal, Arc::new(Recorder::default()));
    assert!(name.starts_with(r"\\.\pipe\"));
    assert!(open_pipe(&name).await.is_ok());
    assert!(pipe_path(0).starts_with(r"\\.\pipe\"));
}

#[tokio::test]
async fn the_single_backslash_form_never_reaches_the_pipe() {
    let prefix = unique_prefix();
    let name = format!("{prefix}0");
    let _server = listen(&name, Behavior::Normal, Arc::new(Recorder::default()));
    let broken = name.replacen(r"\\.\", r"\.\", 1);
    assert_ne!(broken, name);
    let error = open_pipe(&broken).await.expect_err("must not open");
    assert_eq!(error.kind(), std::io::ErrorKind::NotFound);
}

#[tokio::test]
async fn a_peer_that_never_answers_the_handshake_times_out() {
    let prefix = unique_prefix();
    let _server = listen(&format!("{prefix}0"), Behavior::Silent, Arc::new(Recorder::default()));
    let failure = connect_slots(&prefix, "42", Duration::from_millis(250)).await.err().expect("must fail");
    assert!(matches!(failure, IpcError::Timeout), "{failure:?}");
}

#[tokio::test]
async fn an_error_reply_over_a_real_pipe_is_reported() {
    let prefix = unique_prefix();
    let _server = listen(&format!("{prefix}2"), Behavior::RejectAll(4000), Arc::new(Recorder::default()));
    let mut client = connect_slots(&prefix, "42", IO).await.expect("connect");
    let outcome = client.set_activity(Some(&json!({ "details": "x" }))).await.unwrap();
    assert!(matches!(outcome, SetOutcome::Rejected { code: 4000, .. }), "{outcome:?}");
}

#[tokio::test]
async fn a_closed_server_is_noticed_by_the_client() {
    let prefix = unique_prefix();
    let server = listen(&format!("{prefix}1"), Behavior::Normal, Arc::new(Recorder::default()));
    let client = connect_slots(&prefix, "42", IO).await.expect("connect");
    assert!(!client.is_closed());
    server.abort();
    let reason = tokio::time::timeout(Duration::from_secs(3), client.closed()).await.expect("closed in time");
    assert!(!reason.is_empty());
    assert!(client.is_closed());
}

#[tokio::test]
async fn the_bridge_reconnects_after_the_server_drops_and_resends() {
    let prefix = unique_prefix();
    let name = format!("{prefix}0");
    let dir = tempfile::tempdir().unwrap();
    let hub = FakeHub::new();
    let recorder = Arc::new(Recorder::default());
    let first = listen(&name, Behavior::Normal, recorder.clone());
    let bridge = start(&tokio::runtime::Handle::current(), hub.clone(), PipeConnector::with_prefix(&prefix, IO), dir.path().to_path_buf(), quick());
    hub.publish(Some(playing("Through the pipe")));
    eventually("the first activity", || recorder.activities().len() == 1).await;
    eventually("showing status", || bridge.status() == BridgeStatus::Showing).await;

    first.abort();
    eventually("the lost connection to show up", || bridge.status() != BridgeStatus::Showing).await;
    let second = listen(&name, Behavior::Normal, recorder.clone());
    eventually("the activity on the new server", || recorder.activities().len() >= 2).await;
    eventually("showing status again", || bridge.status() == BridgeStatus::Showing).await;
    assert_eq!(recorder.handshakes().len(), 2);
    assert_eq!(recorder.last().unwrap()["details"], "Through the pipe");
    bridge.stop();
    second.abort();
}

#[tokio::test]
async fn the_bridge_waits_for_a_discord_that_starts_late() {
    let prefix = unique_prefix();
    let name = format!("{prefix}3");
    let dir = tempfile::tempdir().unwrap();
    let hub = FakeHub::new();
    let recorder = Arc::new(Recorder::default());
    let bridge = start(&tokio::runtime::Handle::current(), hub.clone(), PipeConnector::with_prefix(&prefix, IO), dir.path().to_path_buf(), quick());
    hub.publish(Some(playing("Early bird")));
    eventually("the waiting status", || bridge.status() == BridgeStatus::WaitingForDiscord).await;
    let _server = listen(&name, Behavior::Normal, recorder.clone());
    eventually("the activity once the pipe appears", || recorder.activities().len() == 1).await;
    eventually("showing status", || bridge.status() == BridgeStatus::Showing).await;
    bridge.stop();
}
