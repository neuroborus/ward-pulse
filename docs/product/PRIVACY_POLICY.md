# WardPulse Privacy Policy

Effective date: October 13, 2026

WardPulse is a local-first Android application. It does not operate application servers and
does not send analytics or usage telemetry to the WardPulse developer.

## Data Stored On The Phone

WardPulse stores each provider connection's credential in platform-secure storage under a
separate key. Saved credentials are not placed back into credential fields or displayed in
full. Android backup is disabled for the application so encrypted credentials are not restored
without the device-bound key that protects them.

Provider responses are processed locally on the phone, including by WardPulse's on-device Rust
core. Raw provider responses are not sent to a WardPulse service or to Wear OS.

WardPulse also stores each connection's last successfully normalized usage/spending snapshot
in private phone storage, so app restart or background polling can retain earlier data when a
provider is unavailable. These records keep the original successful-sync times and are shown
as stale after a failed refresh. They contain no credentials, prompts or raw provider responses.
Connection removal/replacement clears the obsolete snapshot before it can be reused. Account
identity digests and encrypted-storage key references are local lifecycle metadata and are not
sent to the developer or Wear OS.

Disconnect removes the selected encrypted credential and queues exact-key cleanup for any
retired or interrupted writes. If platform storage is unavailable, cleanup can be retried later;
retired references cannot reconnect the account. Cancelling a reconnect preserves an existing
valid connection. Existing installed credentials migrate locally, with a guarded backup retained
only for the matching migrated credential until refresh, replacement or removal.

## Provider Connections

Reporting requests go directly from the phone to the configured OpenAI, Anthropic, and Cursor
services. Provider sign-in flows open pages operated by the relevant provider.

Cursor dashboard sign-in uses an in-app WebView. That flow can also load third-party identity
and security resources, including Google, GitHub, Microsoft, WorkOS, Cloudflare, and reCAPTCHA,
when required by the sign-in page. WardPulse reads the Cursor session credential only from
`cursor.com`.

## Wear OS

WardPulse sends derived usage and spending summaries to a paired Wear OS device through the
Wear OS Data Layer. These summaries do not contain provider credentials, account identifiers,
authorization headers, prompts, or raw provider payloads.

Google Play services normally transfer this summary between the paired devices. When Bluetooth
is unavailable, Google Play services may relay the derived summary through Google-owned servers;
that cloud-routed transport is end-to-end encrypted.

## Independent Product

WardPulse is an independent usage monitor. It is not affiliated with, endorsed by, or sponsored by OpenAI, Anthropic, Cursor, Google, or any other provider. Product names are trademarks of their respective owners.
