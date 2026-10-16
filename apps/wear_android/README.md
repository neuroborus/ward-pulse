# WardPulse Wear OS App

Native Wear OS shell for compact WardPulse dashboard screens.

The app uses Kotlin, Compose for Wear OS Material 3, and Wear Data Layer. It validates the
versioned `WatchDashboardSummary` payload and persists only the latest successful summary.

## Ownership

- Home Glance text legend (`WEAR_GLANCE_DESIGN.md`): mini remaining arcs, OK/!OK refresh,
  Alerts pill.
- A second page listing plan windows and when each comes back (see **Plan windows** below).
- Alerts screen, reached from the Glance pill — the active list only, no rule editing.
- Watch face setup utility, reached after all Plan windows rows or below the no-summary sync
  prompt. It is a separate swipe-back route; the app still has two home pages.
- Local storage of the latest watch summary.
- Wear-specific navigation, rotary input, shape-aware layouts, and stale data states.
- Wear Data Layer receiver for `/wardpulse/watch-summary`.
- Wear → phone refresh request on `/wardpulse/refresh-request`.
- Ring + strip `RANGED_VALUE` complication data sources for the WardPulse watch face
  (family ColorRamp accents; credits only on the matching provider strip).

Provider credentials are never entered or stored on the watch.
The app shows a neutral sync prompt until the first valid phone summary arrives; it never creates
mock state on its own. Mock summaries are accepted only when explicitly marked by a debug phone
build, and release Wear builds reject them.
The app marks a summary stale when the phone reports stale data or its generation time is at
least two hours old, twice the longest planned MVP polling interval.

The phone and Wear APKs intentionally share the `app.wardpulse` application ID. Their
namespaces remain separate, and paired builds must use the same signing certificate for Data
Layer delivery.

## Plan windows

The Glance answers *how much is left*. The second page answers the other question — *when does
it come back* — and that is why it exists rather than repeating the Glance:

```text
  Plan windows

  Claude · 5-hour session      ← coloured by the window's own status
  0% left · back at 19:00

  Claude · Weekly Opus
  6% left · back Aug 25, 12:00

  Cursor · Cursor Models
  100% left · back Sep 1, 00:00

  Codex · Weekly plan          ← no reset in this payload: the line just ends
  9% left
```

Rules:

- **Every plan window, spent or not.** Glance retains selected known exhausted metrics; this
  page adds reset times and the full window inventory. Untouched ones stay too — the list is
  also the inventory of what the watch knows, and hiding them would change its shape from poll
  to poll, leaving "not spent" indistinguishable from "not reported".
- **Purchased meters never appear** (`source: purchased` — Extra usage, on-demand, purchased
  credits). They do not come back; they are bought again. Cursor's on-demand pool does carry an
  instant, but it is the billing cycle turning over, not capacity returning — the page would be
  promising something it cannot deliver. Their home is the phone's cards.
- **Order: exhausted first, then soonest return.** The screen is read when something has run
  out, so what is waited on comes first. A window that cannot name a **future** moment — none
  published, or one already behind — cannot compete for "soonest", so it sorts last inside its
  own group; still listed, just after everything that can name a time.
- **No future moment, no time on the line** — the line simply ends after the percentage, and
  never says "unknown": a provider that publishes no reset is not the same as one publishing an
  unknown. A reset already behind counts as none, because the provider has not caught up with
  its own clock (Cursor aggregates about hourly), and printing a moment that has passed would
  say the window is late rather than that the number is.
- **A window with no share shows its remainder** (`1.7K credits left`, compact as everywhere
  else on the watch — `WEAR_GLANCE_DESIGN.md`, revision 2026-10-11) — a plan whose ceiling
  the provider does not publish, Cursor's among them, still knows how much is left, and a
  remainder at zero counts as exhausted like any full percentage.
- **An unlimited window says so** (`Unlimited`), and one that can say neither a share nor a
  moment reads `Unavailable` — the word the rest of the watch already uses for a meter that
  reported nothing. A blank line under a label would read as a rendering fault, not as silence.
- Time is the device's own clock, and "inside a day" means **today's date**, not the next
  twenty-four hours: `back at HH:MM` for a window rolling today, `back MMM d, HH:mm` for any
  other, so tomorrow evening never reads like tonight.

## Watch face setup

Scroll past the complete Plan windows list and tap **Watch face**. Before the first phone
summary, the same entry appears below **Sync from phone**. Summary arrival, replacement or
loss does not reset this route or a pending permission result.

On supported Wear OS 6+ devices, the bundled Push face can be installed with the Wear app.
If it is missing and a slot is free, **Install watch face** installs it without activating
it. An unknown occupied slot is left untouched; **Check again** only refreshes status after
capacity becomes available. A failed status check has the same read-only recovery action.

**Use watch face** is a separate explicit action. It may request activation permission once;
permission and activation-attempt history is committed before those effects and retained
across recreation. Denial, dismissal or an unavailable/consumed activation opportunity leads
to manual-picker guidance. The app never reactivates a face after the user chooses another.
Only a fresh platform observation can report **In use**.

**Update watch face** appears when the actual bundled version is newer than the installed
Push face. It updates only that package, preserving configuration and face selection. Even
an **In use** face can offer an update. Installation/update completion reports **Installed**;
it does not check current activity immediately after an update. **Try again** repeats only
the failed installation or update. Busy actions are disabled.

Wear OS 5 and other WFF 2 devices without Push receive separate-install/manual-selection
guidance. On Wear OS 4 / API 33 the dashboard remains usable, but the face requires Wear OS 5
or later. The legacy `app.wardpulse.watchface` package and its settings remain separate.

Local development acceptance on **2026-10-16** covers final debug artifacts, API33/API34/API36
emulators, real summary delivery, explicit consent and N1-to-N2 customization/selection
retention. See the [acceptance record](../../docs/product/RELEASE_CHECKLIST.md#watch-face-push-acceptance)
for exact evidence, observed system/scroll limitations and remaining production signing,
Play, API35 and hardware gates. The
[dated baseline](../../docs/product/WEAR_GLANCE_DESIGN.md#revision-2026-10-16--watch-face-utility-entry)
and [indexed manual-selection capture](../../docs/assets/README.md#watch-face-utility-provenance-and-wear-freshness-2026-10-16)
are integrated; existing screenshot bytes and Glance geometry are preserved.

The durable-consent device tests in `WatchFaceConsentStoreTest`, included in
`just test-wear-device`, verify synchronous on-disk history. The retained-navigation UI
tests use synthetic summary availability; the controller tests use injected effects.
Actual platform consent/data observations are recorded separately in the acceptance record.

## Commands

From the repository root:

```sh
just check-wear
just build-wear
just test-wear-device
just run-wear
```

`test-wear-device` and `run-wear` require one active Wear AVD. Canonical AVD names and setup
commands live in
[`docs/ANDROID_TOOLCHAIN.md`](https://github.com/neuroborus/ward-pulse/blob/main/docs/ANDROID_TOOLCHAIN.md).
