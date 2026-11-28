# Getting started

WardPulse shows AI plan capacity, purchased balances and API reporting on your Android phone.
The phone also sends a compact summary to a paired Wear OS watch and updates a home-screen widget.
You can use the phone without either optional surface.

## Before you start

The WardPulse watch face is a separate package and requires **Wear OS 5 or later**.

For direct APK downloads, choose `WardPulse-V-Android.apk` for your phone and
`WardPulse-V-WearOS.apk` for the watch app; V is the release version. The optional face uses
`WardPulse-V-WatchFace-WearOS5Plus.apk`. See [watch setup](/guide/watch#select-and-customize-the-face).

To monitor your own usage, have an account or reporting credential for at least one supported
provider. Connect the phone to the internet for sign-in and fresh reporting. WardPulse stores
credentials encrypted on the phone and uses them directly with their provider; you do not enter
them on the watch.
Read the [privacy policy](/product/privacy-policy) for what is stored and sent between devices.

## Explore with Demo mode

You can explore WardPulse before connecting a provider account.

1. Open **Settings** and turn on **Demo mode** in the **Demo** section. It starts off.
2. Open **Dashboard**. **Demo data** at the top marks the sample readings. Use **Refresh**, or
   pull down on the list, for a new sample.
3. Choose metrics on **Widget**, then [add the home widget](/guide/widget). It shows the
   same sample.
4. For the watch, pair it with your phone, install the WardPulse watch app and open it from
   the watch's app launcher. Glance shows **Demo data**. To use the face, install it, then
   touch and hold your current face and choose WardPulse. Follow
   [Demo mode on the watch](/guide/watch#demo-mode-on-the-watch) for details.

The sample is generated on the phone; it is not your usage. While Demo mode is on, WardPulse
does not refresh provider data or post alert or plan recovery notifications, and the sample
shows no alerts. Your connections, alert rules, budget limits and saved history stay as they
are, and you can still edit them on **Providers**. Claude plan readings stay paused, as in
the rest of the public app.

Turn **Demo mode** off to return to your providers' readings, or to the empty Dashboard if no
provider is connected. WardPulse then updates the widget and watch the same way.

## Connect your first provider

1. Open WardPulse. A brief loading screen can appear while it reads data.
2. Open **Providers** in the bottom navigation. An empty Dashboard also offers **Open Providers**.
3. Sign in on a plan row, or enter a key with the required access on the separate reporting
   row and tap **Save**. Follow the corresponding [provider instructions](/guide/providers).
4. For a reporting key, check the result beside its row. **Checking…** means a report request
   is running. **Connected** appears after reporting succeeds; a saved key alone does not
   confirm access.
5. Return to **Dashboard** to read balances and status. Use **Refresh** at the top, or pull
   down on the list, if you need another reporting attempt.

Plan sign-in and reporting have separate rows under **Providers**. Reporting uses an OpenAI
organization Admin key, a qualifying non-workspace-scoped Anthropic key with organization
reporting rights, or a Cursor Team key with reporting access. A personal plan alone does
not grant organization/team reporting access.

[Claude plan sign-in and monitoring](/guide/providers-anthropic#claude-plan) are temporarily
unavailable in the public app. Anthropic **Organization reporting** is available with a
qualifying Claude Console key.

Until a connected provider reports successfully, WardPulse has no usage data to show. A
provider may also omit a meter that your account does not expose. **Unknown** or **Balance
unavailable** is different from a real zero. If a refresh fails after an earlier success,
WardPulse can retain that earlier data and mark it stale. See [Dashboard](/guide/dashboard)
and [Troubleshooting](/guide/troubleshooting).

## Find the controls you need

| Tab | What you do there |
| --- | --- |
| Dashboard | Read balances, reporting, history where available, and active alerts. |
| Watchface | Choose which known metrics fill the watch's ring slots. |
| Widget | Choose the phone home widget's independent metric list. |
| Providers | Connect accounts or keys, reconnect/remove them, and set alert thresholds or budget limits. |
| Settings | Set refresh and notification preferences, turn Demo mode on or off, check sync, or open the Privacy Policy. |

Next, [set up the watch](/guide/watch), [add a home widget](/guide/widget), or adjust
[sync and notifications](/guide/sync). WardPulse's budget limits help you track spending;
they do not stop provider requests or change provider billing.
