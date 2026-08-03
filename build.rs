fn main() {
    if cfg!(target_os = "windows") {
        let mut res = winres::WindowsResource::new();
        res.set_icon("assets/app-icon.ico");
        let _ = res.compile();
    }
    println!("cargo:rerun-if-changed=signing.pub");
}
