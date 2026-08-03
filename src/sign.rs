use ed25519_dalek::{Signer, SigningKey};
use std::io::Read;

fn main() {
    let exe_path = std::env::args().nth(1).expect("Usage: sign <exe_path>");

    let root = format!("E:{}", std::path::MAIN_SEPARATOR);
    let key_path = std::path::PathBuf::from(root)
        .join("LRG").join("LRG Data Cloud").join("L.R.G")
        .join("Devoloping").join("Coding").join("Security keys")
        .join("RUST").join("LRGEX-sync").join("keys").join("signing.key");

    let priv_hex = std::fs::read_to_string(&key_path)
        .unwrap_or_else(|e| panic!("Cannot read signing key at {}: {}", key_path.display(), e));
    let priv_bytes = hex::decode(priv_hex.trim()).expect("Invalid key format");
    let mut secret = [0u8; 32];
    secret.copy_from_slice(&priv_bytes);
    let signing_key = SigningKey::from_bytes(&secret);

    let mut file = std::fs::File::open(&exe_path).expect("Cannot open exe");
    let mut data = Vec::new();
    file.read_to_end(&mut data).expect("Cannot read exe");

    let signature = signing_key.sign(&data);
    println!("{}", hex::encode(signature.to_bytes()));
}
