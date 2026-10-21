# WardPulse Privacy Policy

Effective date: October 13, 2026

WardPulse is a local-first Android application. It does not operate application servers
and does not send analytics or usage telemetry to the WardPulse developer.

## Data Stored On The Phone

WardPulse stores your API keys and sign-in credentials encrypted in secure phone storage.
It uses them to authenticate requests directly to the matching provider. Saved credentials
are not shown back in full.
Android backup is disabled for WardPulse's app data, so a new installation or device needs
provider connections to be set up again.

Usage reports are processed on the phone. Full provider reports are not sent to a WardPulse
server or to the watch. WardPulse also keeps each connection's last successful usage and
spending data so earlier values can remain available after a failed refresh or app restart.
They keep their original successful-update times and are marked stale after a failed refresh.
Those stored records contain no credentials, prompts or full provider reports.

Removing or replacing a connection prevents its obsolete stored data from being reused.
Disconnect removes the selected local credential; if secure storage is temporarily
unavailable, remaining cleanup can be retried later without reconnecting the removed account.
Cancelling a replacement sign-in preserves an existing valid connection. Clearing Android
app storage removes local credentials, stored data and preferences.

## Provider Connections

Reporting requests go directly from the phone to the configured OpenAI, Anthropic or Cursor
service. Provider sign-in opens pages operated by that provider.

Depending on your chosen sign-in method, the provider may also use other sign-in and
security services.

## Wear OS

The paired watch receives compact usage and spending summaries. These do not include API
keys, sign-in credentials, information identifying your account, prompts or full provider reports.

Google Play services normally transfers summaries between the paired devices. If Bluetooth
is unavailable, it may relay them through Google-owned servers; that relayed transport is
end-to-end encrypted. This is separate from provider credentials, which are not sent to the
watch or a WardPulse server.

## Independent Product

WardPulse is an independent usage monitor. It is not affiliated with, endorsed by or sponsored
by OpenAI, Anthropic, Cursor, Google or any other provider. Product names are trademarks of
their respective owners.
