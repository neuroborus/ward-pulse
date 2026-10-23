# Finalization checks

Read completely through [finalization](../SKILL.md) before choosing applicable gates.

## 4. Tests And Checks

Apply [test-authoring](../../test-authoring/SKILL.md) when authoring or changing tests and during
finalization review: verify necessity, determinism and measured cost. Every required gate
below remains mandatory.

Most of this section reaches for the network or a device, so an isolated agent cannot finish it
alone. That does not excuse a box: name every check you could not run and hand it to the
operator, never tick one you did not execute. `AGENTS.md`, *When a check cannot run where you
are*, lists which is which.

- [ ] If Rust code changed, run:

```bash
cd core && cargo fmt --all -- --check
cd core && cargo clippy --workspace --all-targets -- -D warnings
cd core && RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --document-private-items
cd core && cargo test --workspace
```

- [ ] If Flutter code changed and the project is generated, run:

```bash
just check-phone
```

  This runs `dart format --set-exit-if-changed` over `apps/phone_flutter` and `bindings/dart`,
  then `flutter analyze` and `flutter test`. Use `just fmt-phone` to apply formatting.

- [ ] If Android/Wear/WFF Gradle projects are generated, run the relevant Gradle test/build task.
- [ ] If schemas or fixtures changed, run `just validate-fixtures`: it parses every file and checks each golden fixture against its schema.
- [ ] If GitHub Actions workflows changed, run `actionlint .github/workflows/*.yml`.
- [ ] If a local skill changed, run the `quick_validate.py` command from `AGENTS.md` for each affected skill directory.
- [ ] If build or validation artifact downloads, pins or caches changed, or a CI failure suggests a warm cache is hiding a download failure, run the affected existing check on a network-capable host with a new, empty, task-owned cache. Verify the actual download, checksum and tool completion, then repeat once with that cache to prove reuse. Do not delete or seed shared caches, copy the repository, or add a test framework for this check. Record the command, cache location and outcomes; a warm-cache pass alone does not prove the download works.
- [ ] If durable docs, Vocs pages, component READMEs, or site navigation changed, run:

```bash
just check-docs
```

- [ ] For a CI repair, after an already-authorized push, verify that the workflows expected for that event and the affected paths all completed successfully on the exact pushed commit. Pending, failed or canceled runs, and successful runs on an older commit, do not establish success. This is post-push acceptance, not a local precommit gate or permission to push.

## 5. Emulator Check

Automated gates do not exercise the app. Unit tests use fakes, so they never load
`libward_pulse_ffi.so`, never resolve an exported symbol, and never render a screen.

Run the app on an emulator when the change could only fail there:

- [ ] FFI surface changed — exported symbol names, argument or return shapes, or the
      Dart binding. Symbols resolve at **run time**, so a mismatch survives every build.
- [ ] The serialized snapshot contract changed — a new or renamed field, or a different
      value shape. Host-side round trips do not prove the Android build agrees.
- [ ] UI, widget, watch face, or phone-to-watch payload behaviour changed.
- [ ] Background scheduling, secure storage, or WebView sign-in changed.

Skip it, and say so, for changes that cannot reach a device: pure refactors behind an
unchanged contract, comments and docs, tests, CI wiring, lockfiles.

```bash
adb devices -l                     # phone and Wear AVDs are usually already running
tools/build-android-rust/build.sh  # Rust .so for Android ABIs — slow
cd apps/phone_flutter && flutter build apk --debug
adb -s <serial> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <serial> shell am start -n app.wardpulse/.MainActivity
adb -s <serial> logcat -d | grep -i wardpulse
```

Report what was exercised on device and what was not. "Tests pass" is not evidence that
the app runs; only the device is.
