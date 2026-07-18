# Dart Bindings

Hand-written Dart FFI wrapper for the narrow JSON interface exported by
`core/ward-pulse-ffi/`.

The package loads `libward_pulse_ffi.so`, converts the returned UTF-8 JSON to a Dart
string, and releases the Rust allocation. Domain models and calculations stay in Rust;
Flutter owns JSON decoding and UI-safe error handling.

Build the Android libraries before running the phone app:

```sh
just build-android-rust
```
