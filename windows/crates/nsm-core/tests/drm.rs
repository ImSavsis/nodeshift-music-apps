use std::path::PathBuf;

use base64::Engine;
use nsm_core::drm::{decrypt_range, Exchange, Header, WireItem, WireLicense, HEADER_SIZE, KIND_LOSSY};
use serde_json::Value;
use sha2::{Digest, Sha256};

fn vector(name: &str) -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../shared/testdata").join(name);
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

fn locked_sample() -> (Vec<u8>, [u8; 32], Value) {
    let sample = vector("nlac.json");
    let locked = base64::engine::general_purpose::STANDARD.decode(sample["locked_b64"].as_str().unwrap()).unwrap();
    let key: [u8; 32] = hex::decode(sample["key_hex"].as_str().unwrap()).unwrap().try_into().unwrap();
    (locked, key, sample)
}

fn read(locked: &[u8], key: &[u8; 32], header: &Header, start: u64, end: u64) -> Vec<u8> {
    let span = header.span(start, end);
    let blob = &locked[span.offset as usize..(span.offset + span.length) as usize];
    decrypt_range(key, header, span, blob, start, end).unwrap()
}

#[test]
fn header_matches_the_shared_vector() {
    let (locked, _, sample) = locked_sample();
    let header = Header::parse(&locked[..HEADER_SIZE]).unwrap();
    assert_eq!(header.codec, sample["codec"].as_str().unwrap());
    assert_eq!(header.plain_length, sample["plain_length"].as_u64().unwrap());
    assert_eq!(header.chunk_size as u64, sample["chunk_size"].as_u64().unwrap());
    assert_eq!(header.key_id as u64, sample["key_id"].as_u64().unwrap());
    assert_eq!(header.kind as u64, sample["kind"].as_u64().unwrap());
    assert_eq!(header.mime(), "audio/flac");
}

#[test]
fn ranges_decrypt_to_the_expected_bytes() {
    let (locked, key, sample) = locked_sample();
    let header = Header::parse(&locked[..HEADER_SIZE]).unwrap();
    let ranges = sample["ranges"].as_array().unwrap();
    let hashes = sample["range_sha256"].as_array().unwrap();
    for (range, expected) in ranges.iter().zip(hashes) {
        let (start, end) = (range[0].as_u64().unwrap(), range[1].as_u64().unwrap());
        let plain = read(&locked, &key, &header, start, end);
        assert_eq!(plain.len() as u64, end - start + 1);
        assert_eq!(hex::encode(Sha256::digest(&plain)), expected.as_str().unwrap());
    }
}

#[test]
fn a_flipped_byte_or_wrong_key_is_rejected() {
    let (mut locked, key, _) = locked_sample();
    let header = Header::parse(&locked[..HEADER_SIZE]).unwrap();
    let span = header.span(0, 99);
    let blob = locked[span.offset as usize..(span.offset + span.length) as usize].to_vec();
    assert!(decrypt_range(&[9u8; 32], &header, span, &blob, 0, 99).is_err());
    locked[HEADER_SIZE + 10] ^= 1;
    let tampered = locked[span.offset as usize..(span.offset + span.length) as usize].to_vec();
    assert!(decrypt_range(&key, &header, span, &tampered, 0, 99).is_err());
}

#[test]
fn foreign_files_are_not_locked_audio() {
    assert!(Header::parse(b"fLaC").is_err());
    assert!(Header::parse(&[0u8; 64]).is_err());
}

#[test]
fn license_vector_unwraps_to_the_content_key() {
    let sample = vector("license.json");
    let exchange = Exchange::from_bytes(&hex::decode(sample["client_private_hex"].as_str().unwrap()).unwrap()).unwrap();
    assert_eq!(base64::engine::general_purpose::STANDARD.encode(exchange.public_bytes()), sample["client_pub_b64"].as_str().unwrap());
    let license = WireLicense {
        server_pub: sample["server_pub_b64"].as_str().unwrap().to_string(),
        expires_at: sample["expires_at"].as_u64().unwrap(),
        items: vec![WireItem {
            track_id: sample["track_id"].as_u64().unwrap() as u32,
            kind: "lossy".into(),
            key_id: sample["key_id"].as_u64().unwrap() as u32,
            name: "x.np3".into(),
            codec: "mp3".into(),
            plain_length: 1,
            nonce: sample["nonce_b64"].as_str().unwrap().to_string(),
            wrapped: sample["wrapped_b64"].as_str().unwrap().to_string(),
        }],
    };
    let grants = exchange.open(&license).unwrap();
    assert_eq!(grants[0].key_hex, sample["content_key_hex"].as_str().unwrap());
    assert_eq!(grants[0].kind, KIND_LOSSY);
}

#[test]
fn a_license_for_another_track_does_not_open() {
    let sample = vector("license.json");
    let exchange = Exchange::from_bytes(&hex::decode(sample["client_private_hex"].as_str().unwrap()).unwrap()).unwrap();
    let license = WireLicense {
        server_pub: sample["server_pub_b64"].as_str().unwrap().to_string(),
        expires_at: sample["expires_at"].as_u64().unwrap(),
        items: vec![WireItem {
            track_id: 43,
            kind: "lossy".into(),
            key_id: sample["key_id"].as_u64().unwrap() as u32,
            name: "x.np3".into(),
            codec: "mp3".into(),
            plain_length: 1,
            nonce: sample["nonce_b64"].as_str().unwrap().to_string(),
            wrapped: sample["wrapped_b64"].as_str().unwrap().to_string(),
        }],
    };
    assert!(exchange.open(&license).is_err());
}

#[test]
fn a_fresh_exchange_has_an_uncompressed_public_key() {
    let exchange = Exchange::random();
    let bytes = exchange.public_bytes();
    assert_eq!(bytes.len(), 65);
    assert_eq!(bytes[0], 4);
}

#[test]
fn app_proof_matches_the_server_vector() {
    let sample = vector("trust.json");
    let secret = hex::decode(sample["secret_hex"].as_str().unwrap()).unwrap();
    let proof = nsm_core::drm::proof_with(&secret, sample["stamp"].as_u64().unwrap(), sample["subject"].as_str().unwrap()).unwrap();
    assert_eq!(proof, sample["proof"].as_str().unwrap());
}

#[test]
fn device_identity_and_signatures_match_the_server_format() {
    use p256::ecdsa::signature::Verifier;
    use p256::ecdsa::{Signature, VerifyingKey};
    let sample = vector("trust.json");
    let device = nsm_core::drm::Device::from_bytes(&hex::decode(sample["device_private_hex"].as_str().unwrap()).unwrap()).unwrap();
    assert_eq!(device.public_b64(), sample["device_public_b64"].as_str().unwrap());
    assert_eq!(device.id(), sample["device_id"].as_str().unwrap());

    let stamp = sample["stamp"].as_u64().unwrap();
    let subject = sample["subject"].as_str().unwrap();
    let key = VerifyingKey::from_sec1_bytes(&device.public_bytes()).unwrap();
    let message = format!("NSM-DEV|{}|{stamp}|{subject}", device.id());

    let ours = device.sign(stamp, subject);
    let parts: Vec<&str> = ours.split('.').collect();
    assert_eq!(parts[0], device.id());
    assert_eq!(parts[1], stamp.to_string());
    let raw = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(parts[2]).unwrap();
    assert_eq!(raw.len(), 64);
    assert!(key.verify(message.as_bytes(), &Signature::from_slice(&raw).unwrap()).is_ok());

    let theirs = sample["device_header"].as_str().unwrap().split('.').nth(2).unwrap().to_string();
    let raw = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(theirs).unwrap();
    assert!(key.verify(message.as_bytes(), &Signature::from_slice(&raw).unwrap()).is_ok());
    assert!(key.verify(b"other", &Signature::from_slice(&raw).unwrap()).is_err());
}
