//! Ed25519 keypair generator for update signing.
//! Run once: `cargo run --bin keygen`
//! Generates a keypair, saves the PRIVATE key locally (never commit/upload),
//! and prints the PUBLIC key to paste into update.rs.

use ed25519_dalek::{SigningKey, VerifyingKey};
use rand::RngCore;

fn main() {
    // Generate random 32-byte secret
    let mut secret = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut secret);
    let signing_key = SigningKey::from_bytes(&secret);
    let verifying_key: VerifyingKey = signing_key.verifying_key();

    // Save private key to secure location (E: drive, cloud-synced, gitignored)
    let root = format!("E:{}", std::path::MAIN_SEPARATOR);
    let key_dir = std::path::PathBuf::from(root)
        .join("LRG").join("LRG Data Cloud").join("L.R.G")
        .join("Devoloping").join("Coding").join("Security keys")
        .join("RUST").join("LRGEX-sync").join("keys");
    let _ = std::fs::create_dir_all(&key_dir);
    let key_path = key_dir.join("signing.key");

    let priv_hex = hex::encode(signing_key.to_bytes());
    std::fs::write(&key_path, &priv_hex).expect("Failed to write signing key");
    eprintln!("Private key saved to: {}", key_path.display());
    eprintln!("NEVER commit or upload this file!");

    // Print public key for embedding in update.rs
    let pub_hex = hex::encode(verifying_key.to_bytes());
    println!("PUBKEY:{}", pub_hex);
}
