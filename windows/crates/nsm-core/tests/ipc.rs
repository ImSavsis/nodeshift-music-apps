mod common;

use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::time::{Duration, Instant};

use common::{eventually, serve, Behavior, Recorder};
use nsm_core::discord_ipc::{IpcClient, IpcError, SetOutcome};
use serde_json::{json, Value};
use tokio::task::JoinHandle;

const IO: Duration = Duration::from_millis(300);

struct Peer {
    recorder: Arc<Recorder>,
    server: JoinHandle<()>,
}

async fn attach(behavior: Behavior) -> (Result<IpcClient, IpcError>, Peer) {
    let recorder = Arc::new(Recorder::default());
    let (client_side, server_side) = tokio::io::duplex(1 << 16);
    let server = tokio::spawn(serve(server_side, behavior, recorder.clone()));
    (IpcClient::handshake(client_side, "123", IO).await, Peer { recorder, server })
}

async fn ready(behavior: Behavior) -> (IpcClient, Peer) {
    let (client, peer) = attach(behavior).await;
    (client.expect("handshake"), peer)
}

fn activity() -> Value {
    json!({ "details": "Song", "type": 2 })
}

#[tokio::test]
async fn the_handshake_carries_the_application_id() {
    let (client, peer) = ready(Behavior::Normal).await;
    assert_eq!(client.app_id(), "123");
    assert_eq!(peer.recorder.handshakes(), vec!["123".to_string()]);
    assert!(!client.is_closed());
}

#[tokio::test]
async fn a_silent_peer_times_out_instead_of_hanging() {
    let started = Instant::now();
    let (client, _peer) = attach(Behavior::Silent).await;
    assert!(matches!(client, Err(IpcError::Timeout)), "{:?}", client.err());
    assert!(started.elapsed() < Duration::from_secs(3));
}

#[tokio::test]
async fn an_acknowledged_update_is_accepted_and_reaches_the_peer() {
    let (mut client, peer) = ready(Behavior::Normal).await;
    assert_eq!(client.set_activity(Some(&activity())).await.unwrap(), SetOutcome::Accepted);
    assert_eq!(peer.recorder.last(), Some(activity()));
}

#[tokio::test]
async fn clearing_sends_a_null_activity() {
    let (mut client, peer) = ready(Behavior::Normal).await;
    assert_eq!(client.set_activity(None).await.unwrap(), SetOutcome::Accepted);
    assert_eq!(peer.recorder.last(), Some(Value::Null));
}

#[tokio::test]
async fn an_error_reply_is_not_mistaken_for_success() {
    let (mut client, _peer) = ready(Behavior::RejectAll(4000)).await;
    match client.set_activity(Some(&activity())).await.unwrap() {
        SetOutcome::Rejected { code, message } => {
            assert_eq!(code, 4000);
            assert_eq!(message, "Invalid payload");
        }
        other => panic!("{other:?}"),
    }
}

#[tokio::test]
async fn replies_are_matched_by_nonce() {
    let (mut client, _peer) = ready(Behavior::NoiseBeforeReply).await;
    for _ in 0..3 {
        assert_eq!(client.set_activity(Some(&activity())).await.unwrap(), SetOutcome::Accepted);
    }
}

#[tokio::test]
async fn a_ping_is_answered_and_does_not_shift_later_replies() {
    let (mut client, peer) = ready(Behavior::PingAfterReady).await;
    eventually("the pong", || peer.recorder.pongs.load(Ordering::SeqCst) >= 1).await;
    assert_eq!(client.set_activity(Some(&activity())).await.unwrap(), SetOutcome::Accepted);
    assert!(!client.is_closed());
}

#[tokio::test]
async fn an_oversize_frame_is_a_connection_error() {
    let (mut client, _peer) = ready(Behavior::OversizeAfterReady).await;
    let reason = tokio::time::timeout(Duration::from_secs(2), client.closed()).await.expect("closed in time");
    assert!(reason.contains("bytes"), "{reason}");
    assert!(client.is_closed());
    assert!(matches!(client.set_activity(Some(&activity())).await, Err(IpcError::Closed(_))));
}

#[tokio::test]
async fn a_close_frame_ends_the_connection() {
    let (client, _peer) = ready(Behavior::CloseAfterReady).await;
    let reason = tokio::time::timeout(Duration::from_secs(2), client.closed()).await.expect("closed in time");
    assert!(reason.contains("peer closed"), "{reason}");
    assert!(client.is_closed());
}

#[tokio::test]
async fn a_vanished_peer_is_noticed_without_writing() {
    let (mut client, peer) = ready(Behavior::Normal).await;
    assert!(!client.is_closed());
    peer.server.abort();
    let reason = tokio::time::timeout(Duration::from_secs(2), client.closed()).await.expect("closed in time");
    assert!(reason.contains("read failed"), "{reason}");
    assert!(matches!(client.set_activity(Some(&activity())).await, Err(IpcError::Closed(_))));
}

#[tokio::test]
async fn a_refused_handshake_is_reported() {
    let (client, _peer) = attach(Behavior::RefuseHandshake).await;
    assert!(matches!(client, Err(IpcError::Refused(_))), "{:?}", client.err());
}
