---
name: user-docs
description: Author and review WardPulse public Vocs user guides, product landing/README copy and UI screenshots. Use when user-visible behaviour or setup changes, or when updating public guidance; keep engineering documentation with its repository owners.
---

# User Documentation — WardPulse

Apply [docs-gate](../docs-gate/SKILL.md) for ownership and currency and
[delegation](../delegation/SKILL.md) for authorship. Delegated authors write plain Markdown
and workflow prose; actual MDX/TS/CSS, scripts and other code are authored only by Runner
execution with independent review. This skill changes no check or commit authority.

## Public audience and owners

- Write for someone using the installed Android phone/Wear applications. Lead with the
  task, visible controls, expected result and useful recovery. Use concise, concrete language;
  remove AI boilerplate, stock phrases, repetition and filler.
- Omit generic installed-build/distribution filler; retain useful compatibility and network
  prerequisites. Providers connects existing accounts or reporting keys, not subscription
  tiers chosen in WardPulse. Give browser-specific steps for Chrome, Firefox and Safari
  when cookie setup needs them, rather than relabelling Chromium instructions.
- Keep Last updated small and visually quiet, with lower contrast that remains readable.
  Preserve its accurate date and meaning; do not hide it or make it a prominent banner.
- Authoritative task guides live in `docs/product/user-guide/`; the public privacy policy
  remains `docs/product/PRIVACY_POLICY.md`. The landing page and root README begin with a
  short product introduction, approved screenshot gallery and clear guide entry.
- Public Vocs publishes only user guidance and relevant privacy/help. Do not publish
  developer source notes, file paths/symbols, architecture, plans, toolchain/workflows,
  bindings or internal design/reference pages. Remove their public adapters/routes rather
  than only hiding navigation. Preserve the originals and index them in `docs/README.md`;
  engineering documentation retains its ordinary repository availability.
- Provider/browser account instructions needed for connection are allowed, including the
  exact cookie name and browser controls. They are user tasks, not app implementation notes.
- Direct help requests to the repository's GitHub issues and the single owning
  `docs/product/user-guide/REPORT_AN_ISSUE.md` format: Actual behaviour, Expected behaviour
  and Steps to reproduce are required; Notes is optional. Do not add mandatory fields or
  duplicate its template elsewhere.
- Give meaningful guide sections stable permalinks usable by future app links. Preserve
  existing section IDs when prose changes; coordinate heading changes or explicit IDs with
  Runner rather than silently breaking hashes. Check direct URLs with headings clear of
  sticky bars. Record section URLs in existing internal review notes, not developer paths
  on public pages; app-link implementation is a separate code task.

## Accuracy and private review evidence

Check prose against actual UI, capabilities and limitations using existing owning sources
and internal review notes. Do not invent public download/store routes, successful live
authentication, exact background scheduling or release/hardware acceptance.

Do not add public Source notes to satisfy the citation gate: it rejects unstable `path:line`
references and does not require source footers. Keep source verification internal, with
stable files plus named symbols/recipes or document sections when citing those sources.
No new registry, tooling or dependency is needed solely for that check.

Explain privacy accurately: credentials are stored encrypted on the phone and used to
authenticate requests directly to their provider. They are not sent to a WardPulse server
or the watch. Distinguish this from derived summaries, which Google Play services can relay
between paired devices. Do not imply that credentials never travel over the network.

## Screenshot contract

Choose up to THREE showcase screenshots PER platform for the landing/README gallery.
Android phone and Wear OS count as ONE platform: its current gallery has three showcase subjects, with
both phone and watch represented. This is a showcase selection limit, not a global cap
on the screenshot library or other platforms. Reuse the approved set on the landing page
and root README. Place the gallery near the beginning, before long explanatory material;
use useful captions/alt text.

The three-subject limit applies only to the landing/README showcase. Use meaningful task
screenshots near the related steps or results to break long explanations where a picture
helps. Include real Providers connection examples, Widget selection/configuration and actual
home-screen widgets. Choose the smallest useful set; avoid decorative quotas or duplicated
walls of images. Guide images follow the same theme, clean-status-bar, privacy, size, index
and freshness rules below.

Prefer clear captions. Useful action highlights are optional editorial overlays authored by
Runner over clean PNGs: transparent interior, `#2563EB` outline at 2 CSS px, 4 CSS px clearance
around the confirmed glyph bounds and 8 CSS px corner radius, retained at responsive sizes.
Do not outline adjacent full touch boxes. If numbering helps, use a 20 CSS px blue circle
with a 12 CSS px bold white sans-serif digit outside the control bounds. Keep glyphs, text
and sensitive areas unobscured; never invent controls or make the decoration interactive.
Captions name the real icons/actions and remain true for clean Markdown exports; do not
claim marks are baked into the PNG. Preserve clean original-image links and PNG bytes.
Index a derivative with its source only if an actual separate annotated PNG is produced.

- Store PNGs in `docs/assets/` with meaningful lower-kebab filenames.
- Phone screenshot height is 1920px with source aspect ratio preserved; record actual width.
- Watch screenshots are 500×500px PNGs with transparency outside the actual circular screen.
  Preserve all UI inside the circle; do not crop the face, distort, recolour or fabricate it.
- Frames use a 1 CSS px neutral outline (`--vocs-border-color-primary`) in both themes:
  rectangular phone with radius 0, circular Wear with radius 50%. No additional shadow or
  UI clipping. Desktop target/max width is 288 CSS px for guide previews; landing/README
  targets are 216 CSS px for phone and 200 CSS px for Wear. Responsive reductions preserve
  aspect ratio. GitHub uses its supported 1 px neutral table-border fallback, not stripped
  CSS. Keep these tokens out of public prose.
- Use content approved for public sharing: no credentials, identifying account information,
  prompts or sensitive provider data. Review visible usage before publication. Record real
  anonymous app captures as such; do not label them Mock/demo. Describe demonstration or
  sanitized content honestly, and do not invent data or unperformed captures.
- Capture success illustrations in an appropriate real device state, without irrelevant
  system notifications/service icons, low-battery warnings or transient errors. Use existing
  OS/device controls; never erase, fake or retouch legitimate app UI. Show a warning when
  illustrating that documented state; otherwise capture the actual normal state.
  Before phone captures, hide extraneous status-bar icons with visibility-only OS controls;
  ordinary clock, battery and network indicators may remain. Do not dismiss notifications
  or erase data. Restore temporary OS/device state after capture, and review both phone
  theme variants for private or identifying data before publication.
- `docs/assets/README.md` must index every screenshot with description and DATE ADDED.
  Record capture/verification dates, dimensions, known app/context, data treatment and
  locations where it is used; include a build version only if actually recorded. Do not add rows
  for planned/nonexistent screenshots as though they were captured.
- When pictured UI changes, update the affected PNGs and index in the same change set;
  review the whole set for consistency. If captures cannot run yet, record the pending work
  accurately and do not claim screenshot freshness or final acceptance. Preserve the
  existing host/device check division and Runner commit boundary.

### Theme matching

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

## Final review

Check ALL public pages, menus, direct routes, links and gallery uses against this skill,
not just the last changed paragraph. Independent review and the coordinator's full final
pass must reach ZERO; return findings to the same prose/design author or to Runner for
code fixes, then repeat the whole pass after the last fix.

Keep affected guides, policy, screenshot index and existing workflows current. If none are
affected, give a short reason in the handoff. Existing required validators/build checks
remain mandatory; browser/capture evidence must report what was actually measured and
what remains pending. Do not close unrelated provider, hardware or release acceptance.
