# Getting started

WardPulse shows AI plan capacity, purchased balances and API reporting on your Android phone.
The phone also sends a compact summary to a paired Wear OS watch and updates a home-screen widget.
You can use the phone without either optional surface.

## Before you start

The WardPulse watch face is a separate package and requires **Wear OS 5 or later**.

Have an account or reporting credential for at least one supported provider. Connect the
phone to the internet for sign-in and fresh reporting. WardPulse stores credentials encrypted
on the phone and uses them directly with their provider; you do not enter them on the watch.
Read the [privacy policy](/product/privacy-policy) for what is stored and sent between devices.

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

![Providers connection choices in the light theme.](/screenshots/phone-providers-light.png)

![Providers connection choices in the dark theme.](/screenshots/phone-providers-dark.png)

Plan sign-in and reporting have separate rows under **Providers**. Reporting uses an OpenAI
organization Admin key, an Anthropic key with organization reporting rights, or a Cursor
key with team reporting access.

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
| Settings | Set refresh cadence and Plan recovery notifications; read sync information and legal information. |

Next, [set up the watch](/guide/watch), [add a home widget](/guide/widget), or adjust
[sync and notifications](/guide/sync). WardPulse's budget limits help you track spending;
they do not stop provider requests or change provider billing.
