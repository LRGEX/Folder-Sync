use ed25519_dalek::{SigningKey, VerifyingKey};
use rand::RngCore;

fn main() {
    let mut secret = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut secret);
    let signing_key = SigningKey::from_bytes(&secret);
    let verifying_key: VerifyingKey = signing_key.verifying_key();

    let sep = std::path::MAIN_SEPARATOR;
    let user_profile = std::env::var("USERPROFILE").unwrap_or_default();
    let key_dir = format!("{}{}.lrgex", user_profile, sep);
    let _ = std::fs::create_dir_all(&key_dir);
    let key_path = format!("{}{}signing.key", key_dir, sep);

    let priv_hex = hex::encode(signing_key.to_bytes());
    std::fs::write(&key_path, &priv_hex).expect("Failed to write signing key");
    eprintln!("Private key saved to: {}", key_path);
    eprintln!("NEVER commit or upload this file!");

    let pub_hex = hex::encode(verifying_key.to_bytes());
    println!("PUBKEY:{}", pub_hex);
}
