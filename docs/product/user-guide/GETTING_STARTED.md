# Getting started

WardPulse shows AI plan capacity, purchased balances and API reporting on your Android phone.
The phone also sends a compact summary to a paired Wear OS watch and updates a home-screen widget.
You can use the phone without either optional surface.

## Before you start

This guide assumes WardPulse is already installed, or that you have a compatible build supplied
by the maintainer. If you also use a watch, use matching phone and Wear builds from the same
distribution. The WardPulse watch
face is a separate package and requires Wear OS 5 or later.

Have an account or reporting credential for at least one supported provider. Connect the
phone to the internet for sign-in and fresh reporting. Your credentials stay in secure phone
storage; you do not enter them on the watch. Read the [privacy policy](/product/privacy-policy)
for what is stored and sent between devices.

## Connect your first provider

1. Open WardPulse. A brief loading screen can appear while it reads data.
2. Open **Providers** in the bottom navigation. An empty Dashboard also offers **Open Providers**.
3. Choose the connection you need: a personal plan sign-in or organization/team reporting.
   Follow the corresponding [provider instructions](/guide/providers).
4. Return to **Dashboard**. Use **Refresh** at the top, or pull down on the list, if you need
   another reporting attempt.
5. Check the displayed balances and status. **Connected** describes the saved connection;
   it does not guarantee that the latest reporting request succeeded.

An unconnected production app does not create sample usage. A provider may also omit a meter
that your account does not expose. **Unknown** or **Balance unavailable** is different from
a real zero. If a refresh fails after an earlier success, WardPulse can retain that earlier
data and mark it stale. See [Dashboard](/guide/dashboard) and [Troubleshooting](/guide/troubleshooting).

## Find the controls you need

| Tab | What you do there |
| --- | --- |
| Dashboard | Read balances, reporting, history where available, and active alerts. |
| Watchface | Choose which known metrics fill the watch's ring slots. |
| Widget | Choose the phone home widget's independent metric list. |
| Providers | Connect accounts or keys, reconnect/remove them, and set alert thresholds or budget limits. |
| Settings | Set refresh cadence and Plan recovery notifications; read sync diagnostics and legal information. |

Next, [set up the watch](/guide/watch), [add a home widget](/guide/widget), or adjust
[sync and notifications](/guide/sync). WardPulse's local budget limits describe your chosen
reporting ceiling; they do not stop provider requests or change provider billing.

## Source notes

Phone sources are under `apps/phone_flutter/lib/`: navigation and first use in
`app` and `dashboard`, connection labels in `providers`, and Settings in `settings`.
See `ward_pulse_app.dart` (`DashboardHost`), `dashboard_screen.dart`
(`ConnectProviderPrompt`), `provider_connection.dart` (`providerConnectionCatalog`),
and `settings_screen.dart` (`SettingsScreen`). See privacy policy
[phone storage](/product/privacy-policy#data-stored-on-the-phone) and
[Wear OS transport](/product/privacy-policy#wear-os). In the watch-face package
`apps/watchface_wff/`, the main `AndroidManifest.xml` declares format version 2
(`com.google.wear.watchface.format.version`);
[Android's version table](https://developer.android.com/training/wearables/wff#versioning-wff)
maps that version to Wear OS 5.
