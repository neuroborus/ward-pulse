# Security Model

WardPulse is local-first. The MVP must not introduce a custom cloud path for provider credentials or raw provider data.

## Credential Rules

- Credentials are entered on the phone only.
- Credentials are stored with platform-secure storage.
- Credentials are never displayed in full after save.
- Credentials are never sent to a WardPulse cloud service in the MVP.
- Wear OS surfaces receive dashboard summaries, not provider credentials.

## Logging Rules

Logs must not include:

- provider credentials;
- authorization headers;
- raw prompts;
- raw completions;
- sensitive raw provider payloads;
- full account identifiers when a masked form is enough.

Diagnostics export must redact sensitive data before writing files or sharing logs.

## Rust Core Rule

Rust may normalize raw provider response bodies, but it does not own credential storage, platform auth flows, background sync loops, or billing.
