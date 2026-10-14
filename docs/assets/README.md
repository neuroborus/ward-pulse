# WardPulse UI screenshots

This directory owns the public UI PNGs used by the site, root README and optional guide illustrations.
Apply [user-docs](../../.agents/skills/user-docs/SKILL.md) when capturing or reviewing them.

Select up to three showcase screenshots per platform for the landing/README gallery.
Android phone and Wear OS are one platform: its current gallery has three showcase subjects, with both
phone and watch represented. This does not cap the whole screenshot library or other
platforms. Reuse the same assets instead of adding another gallery's copies.
Use meaningful lower-kebab filenames. Phone PNG height is 1920px with its original aspect
ratio retained; watch PNGs are 500×500px.

## Screenshot index

Every screenshot file must have a row with DATE ADDED and a short description. The four
screenshots below were captured and added on 2026-10-14.

| File | Description | Theme | Date added | Captured | Last verified | Dimensions | App | Used in |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| [phone-dashboard-light.png](phone-dashboard-light.png) | Dashboard plan capacity and update status. | Light | 2026-10-14 | 2026-10-14 | 2026-10-14 | 864×1920 | WardPulse phone | Light landing/README |
| [phone-dashboard-dark.png](phone-dashboard-dark.png) | Dashboard plan capacity and update status. | Dark | 2026-10-14 | 2026-10-14 | 2026-10-14 | 864×1920 | WardPulse phone | Dark landing/README |
| [wear-glance.png](wear-glance.png) | Glance balances and refresh status. | Fixed dark | 2026-10-14 | 2026-10-14 | 2026-10-14 | 500×500 | WardPulse Wear | Both landing/README themes |
| [wear-watch-face.png](wear-watch-face.png) | Watch-face usage rings and upper complications. | Fixed dark | 2026-10-14 | 2026-10-14 | 2026-10-14 | 500×500 | WardPulse watch face | Both landing/README themes |

All four are real anonymous app captures with normalized usage, no identifying account
information or credentials; they are not Mock/demo. Captured UI was verified against source
revision `74cf501`; the installed APK version was not recorded and is not asserted here.

The phone pair was captured with extraneous status-bar icons temporarily hidden using OS
visibility controls; clock, network and battery remain. No notifications were dismissed,
data erased or valid app UI hidden or retouched; temporary OS appearance was restored.

| File | SHA256 |
| --- | --- |
| `phone-dashboard-light.png` | `c752adc0ba795b3cfbd98da09bcc5545f619a34a04865fc4013c14b53d1e5e7a` |
| `phone-dashboard-dark.png` | `1b28e1587dd0a4754477051da621f505332c53e2d382dd9d9aaecb1768401c5f` |
| `wear-glance.png` | `93db11c9c354b0e07bb806bf80539a7ff0dd5ed79106ef7262424590eeee57ce` |
| `wear-watch-face.png` | `60b6174a907c8c4bdbdf608896ed5ace341a7b00e136866c421ef91be04caaa9` |

## Theme inventory

The phone supports light and dark themes and follows system appearance by default. Its
paired light/dark captures must match the documentation theme, including original-image
links. WardPulse Wear and the watch face use a fixed dark appearance; their unchanged
actual captures are reused in both documentation themes. They have no fabricated light
counterparts, and this fixed-theme limitation does not relax phone theme correspondence.
The four PNG variants represent three showcase subjects, not four visible gallery slots.

## Update gate

When pictured UI changes, refresh the affected PNGs and their metadata in the same change
set. Review all gallery uses and ensure obsolete copies are not still embedded. Images must
be readable, undistorted and approved for public sharing: no credentials, identifying account
information, prompts or sensitive provider responses. Review visible usage before publication.
Date added describes when a file entered this directory; capture and verification dates
describe those actual events, not this index's edit date. Record unperformed capture work as pending;
do not certify stale or nonexistent images as current.

Review both theme variants for UI freshness and refresh every affected variant and its
metadata. Paired filenames identify the actual captured light/dark app appearance; never
recolour or invert a screenshot to create a counterpart. Keep fixed-theme filenames honest.
