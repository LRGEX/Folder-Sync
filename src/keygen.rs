//! Ed25519 keypair generator for update signing.
//! Run ONCE: cargo run --bin keygen
//! Writes signing.key (private) + signing.pub (public anchor).
//! REFUSES to overwrite EITHER file. Both must be deleted manually first.

use ed25519_dalek::{SigningKey, VerifyingKey};
use rand::RngCore;

fn main() {
    let root = format!("E:{}", std::path::MAIN_SEPARATOR);
    let key_dir = std::path::PathBuf::from(root)
        .join("LRG").join("LRG Data Cloud").join("L.R.G")
        .join("Devoloping").join("Coding").join("Security keys")
        .join("RUST").join("LRGEX-sync").join("keys");
    let _ = std::fs::create_dir_all(&key_dir);
    let key_path = key_dir.join("signing.key");
    let pub_path = std::path::PathBuf::from(".").join("signing.pub");

    if key_path.exists() {
        eprintln!("ERROR: signing.key already exists at {}", key_path.display());
        eprintln!("Refusing to overwrite. Delete BOTH signing.key and signing.pub to regenerate.");
        eprintln!("WARNING: new keypair strands all deployed clients!");
        std::process::exit(1);
    }
    if pub_path.exists() {
        eprintln!("ERROR: signing.pub already exists at {}", pub_path.display());
        eprintln!("Refusing to overwrite. Delete BOTH signing.key and signing.pub to regenerate.");
        eprintln!("WARNING: new keypair strands all deployed clients!");
        std::process::exit(1);
    }

    let mut secret = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut secret);
    let signing_key = SigningKey::from_bytes(&secret);
    let verifying_key: VerifyingKey = signing_key.verifying_key();

    let priv_hex = hex::encode(signing_key.to_bytes());
    std::fs::write(&key_path, &priv_hex).expect("Failed to write signing.key");

    let pub_hex = hex::encode(verifying_key.to_bytes());
    std::fs::write(&pub_path, &pub_hex).expect("Failed to write signing.pub");

    eprintln!("Generated:");
    eprintln!("  Private: {} (gitignored)", key_path.display());
    eprintln!("  Public:  signing.pub (committed to git)");
    eprintln!("  Pubkey:  {}", pub_hex);
}
