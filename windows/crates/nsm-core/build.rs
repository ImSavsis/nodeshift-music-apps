use std::env;
use std::fs;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-env-changed=NSM_APP_SECRET");
    println!("cargo:rerun-if-changed=build.rs");
    let secret = env::var("NSM_APP_SECRET").unwrap_or_default();
    let seed: u64 = 0x9E37_79B9_7F4A_7C15 ^ (secret.len() as u64).wrapping_mul(0x0100_0000_01B3);
    let mut state = seed;
    let masked: Vec<u8> = secret
        .bytes()
        .map(|byte| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            byte ^ ((state >> 24) as u8)
        })
        .collect();
    let out = PathBuf::from(env::var("OUT_DIR").unwrap()).join("app_secret.rs");
    fs::write(out, format!("const SEED: u64 = {seed};\nconst MASKED: [u8; {}] = {:?};\n", masked.len(), masked)).unwrap();
}
