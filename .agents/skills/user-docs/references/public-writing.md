# Public writing rules

Read completely before public authoring or review through [user-docs](../SKILL.md).

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
- Public Vocs publishes user guidance, an owner-requested product roadmap and relevant
  privacy/help. The roadmap describes user benefits and planned milestones without release
  dates or completed-release claims unless verified; keep tentative features visibly tentative.
  Do not publish developer source notes, file paths/symbols, architecture, implementation
  plans, toolchain/workflows, bindings or internal design/reference pages. Remove their
  public adapters/routes rather than only hiding navigation. Preserve the originals and
  index them in `docs/README.md`; engineering documentation retains its ordinary repository
  availability.
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
