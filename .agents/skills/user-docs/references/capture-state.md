# Capture state

Read completely together with [screenshots.md](screenshots.md) before screenshot work
routed by [user-docs](../SKILL.md). Apply [android-emulators](../../android-emulators/SKILL.md)
for actual device operations and persisted-state preservation.

## Privacy and relevant UI state

- Use content approved for public sharing: no credentials, identifying account information,
  prompts or sensitive provider data. Review visible usage before publication. Record real
  anonymous app captures as such; do not label them Mock/demo. Describe demonstration or
  sanitized content honestly, and do not invent data or unperformed captures.
- General examples, setup steps and showcases must use screenshots without errors,
  warnings or stale-data indicators such as `Stale`, including persistent credential or
  provider errors. Show an error, warning or stale-data state only when
  nearby text explicitly explains that exact state; never use it as a generic illustration.
  Capture the appropriate real device state without irrelevant system notifications/service
  icons or low-battery warnings. Use existing OS/device controls; never erase, fake or
  retouch legitimate app UI.
  Before phone captures, hide extraneous status-bar icons with visibility-only OS controls;
  ordinary clock, battery and network indicators may remain. Do not dismiss notifications
  or erase data. Restore temporary OS/device state after capture, and review both phone
  theme variants for private or identifying data before publication.

## Clean home screen and dock

For phone-home or widget demonstrations, keep the displayed launcher page free of unrelated
shortcuts and widgets. Move unrelated items to another page where possible; removing a
launcher shortcut is not authorization to uninstall an app or erase its data. Place the real
WardPulse app shortcut in the far-right position of the fixed favorites dock, replacing an
unrelated shortcut such as Photos. Use actual launcher controls, never image retouching.
Keep this arrangement consistent across related sizes, cases and both themes.

Restore temporary capture-only launcher/OS changes after capture. If the Owner explicitly
requests the cleaned page or WardPulse dock placement as a persistent arrangement, preserve
that requested arrangement; restore only the other temporary capture state.

## Theme matching

Where a surface supports both themes, light documentation must show an actual light-app
capture and dark documentation an actual dark-app capture. Vocs and README selection,
previews and original-image links must agree; never silently substitute the opposite
phone theme. Name paired variants with meaningful `-light.png` and `-dark.png` suffixes.
Capture the app itself; never recolour or invert a screenshot to fabricate a theme.

Record each surface's supported/fixed theme in the asset index and each PNG's theme,
Date added, capture and verification dates. Operator-confirmed fixed-theme surfaces reuse
their unchanged actual capture in both documentation themes, with the limitation recorded
once in the index. WardPulse Wear and its face currently have a fixed dark appearance;
this exception does not apply to the phone, which supports light/dark/system. Fixed-theme
filenames may remain unchanged; do not invent a light counterpart.

When pictured UI changes, review both theme variants and refresh every affected variant
plus its metadata. Unperformed capture/verification stays pending. Keep up to three subjects
per platform in the landing/README gallery; paired variants do not add showcase slots or
require displaying six screenshots at once.
