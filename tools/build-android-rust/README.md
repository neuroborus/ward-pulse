# Android Rust Build Tools

Builds `ward-pulse-ffi` for the phone MVP's supported Android ABIs and places the
libraries in Flutter's generated `jniLibs` directory.

Pinned prerequisites:

- Android NDK `29.0.14206865`;
- `cargo-ndk 4.1.2`;
- Rust targets `aarch64-linux-android` and `x86_64-linux-android`.

Install the Rust tooling once:

```sh
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
```

Build from the repository root:

```sh
just build-android-rust
```

The generated `.so` files are local build outputs and are not committed.
