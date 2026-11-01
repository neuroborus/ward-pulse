# Dart Bindings

Hand-written Dart FFI wrapper for the narrow JSON interface exported by
`core/ward-pulse-ffi/`.

The package loads `libward_pulse_ffi.so`, converts the returned UTF-8 JSON to a Dart
string, and releases the Rust allocation. Domain models and calculations stay in Rust;
Flutter owns JSON decoding and UI-safe error handling.

## Threshold condition observations

The existing `ward_pulse_apply_alert_settings_result_json` export returns an optional
`alertConditions` array in `DashboardSnapshot`. It is omitted when empty; snapshots without
it decode as having no observations. Each record has `key` and `state`. The key contains
`provider`, `accountId`, the resolved `connection` storage key (including the legacy fallback),
and a typed `target`: `{ "kind": "allowance", "source": "plan", "id": "window-a" }` or
`{ "kind": "budget", "period": "today" }`. Allowance sources are `plan`/`purchased`; budget
periods are `today`/`week`/`month`. Labels and configured threshold values are not identity.

Rust emits `crossed`, `clear`, or `unknown` for enabled, present targets. A `crossed` record
carries its exact emitted `alert` (`severity` and `message`); `alerts` is derived from those
records. `clear` and `unknown` carry no alert. Disabled rules and missing accounts/windows
produce no observation, and neither absence nor unknown usage means clear. Local budgets,
Plan inheritance and explicit Off retain their existing eligibility rules. Dart only decodes
these evaluations; it must not infer them from messages, severity or percentages.

This additive contract uses the existing JSON-string ABI and does not change WatchSummary.
Phone-only lifecycle provenance stays outside shared JSON and is restored after the transform
by `applyUserAlertSettings` in the phone shell.

Build the Android libraries before running the phone app:

```sh
just build-android-rust
```
