# Security Model

WardPulse is local-first. The MVP must not introduce a custom cloud path for provider credentials or raw provider data.

## Credential Rules

- Credentials are entered on the phone only.
- Credentials are stored with platform-secure storage.
- Saved credentials are never displayed in full. Credential entry may reveal only the current unsaved value after an explicit user action.
- Credentials are never sent to a WardPulse cloud service in the MVP.
- Wear OS surfaces receive dashboard summaries, not provider credentials.
- Android encrypted credential data is excluded from backup because its key is device-bound.

## Phone-to-Watch Sync

- The Data Layer payload follows `schemas/watch_dashboard_summary.schema.json` and contains only
  derived budget, provider-status, alert, and freshness fields.
- Account identifiers, credentials, authorization headers, prompts, and raw provider
  payloads are excluded from the watch contract.
- Google Play services restricts Data Layer data to paired apps with matching application
  IDs and signing certificates.
- Data Layer may route the derived summary through Google-owned servers when Bluetooth is
  unavailable; that cloud-routed transport is end-to-end encrypted.
- The Wear app validates the schema version and required value shapes before replacing its
  locally saved summary. Invalid payloads leave the previous summary intact.

## Logging Rules

Logs must not include:

- provider credentials;
- authorization headers;
- raw prompts;
- raw completions;
- sensitive raw provider payloads;
- full account identifiers when a masked form is enough.

Diagnostics export must redact sensitive data before writing files or sharing logs.
Phone-to-watch logs record outcomes only and never include the serialized summary.

## Rust Core Rule

Rust may normalize raw provider response bodies, but it does not own credential storage, platform auth flows, background sync loops, or billing.
