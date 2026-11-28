# Wear OS store gallery

Sample usage data is shown throughout, without the paused Claude plan. The captures use the
fixed dark appearance of the Wear app and watch face. All four screenshots are native 384 × 384
RGB PNGs captured on 2026-11-28 (Europe/Paris) on the canonical round Wear emulator paired with
the canonical phone emulator: Glance and Plan windows at 20:41–20:42, both faces at 21:48–21:49
after the upper cells were set. Glance, Plan windows and the three-band face come from one stored
summary. The two-band face uses the phone's later payload, which differs only in the deselected
Anthropic band. The captures agree on these readings, where shown:

- Anthropic organization spend this week, 53% of the local cap left (USD 1.24 of USD 2.62);
- Codex plan weekly window, 54% left, with 1.2K purchased credits;
- Cursor plan, 98% left on Cursor Models and 80% left on Other Models.

| Repository order | File | Content |
| --- | --- | --- |
| 0 | [Promotional cover](0-cover.png) | 1254 × 1254 RGB art. An illustrated, unbranded watch shows the three-band face, a second watch shows Glance, and a phone behind them shows the Codex Dashboard. |
| 1 | [Watch face with three bands](1-watch-face-three-bands.png) | Upper cells Sat, 0 and 100. Orange Anthropic weekly spend ring with 7D marks, green Codex weekly ring and the outer Cursor pair. The legend reads `$1.24/3`, `54% · 1.2K` and `98% · 80%`. |
| 2 | [Glance](2-glance.png) | Green OK, Anthropic platform · Week 53% left, Codex plan · Weekly 54% left · 1.2K credits, Cursor / Others 98% · 80% left and Alerts: 0. |
| 3 | [Plan windows](3-plan-windows.png) | Plan windows title with the first card: Cursor · Cursor Models, 98% left, back Dec 1, 01:00. |
| 4 | [Watch face with two bands](4-watch-face-two-bands.png) | Upper cells Sat, 0 and 100. Widened green Codex ring and the outer Cursor pair. The legend reads `54% · 1.2K` and `98% · 80%`. |

Use slots 2 and 3 in the Google Play Wear OS app listing. Use slots 1 and 4 in the separate
watch face listing. Slot 0 is promotional art. Google Play requires unframed screenshots of
the app or watch face in each listing.

## Capture notes

The phone ran a debug build of WardPulse 0.1.0 with **Debug → Mock data** and the documentation
sample. The watch face rings were set on the Watchface tab. Mock data still includes the paused
Claude plan. Before capture, the summary the phone had sent was written back to the debug Wear
app without the Claude plan windows, with the data mode set to live. The Glance therefore shows
no Mock data label. All other values are the phone's own. The two-band summary is the phone's
payload after Anthropic Week was deselected.

The face's upper cells are wearer-chosen complications. By default they show the day, the
temperature and the UV index. The emulator had no weather data, so the default temperature and UV
cells were replaced in the system face editor with Wear OS **Step count** and **Battery**. They
read 0 and 100 beside the default day cell, Sat. Sunrise and sunset was tried first and showed
`--` without a location. After capture, the cells were returned to their default setting. The
written-back summary and these substituted cells both depart from the
[capture-state reference](../../../.agents/skills/user-docs/references/capture-state.md#privacy-and-relevant-ui-state),
and the owner accepted both departures on 2026-11-28. The charging indicator and the unread
notification dot were hidden through system settings during capture and restored
afterwards.

The cover was first added on 2026-11-22. On 2026-11-28 its two watch screens were replaced with
captures 1 and 2 above. They were projected onto the original blank hardware plate with the same
perspective, and the bezels, phone, background and headline are unchanged.

[Google Play preview asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en-GB)
