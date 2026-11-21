---
name: documentation-structure
description: Organize maintained WardPulse Markdown by ownership, semantic splits, physical line limits, and reading routes. Use when adding, splitting, moving, or retiring documents or repairing README gates, links, and anchors.
---

# Documentation Structure

Start at the [docs index](../../../docs/README.md) to find the existing owner of the
topic. Use [docs-gate](../docs-gate/SKILL.md) for content ownership, [project-structure](../project-structure/SKILL.md)
for placement, and [documentation tooling](../../../docs/DOCUMENTATION.md) for Vocs and
source citations. Apply [delegation](../delegation/SKILL.md) to authorship.

## Scope and line limits

Maintained Markdown includes tracked and non-ignored untracked `.md` and `.markdown`
files. Count each canonical file once, including skill files reached through the
`.claude/skills` alias. Ignored reports, task packets, clarifications and local
artifacts follow their own contracts.

| File | Maximum physical lines |
| --- | ---: |
| Markdown inside a skill tree, including nested references and README files | 100 |
| Other `README.md` and `README.markdown` entry points | 150 |
| Other maintained Markdown | 1,000 |

Count the final formatted file, including frontmatter, blank lines, code fences
and a final line without a newline. Visual wrapping and byte size are separate
from physical line count. Split at coherent boundaries and keep prose readable.
Apply the limits to the documents in scope. Track unrelated existing overages
with the broader Markdown migration.

## Split by ownership and route readers

- Give each rule one owner. Extend that document or link to it.
- Split by component, contract, or reading task. Preserve the meaning of rules,
  active permissions, examples and code fences. Keep decisions with their owners.
- Give a documentation family a concise README gate describing its purpose,
  each child's ownership and when to read it. Use nested gates where they reduce
  required reading.
- Link each maintained document through relative links reachable from
  [docs/README.md](../../../docs/README.md). Follow the repo's existing component
  gates and skill entry points.
- Keep authoritative user topics in the user guide. Route public Vocs pages
  through their existing imports and navigation under [user-docs](../user-docs/SKILL.md).

## Move, split, or retire

- Before editing, search for the existing paths and affected anchors. Check
  incoming and outgoing links and real consumers, including AGENTS and skill
  routes, prompts, Vocs imports and navigation, tests matching paths or text,
  runtime loaders, packaged or frozen file lists, and release assembly.
- Update each affected consumer in the same change. Preserve stable entry paths
  and relied-on anchors with concise compatibility routes when required. Update
  loaders and packaging at the source of delivery.
- Record each original section's destination and whether it was retained, moved,
  merged or retired. Put the mapping in the handoff or an authorized, ignored
  project-local artifact under `LOCAL_ARTIFACTS/`.

## Verify the final documents

- Measure the scoped files after formatting. Resolve relative paths inside the
  repository and verify fragments against GitHub's slugs for rendered headings.
  Trace reachability from the docs index. Check affected Vocs routes separately.
- Use [finalization](../finalization/SKILL.md) to select repository gates.
  `just check-docs` checks stable source citations and builds Vocs. Check line
  counts, local links and anchors, reachability and loader routing separately.
  Run the skill metadata validator from `AGENTS.md` for changed skill roots.
- Review the complete resulting documents and affected consumers through the
  task's existing independent review gate. Confirm active rules and evidence
  retain their meaning and report the checks actually performed.
