use ed25519_dalek::{SigningKey, VerifyingKey};
use rand::RngCore;

fn main() {
    let mut secret = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut secret);
    let signing_key = SigningKey::from_bytes(&secret);
    let verifying_key: VerifyingKey = signing_key.verifying_key();

    let key_dir = std::path::PathBuf::from("E:")
        .join("LRG").join("LRG Data Cloud").join("L.R.G")
        .join("Devoloping").join("Coding").join("Security keys")
        .join("RUST").join("LRGEX-sync").join("keys");
    let _ = std::fs::create_dir_all(&key_dir);
    let key_path = key_dir.join("signing.key");

    let priv_hex = hex::encode(signing_key.to_bytes());
    std::fs::write(&key_path, &priv_hex).expect("Failed to write signing key");
    eprintln!("Private key saved to: {}", key_path.display());
    eprintln!("NEVER commit or upload this file!");

    let pub_hex = hex::encode(verifying_key.to_bytes());
    println!("PUBKEY:{}", pub_hex);
}
