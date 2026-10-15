mod common;

use std::collections::HashSet;
use std::sync::atomic::Ordering;
use std::time::Duration;

use common::{eventually, playing, quick, write_config, Behavior, DuplexConnector, FakeHub};
use nsm_core::bridge::{start, Bridge, BridgeStatus};
use nsm_core::model::now_ms;
use serde_json::Value;

struct Rig {
    bridge: Bridge,
    hub: FakeHub,
    connector: DuplexConnector,
    dir: tempfile::TempDir,
}

fn rig(behavior: Behavior) -> Rig {
    let dir = tempfile::tempdir().unwrap();
    let hub = FakeHub::new();
    let connector = DuplexConnector::new(behavior);
    let bridge = start(&tokio::runtime::Handle::current(), hub.clone(), connector.handle(), dir.path().to_path_buf(), quick());
    Rig { bridge, hub, connector, dir }
}

fn titles(rig: &Rig) -> Vec<String> {
    rig.connector.recorder.activities().iter().map(|activity| activity["details"].as_str().unwrap_or("").to_string()).collect()
}

#[tokio::test]
async fn playing_state_reaches_discord_with_an_age_based_start() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("First")));
    eventually("the first activity", || !rig.connector.recorder.activities().is_empty()).await;
    let activity = rig.connector.recorder.last().unwrap();
    assert_eq!(activity["details"], "First");
    assert_eq!(activity["type"], 2);
    let start = activity["timestamps"]["start"].as_i64().unwrap();
    let expected = (now_ms() - 2_500 - 10_000) / 1000;
    assert!((start - expected).abs() <= 3, "{start} vs {expected}");
    assert_eq!(activity["timestamps"]["end"].as_i64().unwrap(), start + 240);
    eventually("showing status", || rig.bridge.status() == BridgeStatus::Showing).await;
    rig.bridge.stop();
}

#[tokio::test]
async fn an_unchanged_version_is_not_sent_again() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("Same")));
    eventually("the first activity", || !rig.connector.recorder.activities().is_empty()).await;
    tokio::time::sleep(Duration::from_millis(900)).await;
    assert!(rig.hub.0.polls.load(Ordering::SeqCst) >= 3);
    assert_eq!(rig.connector.recorder.activities().len(), 1);
    assert_eq!(rig.connector.attempts.load(Ordering::SeqCst), 1);
    rig.bridge.stop();
}

#[tokio::test]
async fn bursts_collapse_to_the_latest_state() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("Track 0")));
    eventually("the first activity", || !rig.connector.recorder.activities().is_empty()).await;
    for index in 1..=6 {
        rig.hub.publish(Some(playing(&format!("Track {index}"))));
        tokio::time::sleep(Duration::from_millis(15)).await;
    }
    eventually("the last track", || titles(&rig).last().is_some_and(|title| title == "Track 6")).await;
    tokio::time::sleep(Duration::from_millis(400)).await;
    let seen = titles(&rig);
    assert!(seen.len() <= 4, "{seen:?}");
    assert_eq!(seen.last().unwrap(), "Track 6");
    rig.bridge.stop();
}

#[tokio::test]
async fn a_stop_clears_the_activity() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("Gone soon")));
    eventually("the activity", || !rig.connector.recorder.activities().is_empty()).await;
    rig.hub.publish(None);
    eventually("the clear", || rig.connector.recorder.last() == Some(Value::Null)).await;
    eventually("idle status", || rig.bridge.status() == BridgeStatus::Idle).await;
    rig.bridge.stop();
}

#[tokio::test]
async fn discord_started_late_still_gets_the_current_track() {
    let rig = rig(Behavior::Normal);
    rig.connector.failures_left.store(3, Ordering::SeqCst);
    rig.hub.publish(Some(playing("Waiting")));
    let mut seen = HashSet::new();
    eventually("the activity after retries", || {
        seen.insert(rig.bridge.status());
        !rig.connector.recorder.activities().is_empty()
    })
    .await;
    assert!(seen.contains(&BridgeStatus::WaitingForDiscord), "{seen:?}");
    assert!(rig.connector.attempts.load(Ordering::SeqCst) >= 4);
    assert_eq!(titles(&rig), vec!["Waiting".to_string()]);
    rig.bridge.stop();
}

#[tokio::test]
async fn a_restarted_discord_gets_the_activity_again() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("Survivor")));
    eventually("the first activity", || !rig.connector.recorder.activities().is_empty()).await;
    rig.connector.kill_servers();
    eventually("the activity on the new connection", || rig.connector.recorder.activities().len() >= 2).await;
    assert_eq!(rig.connector.attempts.load(Ordering::SeqCst), 2);
    assert_eq!(titles(&rig), vec!["Survivor".to_string(), "Survivor".to_string()]);
    rig.bridge.stop();
}

#[tokio::test]
async fn a_rejected_payload_is_retried_without_buttons_and_cover() {
    let rig = rig(Behavior::RejectFancy(4000));
    rig.hub.publish(Some(playing("Fancy")));
    eventually("two attempts", || rig.connector.recorder.activities().len() >= 2).await;
    let attempts = rig.connector.recorder.activities();
    assert!(attempts[0].get("buttons").is_some());
    assert!(attempts[1].get("buttons").is_none());
    assert!(attempts[1]["assets"].get("large_image").is_none());
    eventually("showing status", || rig.bridge.status() == BridgeStatus::Showing).await;
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(rig.connector.recorder.activities().len(), 2);
    rig.bridge.stop();
}

#[tokio::test]
async fn session_loss_is_reported_once() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("Before")));
    eventually("the activity", || !rig.connector.recorder.activities().is_empty()).await;
    rig.hub.drop_session();
    eventually("the notification", || rig.hub.lost_calls() == 1).await;
    eventually("login status", || rig.bridge.status() == BridgeStatus::NeedsLogin).await;
    eventually("the clear", || rig.connector.recorder.last() == Some(Value::Null)).await;
    tokio::time::sleep(Duration::from_millis(400)).await;
    assert_eq!(rig.hub.lost_calls(), 1);
    rig.bridge.stop();
}

#[tokio::test]
async fn the_switch_clears_and_restores_the_activity() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("Toggled")));
    eventually("the activity", || !rig.connector.recorder.activities().is_empty()).await;
    write_config(rig.dir.path(), r#"{"enabled": false}"#);
    rig.bridge.wake();
    eventually("the clear", || rig.connector.recorder.last() == Some(Value::Null)).await;
    eventually("disabled status", || rig.bridge.status() == BridgeStatus::Disabled).await;
    write_config(rig.dir.path(), r#"{"enabled": true}"#);
    rig.bridge.wake();
    eventually("the activity again", || rig.connector.recorder.last().is_some_and(|activity| activity["details"] == "Toggled")).await;
    rig.bridge.stop();
}

#[tokio::test]
async fn changing_the_application_id_reconnects() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("Moved")));
    eventually("the activity", || !rig.connector.recorder.activities().is_empty()).await;
    write_config(rig.dir.path(), r#"{"app_id": "4242", "name": "Other"}"#);
    rig.bridge.wake();
    eventually("a second handshake", || rig.connector.recorder.handshakes().len() >= 2).await;
    let handshakes = rig.connector.recorder.handshakes();
    assert_eq!(handshakes[1], "4242");
    eventually("the renamed activity", || rig.connector.recorder.last().is_some_and(|activity| activity["name"] == "Other")).await;
    rig.bridge.stop();
}

#[tokio::test]
async fn a_silent_hub_clears_the_activity_and_recovers() {
    let rig = rig(Behavior::Normal);
    rig.hub.publish(Some(playing("Lonely")));
    eventually("the activity", || !rig.connector.recorder.activities().is_empty()).await;
    rig.hub.set_down(true);
    eventually("the unreachable status", || rig.bridge.status() == BridgeStatus::HubUnreachable).await;
    eventually("the local clear", || rig.connector.recorder.last() == Some(Value::Null)).await;
    rig.hub.set_down(false);
    eventually("the activity after recovery", || rig.connector.recorder.last().is_some_and(|activity| activity["details"] == "Lonely")).await;
    eventually("showing status", || rig.bridge.status() == BridgeStatus::Showing).await;
    rig.bridge.stop();
}
