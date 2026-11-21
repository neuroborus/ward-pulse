# Connection and local profile

Use this reference when identifying/reconnecting physical devices or loading the local
profile. USB debugging authorization and wireless pairing are owner/device actions;
existing authorization does not need to be requested again for routine scoped work.

## Transport and identity

Discover transports with `adb devices -l`. Before device mutations, compare the selected
target's `ro.product.model`, stable `ro.serialno` or `ro.boot.serialno`, and
`ro.build.version.sdk` against its expected profile. Record which hardware-ID property
is used. Reject a model-only match, an emulator transport or an unexpected identity.
Use `adb -s <verified-serial>` for every target operation, including property reads,
UI inspection, input, package checks and installs. An offline/unauthorized entry is not
a usable device; do not silently switch to another connected target.

For a previously paired wireless device, try its known connection endpoint, then inspect
`adb mdns services` for that same device before asking the owner for a new port. Verify
identity after connecting; an IP or discovered name alone is not sufficient. A static
DHCP address does not keep the connection port fixed. The main **Wireless debugging →
IP address & port** value is the connection endpoint; **Pair device with pairing code**
uses a different, ephemeral pairing port. Pairing codes must not be saved in the profile.

Use the existing paired connection where possible. Do not loop through guessed ports,
re-pair blindly, disconnect unrelated devices or run `adb kill-server` as routine recovery.
Ask for the current main-screen endpoint only when discovery cannot resolve it; ask for
fresh pairing only if the actual pairing state requires it. USB and mDNS aliases may both
refer to the same hardware; do not treat them as two test devices.

## Private profile

The skill-local `.env` is optional local operator data, not a shell script or an access
grant. Its only fields are those documented in [../.env.example](../.env.example).
Use an existing nonexecuting parser or a bounded operational read; do not add a parser
helper. Allowlist keys, split literal `KEY=value` data, preserve PIN leading zeroes, and
do not expand variables, interpret escapes or evaluate shell syntax. Comments occupy
their own lines; values are unquoted literal text, with internal spaces preserved.
Never use shell `source`, `.`, `eval`, `xtrace`, or commands that display the file.

Before creating or updating the real file, prove it is ignored with `git check-ignore`.
Create it with mode 600 before writing real values. Keep the example empty. Store an
unlock secret only if the owner explicitly requested that storage; its presence does not
create unlock permission.
Keep it in memory for the authorized operation and out of tool command text, logs,
screenshots, proof artifacts and delegated-agent context. Never forward the real profile.

Blank unlock fields mean no stored unlock method. Blank identity fields are not wildcard
matches: establish the device through existing owner-confirmed evidence before mutation.
Refresh a changed endpoint only after verifying the same physical identity. Sanitized
working notes may retain nonsecret connection information; unlock material belongs only
in the ignored mode-600 profile when explicitly requested.
